// MainFlowView.swift
// Alternative top-level view for the capture → process → edit → submit pipeline.
// Kept for reference; primary flow is handled by FlowCoordinator in RootView.

import SwiftUI

struct MainFlowView: View {

    @EnvironmentObject var appSettings:  AppSettings
    @EnvironmentObject var offlineQueue: OfflineQueueManager
    @EnvironmentObject var analyticsStore: AnalyticsStore

    @StateObject private var googleAuth = GoogleAuthService()
    @StateObject private var viewModel: CameraViewModel

    init() {
        _viewModel = StateObject(wrappedValue: CameraViewModel(
            appSettings: AppSettings(),
            googleAuth: GoogleAuthService(),
            offlineQueue: OfflineQueueManager(),
            analyticsStore: AnalyticsStore()
        ))
    }

    var body: some View {
        ZStack {
            switch viewModel.stage {
            case .idle, .authorized:
                CameraView(viewModel: viewModel)

            case .capturing:
                CameraView(viewModel: viewModel)
                    .overlay(LoadingOverlay(message: "Capturing..."))

            case .processing(let msg):
                if let image = viewModel.capturedImage {
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .ignoresSafeArea()
                            .blur(radius: 6)
                        LoadingOverlay(message: msg)
                    }
                } else {
                    LoadingOverlay(message: msg)
                }

            case .editing:
                ReceiptEditView(viewModel: viewModel)

            case .submitting:
                if let image = viewModel.capturedImage {
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .ignoresSafeArea()
                            .blur(radius: 6)
                        LoadingOverlay(message: "Saving to Google Sheets...")
                    }
                }

            case .success(let receipt):
                SuccessOverlay(receipt: receipt) {
                    viewModel.retakePhoto()
                }

            case .failed(let error):
                CameraView(viewModel: viewModel)
                    .overlay(alignment: .top) {
                        ErrorBanner(error: error) {
                            viewModel.stage = .idle
                        }
                        .padding(.top, 60)
                    }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: stageID)
    }

    private var stageID: String {
        switch viewModel.stage {
        case .idle:           return "idle"
        case .authorized:     return "authorized"
        case .capturing:      return "capturing"
        case .processing:     return "processing"
        case .editing:        return "editing"
        case .submitting:     return "submitting"
        case .success:        return "success"
        case .failed:         return "failed"
        }
    }
}
