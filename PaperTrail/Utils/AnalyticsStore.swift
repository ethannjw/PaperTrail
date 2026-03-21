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
            let (headers, rows) = try await service.fetchAllReceiptsWithHeaders()
            NSLog("[PaperTrail] Headers: %@", headers.joined(separator: " | "))
            if let firstRow = rows.first {
                NSLog("[PaperTrail] First row: %@", firstRow.map { "\($0)" }.joined(separator: " | "))
            }
            let parsed = parseRows(rows, headers: headers)
            NSLog("[PaperTrail] Parsed %d receipts. First date: '%@'", parsed.count, parsed.first?.date ?? "nil")
            receipts = parsed
            saveCache()
        } catch {
            NSLog("[PaperTrail] Fetch error: %@", error.localizedDescription)
            lastSyncError = error.localizedDescription
        }
    }

    // MARK: - Add locally (for immediate UI update before sync)

    func add(_ receipt: Receipt) {
        receipts.append(receipt)
        saveCache()
    }

    // MARK: - Parse Sheet Rows into Receipts

    // MARK: - Header-Aware Row Parsing

    private func parseRows(_ rows: [[Any]], headers: [String]) -> [Receipt] {
        // Build a column index lookup from header names (case-insensitive)
        var col: [String: Int] = [:]
        for (i, h) in headers.enumerated() {
            col[h.lowercased().trimmingCharacters(in: .whitespaces)] = i
        }

        return rows.compactMap { row in
            func str(_ key: String) -> String? {
                guard let i = col[key], let val = row[safe: i] else { return nil }
                let s = "\(val)".trimmingCharacters(in: .whitespaces)
                return s.isEmpty ? nil : s
            }
            func num(_ key: String) -> Double {
                guard let i = col[key] else { return 0 }
                return parseDouble(row[safe: i])
            }

            let merchant = str("merchant") ?? ""
            let date = normalizeDate(str("date") ?? "")
            let total = num("total")

            // Skip rows with no merchant and no total
            guard !merchant.isEmpty || total > 0 else { return nil }

            return Receipt(
                merchant: merchant,
                date: date,
                total: total,
                currency: str("currency") ?? "USD",
                taxAmount: num("tax") > 0 ? num("tax") : nil,
                receiptNumber: str("receipt number"),
                purpose: str("purpose"),
                suggestedFilename: str("suggested filename"),
                category: str("category"),
                imageDriveURL: str("image link"),
                syncStatus: .synced
            )
        }
    }

    private func parseDouble(_ value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let s = value as? String {
            // Handle currency symbols and commas: "$1,234.56" → 1234.56
            let cleaned = s.replacingOccurrences(of: "[^0-9.\\-]", with: "", options: .regularExpression)
            if let d = Double(cleaned) { return d }
        }
        return 0
    }

    /// Normalize various date formats to YYYY-MM-DD
    private func normalizeDate(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        // Already YYYY-MM-DD
        if trimmed.count == 10 && trimmed.prefix(4).allSatisfy(\.isNumber) && trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)] == "-" {
            return trimmed
        }

        // Try common date formats
        let formatters: [String] = [
            "M/d/yyyy", "MM/dd/yyyy", "d/M/yyyy", "dd/MM/yyyy",
            "MMM d, yyyy", "d MMM yyyy", "yyyy-MM-dd", "yyyy/MM/dd"
        ]
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "yyyy-MM-dd"

        for fmt in formatters {
            let df = DateFormatter()
            df.dateFormat = fmt
            df.locale = Locale(identifier: "en_US_POSIX")
            if let date = df.date(from: trimmed) {
                return outputFormatter.string(from: date)
            }
        }

        // Last resort: return as-is
        return trimmed
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
