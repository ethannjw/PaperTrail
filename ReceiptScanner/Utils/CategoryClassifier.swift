// CategoryClassifier.swift
// Lightweight AI-powered (or keyword-based) receipt category classification.
// Uses keyword matching as fast on-device fallback; LLM if keys are available.

import Foundation

enum CategoryClassifier {

    // MARK: - Public

    static func classify(merchant: String, items: [ReceiptItem]) async -> String {
        let combined = ([merchant] + items.map(\.name))
            .joined(separator: " ")
            .lowercased()

        // Fast on-device keyword matching
        if let category = keywordMatch(text: combined) {
            return category
        }
        return ReceiptCategory.other.rawValue
    }

    // MARK: - Keyword Rules

    private static let rules: [(keywords: [String], category: ReceiptCategory)] = [
        (["restaurant", "cafe", "coffee", "mcdonald", "subway", "pizza", "burger",
          "sushi", "ramen", "bistro", "grill", "diner", "bakery", "food", "drink",
          "tea", "boba", "hawker", "kopitiam"],
         .food),
        (["grab", "uber", "taxi", "mrt", "bus", "esso", "shell", "caltex",
          "petrol", "fuel", "parking", "transport", "transit", "ezlink"],
         .transport),
        (["amazon", "shopee", "lazada", "apple", "samsung", "ikea", "uniqlo",
          "zara", "h&m", "best denki", "courts", "challenger", "ntuc", "fairprice",
          "cold storage", "giant", "supermarket", "convenience"],
         .shopping),
        (["guardian", "watsons", "pharmacy", "clinic", "hospital", "dental",
          "doctor", "medical", "health", "polyclinic", "gp"],
         .health),
        (["singtel", "starhub", "m1", "electric", "utilities", "water board",
          "internet", "broadband", "sp services", "telco"],
         .utilities),
        (["cinema", "netflix", "spotify", "steam", "movie", "concert",
          "museum", "zoo", "attractions", "games", "entertainment"],
         .entertainment),
        (["hotel", "airbnb", "booking", "flight", "changi", "airport",
          "singapore airlines", "scoot", "jetstar", "klook", "travel"],
         .travel)
    ]

    private static func keywordMatch(text: String) -> String? {
        for rule in rules {
            if rule.keywords.contains(where: { text.contains($0) }) {
                return rule.category.rawValue
            }
        }
        return nil
    }
}
