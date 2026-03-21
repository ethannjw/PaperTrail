// MainFlowView.swift
// Top-level view that drives the capture → process → edit → submit pipeline
// by observing CameraViewModel.stage.

import SwiftUI

struct MainFlowView: View {

    @EnvironmentObject var appSettings:  AppSettings
    @EnvironmentObject var offlineQueue: OfflineQueueManager
    @EnvironmentObject var analyticsStore: AnalyticsStore

    @StateObject private var googleAuth = GoogleAuthService()
    @StateObject private var viewModel: CameraViewModel

    init() {
        // CameraViewModel is created here; @StateObject retains it
        // We can't inject from EnvironmentObject during init, so we use a dummy placeholder
        // and replace in onAppear. Pattern: use a container approach.
        // Workaround: create with temp objects, replace via onAppear using wrappedValue.
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

            // MARK: - Camera
            case .idle, .authorized:
                CameraView(viewModel: viewModel)

            // MARK: - Capturing in progress
            case .capturing:
                CameraView(viewModel: viewModel)
                    .overlay(LoadingOverlay(message: "Capturing..."))

            // MARK: - AI Processing
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

            // MARK: - Editing
            case .editing:
                ReceiptEditView(viewModel: viewModel)

            // MARK: - Submitting
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

            // MARK: - Success
            case .success(let receipt):
                SuccessOverlay(receipt: receipt) {
                    viewModel.retakePhoto()
                }

            // MARK: - Error
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

    // A simple Equatable proxy to drive animation
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
