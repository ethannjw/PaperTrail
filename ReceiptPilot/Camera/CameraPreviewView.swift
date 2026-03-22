// CameraPreviewView.swift
// UIViewRepresentable wrapper that hosts the AVCaptureVideoPreviewLayer
// inside a SwiftUI hierarchy.

import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // Layout is handled by the view itself
    }
}

// MARK: - PreviewUIView

final class PreviewUIView: UIView {

    var session: AVCaptureSession? {
        didSet {
            guard let session else { return }
            previewLayer.session = session
        }
    }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame        = bounds
        previewLayer.videoGravity = .resizeAspectFill
        // Keep portrait orientation
        if let connection = previewLayer.connection,
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
}
