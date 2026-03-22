// DocumentScannerView.swift
// VisionKit-based document scanner as an alternative to the custom camera.
// Uses Apple's built-in edge detection, auto-capture, and perspective correction.

import SwiftUI
import VisionKit

struct DocumentScannerView: UIViewControllerRepresentable {

    let onScanComplete: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanComplete: onScanComplete, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScanComplete: (UIImage) -> Void
        let onCancel: () -> Void

        init(onScanComplete: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onScanComplete = onScanComplete
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            // Take the first page (receipt = single page)
            guard scan.pageCount > 0 else {
                onCancel()
                return
            }
            let image = scan.imageOfPage(at: 0)
            onScanComplete(image)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            print("[DocumentScanner] Error: \(error.localizedDescription)")
            onCancel()
        }
    }
}
