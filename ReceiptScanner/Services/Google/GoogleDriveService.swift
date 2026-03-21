// GoogleDriveService.swift
// Uploads receipt images to Google Drive using the Drive REST API v3.
// Uses multipart upload for files with metadata in one request.

import Foundation
import UIKit

final class GoogleDriveService {

    private let authService: GoogleAuthService
    private let config = AppConfig.shared

    init(authService: GoogleAuthService) {
        self.authService = authService
    }

    // MARK: - Public API

    /// Upload a receipt image to Drive. Returns shareable web link.
    /// - Parameters:
    ///   - image: The captured receipt image.
    ///   - receipt: Associated receipt for naming.
    /// - Returns: Web view link (shareable URL).
    func uploadReceiptImage(
        _ image: UIImage,
        receipt: Receipt
    ) async throws -> String {
        let token = try await authService.validAccessToken()
        let imageData = try compressImage(image)
        let filename  = buildFilename(receipt: receipt)
        let metadata  = buildMetadata(filename: filename)

        let response = try await performMultipartUpload(
            token: token,
            imageData: imageData,
            metadata: metadata
        )

        // Make file publicly readable (view only)
        try await makePubliclyReadable(fileID: response.id, token: token)

        return response.webViewLink ?? "https://drive.google.com/file/d/\(response.id)/view"
    }

    // MARK: - Private Helpers

    private func compressImage(_ image: UIImage) throws -> Data {
        let resized = image.resizedIfNeeded(maxDimension: 2000)
        guard let data = resized.jpegData(compressionQuality: 0.90) else {
            throw AppError.imageCaptureFailed
        }
        return data
    }

    private func buildFilename(receipt: Receipt) -> String {
        let safe = receipt.merchant
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let date = receipt.date.isEmpty ? ISO8601DateFormatter().string(from: Date()).prefix(10) : receipt.date
        return "receipt_\(safe)_\(date)_\(receipt.id.uuidString.prefix(8)).jpg"
    }

    private func buildMetadata(filename: String) -> [String: Any] {
        var meta: [String: Any] = [
            "name": filename,
            "mimeType": "image/jpeg"
        ]
        let folderID = config.googleDriveFolderID
        if !folderID.isEmpty && folderID != "YOUR_GOOGLE_DRIVE_FOLDER_ID" {
            meta["parents"] = [folderID]
        }
        return meta
    }

    // MARK: - Multipart Upload

    private struct DriveUploadResponse: Decodable {
        let id: String
        let webViewLink: String?
    }

    private func performMultipartUpload(
        token: String,
        imageData: Data,
        metadata: [String: Any]
    ) async throws -> DriveUploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)

        var body = Data()
        // Metadata part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataJSON)
        body.append("\r\n".data(using: .utf8)!)
        // Image part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let uploadURL = URL(
            string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink"
        )!

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/related; boundary=\"\(boundary)\"",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body
        request.timeoutInterval = 60 // Uploads can take longer

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AppError.googleDriveUploadFailed("Non-HTTP response")
        }
        guard http.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            throw AppError.googleDriveUploadFailed("HTTP \(http.statusCode): \(errBody)")
        }

        let decoded = try JSONDecoder().decode(DriveUploadResponse.self, from: data)
        return decoded
    }

    // MARK: - Permissions

    private func makePubliclyReadable(fileID: String, token: String) async throws {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)/permissions")!
        let body: [String: Any] = ["role": "reader", "type": "anyone"]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)",    forHTTPHeaderField: "Authorization")
        request.setValue("application/json",   forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else {
            // Non-fatal: file uploaded but not shared publicly
            // Log and continue
            print("[GoogleDrive] Warning: Could not set public permission on \(fileID)")
        }
    }
}
