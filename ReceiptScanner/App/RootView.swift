// RootView.swift
// Tab-based root navigation. Tabs: Scan | History | Analytics | Settings

import SwiftUI

struct RootView: View {

    @EnvironmentObject var appSettings:   AppSettings
    @EnvironmentObject var offlineQueue:  OfflineQueueManager
    @EnvironmentObject var analyticsStore: AnalyticsStore

    @StateObject private var googleAuth = GoogleAuthService()

    var body: some View {
        TabView {
            // MARK: - Scan Tab
            ScanTab(googleAuth: googleAuth)
                .tabItem {
                    Label("Scan", systemImage: "camera.fill")
                }

            // MARK: - History Tab
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "list.bullet.rectangle")
                }

            // MARK: - Analytics Tab
            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar.fill")
                }

            // MARK: - Settings Tab
            SettingsView(googleAuth: googleAuth)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .environmentObject(googleAuth)
    }
}

// MARK: - Scan Tab Wrapper

private struct ScanTab: View {
    @EnvironmentObject var appSettings:   AppSettings
    @EnvironmentObject var offlineQueue:  OfflineQueueManager
    @EnvironmentObject var analyticsStore: AnalyticsStore
    @ObservedObject var googleAuth: GoogleAuthService

    @StateObject private var viewModel: CameraViewModel

    init(googleAuth: GoogleAuthService) {
        self.googleAuth = googleAuth
        _viewModel = StateObject(wrappedValue: CameraViewModel(
            appSettings: AppSettings(),
            googleAuth: googleAuth,
            offlineQueue: OfflineQueueManager(),
            analyticsStore: AnalyticsStore()
        ))
    }

    var body: some View {
        NavigationView {
            FlowCoordinator(viewModel: viewModel)
                .navigationTitle("")
                .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Flow Coordinator

private struct FlowCoordinator: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        ZStack {
            switch viewModel.stage {
            case .idle, .authorized, .capturing:
                CameraView(viewModel: viewModel)

            case .processing(let msg):
                processingView(msg)

            case .editing:
                ReceiptEditView(viewModel: viewModel)

            case .submitting:
                processingView("Saving to Google Sheets...")

            case .success(let receipt):
                SuccessOverlay(receipt: receipt) { viewModel.retakePhoto() }

            case .failed(let error):
                CameraView(viewModel: viewModel)
                    .overlay(alignment: .top) {
                        ErrorBanner(error: error) { viewModel.stage = .idle }
                            .padding(.top, 60)
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.stage == .idle)
    }

    @ViewBuilder
    private func processingView(_ msg: String) -> some View {
        ZStack {
            if let img = viewModel.capturedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .blur(radius: 8)
            } else {
                Color.black.ignoresSafeArea()
            }
            LoadingOverlay(message: msg)
        }
    }
}
