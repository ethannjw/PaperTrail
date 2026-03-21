// AnalyticsStore.swift
// Analytics store that reads from Google Sheets as source of truth.
// Falls back to local cache when offline.

import Foundation
import Combine

final class AnalyticsStore: ObservableObject {

    @Published private(set) var receipts: [Receipt] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastSyncError: String?

    private var sheetsService: GoogleSheetsService?

    private let cacheURL: URL = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("analytics_cache.json")
    }()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        loadCache()
    }

    // MARK: - Configure (called when Google services are available)

    func configure(sheetsService: GoogleSheetsService) {
        self.sheetsService = sheetsService
    }

    // MARK: - Sync from Google Sheets

    @MainActor
    func refreshFromSheets() async {
        guard let service = sheetsService else {
            lastSyncError = "Google Sheets not configured"
            return
        }

        isLoading = true
        lastSyncError = nil
        defer { isLoading = false }

        do {
            let rows = try await service.fetchAllReceipts()
            let parsed = parseRows(rows)
            receipts = parsed
            saveCache()
        } catch {
            lastSyncError = error.localizedDescription
            // Keep existing cached data
        }
    }

    // MARK: - Add locally (for immediate UI update before sync)

    func add(_ receipt: Receipt) {
        receipts.append(receipt)
        saveCache()
    }

    // MARK: - Parse Sheet Rows into Receipts

    // Column mapping: A=Timestamp, B=Merchant, C=Date, D=Total, E=Currency,
    //   F=Tax, G=Category, H=Purpose, I=Items Count, J=Image Link,
    //   K=Suggested Filename, L=Receipt ID
    private func parseRows(_ rows: [[Any]]) -> [Receipt] {
        rows.compactMap { row in
            guard row.count >= 5 else { return nil }

            let merchant = row[safe: 1] as? String ?? ""
            let date = row[safe: 2] as? String ?? ""
            let total = parseDouble(row[safe: 3])
            let currency = row[safe: 4] as? String ?? "USD"
            let tax = parseDouble(row[safe: 5])
            let category = row[safe: 6] as? String
            let purpose = row[safe: 7] as? String
            let imageLink = row[safe: 9] as? String
            let suggestedFilename = row[safe: 10] as? String
            let idString = row[safe: 11] as? String

            return Receipt(
                id: UUID(uuidString: idString ?? "") ?? UUID(),
                merchant: merchant,
                date: date,
                total: total,
                currency: currency,
                taxAmount: tax > 0 ? tax : nil,
                purpose: (purpose?.isEmpty == true) ? nil : purpose,
                suggestedFilename: (suggestedFilename?.isEmpty == true) ? nil : suggestedFilename,
                category: (category?.isEmpty == true) ? nil : category,
                imageDriveURL: (imageLink?.isEmpty == true) ? nil : imageLink,
                syncStatus: .synced
            )
        }
    }

    private func parseDouble(_ value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let s = value as? String, let d = Double(s) { return d }
        return 0
    }

    // MARK: - Queries

    struct MonthlySummary: Identifiable {
        let id = UUID()
        let month: String        // "2025-03"
        let total: Double
        let count: Int
        let breakdown: [String: Double]  // category → total
    }

    func monthlySummaries() -> [MonthlySummary] {
        let grouped = Dictionary(grouping: receipts) { receipt -> String in
            String(receipt.date.prefix(7))
        }
        return grouped.map { month, receipts in
            let total = receipts.reduce(0) { $0 + $1.total }
            var breakdown: [String: Double] = [:]
            for r in receipts {
                let cat = r.category ?? ReceiptCategory.other.rawValue
                breakdown[cat, default: 0] += r.total
            }
            return MonthlySummary(month: month, total: total, count: receipts.count, breakdown: breakdown)
        }.sorted { $0.month > $1.month }
    }

    func topMerchants(limit: Int = 5) -> [(merchant: String, total: Double)] {
        Dictionary(grouping: receipts, by: \.merchant)
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.total }) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { ($0.0, $0.1) }
    }

    func currentMonthTotal() -> Double {
        let month = String(ISO8601DateFormatter().string(from: Date()).prefix(7))
        return receipts
            .filter { $0.date.hasPrefix(month) }
            .reduce(0) { $0 + $1.total }
    }

    // MARK: - Local Cache

    private func saveCache() {
        guard let data = try? encoder.encode(receipts) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func loadCache() {
        guard
            let data = try? Data(contentsOf: cacheURL),
            let saved = try? decoder.decode([Receipt].self, from: data)
        else { return }
        receipts = saved
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
