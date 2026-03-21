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
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .environmentObject(googleAuth)
    }
}

// MARK: - Scan Tab Wrapper
// Uses a two-layer approach: outer view captures @EnvironmentObject,
// inner view creates @StateObject with the real dependencies.

private struct ScanTab: View {
    @EnvironmentObject var appSettings:   AppSettings
    @EnvironmentObject var offlineQueue:  OfflineQueueManager
    @EnvironmentObject var analyticsStore: AnalyticsStore
    @ObservedObject var googleAuth: GoogleAuthService

    var body: some View {
        ScanTabInner(
            appSettings: appSettings,
            googleAuth: googleAuth,
            offlineQueue: offlineQueue,
            analyticsStore: analyticsStore
        )
    }
}

private struct ScanTabInner: View {
    let appSettings: AppSettings
    let googleAuth: GoogleAuthService
    let offlineQueue: OfflineQueueManager
    let analyticsStore: AnalyticsStore

    @StateObject private var viewModel: CameraViewModel

    init(appSettings: AppSettings, googleAuth: GoogleAuthService,
         offlineQueue: OfflineQueueManager, analyticsStore: AnalyticsStore) {
        self.appSettings = appSettings
        self.googleAuth = googleAuth
        self.offlineQueue = offlineQueue
        self.analyticsStore = analyticsStore
        _viewModel = StateObject(wrappedValue: CameraViewModel(
            appSettings: appSettings,
            googleAuth: googleAuth,
            offlineQueue: offlineQueue,
            analyticsStore: analyticsStore
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
                ScanLandingView(viewModel: viewModel)

            case .processing(let msg):
                processingView(msg)

            case .editing:
                ReceiptEditView(viewModel: viewModel)

            case .submitting:
                processingView("Saving to Google Sheets...")

            case .success(let receipt):
                SuccessOverlay(receipt: receipt) { viewModel.retakePhoto() }

            case .failed(let error):
                ScanLandingView(viewModel: viewModel)
                    .overlay(alignment: .top) {
                        ErrorBanner(error: error) { viewModel.stage = .idle }
                            .padding(.top, 60)
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.stage == .idle)
        .sheet(isPresented: $viewModel.showDocumentScanner) {
            DocumentScannerView(
                onScanComplete: { image in
                    viewModel.showDocumentScanner = false
                    viewModel.handleDocumentScanResult(image)
                },
                onCancel: {
                    viewModel.showDocumentScanner = false
                }
            )
        }
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
                Color(.systemGroupedBackground).ignoresSafeArea()
            }
            LoadingOverlay(message: msg)
        }
    }
}

// MARK: - Scan Landing View

private struct ScanLandingView: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 72))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Scan Receipt")
                    .font(.title.bold())
                Text("Capture a receipt to extract and save expense data")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                viewModel.showDocumentScanner = true
            } label: {
                Label("Scan Receipt", systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)

            Spacer()
        }
    }
}
