import XCTest
@testable import ReceiptPilot

final class AIServiceTests: XCTestCase {

    // Use MockAIService to access the parseReceiptJSON extension
    private var service: MockAIService!

    override func setUp() {
        service = MockAIService()
    }

    // MARK: - JSON Parsing

    func test_parseReceiptJSON_validJSON() throws {
        let json = """
        {
            "merchant": "Target",
            "date": "2026-03-20",
            "total": 54.32,
            "currency": "USD",
            "tax_amount": 4.12,
            "receipt_number": "TGT-99281",
            "purpose": "Household supplies",
            "suggested_filename": "2026-03-20_Target_54.32_USD",
            "confidence_notes": "Clear print",
            "items": [
                {"name": "Paper Towels", "quantity": 2, "price": 8.99},
                {"name": "Dish Soap", "quantity": 1, "price": 3.49}
            ]
        }
        """
        let result = try service.parseReceiptJSON(json)
        XCTAssertEqual(result.merchant, "Target")
        XCTAssertEqual(result.date, "2026-03-20")
        XCTAssertEqual(result.total, 54.32)
        XCTAssertEqual(result.currency, "USD")
        XCTAssertEqual(result.taxAmount, 4.12)
        XCTAssertEqual(result.receiptNumber, "TGT-99281")
        XCTAssertEqual(result.purpose, "Household supplies")
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items[0].name, "Paper Towels")
        XCTAssertEqual(result.items[0].quantity, 2)
    }

    func test_parseReceiptJSON_stripsMarkdownFences() throws {
        let json = """
        ```json
        {"merchant": "Cafe", "date": "2026-01-01", "total": 5, "currency": "USD", "items": []}
        ```
        """
        let result = try service.parseReceiptJSON(json)
        XCTAssertEqual(result.merchant, "Cafe")
    }

    func test_parseReceiptJSON_minimalFields() throws {
        let json = """
        {"merchant": "X", "date": "2026-01-01", "total": 1, "currency": "USD", "items": []}
        """
        let result = try service.parseReceiptJSON(json)
        XCTAssertEqual(result.merchant, "X")
        XCTAssertNil(result.taxAmount)
        XCTAssertNil(result.receiptNumber)
        XCTAssertNil(result.purpose)
        XCTAssertNil(result.suggestedFilename)
        XCTAssertNil(result.confidenceNotes)
    }

    func test_parseReceiptJSON_invalidJSON_throws() {
        XCTAssertThrowsError(try service.parseReceiptJSON("not json")) { error in
            XCTAssertTrue(error is AppError)
        }
    }

    func test_parseReceiptJSON_emptyString_throws() {
        XCTAssertThrowsError(try service.parseReceiptJSON(""))
    }

    func test_parseReceiptJSON_nullOptionalFields() throws {
        let json = """
        {
            "merchant": "Store",
            "date": "2026-06-15",
            "total": 10.00,
            "currency": "EUR",
            "tax_amount": null,
            "receipt_number": null,
            "purpose": null,
            "suggested_filename": null,
            "confidence_notes": null,
            "items": []
        }
        """
        let result = try service.parseReceiptJSON(json)
        XCTAssertEqual(result.merchant, "Store")
        XCTAssertEqual(result.currency, "EUR")
        XCTAssertNil(result.taxAmount)
        XCTAssertNil(result.receiptNumber)
    }

    // MARK: - Prompt Templates

    func test_defaultSystemPrompt_containsSchema() {
        let prompt = ReceiptPrompts.defaultSystemPrompt
        XCTAssertTrue(prompt.contains("merchant"))
        XCTAssertTrue(prompt.contains("receipt_number"))
        XCTAssertTrue(prompt.contains("tax_amount"))
        XCTAssertTrue(prompt.contains("purpose"))
        XCTAssertTrue(prompt.contains("suggested_filename"))
        XCTAssertTrue(prompt.contains("confidence_notes"))
        XCTAssertTrue(prompt.contains("JSON"))
    }

    func test_ocrUserPrompt_containsText() {
        let prompt = ReceiptPrompts.ocrUserPrompt(text: "HELLO WORLD")
        XCTAssertTrue(prompt.contains("HELLO WORLD"))
        XCTAssertTrue(prompt.contains("OCR TEXT"))
    }

    func test_effectiveSystemPrompt_usesDefault_whenEmpty() {
        let settings = AppSettings()
        settings.customSystemPrompt = ""
        let prompt = ReceiptPrompts.effectiveSystemPrompt(settings: settings)
        XCTAssertEqual(prompt, ReceiptPrompts.defaultSystemPrompt)
    }

    func test_effectiveSystemPrompt_usesCustom_whenSet() {
        let settings = AppSettings()
        settings.customSystemPrompt = "My custom prompt"
        let prompt = ReceiptPrompts.effectiveSystemPrompt(settings: settings)
        XCTAssertEqual(prompt, "My custom prompt")
    }
}
