import XCTest
@testable import AurixCore

final class ScannerTests: XCTestCase {
    func testCanonicalProductCodeAcrossUPCAEANAndGTIN() {
        XCTAssertEqual(Barcode.normalized("036000291452"), "0036000291452")
        XCTAssertEqual(Barcode.normalized("0036000291452"), "0036000291452")
        XCTAssertEqual(Barcode.normalized("00036000291452"), "0036000291452")
        XCTAssertEqual(Barcode.normalized(" 96385074\n"), "96385074")
        XCTAssertEqual(Barcode.normalized("4006381333931"), "4006381333931")
    }
    func testRejectsCorruptedAndNonProductBarcodes() {
        for code in ["", "123", "4006381333932", "40063813339a1", "４００６３８１３３３９３１", "4006381333931000"] {
            XCTAssertNil(Barcode.normalized(code), code)
        }
    }
    func testUPCEExpandsBeforeLookup() {
        XCTAssertEqual(Barcode.expandedUPCE("04252614"), "0042100005264")
        XCTAssertNil(Barcode.expandedUPCE("04252615"))
        XCTAssertNil(Barcode.expandedUPCE("94252614"))
    }
    func testDecodesProductWithCommaNumbersAndKilojoules() throws {
        let data = Data(#"{"status":1,"product":{"product_name_de":"  ","product_name":"Protein drink","quantity":"330 ml","product_quantity":330,"product_quantity_unit":"ml","nutriments":{"energy-kj_100g":418.4,"proteins_100g":"10,5","carbohydrates_100g":12,"fat_100g":1}}}"#.utf8)
        let product = try ProductDecoder.decode(data, barcode: "4006381333931")
        XCTAssertEqual(product.name, "Protein drink")
        XCTAssertEqual(product.per100.calories, 100, accuracy: 0.001)
        XCTAssertEqual(product.per100.protein, 10.5)
        let portion = try ProductResolver.resolve(product)
        XCTAssertEqual(portion.amount, 330)
        XCTAssertEqual(portion.nutrition.calories, 330, accuracy: 0.001)
    }
    func testUnknownProductIsDifferentFromMissingNutrients() {
        XCTAssertThrowsError(try ProductDecoder.decode(Data(#"{"status":0}"#.utf8), barcode: "96385074")) { error in
            guard case ProductLookupError.notFound = error else { return XCTFail("Expected unknown product, got \(error)") }
        }
        XCTAssertThrowsError(try ProductDecoder.decode(Data(#"{"status":1,"product":{"product_name":"Drink","nutriments":{"energy-kcal_100g":100}}}"#.utf8), barcode: "96385074")) { error in
            guard case ProductLookupError.incomplete = error else { return XCTFail("Missing macros must not become zero") }
        }
    }
    func testRejectsImpossibleProductNutrition() {
        XCTAssertThrowsError(try ProductDecoder.decode(Data("not json".utf8), barcode: "96385074"))
        let data = Data(#"{"status":1,"product":{"product_name":"Drink","nutriments":{"energy-kcal_100g":100,"proteins_100g":-1,"carbohydrates_100g":12,"fat_100g":1}}}"#.utf8)
        XCTAssertThrowsError(try ProductDecoder.decode(data, barcode: "96385074"))
    }
}
