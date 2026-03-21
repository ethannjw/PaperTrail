import XCTest
@testable import PaperTrail

final class ImageProcessorTests: XCTestCase {

    private func createTestImage(width: CGFloat = 200, height: CGFloat = 300) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // Draw some "text-like" content
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 20, y: 50, width: 160, height: 2))
            ctx.fill(CGRect(x: 20, y: 70, width: 120, height: 2))
        }
    }

    func test_enhanceReceipt_returnsImage() {
        let input = createTestImage()
        let output = ImageProcessor.enhanceReceipt(input, grayscale: true)
        XCTAssertNotNil(output)
        XCTAssertGreaterThan(output.size.width, 0)
    }

    func test_enhanceReceipt_colorMode() {
        let input = createTestImage()
        let output = ImageProcessor.enhanceReceipt(input, grayscale: false)
        XCTAssertNotNil(output)
    }

    func test_adaptiveThreshold_returnsImage() {
        let input = createTestImage()
        let output = ImageProcessor.adaptiveThreshold(input)
        XCTAssertNotNil(output)
        XCTAssertGreaterThan(output.size.width, 0)
    }
}
