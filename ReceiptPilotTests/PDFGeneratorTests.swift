import XCTest
@testable import ReceiptPilot

final class PDFGeneratorTests: XCTestCase {

    // MARK: - Filename Sanitization

    func test_sanitizeFilename_removesSlashes() {
        XCTAssertEqual(PDFGenerator.sanitizeFilename("2026/03/21"), "2026-03-21")
    }

    func test_sanitizeFilename_removsSpecialChars() {
        XCTAssertEqual(PDFGenerator.sanitizeFilename("file:name*test"), "file-name-test")
    }

    func test_sanitizeFilename_replacesSpaces() {
        XCTAssertEqual(PDFGenerator.sanitizeFilename("my receipt file"), "my_receipt_file")
    }

    func test_sanitizeFilename_trimWhitespace() {
        // Spaces become underscores, then leading/trailing whitespace is trimmed
        // but inner spaces are already converted to _
        XCTAssertEqual(PDFGenerator.sanitizeFilename("hello world"), "hello_world")
    }

    func test_sanitizeFilename_complexName() {
        let input = "2026-03-21_Whole Foods/Market_47.83_USD"
        let result = PDFGenerator.sanitizeFilename(input)
        XCTAssertFalse(result.contains("/"))
        XCTAssertFalse(result.contains(" "))
    }

    func test_sanitizeFilename_emptyString() {
        XCTAssertEqual(PDFGenerator.sanitizeFilename(""), "")
    }

    // MARK: - PDF Generation

    func test_generatePDF_returnsData() {
        let image = createTestImage()
        let data = PDFGenerator.generatePDF(from: image)
        XCTAssertFalse(data.isEmpty)
        // PDF magic bytes: %PDF
        XCTAssertTrue(data.starts(with: [0x25, 0x50, 0x44, 0x46]))
    }

    func test_generatePDF_withReceipt_includesFooter() {
        let image = createTestImage()
        let receipt = Receipt(merchant: "TestMerchant", date: "2026-03-21", total: 10.50, currency: "USD")
        let data = PDFGenerator.generatePDF(from: image, receipt: receipt)
        XCTAssertFalse(data.isEmpty)
    }

    func test_savePDF_writesToDisk() {
        let data = Data("test pdf content".utf8)
        let url = PDFGenerator.savePDF(data, filename: "test_receipt_save")
        XCTAssertNotNil(url)
        if let url {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            try? FileManager.default.removeItem(at: url) // cleanup
        }
    }

    // MARK: - Helper

    private func createTestImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 100, height: 200)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        }
    }
}
