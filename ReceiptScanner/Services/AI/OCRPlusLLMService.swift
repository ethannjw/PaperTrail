// OCRPlusLLMService.swift
// Hybrid Mode C pipeline:
//   1. Apple Vision OCR extracts raw text from the receipt image (on-device)
//   2. Raw text is sent to an LLM (OpenAI or Gemini) for structured JSON parsing
//
// Advantages:
//   - Lower API cost (text is cheaper than image tokens)
//   - Works with complex layouts the LLM can reason about
//   - OCR stays on-device (privacy)

import Foundation
import UIKit

final class OCRPlusLLMService: AIService {

    var appSettings: AppSettings?

    enum LLMProvider {
        case openai
        case gemini
        case claude
    }

    // MARK: - Dependencies
    private let ocrService: OCRService
    private let llmProvider: LLMProvider
    private let baseURL: URL

    init(llmProvider: LLMProvider, ocrService: OCRService = OCRService()) {
        self.llmProvider = llmProvider
        self.ocrService  = ocrService
        switch llmProvider {
        case .openai: self.baseURL = AppConfig.shared.openAIBaseURL
        case .gemini: self.baseURL = AppConfig.shared.geminiBaseURL
        case .claude: self.baseURL = AppConfig.shared.claudeBaseURL
        }
    }

    // MARK: - AIService

    func extractReceipt(from image: UIImage) async throws -> AIReceiptResponse {
        // Step 1: On-device OCR
        let ocrResult = try await ocrService.recognizeText(from: image, level: .accurate)

        // Step 2: Send text to LLM
        let rawJSON = try await sendToLLM(text: ocrResult.text)
        return try parseReceiptJSON(rawJSON)
    }

    // MARK: - LLM Dispatch

    private func sendToLLM(text: String) async throws -> String {
        switch llmProvider {
        case .openai: return try await callOpenAI(text: text)
        case .gemini: return try await callGemini(text: text)
        case .claude: return try await callClaude(text: text)
        }
    }

    // MARK: - OpenAI Text Completion

    private func callOpenAI(text: String) async throws -> String {
        guard let key = try? KeychainService.load(key: .openAIAPIKey), !key.isEmpty else {
            throw AppError.missingAPIKey("OpenAI")
        }

        let body: [String: Any] = [
            "model": "gpt-4o",
            "max_tokens": 1024,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": ReceiptPrompts.ocrUserPrompt(text: text)]
            ]
        ]

        let url = baseURL.appendingPathComponent("/v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json",    forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)",        forHTTPHeaderField: "Authorization")
        request.timeoutInterval = AppConfig.shared.networkTimeoutSeconds
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AppError.httpError(code, errBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let choices = json?["choices"] as? [[String: Any]],
            let content = (choices.first?["message"] as? [String: Any])?["content"] as? String
        else { throw AppError.invalidJSONResponse("OpenAI response structure unexpected") }
        return content
    }

    // MARK: - Gemini Text Completion

    private func callGemini(text: String) async throws -> String {
        guard let key = try? KeychainService.load(key: .geminiAPIKey), !key.isEmpty else {
            throw AppError.missingAPIKey("Gemini")
        }

        let body: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": systemPrompt],
                        ["text": ReceiptPrompts.ocrUserPrompt(text: text)]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0,
                "maxOutputTokens": 1024,
                "responseMimeType": "application/json"
            ]
        ]

        var components = URLComponents(
            url: baseURL.appendingPathComponent("/v1beta/models/gemini-1.5-flash:generateContent"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "key", value: key)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = AppConfig.shared.networkTimeoutSeconds
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AppError.httpError(code, errBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let candidates = json?["candidates"] as? [[String: Any]],
            let parts       = (candidates.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]],
            let text        = parts.first?["text"] as? String
        else { throw AppError.invalidJSONResponse("Gemini response structure unexpected") }
        return text
    }

    // MARK: - Claude Text Completion

    private func callClaude(text: String) async throws -> String {
        guard let key = try? KeychainService.load(key: .claudeAPIKey), !key.isEmpty else {
            throw AppError.missingAPIKey("Claude")
        }

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": ReceiptPrompts.ocrUserPrompt(text: text)]
            ]
        ]

        let url = baseURL.appendingPathComponent("/v1/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = AppConfig.shared.networkTimeoutSeconds
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AppError.httpError(code, errBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let content = json?["content"] as? [[String: Any]],
            let text = content.first?["text"] as? String
        else { throw AppError.invalidJSONResponse("Claude response structure unexpected") }
        return text
    }
}
