// AppSettings.swift
// Observable settings store backed by UserDefaults.
// Exposes runtime-switchable AI provider, processing mode, and Google resource IDs.

import Foundation
import Combine

final class AppSettings: ObservableObject {

    // MARK: - Runtime-overridable settings (persisted in UserDefaults)
    @Published var aiProvider: AppConfig.AIProvider {
        didSet { UserDefaults.standard.set(aiProvider.rawValue, forKey: Keys.aiProvider) }
    }
    @Published var processingMode: AppConfig.ProcessingMode {
        didSet { UserDefaults.standard.set(processingMode.rawValue, forKey: Keys.processingMode) }
    }
    @Published var defaultCurrency: String {
        didSet { UserDefaults.standard.set(defaultCurrency, forKey: Keys.defaultCurrency) }
    }
    @Published var autoSubmit: Bool {
        didSet { UserDefaults.standard.set(autoSubmit, forKey: Keys.autoSubmit) }
    }

    // MARK: - Custom AI Prompt (user-configurable)
    @Published var customSystemPrompt: String {
        didSet { UserDefaults.standard.set(customSystemPrompt, forKey: Keys.customSystemPrompt) }
    }

    // MARK: - Google resource IDs (user-configurable)
    @Published var googleSpreadsheetID: String {
        didSet { UserDefaults.standard.set(googleSpreadsheetID, forKey: Keys.googleSpreadsheetID) }
    }
    @Published var googleSpreadsheetName: String {
        didSet { UserDefaults.standard.set(googleSpreadsheetName, forKey: Keys.googleSpreadsheetName) }
    }
    @Published var googleDriveFolderID: String {
        didSet { UserDefaults.standard.set(googleDriveFolderID, forKey: Keys.googleDriveFolderID) }
    }
    @Published var googleDriveFolderName: String {
        didSet { UserDefaults.standard.set(googleDriveFolderName, forKey: Keys.googleDriveFolderName) }
    }

    // MARK: - Keys
    private enum Keys {
        static let aiProvider           = "aiProvider"
        static let processingMode       = "processingMode"
        static let defaultCurrency      = "defaultCurrency"
        static let autoSubmit           = "autoSubmit"
        static let googleSpreadsheetID   = "googleSpreadsheetID"
        static let googleSpreadsheetName = "googleSpreadsheetName"
        static let googleDriveFolderID   = "googleDriveFolderID"
        static let googleDriveFolderName = "googleDriveFolderName"
        static let customSystemPrompt    = "customSystemPrompt"
    }

    // MARK: - Init
    init() {
        let ud = UserDefaults.standard
        let cfg = AppConfig.shared

        let savedProvider = ud.string(forKey: Keys.aiProvider)
            .flatMap(AppConfig.AIProvider.init(rawValue:)) ?? cfg.aiProvider
        let savedMode = ud.string(forKey: Keys.processingMode)
            .flatMap(AppConfig.ProcessingMode.init(rawValue:)) ?? cfg.processingMode

        self.aiProvider         = savedProvider
        self.processingMode     = savedMode
        self.defaultCurrency    = ud.string(forKey: Keys.defaultCurrency) ?? "USD"
        self.autoSubmit         = ud.bool(forKey: Keys.autoSubmit)
        self.googleSpreadsheetID   = ud.string(forKey: Keys.googleSpreadsheetID) ?? cfg.defaultGoogleSpreadsheetID
        self.googleSpreadsheetName = ud.string(forKey: Keys.googleSpreadsheetName) ?? ""
        self.googleDriveFolderID   = ud.string(forKey: Keys.googleDriveFolderID) ?? cfg.defaultGoogleDriveFolderID
        self.googleDriveFolderName = ud.string(forKey: Keys.googleDriveFolderName) ?? ""
        self.customSystemPrompt    = ud.string(forKey: Keys.customSystemPrompt) ?? ""
    }
}
