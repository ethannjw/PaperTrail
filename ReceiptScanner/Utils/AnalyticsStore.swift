// AnalyticsStore.swift
// Local analytics store for the monthly spending dashboard.
// Persists submitted receipts in Documents/analytics.json.

import Foundation
import Combine

final class AnalyticsStore: ObservableObject {

    @Published private(set) var receipts: [Receipt] = []

    private let storeURL: URL = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("analytics.json")
    }()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() { load() }

    // MARK: - Write

    func add(_ receipt: Receipt) {
        receipts.append(receipt)
        save()
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
            String(receipt.date.prefix(7)) // "YYYY-MM"
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

    // MARK: - Persistence

    private func save() {
        guard let data = try? encoder.encode(receipts) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: storeURL),
            let saved = try? decoder.decode([Receipt].self, from: data)
        else { return }
        receipts = saved
    }
}
