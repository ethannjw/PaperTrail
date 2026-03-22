// CameraViewModel.swift
// Orchestrates the full receipt capture pipeline:
//   Camera → Image Enhancement → OCR/AI extraction → Validation → Submission
// MVVM: Views observe @Published properties; this VM holds all state.

import Foundation
import UIKit
import Combine

// MARK: - Pipeline Stage

enum PipelineStage: Equatable {
    case idle
    case authorized
    case capturing
    case processing(String)    // Message like "Extracting data…"
    case editing(Receipt)
    case submitting
    case success(Receipt)
    case failed(AppError)
}

// MARK: - ViewModel

@MainActor
final class CameraViewModel: ObservableObject {

    // MARK: - Published State
    @Published var stage: PipelineStage = .idle
    @Published var capturedImage: UIImage?
    @Published var enhancedImage: UIImage?
    @Published var editableReceipt: Receipt = Receipt()
    @Published var validationIssues: [String] = []
    @Published var showValidationAlert: Bool  = false
    @Published var showDocumentScanner: Bool  = false
    @Published var showPhotoPicker: Bool      = false

    // MARK: - Dependencies
    let cameraManager: CameraManager
    private let ocrService = OCRService()
    private let appSettings: AppSettings
    private let googleAuth: GoogleAuthService
    private let driveService: GoogleDriveService
    private let sheetsService: GoogleSheetsService
    private let offlineQueue: OfflineQueueManager
    private let duplicateDetector: DuplicateDetector
    private let analyticsStore: AnalyticsStore

    // MARK: - Init
    init(
        appSettings: AppSettings,
        googleAuth: GoogleAuthService,
        offlineQueue: OfflineQueueManager,
        analyticsStore: AnalyticsStore
    ) {
        self.appSettings       = appSettings
        self.googleAuth        = googleAuth
        self.driveService      = GoogleDriveService(authService: googleAuth, appSettings: appSettings)
        self.sheetsService     = GoogleSheetsService(authService: googleAuth, appSettings: appSettings)
        self.offlineQueue      = offlineQueue
        self.analyticsStore    = analyticsStore
        self.cameraManager     = CameraManager()
        self.duplicateDetector = DuplicateDetector()

        // Wire up analytics to read from sheets
        analyticsStore.configure(sheetsService: self.sheetsService)
    }

    // MARK: - Camera Lifecycle

    func startCamera() async {
        await cameraManager.requestPermissionAndStart()
    }

    func stopCamera() {
        cameraManager.stopSession()
    }

    // MARK: - Step 1: Capture (Custom Camera)

    func capturePhoto() async {
        do {
            stage = .capturing
            let image = try await cameraManager.capturePhoto()
            capturedImage = image
            await processImage(image)
        } catch let appErr as AppError {
            stage = .failed(appErr)
        } catch {
            stage = .failed(.unknown(error.localizedDescription))
        }
    }

    // MARK: - Step 1b: Capture (VisionKit Document Scanner)

    func handleDocumentScanResult(_ image: UIImage) {
        capturedImage = image
        Task { await processImage(image) }
    }

    func retakePhoto() {
        capturedImage = nil
        enhancedImage = nil
        editableReceipt = Receipt()
        validationIssues = []
        stage = .idle
    }

    // MARK: - Step 2: Image Enhancement + AI Processing

    func processImage(_ image: UIImage) async {
        stage = .processing("Detecting receipt edges...")

        do {
            // Auto-crop using Vision rectangle detection
            let cropped = await ocrService.detectAndCropReceipt(from: image)

            // Apply image enhancement pipeline
            stage = .processing("Enhancing image...")
            let enhanced = ImageProcessor.enhanceReceipt(cropped, grayscale: true)
            enhancedImage = enhanced
            capturedImage = cropped  // Keep original crop for upload

            // Generate PDF
            stage = .processing("Generating PDF...")
            let pdfData = PDFGenerator.generatePDF(from: cropped)

            stage = .processing("Extracting data with AI...")
            let aiService = AIServiceFactory.makeCurrentService(settings: appSettings)
            let response  = try await aiService.extractReceipt(from: cropped)
            var receipt   = response.toReceipt()
            receipt.imageLocalURL = saveImageLocally(cropped, id: receipt.id)
            receipt.currency      = receipt.currency.isEmpty ? appSettings.defaultCurrency : receipt.currency

            // Save PDF locally
            let filename = receipt.suggestedFilename ?? "\(receipt.date)_\(receipt.merchant)"
            receipt.pdfLocalURL = PDFGenerator.savePDF(pdfData, filename: filename)

            // Category classification
            stage = .processing("Classifying category...")
            let aiCategory = receipt.category
            if aiCategory == nil || aiCategory?.isEmpty == true {
                receipt.category = await CategoryClassifier.classify(
                    merchant: receipt.merchant,
                    items: receipt.items
                )
            }

            // Duplicate check
            receipt.isDuplicate = await duplicateDetector.isDuplicate(receipt)

            editableReceipt = receipt
            stage = .editing(receipt)
        } catch let appErr as AppError {
            stage = .failed(appErr)
        } catch {
            stage = .failed(.unknown(error.localizedDescription))
        }
    }

    // MARK: - Step 3: Validation

    func validateAndProceed() {
        let issues = editableReceipt.validate()
        if issues.isEmpty {
            Task { await submitReceipt() }
        } else {
            validationIssues = issues
            showValidationAlert = true
        }
    }

    func forceSubmit() {
        Task { await submitReceipt() }
    }

    // MARK: - Step 4: Submit

    func submitReceipt() async {
        stage = .submitting
        var receipt = editableReceipt
        receipt.submittedAt = Date()
        receipt.syncStatus = .uploading

        do {
            // Check connectivity
            guard NetworkMonitor.shared.isConnected else {
                receipt.syncStatus = .failed
                try offlineQueue.enqueue(receipt)
                stage = .failed(.networkUnavailable)
                return
            }

            NSLog("[PaperTrail] Starting submit — sheetID: '%@', sheetName: '%@', folderID: '%@'",
                  appSettings.googleSpreadsheetID, appSettings.googleSpreadsheetName, appSettings.googleDriveFolderID)

            // Save PDF to Files app (accessible via iCloud Drive, etc.)
            if let image = capturedImage {
                stage = .processing("Saving to Files...")
                saveToFilesApp(image: image, receipt: receipt)

                // Upload PDF to Google Drive
                stage = .processing("Uploading to Drive...")
                NSLog("[PaperTrail] Uploading to Drive...")
                receipt.imageDriveURL = try await driveService.uploadReceipt(image: image, receipt: receipt)
                NSLog("[PaperTrail] Drive upload done: %@", receipt.imageDriveURL ?? "nil")
            }

            // Write to Sheets
            stage = .processing("Saving to Google Sheets...")
            NSLog("[PaperTrail] Writing to Sheets...")
            try await sheetsService.appendReceipt(receipt)
            NSLog("[PaperTrail] Sheets write done")

            // Mark as synced
            receipt.syncStatus = .synced

            // Persist locally for analytics
            analyticsStore.add(receipt)
            editableReceipt = receipt
            stage = .success(receipt)

        } catch let appErr as AppError {
            NSLog("[PaperTrail] Submit failed (AppError): %@", appErr.localizedDescription)
            receipt.syncStatus = .failed
            if case .networkUnavailable = appErr {
                try? offlineQueue.enqueue(receipt)
            }
            stage = .failed(appErr)
        } catch {
            NSLog("[PaperTrail] Submit failed (other): %@", error.localizedDescription)
            receipt.syncStatus = .failed
            stage = .failed(.unknown(error.localizedDescription))
        }
    }

    // MARK: - Retry

    func retrySubmit() {
        Task { await submitReceipt() }
    }

    // MARK: - Local Image Persistence

    private func saveImageLocally(_ image: UIImage, id: UUID) -> URL? {
        let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("receipts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(id.uuidString).jpg")
        if let data = image.jpegData(compressionQuality: 0.9) {
            try? data.write(to: url)
            return url
        }
        return nil
    }

    // MARK: - Save to Files App

    /// Saves the receipt PDF to the user's chosen folder (or default Documents).
    private func saveToFilesApp(image: UIImage, receipt: Receipt) {
        let fm = FileManager.default

        let filename = receipt.suggestedFilename ?? "\(receipt.date)_\(receipt.merchant)_\(receipt.id.uuidString.prefix(6))"
        let sanitized = PDFGenerator.sanitizeFilename(filename)
        let pdfData = PDFGenerator.generatePDF(from: image, receipt: receipt)

        // Try user-selected folder first
        if let bookmarkedURL = FolderBookmarkService.resolveBookmark() {
            guard bookmarkedURL.startAccessingSecurityScopedResource() else { return saveFallback(pdfData, sanitized: sanitized) }
            defer { bookmarkedURL.stopAccessingSecurityScopedResource() }

            let pdfURL = bookmarkedURL.appendingPathComponent("\(sanitized).pdf")
            do {
                try pdfData.write(to: pdfURL, options: .atomic)
                editableReceipt.pdfLocalURL = pdfURL
                return
            } catch {
                print("[Files] Failed to write to bookmarked folder: \(error). Falling back.")
            }
        }

        saveFallback(pdfData, sanitized: sanitized)
    }

    private func saveFallback(_ pdfData: Data, sanitized: String) {
        let fm = FileManager.default
        guard var baseDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        baseDir = baseDir.appendingPathComponent("Scanned Receipts", isDirectory: true)
        try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let pdfURL = baseDir.appendingPathComponent("\(sanitized).pdf")
        try? pdfData.write(to: pdfURL, options: .atomic)
        editableReceipt.pdfLocalURL = pdfURL
    }
}
