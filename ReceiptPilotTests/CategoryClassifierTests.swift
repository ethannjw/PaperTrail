import XCTest
@testable import ReceiptPilot

final class CategoryClassifierTests: XCTestCase {

    func test_classify_foodByKeyword() async {
        let result = await CategoryClassifier.classify(merchant: "McDonald's Restaurant", items: [])
        XCTAssertEqual(result, ReceiptCategory.food.rawValue)
    }

    func test_classify_foodByItem() async {
        let items = [ReceiptItem(name: "Pizza Margherita", quantity: 1, price: 12)]
        let result = await CategoryClassifier.classify(merchant: "Some Place", items: items)
        XCTAssertEqual(result, ReceiptCategory.food.rawValue)
    }

    func test_classify_foodByCafe() async {
        let result = await CategoryClassifier.classify(merchant: "Blue Bottle Cafe", items: [])
        XCTAssertEqual(result, ReceiptCategory.food.rawValue)
    }

    func test_classify_transport() async {
        let result = await CategoryClassifier.classify(merchant: "Grab Taxi", items: [])
        XCTAssertEqual(result, ReceiptCategory.transport.rawValue)
    }

    func test_classify_shopping() async {
        let result = await CategoryClassifier.classify(merchant: "Amazon", items: [])
        XCTAssertEqual(result, ReceiptCategory.shopping.rawValue)
    }

    func test_classify_health() async {
        let result = await CategoryClassifier.classify(merchant: "Guardian Pharmacy", items: [])
        XCTAssertEqual(result, ReceiptCategory.health.rawValue)
    }

    func test_classify_entertainment() async {
        let result = await CategoryClassifier.classify(merchant: "Netflix", items: [])
        XCTAssertEqual(result, ReceiptCategory.entertainment.rawValue)
    }

    func test_classify_travel() async {
        let result = await CategoryClassifier.classify(merchant: "Airbnb Booking", items: [])
        XCTAssertEqual(result, ReceiptCategory.travel.rawValue)
    }

    func test_classify_unknown_returnsOther() async {
        let result = await CategoryClassifier.classify(merchant: "XYZABC Corp", items: [])
        XCTAssertEqual(result, ReceiptCategory.other.rawValue)
    }

    func test_classify_caseInsensitive() async {
        // "cafe" is in the food keywords, lowercased matching should work
        let result = await CategoryClassifier.classify(merchant: "BLUE BOTTLE CAFE", items: [])
        XCTAssertEqual(result, ReceiptCategory.food.rawValue)
    }
}
