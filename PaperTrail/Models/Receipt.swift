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

    // AI-extracted enrichment fields
    var taxAmount: Double?
    var receiptNumber: String?
    var purpose: String?
    var suggestedFilename: String?
    var confidenceNotes: String?

    // App-managed metadata
    var category: String?
    var imageLocalURL: URL?
    var pdfLocalURL: URL?
    var imageDriveURL: String?
    var capturedAt: Date
    var submittedAt: Date?
    var isDuplicate: Bool
    var syncStatus: SyncStatus

    // MARK: - Init
    init(
        id: UUID = UUID(),
        merchant: String = "",
        date: String = "",
        total: Double = 0,
        currency: String = "USD",
        items: [ReceiptItem] = [],
        taxAmount: Double? = nil,
        receiptNumber: String? = nil,
        purpose: String? = nil,
        suggestedFilename: String? = nil,
        confidenceNotes: String? = nil,
        category: String? = nil,
        imageLocalURL: URL? = nil,
        pdfLocalURL: URL? = nil,
        imageDriveURL: String? = nil,
        capturedAt: Date = Date(),
        submittedAt: Date? = nil,
        isDuplicate: Bool = false,
        syncStatus: SyncStatus = .pending
    ) {
        self.id                = id
        self.merchant          = merchant
        self.date              = date
        self.total             = total
        self.currency          = currency
        self.items             = items
        self.taxAmount         = taxAmount
        self.receiptNumber     = receiptNumber
        self.purpose           = purpose
        self.suggestedFilename = suggestedFilename
        self.confidenceNotes   = confidenceNotes
        self.category          = category
        self.imageLocalURL     = imageLocalURL
        self.pdfLocalURL       = pdfLocalURL
        self.imageDriveURL     = imageDriveURL
        self.capturedAt        = capturedAt
        self.submittedAt       = submittedAt
        self.isDuplicate       = isDuplicate
        self.syncStatus        = syncStatus
    }
}

// MARK: - Sync Status

enum SyncStatus: String, Codable, Equatable {
    case pending
    case uploading
    case synced
    case failed
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
    let taxAmount: Double?
    let receiptNumber: String?
    let purpose: String?
    let suggestedFilename: String?
    let confidenceNotes: String?
    let items: [ReceiptItem]

    enum CodingKeys: String, CodingKey {
        case merchant, date, total, currency, items
        case taxAmount = "tax_amount"
        case receiptNumber = "receipt_number"
        case purpose
        case suggestedFilename = "suggested_filename"
        case confidenceNotes = "confidence_notes"
    }

    init(
        merchant: String, date: String, total: Double, currency: String,
        taxAmount: Double? = nil, receiptNumber: String? = nil, purpose: String? = nil,
        suggestedFilename: String? = nil, confidenceNotes: String? = nil,
        items: [ReceiptItem] = []
    ) {
        self.merchant = merchant; self.date = date; self.total = total
        self.currency = currency; self.taxAmount = taxAmount
        self.receiptNumber = receiptNumber; self.purpose = purpose; self.suggestedFilename = suggestedFilename
        self.confidenceNotes = confidenceNotes; self.items = items
    }

    /// Convert to a full Receipt model, preserving app metadata.
    func toReceipt(preserving existing: Receipt? = nil) -> Receipt {
        var r = existing ?? Receipt()
        r.merchant          = merchant
        r.date              = date
        r.total             = total
        r.currency          = currency
        r.items             = items
        r.taxAmount         = taxAmount
        r.receiptNumber     = receiptNumber
        r.purpose           = purpose
        r.suggestedFilename = suggestedFilename
        r.confidenceNotes   = confidenceNotes
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
