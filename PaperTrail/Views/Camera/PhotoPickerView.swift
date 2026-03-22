// PhotoPickerView.swift
// Presents the system photo picker to select a receipt image from the library.

import SwiftUI
import PhotosUI

struct PhotoPickerView: UIViewControllerRepresentable {

    let onImageSelected: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageSelected: onImageSelected, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImageSelected: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImageSelected: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImageSelected = onImageSelected
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                onCancel()
                return
            }

            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                DispatchQueue.main.async {
                    if let image = object as? UIImage {
                        self?.onImageSelected(image)
                    } else {
                        self?.onCancel()
                    }
                }
            }
        }
    }
}
