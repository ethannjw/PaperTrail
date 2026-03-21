// CameraView.swift
// Full-screen camera UI with viewfinder overlay, capture button,
// flash toggle, and tap-to-focus gesture.

import SwiftUI
import AVFoundation

struct CameraView: View {

    @ObservedObject var viewModel: CameraViewModel
    @State private var showFocusIndicator = false
    @State private var focusPoint: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // MARK: - Camera Preview
                CameraPreviewView(session: viewModel.cameraManager.session)
                    .ignoresSafeArea()
                    .onTapGesture { location in
                        focusPoint = location
                        showFocusIndicator = true
                        viewModel.cameraManager.focus(at: location, in: geo.size)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showFocusIndicator = false
                        }
                    }

                // MARK: - Receipt Frame Guide
                ReceiptFrameOverlay()

                // MARK: - Focus Indicator
                if showFocusIndicator {
                    FocusIndicator()
                        .position(focusPoint)
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.3), value: showFocusIndicator)
                }

                // MARK: - Controls
                VStack {
                    Spacer()
                    CameraControlBar(viewModel: viewModel)
                        .padding(.bottom, 40)
                }
            }
        }
        .task { await viewModel.startCamera() }
        .onDisappear { viewModel.stopCamera() }
    }
}

// MARK: - Receipt Frame Overlay

private struct ReceiptFrameOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let width  = geo.size.width * 0.88
            let height = width * 1.5
            let rect   = CGRect(
                x: (geo.size.width  - width)  / 2,
                y: (geo.size.height - height) / 2,
                width: width,
                height: height
            )

            ZStack {
                // Dim outside the cutout using a shape with an inner hole
                DimmedCutout(cutout: rect, cornerRadius: 12)
                    .fill(Color.black.opacity(0.45))

                // Corner brackets
                CornerBrackets(rect: rect)
            }
        }
        .ignoresSafeArea()
    }
}

/// Shape that fills the entire frame EXCEPT for a rounded-rect cutout.
private struct DimmedCutout: Shape {
    let cutout: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(in: cutout, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        return path
    }
}

private struct CornerBrackets: View {
    let rect: CGRect
    private let len: CGFloat = 24
    private let lineWidth: CGFloat = 3

    var body: some View {
        let tl = CGPoint(x: rect.minX, y: rect.minY)
        let tr = CGPoint(x: rect.maxX, y: rect.minY)
        let bl = CGPoint(x: rect.minX, y: rect.maxY)
        let br = CGPoint(x: rect.maxX, y: rect.maxY)

        Canvas { ctx, _ in
            let color = Color.white
            for (corner, xDir, yDir) in [(tl, 1.0, 1.0), (tr, -1.0, 1.0),
                                          (bl, 1.0, -1.0), (br, -1.0, -1.0)] {
                var h = Path()
                h.move(to: corner)
                h.addLine(to: CGPoint(x: corner.x + xDir * len, y: corner.y))
                var v = Path()
                v.move(to: corner)
                v.addLine(to: CGPoint(x: corner.x, y: corner.y + yDir * len))
                ctx.stroke(h, with: .color(color), lineWidth: lineWidth)
                ctx.stroke(v, with: .color(color), lineWidth: lineWidth)
            }
        }
    }
}

// MARK: - Focus Indicator

private struct FocusIndicator: View {
    @State private var scale: CGFloat = 1.3

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(Color.yellow, lineWidth: 1.5)
            .frame(width: 70, height: 70)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) { scale = 1.0 }
            }
    }
}

// MARK: - Camera Control Bar

private struct CameraControlBar: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        HStack(spacing: 40) {
            // Flash toggle
            Button {
                let modes: [AVCaptureDevice.FlashMode] = [.auto, .on, .off]
                let idx = modes.firstIndex(of: viewModel.cameraManager.flashMode) ?? 0
                viewModel.cameraManager.flashMode = modes[(idx + 1) % modes.count]
            } label: {
                Image(systemName: flashIcon)
                    .font(.title2)
                    .foregroundColor(.white)
            }

            // Capture button
            Button {
                Task { await viewModel.capturePhoto() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.6), lineWidth: 3)
                        .frame(width: 84, height: 84)
                }
            }
            .disabled(viewModel.stage == .capturing)
            .opacity(viewModel.stage == .capturing ? 0.5 : 1)

            // Torch toggle
            Button {
                viewModel.cameraManager.toggleTorch()
            } label: {
                Image(systemName: viewModel.cameraManager.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }
        }
    }

    private var flashIcon: String {
        switch viewModel.cameraManager.flashMode {
        case .auto:  return "bolt.badge.a"
        case .on:    return "bolt.fill"
        case .off:   return "bolt.slash"
        @unknown default: return "bolt.badge.a"
        }
    }
}
