// AppSettings.swift
// Observable settings store backed by UserDefaults.
// Exposes runtime-switchable AI provider & processing mode.

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

    // MARK: - Keys
    private enum Keys {
        static let aiProvider      = "aiProvider"
        static let processingMode  = "processingMode"
        static let defaultCurrency = "defaultCurrency"
        static let autoSubmit      = "autoSubmit"
    }

    // MARK: - Init
    init() {
        let ud = UserDefaults.standard
        let cfg = AppConfig.shared

        let savedProvider = ud.string(forKey: Keys.aiProvider)
            .flatMap(AppConfig.AIProvider.init(rawValue:)) ?? cfg.aiProvider
        let savedMode = ud.string(forKey: Keys.processingMode)
            .flatMap(AppConfig.ProcessingMode.init(rawValue:)) ?? cfg.processingMode

        self.aiProvider      = savedProvider
        self.processingMode  = savedMode
        self.defaultCurrency = ud.string(forKey: Keys.defaultCurrency) ?? "USD"
        self.autoSubmit      = ud.bool(forKey: Keys.autoSubmit)
    }
}
