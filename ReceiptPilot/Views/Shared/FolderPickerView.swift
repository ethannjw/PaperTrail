// FolderPickerView.swift
// Presents the system document picker in folder-selection mode.

import SwiftUI
import UIKit

struct FolderPickerView: UIViewControllerRepresentable {

    let onFolderSelected: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFolderSelected: onFolderSelected, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFolderSelected: (URL) -> Void
        let onCancel: () -> Void

        init(onFolderSelected: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onFolderSelected = onFolderSelected
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onFolderSelected(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
