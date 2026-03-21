// AppConfig.swift
// Central configuration loaded from Config.plist (excluded from source control).
// Never hardcode secrets — all keys are read from the plist or Keychain.

import Foundation

/// Top-level configuration bag. Loaded once at startup.
struct AppConfig {

    // MARK: - AI Provider
    enum AIProvider: String, CaseIterable, Codable {
        case openai  = "openai"
        case gemini  = "gemini"
        case claude  = "claude"
        case mock    = "mock"
    }

    enum ProcessingMode: String, CaseIterable, Codable {
        case vision      = "vision"        // Pure vision API
        case ocrPlusLLM  = "ocr_plus_llm"  // Apple OCR → LLM
    }

    // MARK: - Shared singleton
    static let shared = AppConfig()

    // MARK: - Values
    let aiProvider: AIProvider
    let processingMode: ProcessingMode

    // Endpoint overrides (useful for proxies / enterprise gateways)
    let openAIBaseURL: URL
    let geminiBaseURL: URL
    let claudeBaseURL: URL

    // Google OAuth
    let googleClientID: String
    let googleRedirectURI: String

    // Google resource identifiers (defaults — user can override in Settings)
    let defaultGoogleDriveFolderID: String
    let defaultGoogleSpreadsheetID: String

    // Timeouts
    let networkTimeoutSeconds: Double

    // MARK: - Init from Config.plist
    private init() {
        guard
            let url  = Bundle.main.url(forResource: "Config", withExtension: "plist"),
            let dict = NSDictionary(contentsOf: url) as? [String: Any]
        else {
            fatalError("Config.plist not found. See SETUP.md for instructions.")
        }

        func require<T>(_ key: String) -> T {
            guard let value = dict[key] as? T else {
                fatalError("Config.plist missing required key '\(key)' of type \(T.self)")
            }
            return value
        }

        let providerRaw: String = require("AIProvider")
        aiProvider = AIProvider(rawValue: providerRaw) ?? .openai

        let modeRaw: String = require("ProcessingMode")
        processingMode = ProcessingMode(rawValue: modeRaw) ?? .vision

        let openAIBase: String = dict["OpenAIBaseURL"] as? String ?? "https://api.openai.com"
        openAIBaseURL = URL(string: openAIBase)!

        let geminiBase: String = dict["GeminiBaseURL"] as? String
            ?? "https://generativelanguage.googleapis.com"
        geminiBaseURL = URL(string: geminiBase)!

        let claudeBase: String = dict["ClaudeBaseURL"] as? String
            ?? "https://api.anthropic.com"
        claudeBaseURL = URL(string: claudeBase)!

        googleClientID    = require("GoogleClientID")
        googleRedirectURI = require("GoogleRedirectURI")
        defaultGoogleDriveFolderID = dict["GoogleDriveFolderID"] as? String ?? ""
        defaultGoogleSpreadsheetID = dict["GoogleSpreadsheetID"] as? String ?? ""

        networkTimeoutSeconds = dict["NetworkTimeoutSeconds"] as? Double ?? 30.0
    }
}
