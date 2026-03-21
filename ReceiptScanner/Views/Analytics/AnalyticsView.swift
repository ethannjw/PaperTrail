// AnalyticsView.swift
// Monthly spending dashboard with bar chart, top merchants, and category breakdown.

import SwiftUI
import Charts

struct AnalyticsView: View {

    @EnvironmentObject var store: AnalyticsStore

    private var summaries: [AnalyticsStore.MonthlySummary] {
        store.monthlySummaries()
    }
    private var topMerchants: [(merchant: String, total: Double)] {
        store.topMerchants(limit: 5)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - This Month KPI
                    KPICard(
                        title: "This Month",
                        value: String(format: "$%.2f", store.currentMonthTotal()),
                        subtitle: "\(currentMonthCount) receipts"
                    )
                    .padding(.horizontal)

                    // MARK: - Monthly Bar Chart
                    if !summaries.isEmpty {
                        GroupBox("Monthly Spending") {
                            Chart(summaries.prefix(6), id: \.month) { s in
                                BarMark(
                                    x: .value("Month", s.month),
                                    y: .value("Total", s.total)
                                )
                                .foregroundStyle(Color.accentColor.gradient)
                                .cornerRadius(4)
                            }
                            .frame(height: 200)
                            .padding(.top, 8)
                        }
                        .padding(.horizontal)
                    }

                    // MARK: - Category Breakdown (current month)
                    if let currentSummary = summaries.first {
                        GroupBox("Category Breakdown") {
                            ForEach(
                                currentSummary.breakdown.sorted { $0.value > $1.value },
                                id: \.key
                            ) { cat, total in
                                HStack {
                                    Text(cat)
                                        .font(.subheadline)
                                    Spacer()
                                    Text(String(format: "$%.2f", total))
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 3)
                                Divider()
                            }
                        }
                        .padding(.horizontal)
                    }

                    // MARK: - Top Merchants
                    if !topMerchants.isEmpty {
                        GroupBox("Top Merchants") {
                            ForEach(topMerchants, id: \.merchant) { item in
                                HStack {
                                    Text(item.merchant)
                                        .font(.subheadline)
                                    Spacer()
                                    Text(String(format: "$%.2f", item.total))
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 3)
                                Divider()
                            }
                        }
                        .padding(.horizontal)
                    }

                    if summaries.isEmpty {
                        ContentUnavailableView(
                            "No Data Yet",
                            systemImage: "chart.bar.xaxis",
                            description: Text("Scan and submit receipts to see spending analytics.")
                        )
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Analytics")
        }
    }

    private var currentMonthCount: Int {
        let month = String(ISO8601DateFormatter().string(from: Date()).prefix(7))
        return store.receipts.filter { $0.date.hasPrefix(month) }.count
    }
}

// MARK: - KPI Card

private struct KPICard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "creditcard.fill")
                .font(.system(size: 40))
                .foregroundColor(.accentColor.opacity(0.3))
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
