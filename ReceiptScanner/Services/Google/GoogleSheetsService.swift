// GoogleSheetsService.swift
// Appends receipt rows to a Google Spreadsheet using Sheets REST API v4.
// Creates the header row on first use if the sheet is empty.

import Foundation

final class GoogleSheetsService {

    private let authService: GoogleAuthService
    private let spreadsheetID: String
    private let sheetName = "Receipts"

    init(authService: GoogleAuthService) {
        self.authService   = authService
        self.spreadsheetID = AppConfig.shared.googleSpreadsheetID
    }

    // MARK: - Column Headers
    private static let headers = [
        "Timestamp", "Merchant", "Date", "Total", "Currency",
        "Category", "Items Count", "Image Link", "Receipt ID"
    ]

    // MARK: - Public API

    /// Append a receipt row to the spreadsheet.
    /// Ensures header row exists on first call.
    func appendReceipt(_ receipt: Receipt) async throws {
        let token = try await authService.validAccessToken()
        try await ensureHeaderRow(token: token)
        try await appendRow(for: receipt, token: token)
    }

    // MARK: - Row Construction

    private func buildRow(for receipt: Receipt) -> [Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        return [
            formatter.string(from: receipt.submittedAt ?? Date()),
            receipt.merchant,
            receipt.date,
            receipt.total,
            receipt.currency,
            receipt.category ?? "",
            receipt.items.count,
            receipt.imageDriveURL ?? "",
            receipt.id.uuidString
        ]
    }

    // MARK: - Sheets API Requests

    /// Checks if A1 has content; if not, writes header row.
    private func ensureHeaderRow(token: String) async throws {
        let range = "\(sheetName)!A1"
        let getURL = URL(
            string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values/\(range)"
        )!

        var getReq = URLRequest(url: getURL)
        getReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: getReq)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let values = json?["values"] as? [[Any]]

        if values?.first?.isEmpty ?? true || values == nil {
            try await writeRow(
                Self.headers.map { $0 as Any },
                range: "\(sheetName)!A1",
                token: token
            )
        }
    }

    private func appendRow(for receipt: Receipt, token: String) async throws {
        let range = "\(sheetName)!A:I"
        let url = URL(
            string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values/\(range):append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS"
        )!

        let body: [String: Any] = [
            "majorDimension": "ROWS",
            "values": [buildRow(for: receipt)]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)",  forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = AppConfig.shared.networkTimeoutSeconds

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AppError.googleSheetsWriteFailed("Non-HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            throw AppError.googleSheetsWriteFailed("HTTP \(http.statusCode): \(errBody)")
        }
    }

    private func writeRow(_ values: [Any], range: String, token: String) async throws {
        let url = URL(
            string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values/\(range)?valueInputOption=RAW"
        )!
        let body: [String: Any] = [
            "majorDimension": "ROWS",
            "values": [values]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)",  forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AppError.googleSheetsWriteFailed("Header write failed: \(code) \(errBody)")
        }
    }

    // MARK: - Analytics: Monthly Summary

    /// Fetch all rows for local aggregation.
    func fetchAllReceipts() async throws -> [[Any]] {
        let token = try await authService.validAccessToken()
        let range = "\(sheetName)!A2:I"
        let url = URL(
            string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values/\(range)"
        )!

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.googleSheetsWriteFailed("Fetch failed")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["values"] as? [[Any]] ?? []
    }
}
