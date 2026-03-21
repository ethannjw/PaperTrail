// GeminiVisionService.swift
// Sends a receipt image to Google Gemini Vision API (gemini-1.5-flash)
// using multipart content parts and returns structured JSON.

import Foundation
import UIKit

final class GeminiVisionService: AIService {

    var appSettings: AppSettings?

    // MARK: - Configuration
    private let model = "gemini-1.5-flash"
    private let baseURL: URL

    private var apiKey: String {
        get throws {
            guard let key = try? KeychainService.load(key: .geminiAPIKey), !key.isEmpty else {
                throw AppError.missingAPIKey("Gemini")
            }
            return key
        }
    }

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL ?? AppConfig.shared.geminiBaseURL
    }

    // MARK: - AIService

    func extractReceipt(from image: UIImage) async throws -> AIReceiptResponse {
        let base64Image = try encodeImage(image)
        let requestBody = buildRequestBody(base64Image: base64Image)
        let raw = try await performRequest(body: requestBody)
        return try parseReceiptJSON(raw)
    }

    // MARK: - Private Helpers

    private func encodeImage(_ image: UIImage) throws -> String {
        let compressed = image.resizedIfNeeded(maxDimension: 1500)
        guard let jpegData = compressed.jpegData(compressionQuality: 0.85) else {
            throw AppError.imageCaptureFailed
        }
        return jpegData.base64EncodedString()
    }

    private func buildRequestBody(base64Image: String) -> [String: Any] {
        // Gemini uses a "contents" array with "parts"
        let systemPart: [String: Any] = ["text": systemPrompt]
        let userTextPart: [String: Any] = ["text": ReceiptPrompts.visionUserPrompt]
        let imagePart: [String: Any] = [
            "inline_data": [
                "mime_type": "image/jpeg",
                "data": base64Image
            ]
        ]

        return [
            "contents": [
                [
                    "role": "user",
                    "parts": [systemPart, userTextPart, imagePart]
                ]
            ],
            "generationConfig": [
                "temperature": 0,
                "maxOutputTokens": 1024,
                "responseMimeType": "application/json"   // Forces JSON output
            ]
        ]
    }

    private func performRequest(body: [String: Any]) async throws -> String {
        let key = try apiKey
        // Gemini endpoint: /v1beta/models/{model}:generateContent?key=API_KEY
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/v1beta/models/\(model):generateContent"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "key", value: key)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = AppConfig.shared.networkTimeoutSeconds
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AppError.unknown("Non-HTTP response from Gemini")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AppError.httpError(http.statusCode, body)
        }

        // Extract: candidates[0].content.parts[0].text
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let candidates = json?["candidates"] as? [[String: Any]],
            let first       = candidates.first,
            let content     = first["content"] as? [String: Any],
            let parts       = content["parts"] as? [[String: Any]],
            let text        = parts.first?["text"] as? String
        else {
            throw AppError.invalidJSONResponse("Gemini response structure unexpected")
        }
        return text
    }
}

// resizedIfNeeded is defined in UIImage+Extensions.swift
