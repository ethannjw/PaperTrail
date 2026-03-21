// AIService.swift
// Protocol defining the contract for all AI receipt extraction providers.
// Any new provider only needs to conform to this protocol.

import Foundation
import UIKit

// MARK: - Core Protocol

/// All AI providers conform to this protocol.
protocol AIService {
    /// Extract structured receipt data from a UIImage.
    func extractReceipt(from image: UIImage) async throws -> AIReceiptResponse
    var appSettings: AppSettings? { get set }
}

extension AIService {
    /// The system prompt to use — custom if set, otherwise default.
    var systemPrompt: String {
        if let settings = appSettings {
            return ReceiptPrompts.effectiveSystemPrompt(settings: settings)
        }
        return ReceiptPrompts.defaultSystemPrompt
    }
}

// MARK: - Factory

/// Returns the correct AIService implementation based on current settings.
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

        case (.claude, .vision):
            return ClaudeVisionService()

        case (.mock, _):
            return MockAIService()

        case (.openai, .ocrPlusLLM):
            return OCRPlusLLMService(llmProvider: .openai)

        case (.gemini, .ocrPlusLLM):
            return OCRPlusLLMService(llmProvider: .gemini)

        case (.claude, .ocrPlusLLM):
            return OCRPlusLLMService(llmProvider: .claude)
        }
    }

    /// Convenience: reads from AppSettings at call time.
    static func makeCurrentService(settings: AppSettings) -> AIService {
        var service = makeService(provider: settings.aiProvider, mode: settings.processingMode)
        service.appSettings = settings
        return service
    }
}

// MARK: - Shared Prompt Templates

enum ReceiptPrompts {

    /// Returns the custom prompt if set, otherwise the default.
    static func effectiveSystemPrompt(settings: AppSettings) -> String {
        let custom = settings.customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? defaultSystemPrompt : custom
    }

    /// Default system prompt instructing the model to return strict JSON with full schema.
    static let defaultSystemPrompt = """
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
         "tax_amount": number or null,
         "receipt_number": "string or null — the receipt/invoice/transaction number printed on the receipt",
         "purpose": "concise business description of the expense",
         "suggested_filename": "YYYY-MM-DD_VENDOR_AMOUNT_CURRENCY (filesystem safe)",
         "confidence_notes": "brief note on extraction confidence or issues",
         "items": [
           {"name": "string", "quantity": number, "price": number}
         ]
       }
    3. If a field cannot be determined, use sensible defaults:
       - merchant: "Unknown"
       - date: today's date in YYYY-MM-DD
       - total: sum of items or 0
       - currency: infer from symbols ($ € £ ¥), merchant country, language, or locale hints. Default "USD" only if no clues
       - tax_amount: null if not visible
       - receipt_number: null if not visible
       - items: []
    4. price in items is the per-unit price.
    5. total includes tax and discounts.
    6. purpose should be a concise business expense description, e.g. "Team lunch with client" or "Office supplies purchase".
    7. suggested_filename format: YYYY-MM-DD_Vendor-Name_Amount_CUR — replace spaces with hyphens, remove special characters.
    8. confidence_notes: note any ambiguities, unclear text, or low-confidence extractions.
    """

    /// User prompt for vision-based extraction.
    static let visionUserPrompt = """
    Extract all receipt data from this image and return it as JSON matching \
    the schema described. Be precise with numbers and dates. \
    Infer currency from symbols if not explicitly stated.
    """

    /// User prompt for OCR text-based extraction.
    static func ocrUserPrompt(text: String) -> String {
        """
        Extract receipt data from the following OCR text and return JSON \
        matching the schema described. Be precise with numbers and dates. \
        Infer currency from symbols if not explicitly stated.

        OCR TEXT:
        \(text)
        """
    }
}

// MARK: - JSON Parsing Helpers

extension AIService {

    /// Strips markdown code fences and parses AIReceiptResponse from a JSON string.
    func parseReceiptJSON(_ raw: String) throws -> AIReceiptResponse {
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
