import XCTest
@testable import PaperTrail

final class AnalyticsStoreTests: XCTestCase {

    private var store: AnalyticsStore!

    override func setUp() {
        store = AnalyticsStore()
        // Clear any cached data from previous runs
        let cacheURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("analytics_cache.json")
        try? FileManager.default.removeItem(at: cacheURL)
        // Re-create with clean state
        store = AnalyticsStore()
    }

    // MARK: - Add & Query

    func test_add_incrementsCount() {
        let r = Receipt(merchant: "Store", date: "2026-03-21", total: 10, currency: "USD")
        store.add(r)
        XCTAssertEqual(store.receipts.count, 1)
    }

    func test_monthlySummaries_groupsByMonth() {
        store.add(Receipt(merchant: "A", date: "2026-03-01", total: 10, currency: "USD"))
        store.add(Receipt(merchant: "B", date: "2026-03-15", total: 20, currency: "USD"))
        store.add(Receipt(merchant: "C", date: "2026-02-01", total: 5, currency: "USD"))

        let summaries = store.monthlySummaries()
        XCTAssertEqual(summaries.count, 2)

        let march = summaries.first { $0.month == "2026-03" }
        XCTAssertNotNil(march)
        XCTAssertEqual(march?.total ?? 0, 30.0, accuracy: 0.01)
        XCTAssertEqual(march?.count, 2)
    }

    func test_monthlySummaries_categoryBreakdown() {
        store.add(Receipt(merchant: "A", date: "2026-03-01", total: 10, currency: "USD", category: "Food & Dining"))
        store.add(Receipt(merchant: "B", date: "2026-03-02", total: 20, currency: "USD", category: "Transport"))
        store.add(Receipt(merchant: "C", date: "2026-03-03", total: 5, currency: "USD", category: "Food & Dining"))

        let summaries = store.monthlySummaries()
        let march = summaries.first { $0.month == "2026-03" }!
        XCTAssertEqual(march.breakdown["Food & Dining"] ?? 0, 15.0, accuracy: 0.01)
        XCTAssertEqual(march.breakdown["Transport"] ?? 0, 20.0, accuracy: 0.01)
    }

    func test_topMerchants_sortedByTotal() {
        store.add(Receipt(merchant: "Small", date: "2026-03-01", total: 5, currency: "USD"))
        store.add(Receipt(merchant: "Big", date: "2026-03-01", total: 100, currency: "USD"))
        store.add(Receipt(merchant: "Medium", date: "2026-03-01", total: 50, currency: "USD"))

        let top = store.topMerchants(limit: 2)
        XCTAssertEqual(top.count, 2)
        XCTAssertEqual(top[0].merchant, "Big")
        XCTAssertEqual(top[1].merchant, "Medium")
    }

    func test_topMerchants_aggregatesSameMerchant() {
        store.add(Receipt(merchant: "Starbucks", date: "2026-03-01", total: 5, currency: "USD"))
        store.add(Receipt(merchant: "Starbucks", date: "2026-03-02", total: 6, currency: "USD"))

        let top = store.topMerchants(limit: 5)
        let starbucks = top.first { $0.merchant == "Starbucks" }
        XCTAssertNotNil(starbucks)
        XCTAssertEqual(starbucks?.total ?? 0, 11.0, accuracy: 0.01)
    }

    func test_currentMonthTotal() {
        let thisMonth = String(ISO8601DateFormatter().string(from: Date()).prefix(7))
        store.add(Receipt(merchant: "A", date: "\(thisMonth)-01", total: 25, currency: "USD"))
        store.add(Receipt(merchant: "B", date: "\(thisMonth)-15", total: 30, currency: "USD"))
        store.add(Receipt(merchant: "C", date: "2020-01-01", total: 999, currency: "USD"))

        XCTAssertEqual(store.currentMonthTotal(), 55.0, accuracy: 0.01)
    }

    // MARK: - Empty State

    func test_monthlySummaries_empty() {
        XCTAssertTrue(store.monthlySummaries().isEmpty)
    }

    func test_topMerchants_empty() {
        XCTAssertTrue(store.topMerchants().isEmpty)
    }

    func test_currentMonthTotal_empty() {
        XCTAssertEqual(store.currentMonthTotal(), 0)
    }
}
