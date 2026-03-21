// AIService.swift
// Protocol defining the contract for all AI receipt extraction providers.
// Any new provider (e.g. Claude, Azure OpenAI) only needs to conform to this.

import Foundation
import UIKit

// MARK: - Core Protocol

/// All AI providers conform to this protocol.
protocol AIService {
    /// Extract structured receipt data from a UIImage.
    /// - Parameter image: The captured receipt image.
    /// - Returns: A fully parsed AIReceiptResponse.
    func extractReceipt(from image: UIImage) async throws -> AIReceiptResponse
}

// MARK: - Factory

/// Returns the correct AIService implementation based on current AppConfig.
enum AIServiceFactory {

    static func makeService(
        provider: AppConfig.AIProvider,
        mode: AppConfig.ProcessingMode
    ) -> AIService {
        switch (provider, mode) {
        case (.openai, .vision):
            return OpenAIVisionService()

        case (.gemini, .vision):
            return GeminiVisionService()

        case (.openai, .ocrPlusLLM):
            return OCRPlusLLMService(llmProvider: .openai)

        case (.gemini, .ocrPlusLLM):
            return OCRPlusLLMService(llmProvider: .gemini)
        }
    }

    /// Convenience: reads from AppSettings at call time.
    static func makeCurrentService(settings: AppSettings) -> AIService {
        makeService(provider: settings.aiProvider, mode: settings.processingMode)
    }
}

// MARK: - Shared Prompt Templates

enum ReceiptPrompts {

    /// System prompt instructing the model to return strict JSON.
    static let systemPrompt = """
    You are a receipt OCR assistant. Your only task is to extract structured data \
    from receipt images or text and return it as valid JSON.

    CRITICAL RULES:
    1. Return ONLY valid JSON — no markdown fences, no prose, no explanations.
    2. Use exactly this schema:
       {
         "merchant": "string",
         "date": "YYYY-MM-DD",
         "total": number,
         "currency": "3-letter ISO code",
         "items": [
           {"name": "string", "quantity": number, "price": number}
         ]
       }
    3. If a field cannot be determined, use sensible defaults:
       - merchant: "Unknown"
       - date: today's date in YYYY-MM-DD
       - total: sum of items or 0
       - currency: "USD"
       - items: []
    4. price in items is the per-unit price.
    5. total includes tax and discounts.
    """

    /// User prompt for vision-based extraction.
    static let visionUserPrompt = """
    Extract all receipt data from this image and return it as JSON matching \
    the schema described. Be precise with numbers and dates.
    """

    /// User prompt for OCR text-based extraction.
    static func ocrUserPrompt(text: String) -> String {
        """
        Extract receipt data from the following OCR text and return JSON \
        matching the schema described. Be precise with numbers and dates.

        OCR TEXT:
        \(text)
        """
    }
}

// MARK: - JSON Parsing Helpers

extension AIService {

    /// Strips markdown code fences and parses AIReceiptResponse from a JSON string.
    func parseReceiptJSON(_ raw: String) throws -> AIReceiptResponse {
        // Strip potential ```json ... ``` wrappers
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```") {
            clean = clean
                .components(separatedBy: "\n")
                .dropFirst()
                .dropLast()
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = clean.data(using: .utf8) else {
            throw AppError.invalidJSONResponse("Could not encode response as UTF-8")
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(AIReceiptResponse.self, from: data)
        } catch {
            throw AppError.invalidJSONResponse(
                "JSON parse error: \(error.localizedDescription). Raw: \(clean.prefix(200))"
            )
        }
    }
}
