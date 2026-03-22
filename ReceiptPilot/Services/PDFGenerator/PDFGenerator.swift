// PDFGenerator.swift
// Generates a clean PDF from a receipt image, suitable for archival and upload.

import UIKit
import PDFKit

struct PDFGenerator {

    /// Generate a single-page PDF from a receipt image.
    /// The image is fit to an A4-ish page with margins.
    static func generatePDF(from image: UIImage, receipt: Receipt? = nil) -> Data {
        let pageWidth: CGFloat = 612   // US Letter width in points
        let pageHeight: CGFloat = 792  // US Letter height in points
        let margin: CGFloat = 36       // 0.5 inch margin

        let availableWidth = pageWidth - margin * 2
        let availableHeight = pageHeight - margin * 2

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        )

        return renderer.pdfData { context in
            context.beginPage()

            // Scale image to fit within available space
            let imageAspect = image.size.width / image.size.height
            var drawWidth = availableWidth
            var drawHeight = drawWidth / imageAspect

            if drawHeight > availableHeight {
                drawHeight = availableHeight
                drawWidth = drawHeight * imageAspect
            }

            let x = margin + (availableWidth - drawWidth) / 2
            let y = margin

            let imageRect = CGRect(x: x, y: y, width: drawWidth, height: drawHeight)
            image.draw(in: imageRect)

            // Optional: add metadata footer
            if let receipt {
                let footerY = y + drawHeight + 12
                if footerY < pageHeight - margin {
                    let footerText = "\(receipt.merchant) | \(receipt.date) | \(String(format: "%.2f", receipt.total)) \(receipt.currency)"
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 9, weight: .regular),
                        .foregroundColor: UIColor.darkGray
                    ]
                    let footerStr = NSAttributedString(string: footerText, attributes: attrs)
                    footerStr.draw(at: CGPoint(x: margin, y: footerY))
                }
            }
        }
    }

    /// Save PDF to local Documents directory. Returns the file URL.
    static func savePDF(_ data: Data, filename: String) -> URL? {
        let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("receipts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let sanitized = sanitizeFilename(filename)
        let url = dir.appendingPathComponent("\(sanitized).pdf")

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("[PDFGenerator] Failed to save PDF: \(error)")
            return nil
        }
    }

    /// Sanitize a string for use as a filename.
    static func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name
            .components(separatedBy: invalidChars)
            .joined(separator: "-")
            .replacingOccurrences(of: " ", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
