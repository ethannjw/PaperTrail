// ClaudeVisionService.swift
// Sends a receipt image to the Anthropic Claude Messages API
// using claude-sonnet-4-20250514 vision and returns structured JSON.

import Foundation
import UIKit

final class ClaudeVisionService: AIService {

    var appSettings: AppSettings?

    // MARK: - Configuration
    private let model = "claude-sonnet-4-20250514"
    private let maxTokens = 1024
    private let baseURL: URL

    private var apiKey: String {
        get throws {
            guard let key = try? KeychainService.load(key: .claudeAPIKey), !key.isEmpty else {
                throw AppError.missingAPIKey("Claude")
            }
            return key
        }
    }

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL ?? AppConfig.shared.claudeBaseURL
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
        return [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": ReceiptPrompts.visionUserPrompt
                        ]
                    ]
                ]
            ]
        ]
    }

    private func performRequest(body: [String: Any]) async throws -> String {
        let url = baseURL.appendingPathComponent("/v1/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(try apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = AppConfig.shared.networkTimeoutSeconds

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AppError.unknown("Non-HTTP response from Claude")
        }
        guard http.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            throw AppError.httpError(http.statusCode, errBody)
        }

        // Extract content[0].text from Claude response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let content = json?["content"] as? [[String: Any]],
            let first = content.first,
            let text = first["text"] as? String
        else {
            throw AppError.invalidJSONResponse("Claude response structure unexpected")
        }
        return text
    }
}
