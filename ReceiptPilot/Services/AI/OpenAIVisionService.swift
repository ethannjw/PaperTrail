// OpenAIVisionService.swift
// Sends a receipt image directly to the OpenAI Chat Completions API
// using the gpt-4o vision model and returns structured JSON.

import Foundation
import UIKit

final class OpenAIVisionService: AIService {

    var appSettings: AppSettings?

    // MARK: - Configuration
    private let model = "gpt-4o"
    private let maxTokens = 1024
    private let baseURL: URL

    private var apiKey: String {
        get throws {
            guard let key = try? KeychainService.load(key: .openAIAPIKey), !key.isEmpty else {
                throw AppError.missingAPIKey("OpenAI")
            }
            return key
        }
    }

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL ?? AppConfig.shared.openAIBaseURL
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
        // Resize if > 4MB to stay within API limits
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
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": ReceiptPrompts.visionUserPrompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)",
                                "detail": "high"
                            ]
                        ]
                    ]
                ]
            ]
        ]
    }

    private func performRequest(body: [String: Any]) async throws -> String {
        let url = baseURL.appendingPathComponent("/v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = AppConfig.shared.networkTimeoutSeconds

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AppError.unknown("Non-HTTP response from OpenAI")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AppError.httpError(http.statusCode, body)
        }

        // Extract content from choices[0].message.content
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let choices = json?["choices"] as? [[String: Any]],
            let first   = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw AppError.invalidJSONResponse("OpenAI response structure unexpected")
        }
        return content
    }
}

// resizedIfNeeded is defined as a shared UIImage extension in GeminiVisionService.swift
