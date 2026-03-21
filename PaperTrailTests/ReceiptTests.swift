import XCTest
@testable import PaperTrail

final class ReceiptTests: XCTestCase {

    // MARK: - Defaults

    func test_init_defaults() {
        let r = Receipt()
        XCTAssertEqual(r.merchant, "")
        XCTAssertEqual(r.currency, "USD")
        XCTAssertEqual(r.total, 0)
        XCTAssertEqual(r.syncStatus, .pending)
        XCTAssertFalse(r.isDuplicate)
        XCTAssertNil(r.taxAmount)
        XCTAssertNil(r.receiptNumber)
        XCTAssertNil(r.purpose)
    }

    // MARK: - Validation

    func test_validate_validReceipt_returnsEmpty() {
        let r = Receipt(merchant: "Costco", date: "2026-03-21", total: 42.50, currency: "USD")
        XCTAssertTrue(r.validate().isEmpty)
    }

    func test_validate_emptyMerchant_returnsIssue() {
        let r = Receipt(merchant: "", date: "2026-03-21", total: 10, currency: "USD")
        let issues = r.validate()
        XCTAssertTrue(issues.contains { $0.contains("Merchant") })
    }

    func test_validate_whitespaceMerchant_returnsIssue() {
        let r = Receipt(merchant: "   ", date: "2026-03-21", total: 10, currency: "USD")
        XCTAssertTrue(r.validate().contains { $0.contains("Merchant") })
    }

    func test_validate_invalidDateFormat_returnsIssue() {
        let r = Receipt(merchant: "Store", date: "03/21/2026", total: 10, currency: "USD")
        XCTAssertTrue(r.validate().contains { $0.contains("YYYY-MM-DD") })
    }

    func test_validate_validDate_noIssue() {
        let r = Receipt(merchant: "Store", date: "2026-01-15", total: 10, currency: "USD")
        XCTAssertTrue(r.validate().isEmpty)
    }

    func test_validate_zeroTotal_returnsWarning() {
        let r = Receipt(merchant: "Store", date: "2026-03-21", total: 0, currency: "USD")
        XCTAssertTrue(r.validate().contains { $0.contains("zero") })
    }

    func test_validate_negativeTotal_noIssue() {
        let r = Receipt(merchant: "Store", date: "2026-03-21", total: -5, currency: "USD")
        XCTAssertTrue(r.validate().isEmpty)
    }

    func test_validate_invalidCurrency_returnsIssue() {
        let r = Receipt(merchant: "Store", date: "2026-03-21", total: 10, currency: "US")
        XCTAssertTrue(r.validate().contains { $0.contains("3-letter") })
    }

    func test_validate_fourLetterCurrency_returnsIssue() {
        let r = Receipt(merchant: "Store", date: "2026-03-21", total: 10, currency: "USDD")
        XCTAssertTrue(r.validate().contains { $0.contains("3-letter") })
    }

    func test_validate_itemSumMismatch_returnsWarning() {
        let items = [
            ReceiptItem(name: "A", quantity: 1, price: 5.00),
            ReceiptItem(name: "B", quantity: 1, price: 3.00)
        ]
        let r = Receipt(merchant: "Store", date: "2026-03-21", total: 20.00, currency: "USD", items: items)
        XCTAssertTrue(r.validate().contains { $0.contains("doesn't match") })
    }

    func test_validate_itemSumWithinTolerance_noWarning() {
        let items = [
            ReceiptItem(name: "A", quantity: 1, price: 5.00),
            ReceiptItem(name: "B", quantity: 1, price: 5.05)
        ]
        let r = Receipt(merchant: "Store", date: "2026-03-21", total: 10.10, currency: "USD", items: items)
        XCTAssertTrue(r.validate().isEmpty)
    }

    // MARK: - Computed Total

    func test_computedTotal_emptyItems() {
        let r = Receipt()
        XCTAssertEqual(r.computedTotal, 0)
    }

    func test_computedTotal_multipleItems() {
        let items = [
            ReceiptItem(name: "A", quantity: 2, price: 3.50),
            ReceiptItem(name: "B", quantity: 1, price: 4.00)
        ]
        let r = Receipt(items: items)
        XCTAssertEqual(r.computedTotal, 11.0, accuracy: 0.01)
    }

    // MARK: - AIReceiptResponse

    func test_toReceipt_mapsAllFields() {
        let response = AIReceiptResponse(
            merchant: "Starbucks",
            date: "2026-03-21",
            total: 8.50,
            currency: "SGD",
            taxAmount: 0.60,
            receiptNumber: "SB-1234",
            purpose: "Coffee with client",
            suggestedFilename: "2026-03-21_Starbucks_8.50_SGD",
            confidenceNotes: "Clear receipt"
        )
        let r = response.toReceipt()
        XCTAssertEqual(r.merchant, "Starbucks")
        XCTAssertEqual(r.date, "2026-03-21")
        XCTAssertEqual(r.total, 8.50)
        XCTAssertEqual(r.currency, "SGD")
        XCTAssertEqual(r.taxAmount, 0.60)
        XCTAssertEqual(r.receiptNumber, "SB-1234")
        XCTAssertEqual(r.purpose, "Coffee with client")
        XCTAssertEqual(r.suggestedFilename, "2026-03-21_Starbucks_8.50_SGD")
        XCTAssertEqual(r.confidenceNotes, "Clear receipt")
    }

    func test_toReceipt_preservesExistingMetadata() {
        var existing = Receipt(id: UUID(), capturedAt: Date(), syncStatus: .synced)
        existing.category = "Food & Dining"

        let response = AIReceiptResponse(merchant: "NewMerchant", date: "2026-01-01", total: 5, currency: "USD")
        let r = response.toReceipt(preserving: existing)
        XCTAssertEqual(r.id, existing.id)
        XCTAssertEqual(r.category, "Food & Dining")
        XCTAssertEqual(r.syncStatus, .synced)
        XCTAssertEqual(r.merchant, "NewMerchant")
    }

    // MARK: - Codable Round Trip

    func test_receiptItem_codableRoundTrip() throws {
        let json = """
        {"name": "Coffee", "quantity": 2, "price": 4.50}
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(ReceiptItem.self, from: json)
        XCTAssertEqual(item.name, "Coffee")
        XCTAssertEqual(item.quantity, 2)
        XCTAssertEqual(item.price, 4.50)
        XCTAssertNotNil(item.id) // auto-generated
    }

    func test_receiptItem_missingFields_usesDefaults() throws {
        let json = "{}".data(using: .utf8)!
        let item = try JSONDecoder().decode(ReceiptItem.self, from: json)
        XCTAssertEqual(item.name, "")
        XCTAssertEqual(item.quantity, 1)
        XCTAssertEqual(item.price, 0)
    }

    func test_syncStatus_allCases() {
        XCTAssertEqual(SyncStatus.pending.rawValue, "pending")
        XCTAssertEqual(SyncStatus.uploading.rawValue, "uploading")
        XCTAssertEqual(SyncStatus.synced.rawValue, "synced")
        XCTAssertEqual(SyncStatus.failed.rawValue, "failed")
    }
}
