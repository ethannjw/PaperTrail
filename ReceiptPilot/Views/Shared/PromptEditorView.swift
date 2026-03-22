// PromptEditorView.swift
// Full-screen editor for the AI system prompt.

import SwiftUI

struct PromptEditorView: View {

    @Binding var prompt: String
    @State private var draft: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $draft)
                .font(.system(.body, design: .monospaced))
                .padding(8)

            Divider()

            HStack {
                Button("Reset to Default") {
                    draft = ""
                }
                .foregroundColor(.red)

                Spacer()

                Text("\(draft.count) chars")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle("AI Prompt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    prompt = draft
                    dismiss()
                }
                .bold()
            }
        }
        .onAppear {
            draft = prompt.isEmpty ? ReceiptPrompts.defaultSystemPrompt : prompt
        }
    }
}
