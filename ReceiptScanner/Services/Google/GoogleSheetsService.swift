// GoogleSheetsService.swift
// Appends receipt rows to a Google Spreadsheet using Sheets REST API v4.
// Resolves spreadsheet by name (searching Drive), creates if needed.

import Foundation

final class GoogleSheetsService {

    private let authService: GoogleAuthService
    private let appSettings: AppSettings
    // Resolved at runtime from the first sheet tab
    private var sheetName: String?

    // Cache resolved spreadsheet ID
    private var resolvedSpreadsheetID: String?

    init(authService: GoogleAuthService, appSettings: AppSettings) {
        self.authService = authService
        self.appSettings = appSettings
    }

    // MARK: - Column Headers
    private static let headers = [
        "Timestamp", "Merchant", "Date", "Total", "Currency",
        "Tax", "Category", "Purpose", "Items Count",
        "Image Link", "Suggested Filename", "Receipt Number"
    ]

    // MARK: - Public API

    func appendReceipt(_ receipt: Receipt) async throws {
        let token = try await authService.validAccessToken()
        let ssID = try await resolveSpreadsheetID(token: token)
        let tab = try await resolveSheetTab(spreadsheetID: ssID, token: token)
        try await ensureHeaderRow(spreadsheetID: ssID, sheetTab: tab, token: token)
        try await appendRow(for: receipt, spreadsheetID: ssID, sheetTab: tab, token: token)
    }

    func fetchAllReceipts() async throws -> [[Any]] {
        let token = try await authService.validAccessToken()
        let ssID = try await resolveSpreadsheetID(token: token)
        let tab = try await resolveSheetTab(spreadsheetID: ssID, token: token)
        let range = "\(tab)!A2:L"
        let url = URL(
            string: "https://sheets.googleapis.com/v4/spreadsheets/\(ssID)/values/\(range)"
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

    // MARK: - Spreadsheet Resolution

    private func resolveSpreadsheetID(token: String) async throws -> String {
        let input = appSettings.googleSpreadsheetID.trimmingCharacters(in: .whitespaces)

        guard !input.isEmpty else {
            throw AppError.googleSheetsWriteFailed("No spreadsheet configured. Select one in Settings. (ID: '\(input)', Name: '\(appSettings.googleSpreadsheetName)')")
        }

        // If a display name is set, the ID was picked from the selector — use directly
        if !appSettings.googleSpreadsheetName.isEmpty {
            return input
        }

        // If no spaces and reasonably long, treat as an ID
        if !input.contains(" ") && input.count > 10 {
            return input
        }

        // Check cache
        if let cached = resolvedSpreadsheetID { return cached }

        // Search Drive for a spreadsheet with this name
        if let existingID = try await findSpreadsheet(named: input, token: token) {
            resolvedSpreadsheetID = existingID
            return existingID
        }

        // Create a new spreadsheet
        let newID = try await createSpreadsheet(named: input, token: token)
        resolvedSpreadsheetID = newID
        return newID
    }

    private func findSpreadsheet(named name: String, token: String) async throws -> String? {
        let query = "name='\(name)' and mimeType='application/vnd.google-apps.spreadsheet' and trashed=false"
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "pageSize", value: "1")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [[String: Any]]
        return files?.first?["id"] as? String
    }

    private func createSpreadsheet(named name: String, token: String) async throws -> String {
        let body: [String: Any] = [
            "properties": ["title": name],
            "sheets": [
                ["properties": ["title": sheetName]]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://sheets.googleapis.com/v4/spreadsheets")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            throw AppError.googleSheetsWriteFailed("Failed to create spreadsheet: \(errBody)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = json?["spreadsheetId"] as? String else {
            throw AppError.googleSheetsWriteFailed("No spreadsheet ID in create response")
        }
        return id
    }

    // MARK: - Resolve First Sheet Tab Name

    private func resolveSheetTab(spreadsheetID: String, token: String) async throws -> String {
        if let cached = sheetName { return cached }

        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)?fields=sheets.properties.title")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AppError.googleSheetsWriteFailed("Failed to read spreadsheet: \(body)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let sheets = json?["sheets"] as? [[String: Any]] ?? []
        guard let firstTitle = sheets.first.flatMap({ ($0["properties"] as? [String: Any])?["title"] as? String }) else {
            throw AppError.googleSheetsWriteFailed("Spreadsheet has no sheets")
        }

        sheetName = firstTitle
        return firstTitle
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
            receipt.taxAmount ?? 0,
            receipt.category ?? "",
            receipt.purpose ?? "",
            receipt.items.count,
            receipt.imageDriveURL ?? "",
            receipt.suggestedFilename ?? "",
            receipt.receiptNumber ?? ""
        ]
    }

    // MARK: - Sheets API Requests

    private func ensureHeaderRow(spreadsheetID: String, sheetTab: String, token: String) async throws {
        let range = "\(sheetTab)!A1"
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
                range: "\(sheetTab)!A1",
                spreadsheetID: spreadsheetID,
                token: token
            )
        }
    }

    private func appendRow(for receipt: Receipt, spreadsheetID: String, sheetTab: String, token: String) async throws {
        let range = "\(sheetTab)!A:L"
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

    private func writeRow(_ values: [Any], range: String, spreadsheetID: String, token: String) async throws {
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
}
