// AppError.swift
// Unified error type used throughout the app.
// Wraps domain-specific errors into user-facing messages.

import Foundation

enum AppError: LocalizedError, Equatable {

    // MARK: - Camera
    case cameraPermissionDenied
    case cameraUnavailable
    case imageCaptureFailed

    // MARK: - AI / OCR
    case ocrFailed(String)
    case aiRequestFailed(String)
    case invalidJSONResponse(String)
    case missingAPIKey(String)

    // MARK: - Validation
    case validationFailed([String])

    // MARK: - Google
    case googleAuthRequired
    case googleAuthFailed(String)
    case googleDriveUploadFailed(String)
    case googleSheetsWriteFailed(String)
    case tokenRefreshFailed(String)

    // MARK: - Network
    case networkUnavailable
    case requestTimeout
    case httpError(Int, String)

    // MARK: - Offline Queue
    case offlineQueueFull

    // MARK: - Generic
    case unknown(String)

    // MARK: - User-facing messages
    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Camera access is required. Please enable it in Settings → Privacy → Camera."
        case .cameraUnavailable:
            return "Camera is unavailable on this device."
        case .imageCaptureFailed:
            return "Failed to capture image. Please try again."

        case .ocrFailed(let detail):
            return "Text recognition failed: \(detail)"
        case .aiRequestFailed(let detail):
            return "AI processing failed: \(detail)"
        case .invalidJSONResponse(let detail):
            return "AI returned unexpected data: \(detail)"
        case .missingAPIKey(let provider):
            return "\(provider) API key not configured. Go to Settings → API Keys."

        case .validationFailed(let issues):
            return "Please fix: " + issues.joined(separator: " • ")

        case .googleAuthRequired:
            return "Sign in with Google to enable Sheets and Drive sync."
        case .googleAuthFailed(let detail):
            return "Google sign-in failed: \(detail)"
        case .googleDriveUploadFailed(let detail):
            return "Drive upload failed: \(detail)"
        case .googleSheetsWriteFailed(let detail):
            return "Sheets write failed: \(detail)"
        case .tokenRefreshFailed(let detail):
            return "Google token refresh failed: \(detail)"

        case .networkUnavailable:
            return "No internet connection. Receipt saved to offline queue."
        case .requestTimeout:
            return "Request timed out. Please check your connection."
        case .httpError(let code, let body):
            return "Server error \(code): \(body)"

        case .offlineQueueFull:
            return "Offline queue is full (max 100 receipts). Please submit pending receipts first."

        case .unknown(let detail):
            return "Unexpected error: \(detail)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .networkUnavailable:
            return "Your receipt has been saved locally and will upload automatically when back online."
        case .missingAPIKey:
            return "Navigate to Settings → API Keys to add your key."
        case .googleAuthRequired:
            return "Tap 'Sign in with Google' in Settings."
        default:
            return nil
        }
    }

    static func == (lhs: AppError, rhs: AppError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}
