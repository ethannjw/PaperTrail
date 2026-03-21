// MockAIService.swift
// Returns realistic fake receipt data for development and testing.
// No API keys or network required.

import Foundation
import UIKit

final class MockAIService: AIService {

    var appSettings: AppSettings?

    func extractReceipt(from image: UIImage) async throws -> AIReceiptResponse {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_500_000_000)

        let samples: [AIReceiptResponse] = [
            AIReceiptResponse(
                merchant: "Whole Foods Market",
                date: "2026-03-20",
                total: 47.83,
                currency: "USD",
                taxAmount: 3.52,
                receiptNumber: "WF-20260320-8842",
                purpose: "Weekly grocery shopping",
                suggestedFilename: "2026-03-20_Whole-Foods-Market_47.83_USD",
                confidenceNotes: "High confidence — clear print, standard receipt layout",
                items: [
                    ReceiptItem(name: "Organic Bananas", quantity: 1, price: 2.49),
                    ReceiptItem(name: "Sourdough Bread", quantity: 1, price: 5.99),
                    ReceiptItem(name: "Chicken Breast", quantity: 2, price: 12.49),
                    ReceiptItem(name: "Almond Milk", quantity: 1, price: 4.29),
                    ReceiptItem(name: "Mixed Greens", quantity: 1, price: 6.99)
                ]
            ),
            AIReceiptResponse(
                merchant: "Uber",
                date: "2026-03-19",
                total: 23.45,
                currency: "USD",
                taxAmount: 1.88,
                receiptNumber: "UBER-9X2K4",
                purpose: "Taxi fare to airport for business trip",
                suggestedFilename: "2026-03-19_Uber_23.45_USD",
                confidenceNotes: "High confidence — digital receipt",
                items: [
                    ReceiptItem(name: "UberX ride", quantity: 1, price: 21.57)
                ]
            ),
            AIReceiptResponse(
                merchant: "Blue Bottle Coffee",
                date: "2026-03-21",
                total: 12.50,
                currency: "USD",
                taxAmount: 0.97,
                receiptNumber: nil,
                purpose: "Team coffee meeting with client",
                suggestedFilename: "2026-03-21_Blue-Bottle-Coffee_12.50_USD",
                confidenceNotes: "Medium confidence — slight shadow on total",
                items: [
                    ReceiptItem(name: "Latte", quantity: 2, price: 5.50),
                    ReceiptItem(name: "Pastry", quantity: 1, price: 4.00)
                ]
            )
        ]

        return samples.randomElement()!
    }
}
