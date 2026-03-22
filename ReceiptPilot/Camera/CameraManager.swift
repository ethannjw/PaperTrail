// CameraManager.swift
// Manages the AVCaptureSession lifecycle:
//   - Permission requests
//   - Session setup (rear camera, high-quality photo)
//   - Photo capture via AVCapturePhotoOutput
//   - Preview layer publication for SwiftUI

import AVFoundation
import UIKit
import Combine

// MARK: - Camera State

enum CameraState {
    case idle
    case authorized
    case denied
    case capturing
    case captured(UIImage)
    case error(AppError)
}

// MARK: - CameraManager

@MainActor
final class CameraManager: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var state: CameraState = .idle
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var flashMode: AVCaptureDevice.FlashMode = .auto
    @Published var isTorchOn: Bool = false

    // MARK: - AVFoundation
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var currentDevice: AVCaptureDevice?

    // Continuation for async photo capture
    private var captureCompletion: CheckedContinuation<UIImage, Error>?

    // MARK: - Lifecycle

    override init() {
        super.init()
    }

    func requestPermissionAndStart() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            await setupSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { await setupSession() } else { state = .error(.cameraPermissionDenied) }
        case .denied, .restricted:
            state = .error(.cameraPermissionDenied)
        @unknown default:
            state = .error(.cameraUnavailable)
        }
    }

    func stopSession() {
        Task.detached { [weak self] in
            self?.session.stopRunning()
        }
    }

    // MARK: - Session Setup

    private func setupSession() async {
        guard !session.isRunning else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo

        // Input
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            state = .error(.cameraUnavailable)
            session.commitConfiguration()
            return
        }
        currentDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                state = .error(.cameraUnavailable)
                session.commitConfiguration()
                return
            }
            session.addInput(input)
        } catch {
            state = .error(.cameraUnavailable)
            session.commitConfiguration()
            return
        }

        // Output
        photoOutput.maxPhotoQualityPrioritization = .quality
        photoOutput.isHighResolutionCaptureEnabled = true
        guard session.canAddOutput(photoOutput) else {
            state = .error(.cameraUnavailable)
            session.commitConfiguration()
            return
        }
        session.addOutput(photoOutput)
        session.commitConfiguration()

        // Preview layer (must be on main thread)
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer

        // Start on background thread
        Task.detached { [weak self] in
            self?.session.startRunning()
        }

        state = .authorized
    }

    // MARK: - Capture

    func capturePhoto() async throws -> UIImage {
        guard session.isRunning else { throw AppError.cameraUnavailable }
        state = .capturing

        return try await withCheckedThrowingContinuation { continuation in
            captureCompletion = continuation
            let settings = buildCaptureSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func buildCaptureSettings() -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(
                format: [AVVideoCodecKey: AVVideoCodecType.hevc]
            )
        } else {
            settings = AVCapturePhotoSettings()
        }
        settings.flashMode = flashMode
        settings.isHighResolutionPhotoEnabled = true
        return settings
    }

    // MARK: - Torch

    func toggleTorch() {
        guard let device = currentDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            isTorchOn.toggle()
            device.torchMode = isTorchOn ? .on : .off
            device.unlockForConfiguration()
        } catch {
            print("[Camera] Torch error: \(error)")
        }
    }

    // MARK: - Focus / Exposure (tap to focus)

    func focus(at point: CGPoint, in viewSize: CGSize) {
        guard let device = currentDevice, device.isFocusPointOfInterestSupported else { return }
        let normalizedPoint = CGPoint(
            x: point.y / viewSize.height,
            y: 1 - point.x / viewSize.width
        )
        do {
            try device.lockForConfiguration()
            device.focusPointOfInterest   = normalizedPoint
            device.focusMode              = .autoFocus
            device.exposurePointOfInterest = normalizedPoint
            device.exposureMode           = .autoExpose
            device.unlockForConfiguration()
        } catch {
            print("[Camera] Focus error: \(error)")
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                captureCompletion?.resume(throwing: AppError.aiRequestFailed(error.localizedDescription))
                captureCompletion = nil
                return
            }

            guard
                let data  = photo.fileDataRepresentation(),
                let image = UIImage(data: data)
            else {
                captureCompletion?.resume(throwing: AppError.imageCaptureFailed)
                captureCompletion = nil
                return
            }

            // Auto-orient
            let oriented = image.fixedOrientation()
            state = .captured(oriented)
            captureCompletion?.resume(returning: oriented)
            captureCompletion = nil
        }
    }
}

// fixedOrientation is defined in UIImage+Extensions.swift
