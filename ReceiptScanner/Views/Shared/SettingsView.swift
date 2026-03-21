// SettingsView.swift
// API key management, AI provider switching, Google sign-in, and app preferences.

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject var appSettings: AppSettings
    @ObservedObject var googleAuth: GoogleAuthService

    @State private var openAIKey:     String = ""
    @State private var geminiKey:     String = ""
    @State private var keySaved:      Bool   = false
    @State private var showKeyAlert:  Bool   = false
    @State private var keyAlertMsg:   String = ""
    @State private var isSigningIn:   Bool   = false

    var body: some View {
        NavigationView {
            Form {

                // MARK: - AI Provider
                Section("AI Provider") {
                    Picker("Provider", selection: $appSettings.aiProvider) {
                        Text("OpenAI").tag(AppConfig.AIProvider.openai)
                        Text("Gemini").tag(AppConfig.AIProvider.gemini)
                    }
                    .pickerStyle(.segmented)

                    Picker("Processing Mode", selection: $appSettings.processingMode) {
                        Text("Vision").tag(AppConfig.ProcessingMode.vision)
                        Text("OCR + LLM").tag(AppConfig.ProcessingMode.ocrPlusLLM)
                    }
                    .pickerStyle(.segmented)

                    if appSettings.processingMode == .ocrPlusLLM {
                        Label(
                            "OCR runs on-device; only text is sent to AI.",
                            systemImage: "lock.shield"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }

                // MARK: - API Keys
                Section("API Keys") {
                    SecureField("OpenAI API Key (sk-…)", text: $openAIKey)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)

                    SecureField("Gemini API Key", text: $geminiKey)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)

                    Button("Save Keys to Keychain") {
                        saveKeys()
                    }
                    .disabled(openAIKey.isEmpty && geminiKey.isEmpty)
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

                // MARK: - Preferences
                Section("Preferences") {
                    HStack {
                        Text("Default Currency")
                        Spacer()
                        TextField("USD", text: $appSettings.defaultCurrency)
                            .autocapitalization(.allCharacters)
                            .autocorrectionDisabled()
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                    }

                    Toggle("Auto-submit (skip confirm)", isOn: $appSettings.autoSubmit)
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
            openAIKey = ""
            geminiKey = ""
            keySaved  = true
        } catch {
            keyAlertMsg = error.localizedDescription
            showKeyAlert = true
        }
    }

    private func loadKeys() {
        // Show masked indicators (don't display actual keys)
        if (try? KeychainService.loadOptional(key: .openAIAPIKey)) != nil {
            openAIKey = ""  // Don't pre-fill; just let placeholder indicate "saved"
        }
    }

    // MARK: - App Info
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
