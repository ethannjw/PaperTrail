// LoadingOverlay.swift
// Reusable full-screen loading overlay with progress message.

import SwiftUI

struct LoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.6)
                    .tint(.white)

                Text(message)
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(36)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: message)
    }
}

// MARK: - Success Overlay

struct SuccessOverlay: View {
    let receipt: Receipt
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.green)

                Text("Receipt Saved!")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 6) {
                    LabeledRow(label: "Merchant", value: receipt.merchant)
                    LabeledRow(label: "Date",     value: receipt.date)
                    LabeledRow(label: "Total",    value: String(format: "%.2f %@", receipt.total, receipt.currency))
                    if let cat = receipt.category {
                        LabeledRow(label: "Category", value: cat)
                    }
                    if let link = receipt.imageDriveURL {
                        LabeledRow(label: "Drive", value: "Uploaded ✓")
                        // Tappable
                        if let url = URL(string: link) {
                            Link("View in Drive", destination: url)
                                .font(.caption)
                                .padding(.leading, 80)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)

                Button("Scan Another") { onDismiss() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 24)
        }
    }
}

private struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .trailing)
            Text(value)
                .font(.subheadline)
                .lineLimit(1)
        }
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let error: AppError
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                Text(error.errorDescription ?? "Unknown error")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(16)
        .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring, value: error)
    }
}
