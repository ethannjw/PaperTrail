// ImageProcessor.swift
// CoreImage-based pipeline for receipt image enhancement.
// Applies: grayscale, contrast boost, shadow removal, sharpening, brightness.

import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct ImageProcessor {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Full Enhancement Pipeline

    /// Apply the complete receipt enhancement pipeline.
    static func enhanceReceipt(_ image: UIImage, grayscale: Bool = true) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }

        var processed = ciImage

        // 1. Remove shadows by flattening luminance
        processed = removeShadows(processed)

        // 2. Boost contrast for text clarity
        processed = adjustContrast(processed, amount: 1.3)

        // 3. Increase brightness slightly
        processed = adjustBrightness(processed, amount: 0.05)

        // 4. Convert to grayscale for "scanned" look
        if grayscale {
            processed = toGrayscale(processed)
        }

        // 5. Sharpen text edges
        processed = sharpen(processed, sharpness: 0.5, radius: 1.5)

        // 6. Apply unsharp mask for fine detail
        processed = unsharpMask(processed, radius: 2.5, intensity: 0.6)

        return renderToUIImage(processed, originalSize: image.size) ?? image
    }

    // MARK: - Individual Filters

    static func removeShadows(_ image: CIImage) -> CIImage {
        // Use highlight/shadow adjust to reduce shadows
        let filter = CIFilter.highlightShadowAdjust()
        filter.inputImage = image
        filter.shadowAmount = 1.5       // Brighten shadows
        filter.highlightAmount = 0.9    // Slightly reduce highlights
        return filter.outputImage ?? image
    }

    static func adjustContrast(_ image: CIImage, amount: Double) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.contrast = Float(amount)
        filter.saturation = 1.0
        return filter.outputImage ?? image
    }

    static func adjustBrightness(_ image: CIImage, amount: Double) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.brightness = Float(amount)
        return filter.outputImage ?? image
    }

    static func toGrayscale(_ image: CIImage) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.saturation = 0.0
        return filter.outputImage ?? image
    }

    static func sharpen(_ image: CIImage, sharpness: Double, radius: Double) -> CIImage {
        let filter = CIFilter.sharpenLuminance()
        filter.inputImage = image
        filter.sharpness = Float(sharpness)
        filter.radius = Float(radius)
        return filter.outputImage ?? image
    }

    static func unsharpMask(_ image: CIImage, radius: Double, intensity: Double) -> CIImage {
        let filter = CIFilter.unsharpMask()
        filter.inputImage = image
        filter.radius = Float(radius)
        filter.intensity = Float(intensity)
        return filter.outputImage ?? image
    }

    // MARK: - Adaptive Threshold (for very faded receipts)

    /// Converts to high-contrast black/white using adaptive thresholding.
    static func adaptiveThreshold(_ image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }

        // Grayscale first
        let gray = toGrayscale(ciImage)

        // Gaussian blur as local mean
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = gray
        blur.radius = 20

        guard let blurred = blur.outputImage else { return image }

        // Subtract blurred from original to get local contrast
        let diff = CIFilter.subtractBlendMode()
        diff.inputImage = gray
        diff.backgroundImage = blurred

        guard let diffOutput = diff.outputImage else { return image }

        // Boost and invert to create threshold mask
        let controls = CIFilter.colorControls()
        controls.inputImage = diffOutput
        controls.contrast = 8.0
        controls.brightness = 0.3

        guard let output = controls.outputImage else { return image }
        return renderToUIImage(output, originalSize: image.size) ?? image
    }

    // MARK: - Render Helper

    private static func renderToUIImage(_ ciImage: CIImage, originalSize: CGSize) -> UIImage? {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
