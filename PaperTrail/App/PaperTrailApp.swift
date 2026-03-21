// PaperTrailApp.swift
// Entry point for the PaperTrail application.

import SwiftUI

@main
struct PaperTrailApp: App {

    @StateObject private var appSettings = AppSettings()
    @StateObject private var offlineQueue = OfflineQueueManager()
    @StateObject private var analyticsStore = AnalyticsStore()

    init() {
        URLCache.shared.memoryCapacity = 20 * 1024 * 1024
        URLCache.shared.diskCapacity   = 100 * 1024 * 1024
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appSettings)
                .environmentObject(offlineQueue)
                .environmentObject(analyticsStore)
                .onAppear {
                    Task { await offlineQueue.flushIfConnected() }
                }
        }
    }
}
