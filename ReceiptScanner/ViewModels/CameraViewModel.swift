// CameraViewModel.swift
// Orchestrates the full receipt capture pipeline:
//   Camera → OCR/AI extraction → Validation → Submission
// MVVM: Views observe @Published properties; this VM holds all state.

import Foundation
import UIKit
import Combine

// MARK: - Pipeline Stage

enum PipelineStage: Equatable {
    case idle
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
    @Published var editableReceipt: Receipt = Receipt()
    @Published var validationIssues: [String] = []
    @Published var showValidationAlert: Bool  = false

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
        self.driveService      = GoogleDriveService(authService: googleAuth)
        self.sheetsService     = GoogleSheetsService(authService: googleAuth)
        self.offlineQueue      = offlineQueue
        self.analyticsStore    = analyticsStore
        self.cameraManager     = CameraManager()
        self.duplicateDetector = DuplicateDetector()
    }

    // MARK: - Camera Lifecycle

    func startCamera() async {
        await cameraManager.requestPermissionAndStart()
    }

    func stopCamera() {
        cameraManager.stopSession()
    }

    // MARK: - Step 1: Capture

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

    func retakePhoto() {
        capturedImage = nil
        editableReceipt = Receipt()
        validationIssues = []
        stage = .idle
    }

    // MARK: - Step 2: AI Processing

    func processImage(_ image: UIImage) async {
        stage = .processing("Analyzing receipt...")

        do {
            // Auto-crop using Vision rectangle detection
            let cropped = await ocrService.detectAndCropReceipt(from: image)
            capturedImage = cropped

            stage = .processing("Extracting data with AI...")
            let aiService = AIServiceFactory.makeCurrentService(settings: appSettings)
            let response  = try await aiService.extractReceipt(from: cropped)
            var receipt   = response.toReceipt()
            receipt.imageLocalURL = saveImageLocally(cropped, id: receipt.id)
            receipt.currency      = receipt.currency.isEmpty ? appSettings.defaultCurrency : receipt.currency

            // Category classification
            stage = .processing("Classifying category...")
            receipt.category = await CategoryClassifier.classify(
                merchant: receipt.merchant,
                items: receipt.items
            )

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

        do {
            // Check connectivity
            guard NetworkMonitor.shared.isConnected else {
                try offlineQueue.enqueue(receipt)
                stage = .failed(.networkUnavailable)
                return
            }

            // Upload image to Drive
            if let image = capturedImage {
                stage = .processing("Uploading image to Drive...")
                receipt.imageDriveURL = try await driveService.uploadReceiptImage(image, receipt: receipt)
            }

            // Write to Sheets
            stage = .processing("Saving to Google Sheets...")
            try await sheetsService.appendReceipt(receipt)

            // Persist locally for analytics
            analyticsStore.add(receipt)
            editableReceipt = receipt
            stage = .success(receipt)

        } catch let appErr as AppError {
            // Save to offline queue on network failure
            if case .networkUnavailable = appErr {
                try? offlineQueue.enqueue(receipt)
            }
            stage = .failed(appErr)
        } catch {
            stage = .failed(.unknown(error.localizedDescription))
        }
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
}
