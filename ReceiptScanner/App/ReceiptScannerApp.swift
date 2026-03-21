// ReceiptScannerApp.swift
// Entry point for the Receipt Scanner application.
// Bootstraps dependency injection, environment, and root navigation.

import SwiftUI

@main
struct ReceiptScannerApp: App {

    // MARK: - App-wide singletons injected into the environment
    @StateObject private var appSettings = AppSettings()
    @StateObject private var offlineQueue = OfflineQueueManager()
    @StateObject private var analyticsStore = AnalyticsStore()

    init() {
        // Configure URL session caching and appearance
        URLCache.shared.memoryCapacity = 20 * 1024 * 1024  // 20 MB
        URLCache.shared.diskCapacity   = 100 * 1024 * 1024 // 100 MB
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appSettings)
                .environmentObject(offlineQueue)
                .environmentObject(analyticsStore)
                .onAppear {
                    // Attempt to flush any queued offline receipts on launch
                    Task { await offlineQueue.flushIfConnected() }
                }
        }
    }
}
