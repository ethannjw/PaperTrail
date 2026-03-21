// HistoryView.swift
// Searchable list of all submitted receipts with detail drill-down.

import SwiftUI

struct HistoryView: View {

    @EnvironmentObject var store:       AnalyticsStore
    @EnvironmentObject var offlineQueue: OfflineQueueManager

    @State private var searchText = ""
    @State private var selectedFilter: ReceiptCategory? = nil

    var filtered: [Receipt] {
        store.receipts.filter { receipt in
            let matchesSearch = searchText.isEmpty
                || receipt.merchant.localizedCaseInsensitiveContains(searchText)
                || receipt.date.contains(searchText)
            let matchesCategory = selectedFilter == nil
                || receipt.category == selectedFilter?.rawValue
            return matchesSearch && matchesCategory
        }
        .sorted { ($0.capturedAt) > ($1.capturedAt) }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Category filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(label: "All", isSelected: selectedFilter == nil) {
                            selectedFilter = nil
                        }
                        ForEach(ReceiptCategory.allCases, id: \.self) { cat in
                            FilterChip(label: cat.rawValue, isSelected: selectedFilter == cat) {
                                selectedFilter = (selectedFilter == cat) ? nil : cat
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                // Offline queue banner
                if !offlineQueue.queuedReceipts.isEmpty {
                    HStack {
                        Image(systemName: "wifi.slash")
                        Text("\(offlineQueue.queuedReceipts.count) receipt(s) pending upload")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.15))
                }

                List {
                    ForEach(filtered) { receipt in
                        NavigationLink(destination: ReceiptDetailView(receipt: receipt)) {
                            ReceiptRow(receipt: receipt)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "Search merchant or date")
            }
            .navigationTitle("History")
        }
    }
}

// MARK: - Receipt Row

private struct ReceiptRow: View {
    let receipt: Receipt

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: categoryIcon)
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(receipt.merchant.isEmpty ? "Unknown" : receipt.merchant)
                        .font(.headline)
                        .lineLimit(1)
                    if receipt.isDuplicate {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                Text(receipt.date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let cat = receipt.category {
                    Text(cat)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                        .foregroundColor(.accentColor)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%.2f", receipt.total))
                    .font(.headline.monospacedDigit())
                Text(receipt.currency)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var categoryIcon: String {
        switch receipt.category {
        case ReceiptCategory.food.rawValue:          return "fork.knife"
        case ReceiptCategory.transport.rawValue:     return "car.fill"
        case ReceiptCategory.shopping.rawValue:      return "bag.fill"
        case ReceiptCategory.health.rawValue:        return "cross.fill"
        case ReceiptCategory.utilities.rawValue:     return "bolt.fill"
        case ReceiptCategory.entertainment.rawValue: return "popcorn.fill"
        case ReceiptCategory.travel.rawValue:        return "airplane"
        default:                                      return "doc.text.fill"
        }
    }
}

// MARK: - Receipt Detail View

struct ReceiptDetailView: View {
    let receipt: Receipt

    var body: some View {
        Form {
            Section("Merchant") {
                LabeledContent("Name",     value: receipt.merchant)
                LabeledContent("Date",     value: receipt.date)
                LabeledContent("Category", value: receipt.category ?? "–")
            }

            Section("Amount") {
                LabeledContent("Total",    value: String(format: "%.2f %@", receipt.total, receipt.currency))
                LabeledContent("Items",    value: "\(receipt.items.count)")
            }

            if !receipt.items.isEmpty {
                Section("Line Items") {
                    ForEach(receipt.items) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text("\(Int(item.quantity))×")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text(String(format: "%.2f", item.price))
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section("Links") {
                if let link = receipt.imageDriveURL, let url = URL(string: link) {
                    Link("View in Google Drive", destination: url)
                }
                LabeledContent("Receipt ID", value: receipt.id.uuidString.prefix(8).description)
            }

            if receipt.isDuplicate {
                Section {
                    Label("Possible duplicate detected", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
            }
        }
        .navigationTitle(receipt.merchant.isEmpty ? "Receipt" : receipt.merchant)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15),
                            in: Capsule())
                .foregroundColor(isSelected ? .white : .primary)
        }
    }
}
