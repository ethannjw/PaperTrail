// ReceiptEditView.swift
// Displays AI-extracted receipt data in an editable form.
// Users review, correct fields, add category, then confirm submission.

import SwiftUI

struct ReceiptEditView: View {

    @ObservedObject var viewModel: CameraViewModel
    @State private var showImagePreview  = false
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                // MARK: - Image Thumbnail
                if let image = viewModel.capturedImage {
                    Section {
                        HStack {
                            Spacer()
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(radius: 4)
                                .onTapGesture { showImagePreview = true }
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                }

                // MARK: - Duplicate Warning
                if viewModel.editableReceipt.isDuplicate {
                    Section {
                        Label("Possible duplicate receipt detected.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.subheadline)
                    }
                }

                // MARK: - Merchant & Date
                Section("Merchant") {
                    TextField("Merchant Name", text: $viewModel.editableReceipt.merchant)
                        .autocorrectionDisabled()

                    DatePickerField(
                        label: "Date",
                        dateString: $viewModel.editableReceipt.date
                    )
                }

                // MARK: - Amount
                Section("Amount") {
                    HStack {
                        Text("Total")
                        Spacer()
                        TextField("0.00", value: $viewModel.editableReceipt.total, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Currency")
                        Spacer()
                        TextField("USD", text: $viewModel.editableReceipt.currency)
                            .autocapitalization(.allCharacters)
                            .autocorrectionDisabled()
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // MARK: - Category
                Section("Category") {
                    Picker("Category", selection: $viewModel.editableReceipt.category) {
                        Text("None").tag(Optional<String>.none)
                        ForEach(ReceiptCategory.allCases, id: \.self) { cat in
                            Text(cat.rawValue).tag(Optional(cat.rawValue))
                        }
                    }
                }

                // MARK: - Line Items
                Section {
                    ForEach($viewModel.editableReceipt.items) { $item in
                        ReceiptItemRow(item: $item)
                    }
                    .onDelete { indices in
                        viewModel.editableReceipt.items.remove(atOffsets: indices)
                    }

                    Button {
                        viewModel.editableReceipt.items.append(ReceiptItem())
                    } label: {
                        Label("Add Item", systemImage: "plus.circle")
                    }
                } header: {
                    HStack {
                        Text("Items")
                        Spacer()
                        Text(String(format: "Computed: %.2f %@",
                                    viewModel.editableReceipt.computedTotal,
                                    viewModel.editableReceipt.currency))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: - Submit Button
                Section {
                    Button {
                        viewModel.validateAndProceed()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Submit Receipt")
                                .bold()
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.accentColor)
                    .foregroundColor(.white)
                }
            }
            .navigationTitle("Review Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Retake") { viewModel.retakePhoto() }
                }
            }
            .sheet(isPresented: $showImagePreview) {
                if let image = viewModel.capturedImage {
                    ImagePreviewSheet(image: image)
                }
            }
            .alert("Fix Issues Before Submitting",
                   isPresented: $viewModel.showValidationAlert,
                   actions: {
                Button("Fix") { }
                Button("Submit Anyway", role: .destructive) {
                    viewModel.forceSubmit()
                }
            }, message: {
                Text(viewModel.validationIssues.joined(separator: "\n"))
            })
        }
    }
}

// MARK: - Receipt Item Row

private struct ReceiptItemRow: View {
    @Binding var item: ReceiptItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Item name", text: $item.name)
                .font(.body)

            HStack {
                Text("Qty:")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("1", value: $item.quantity, format: .number)
                    .keyboardType(.decimalPad)
                    .frame(width: 50)
                    .font(.caption)

                Spacer()

                Text("Price:")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("0.00", value: $item.price, format: .number)
                    .keyboardType(.decimalPad)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Date Picker Field

private struct DatePickerField: View {
    let label: String
    @Binding var dateString: String

    @State private var date: Date = Date()
    @State private var showPicker = false

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Button(dateString.isEmpty ? "Select Date" : dateString) {
                if let d = formatter.date(from: dateString) { date = d }
                showPicker.toggle()
            }
            .foregroundColor(dateString.isEmpty ? .accentColor : .primary)
        }

        if showPicker {
            DatePicker(
                "",
                selection: $date,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .onChange(of: date) { newDate in
                dateString = formatter.string(from: newDate)
                showPicker = false
            }
        }
    }
}

// MARK: - Image Preview Sheet

private struct ImagePreviewSheet: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
