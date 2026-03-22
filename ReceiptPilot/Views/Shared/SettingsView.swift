// SettingsView.swift
// API key management, AI provider switching, Google sign-in, and app preferences.

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject var appSettings: AppSettings
    @StateObject private var googleAuth = GoogleAuthService()

    @State private var openAIKey:     String = ""
    @State private var geminiKey:     String = ""
    @State private var claudeKey:     String = ""
    @State private var keySaved:      Bool   = false
    @State private var showKeyAlert:  Bool   = false
    @State private var keyAlertMsg:   String = ""
    @State private var isSigningIn:   Bool   = false
    @State private var showFolderPicker = false
    @State private var savedFolderName: String = FolderBookmarkService.resolveBookmark()?.lastPathComponent ?? ""
    @State private var showSheetPicker = false
    @State private var showDriveFolderPicker = false

    var body: some View {
        NavigationView {
            Form {

                // MARK: - AI Provider
                Section("AI Provider") {
                    Picker("Provider", selection: $appSettings.aiProvider) {
                        Text("OpenAI").tag(AppConfig.AIProvider.openai)
                        Text("Gemini").tag(AppConfig.AIProvider.gemini)
                        Text("Claude").tag(AppConfig.AIProvider.claude)
                        Text("Mock (Dev)").tag(AppConfig.AIProvider.mock)
                    }

                    if appSettings.aiProvider != .mock {
                        Picker("Processing Mode", selection: $appSettings.processingMode) {
                            Text("Vision").tag(AppConfig.ProcessingMode.vision)
                            Text("OCR + LLM").tag(AppConfig.ProcessingMode.ocrPlusLLM)
                        }
                        .pickerStyle(.segmented)
                    }

                    if appSettings.processingMode == .ocrPlusLLM && appSettings.aiProvider != .mock {
                        Label(
                            "OCR runs on-device; only text is sent to AI.",
                            systemImage: "lock.shield"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    if appSettings.aiProvider == .mock {
                        Label(
                            "Mock mode returns sample data. No API key needed.",
                            systemImage: "hammer"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }

                // MARK: - API Keys
                if appSettings.aiProvider != .mock {
                    Section("API Keys") {
                        SecureField("OpenAI API Key (sk-…)", text: $openAIKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        SecureField("Gemini API Key", text: $geminiKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        SecureField("Claude API Key (sk-ant-…)", text: $claudeKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Button("Save Keys to Keychain") {
                            saveKeys()
                        }
                        .disabled(openAIKey.isEmpty && geminiKey.isEmpty && claudeKey.isEmpty)
                    }
                }

                // MARK: - Google
                Section("Google Account") {
                    if googleAuth.isAuthenticated {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Signed in to Google")
                        }
                        Button("Sign Out", role: .destructive) {
                            googleAuth.signOut()
                        }
                    } else {
                        Button {
                            Task {
                                isSigningIn = true
                                defer { isSigningIn = false }
                                do {
                                    try await googleAuth.signIn()
                                } catch {
                                    keyAlertMsg = error.localizedDescription
                                    showKeyAlert = true
                                }
                            }
                        } label: {
                            HStack {
                                if isSigningIn {
                                    ProgressView()
                                } else {
                                    Image(systemName: "person.badge.key.fill")
                                }
                                Text(isSigningIn ? "Signing in…" : "Sign in with Google")
                            }
                        }
                        .disabled(isSigningIn)
                    }
                }

                // MARK: - Google Resources
                Section {
                    // Spreadsheet selector
                    Button {
                        if googleAuth.isAuthenticated {
                            showSheetPicker = true
                        } else {
                            keyAlertMsg = "Sign in with Google first"
                            showKeyAlert = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "tablecells")
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Spreadsheet")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Text(appSettings.googleSpreadsheetName.isEmpty ? "Not selected" : appSettings.googleSpreadsheetName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }

                    // Drive folder selector
                    Button {
                        if googleAuth.isAuthenticated {
                            showDriveFolderPicker = true
                        } else {
                            keyAlertMsg = "Sign in with Google first"
                            showKeyAlert = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Drive Folder")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Text(appSettings.googleDriveFolderName.isEmpty ? "None (uploads to root)" : appSettings.googleDriveFolderName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Google Sheets & Drive")
                } footer: {
                    Text("Select where to save receipt data. Spreadsheet and folder will be created if they don't exist.")
                }

                // MARK: - Local PDF Save
                Section {
                    Button {
                        showFolderPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                            if savedFolderName.isEmpty {
                                Text("Choose Folder")
                            } else {
                                Text(savedFolderName)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.primary)

                    if !savedFolderName.isEmpty {
                        Button("Reset to Default", role: .destructive) {
                            FolderBookmarkService.clearBookmark()
                            savedFolderName = ""
                        }
                        .font(.caption)
                    }
                } header: {
                    Text("Save PDFs To")
                } footer: {
                    Text(savedFolderName.isEmpty
                         ? "PDFs save to On My iPhone > ReceiptPilot. Tap to choose iCloud Drive, Google Drive, or any folder."
                         : "Receipt PDFs will be saved to this folder.")
                }

                // MARK: - Preferences
                Section("Preferences") {
                    HStack {
                        Text("Default Currency")
                        Spacer()
                        TextField("USD", text: $appSettings.defaultCurrency)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                    }

                    Toggle("Auto-submit (skip confirm)", isOn: $appSettings.autoSubmit)
                }

                // MARK: - AI Prompt
                Section {
                    NavigationLink("Edit AI Prompt") {
                        PromptEditorView(prompt: $appSettings.customSystemPrompt)
                    }
                } header: {
                    Text("AI Prompt")
                } footer: {
                    Text(appSettings.customSystemPrompt.isEmpty
                         ? "Using default prompt. Tap to customize what the AI extracts."
                         : "Using custom prompt.")
                }

                // MARK: - About
                Section("About") {
                    LabeledContent("Version",  value: appVersion)
                    LabeledContent("Build",    value: appBuild)
                }
            }
            .navigationTitle("Settings")
            .onAppear { loadKeys() }
            .alert("Saved", isPresented: $keySaved) {
                Button("OK") { }
            } message: {
                Text("API keys saved securely to Keychain.")
            }
            .alert("Error", isPresented: $showKeyAlert) {
                Button("OK") { }
            } message: {
                Text(keyAlertMsg)
            }
            .sheet(isPresented: $showSheetPicker) {
                GoogleResourcePickerView(type: .spreadsheet, authService: googleAuth) { resource in
                    appSettings.googleSpreadsheetID = resource.id
                    appSettings.googleSpreadsheetName = resource.name
                }
            }
            .sheet(isPresented: $showDriveFolderPicker) {
                GoogleResourcePickerView(type: .folder, authService: googleAuth) { resource in
                    appSettings.googleDriveFolderID = resource.id
                    appSettings.googleDriveFolderName = resource.name
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPickerView(
                    onFolderSelected: { url in
                        guard url.startAccessingSecurityScopedResource() else { return }
                        defer { url.stopAccessingSecurityScopedResource() }
                        try? FolderBookmarkService.saveBookmark(for: url)
                        savedFolderName = url.lastPathComponent
                        showFolderPicker = false
                    },
                    onCancel: {
                        showFolderPicker = false
                    }
                )
            }
        }
    }

    // MARK: - Keychain Helpers

    private func saveKeys() {
        do {
            if !openAIKey.isEmpty {
                try KeychainService.save(openAIKey, for: .openAIAPIKey)
            }
            if !geminiKey.isEmpty {
                try KeychainService.save(geminiKey, for: .geminiAPIKey)
            }
            if !claudeKey.isEmpty {
                try KeychainService.save(claudeKey, for: .claudeAPIKey)
            }
            openAIKey = ""
            geminiKey = ""
            claudeKey = ""
            keySaved  = true
        } catch {
            keyAlertMsg = error.localizedDescription
            showKeyAlert = true
        }
    }

    private func loadKeys() {
        // Don't pre-fill; placeholders indicate saved state
    }

    // MARK: - App Info
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
