import XCTest
@testable import PaperTrail

final class UIImageExtensionsTests: XCTestCase {

    func test_resizedIfNeeded_smallImage_unchanged() {
        let image = createImage(width: 100, height: 100)
        let result = image.resizedIfNeeded(maxDimension: 500)
        XCTAssertEqual(result.size.width, 100, accuracy: 1)
        XCTAssertEqual(result.size.height, 100, accuracy: 1)
    }

    func test_resizedIfNeeded_largeImage_scaled() {
        let image = createImage(width: 2000, height: 1000)
        let result = image.resizedIfNeeded(maxDimension: 500)
        XCTAssertEqual(result.size.width, 500, accuracy: 1)
        XCTAssertEqual(result.size.height, 250, accuracy: 1)
    }

    func test_resizedIfNeeded_tallImage_scaled() {
        let image = createImage(width: 500, height: 3000)
        let result = image.resizedIfNeeded(maxDimension: 1500)
        XCTAssertEqual(result.size.height, 1500, accuracy: 1)
        XCTAssertEqual(result.size.width, 250, accuracy: 1)
    }

    func test_resizedIfNeeded_exactDimension_unchanged() {
        let image = createImage(width: 500, height: 500)
        let result = image.resizedIfNeeded(maxDimension: 500)
        XCTAssertEqual(result.size.width, 500, accuracy: 1)
    }

    func test_fixedOrientation_upImage_unchanged() {
        let image = createImage(width: 100, height: 100)
        let result = image.fixedOrientation()
        XCTAssertEqual(result.size.width, 100, accuracy: 1)
    }

    private func createImage(width: CGFloat, height: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}
