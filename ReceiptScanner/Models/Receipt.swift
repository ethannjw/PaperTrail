// Receipt.swift
// Core domain model. This is the canonical data structure throughout the app.
// Must match the JSON schema produced by every AI provider.

import Foundation

// MARK: - Receipt

struct Receipt: Identifiable, Codable, Equatable {
    var id: UUID
    var merchant: String
    var date: String          // YYYY-MM-DD
    var total: Double
    var currency: String
    var items: [ReceiptItem]

    // App-managed metadata (not returned by AI)
    var category: String?
    var imageLocalURL: URL?
    var imageDriveURL: String?
    var capturedAt: Date
    var submittedAt: Date?
    var isDuplicate: Bool

    // MARK: - Init
    init(
        id: UUID = UUID(),
        merchant: String = "",
        date: String = "",
        total: Double = 0,
        currency: String = "USD",
        items: [ReceiptItem] = [],
        category: String? = nil,
        imageLocalURL: URL? = nil,
        imageDriveURL: String? = nil,
        capturedAt: Date = Date(),
        submittedAt: Date? = nil,
        isDuplicate: Bool = false
    ) {
        self.id             = id
        self.merchant       = merchant
        self.date           = date
        self.total          = total
        self.currency       = currency
        self.items          = items
        self.category       = category
        self.imageLocalURL  = imageLocalURL
        self.imageDriveURL  = imageDriveURL
        self.capturedAt     = capturedAt
        self.submittedAt    = submittedAt
        self.isDuplicate    = isDuplicate
    }

    // MARK: - Coding keys (only encode AI-facing fields for API payloads)
    enum CodingKeys: String, CodingKey {
        case id, merchant, date, total, currency, items
        case category, imageLocalURL, imageDriveURL
        case capturedAt, submittedAt, isDuplicate
    }
}

// MARK: - ReceiptItem

struct ReceiptItem: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var quantity: Double
    var price: Double

    init(id: UUID = UUID(), name: String = "", quantity: Double = 1, price: Double = 0) {
        self.id       = id
        self.name     = name
        self.quantity = quantity
        self.price    = price
    }

    // Only name/quantity/price map to the AI JSON schema
    enum CodingKeys: String, CodingKey {
        case name, quantity, price
        // id is excluded from Codable so it's auto-generated on decode
    }

    init(from decoder: Decoder) throws {
        let c   = try decoder.container(keyedBy: CodingKeys.self)
        self.id       = UUID()
        self.name     = try c.decodeIfPresent(String.self, forKey: .name)     ?? ""
        self.quantity = try c.decodeIfPresent(Double.self,  forKey: .quantity) ?? 1
        self.price    = try c.decodeIfPresent(Double.self,  forKey: .price)    ?? 0
    }
}

// MARK: - AI Response Envelope
// This is the strict JSON schema every AI provider must return.

struct AIReceiptResponse: Decodable {
    let merchant: String
    let date: String
    let total: Double
    let currency: String
    let items: [ReceiptItem]

    /// Convert to a full Receipt model, preserving app metadata.
    func toReceipt(preserving existing: Receipt? = nil) -> Receipt {
        var r = existing ?? Receipt()
        r.merchant = merchant
        r.date     = date
        r.total    = total
        r.currency = currency
        r.items    = items
        return r
    }
}

// MARK: - Validation

extension Receipt {
    struct ValidationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    var computedTotal: Double {
        items.reduce(0) { $0 + ($1.price * $1.quantity) }
    }

    /// Returns nil if valid, or a list of issues.
    func validate() -> [String] {
        var issues: [String] = []

        if merchant.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("Merchant name is required.")
        }

        // Date must be YYYY-MM-DD
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if formatter.date(from: date) == nil {
            issues.append("Date '\(date)' is not in YYYY-MM-DD format.")
        }

        if total <= 0 {
            issues.append("Total must be greater than zero.")
        }

        if currency.count != 3 {
            issues.append("Currency must be a 3-letter ISO code (e.g. USD).")
        }

        let roundedComputed = (computedTotal * 100).rounded() / 100
        let roundedTotal    = (total        * 100).rounded() / 100
        if !items.isEmpty && abs(roundedComputed - roundedTotal) > 0.10 {
            issues.append(
                "Items sum (\(String(format: "%.2f", computedTotal))) "
              + "doesn't match total (\(String(format: "%.2f", total))). "
              + "Check for tax or discounts."
            )
        }

        return issues
    }
}

// MARK: - Category

enum ReceiptCategory: String, CaseIterable, Codable {
    case food        = "Food & Dining"
    case transport   = "Transport"
    case shopping    = "Shopping"
    case health      = "Health & Medical"
    case utilities   = "Utilities"
    case entertainment = "Entertainment"
    case travel      = "Travel"
    case other       = "Other"
}
