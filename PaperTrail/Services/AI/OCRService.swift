// OCRService.swift
// On-device text recognition using Apple Vision framework.
// Returns raw concatenated text for downstream LLM processing.

import Foundation
import UIKit
import Vision

// MARK: - OCR Result

struct OCRResult {
    let text: String
    let confidence: Float
    let boundingBoxes: [CGRect]
}

// MARK: - OCR Service

final class OCRService {

    // MARK: - Recognition Level
    enum RecognitionLevel {
        case fast
        case accurate
    }

    // MARK: - Public API

    /// Perform on-device OCR on a UIImage.
    /// - Parameter image: Receipt image to analyze.
    /// - Parameter level: Trade-off between speed and accuracy.
    /// - Returns: OCRResult with extracted text.
    func recognizeText(
        from image: UIImage,
        level: RecognitionLevel = .accurate
    ) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
            throw AppError.ocrFailed("Could not extract CGImage from UIImage")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: AppError.ocrFailed(error.localizedDescription))
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(
                        throwing: AppError.ocrFailed("No text observations returned")
                    )
                    return
                }

                var lines: [String] = []
                var confidenceSum: Float = 0
                var boxes: [CGRect] = []

                for observation in observations {
                    guard let top = observation.topCandidates(1).first else { continue }
                    lines.append(top.string)
                    confidenceSum += top.confidence
                    boxes.append(observation.boundingBox)
                }

                let avgConfidence = observations.isEmpty
                    ? 0
                    : confidenceSum / Float(observations.count)

                let fullText = lines.joined(separator: "\n")

                if fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.resume(
                        throwing: AppError.ocrFailed("No text detected in image")
                    )
                    return
                }

                continuation.resume(
                    returning: OCRResult(
                        text: fullText,
                        confidence: avgConfidence,
                        boundingBoxes: boxes
                    )
                )
            }

            // Configure
            switch level {
            case .fast:
                request.recognitionLevel = .fast
            case .accurate:
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["en-US"]
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: AppError.ocrFailed(error.localizedDescription))
            }
        }
    }

    /// Attempt to auto-detect receipt rectangle and apply perspective correction.
    func detectAndCropReceipt(from image: UIImage) async -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        return await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { req, _ in
                guard
                    let results = req.results as? [VNRectangleObservation],
                    let rect = results.first
                else {
                    continuation.resume(returning: image)
                    return
                }
                let corrected = self.perspectiveCorrected(cgImage: cgImage, observation: rect)
                continuation.resume(returning: corrected)
            }
            request.minimumAspectRatio = 0.3
            request.maximumAspectRatio = 1.0
            request.minimumConfidence  = 0.8
            request.maximumObservations = 1

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    // MARK: - Perspective Correction

    private func perspectiveCorrected(
        cgImage: CGImage,
        observation: VNRectangleObservation
    ) -> UIImage {
        let ciImage = CIImage(cgImage: cgImage)
        let imgSize = CGSize(width: cgImage.width, height: cgImage.height)

        func convert(_ point: CGPoint) -> CIVector {
            CIVector(x: point.x * imgSize.width, y: point.y * imgSize.height)
        }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            return UIImage(cgImage: cgImage)
        }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(convert(observation.topLeft),     forKey: "inputTopLeft")
        filter.setValue(convert(observation.topRight),    forKey: "inputTopRight")
        filter.setValue(convert(observation.bottomRight), forKey: "inputBottomRight")
        filter.setValue(convert(observation.bottomLeft),  forKey: "inputBottomLeft")

        let context = CIContext()
        guard
            let output = filter.outputImage,
            let cgOut   = context.createCGImage(output, from: output.extent)
        else {
            return UIImage(cgImage: cgImage)
        }
        return UIImage(cgImage: cgOut)
    }
}
