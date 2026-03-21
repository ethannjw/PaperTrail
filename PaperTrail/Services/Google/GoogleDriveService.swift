// GoogleDriveService.swift
// Uploads receipt images to Google Drive using the Drive REST API v3.
// Resolves folder by name (creating if needed), uses multipart upload.

import Foundation
import UIKit

final class GoogleDriveService {

    private let authService: GoogleAuthService
    private let appSettings: AppSettings

    // Cache resolved folder ID to avoid repeated lookups
    private var resolvedFolderID: String?

    init(authService: GoogleAuthService, appSettings: AppSettings) {
        self.authService = authService
        self.appSettings = appSettings
    }

    // MARK: - Public API

    /// Upload a receipt PDF to Drive. Falls back to JPEG if no PDF available.
    func uploadReceipt(
        image: UIImage,
        receipt: Receipt
    ) async throws -> String {
        let token = try await authService.validAccessToken()
        let folderID = try await resolveFolderID(token: token)

        let baseFilename = buildBaseFilename(receipt: receipt)

        // Prefer PDF upload
        let pdfData = PDFGenerator.generatePDF(from: image, receipt: receipt)
        let filename = "\(baseFilename).pdf"
        let metadata = buildMetadata(filename: filename, mimeType: "application/pdf", folderID: folderID)

        let response = try await performMultipartUpload(
            token: token,
            fileData: pdfData,
            contentType: "application/pdf",
            metadata: metadata
        )

        try await makePubliclyReadable(fileID: response.id, token: token)

        return response.webViewLink ?? "https://drive.google.com/file/d/\(response.id)/view"
    }

    // MARK: - Folder Resolution

    /// Finds a Drive folder by name, or creates it. Returns the folder ID.
    private func resolveFolderID(token: String) async throws -> String? {
        let folderInput = appSettings.googleDriveFolderID.trimmingCharacters(in: .whitespaces)
        guard !folderInput.isEmpty else { return nil }

        // If a display name is set, the ID was picked from the selector — use directly
        if !appSettings.googleDriveFolderName.isEmpty {
            return folderInput
        }

        // If no spaces and reasonably long, treat as an ID
        if !folderInput.contains(" ") && folderInput.count > 10 {
            return folderInput
        }
        let folderName = folderInput

        // Check cache
        if let cached = resolvedFolderID { return cached }

        // Search for existing folder by name
        if let existingID = try await findFolder(named: folderName, token: token) {
            resolvedFolderID = existingID
            return existingID
        }

        // Create the folder
        let newID = try await createFolder(named: folderName, token: token)
        resolvedFolderID = newID
        return newID
    }

    private func findFolder(named name: String, token: String) async throws -> String? {
        let query = "name='\(name)' and mimeType='application/vnd.google-apps.folder' and trashed=false"
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "pageSize", value: "1")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [[String: Any]]
        return files?.first?["id"] as? String
    }

    private func createFolder(named name: String, token: String) async throws -> String {
        let body: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder"
        ]

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            throw AppError.googleDriveUploadFailed("Failed to create folder: \(errBody)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = json?["id"] as? String else {
            throw AppError.googleDriveUploadFailed("No folder ID in create response")
        }
        return id
    }

    // MARK: - Private Helpers

    private func buildBaseFilename(receipt: Receipt) -> String {
        if let suggested = receipt.suggestedFilename, !suggested.isEmpty {
            return PDFGenerator.sanitizeFilename(suggested)
        }
        let safe = receipt.merchant
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let date = receipt.date.isEmpty
            ? String(ISO8601DateFormatter().string(from: Date()).prefix(10))
            : receipt.date
        return "\(date)_\(safe)_\(String(format: "%.2f", receipt.total))_\(receipt.currency)"
    }

    private func buildMetadata(filename: String, mimeType: String, folderID: String?) -> [String: Any] {
        var meta: [String: Any] = [
            "name": filename,
            "mimeType": mimeType
        ]
        if let folderID, !folderID.isEmpty {
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
        fileData: Data,
        contentType: String,
        metadata: [String: Any]
    ) async throws -> DriveUploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataJSON)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
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
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AppError.googleDriveUploadFailed("Non-HTTP response")
        }
        guard http.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            throw AppError.googleDriveUploadFailed("HTTP \(http.statusCode): \(errBody)")
        }

        return try JSONDecoder().decode(DriveUploadResponse.self, from: data)
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
            print("[GoogleDrive] Warning: Could not set public permission on \(fileID)")
            return
        }
    }
}
