import XCTest
@testable import AurixCore

final class AurixCoreTests: XCTestCase {
    private let values = Nutrition(calories: 200, protein: 10, carbs: 25, fat: 6)
    func testWholeSandwich() throws {
        let product = ProductRecord(barcode: "12345678", name: "Poulet Sandwich", quantityText: "180 g", quantity: 180, serving: "90 g", per100: values)
        let result = try ProductResolver.resolve(product)
        XCTAssertEqual(result.amount, 180)
        XCTAssertEqual(result.nutrition.calories, 360)
        XCTAssertFalse(result.assumed)
    }
    func testSingleDrinkUsesWholeBottle() throws {
        let product = ProductRecord(barcode: "12345678", name: "Protein drink", quantityText: "0,5 l", quantity: 500, quantityUnit: "ml", serving: "100 ml", per100: values)
        let result = try ProductResolver.resolve(product)
        XCTAssertEqual(result.amount, 500)
        XCTAssertEqual(result.unit, "ml")
        XCTAssertEqual(result.nutrition.protein, 50)
    }
    func testMultipackDoesNotBecomeOneMeal() throws {
        let product = ProductRecord(barcode: "12345678", name: "Protein bar", quantityText: "6 x 25 g", quantity: 150, per100: values)
        let result = try ProductResolver.resolve(product)
        XCTAssertEqual(result.amount, 25)
        XCTAssertEqual(result.nutrition.calories, 50)
    }
    func testRiceUsesServingNotEntirePack() throws {
        let product = ProductRecord(barcode: "12345678", name: "Reis", quantityText: "1 kg", quantity: 1000, serving: "1 Portion (75 g)", per100: values)
        XCTAssertEqual(try ProductResolver.resolve(product).amount, 75)
    }
    func testUnknownPortionExplicitlyAssumed() throws {
        let product = ProductRecord(barcode: "12345678", name: "Mischung", per100: values)
        let result = try ProductResolver.resolve(product)
        XCTAssertTrue(result.assumed)
        XCTAssertEqual(result.amount, 100)
    }
    func testLargeYogurtTubIsNotSingleServing() throws {
        let product = ProductRecord(barcode: "12345678", name: "Joghurt", quantityText: "1 kg", quantity: 1000, serving: "150 g", per100: values)
        XCTAssertEqual(try ProductResolver.resolve(product).amount, 150)
    }
    func testBarbecueSauceIsNotAProteinBar() throws {
        let product = ProductRecord(barcode: "12345678", name: "Barbecue Sauce", quantityText: "200 g", quantity: 200, serving: "20 g", per100: values)
        XCTAssertEqual(try ProductResolver.resolve(product).amount, 20)
    }
    func testMeasurementConversion() {
        XCTAssertEqual(ProductResolver.measurement(in: "1 Becher (180 g)")?.amount, 180)
        XCTAssertEqual(ProductResolver.measurement(in: "1,5 l")?.amount, 1500)
        XCTAssertEqual(ProductResolver.measurement(in: "33 cl")?.amount, 330)
        XCTAssertNil(ProductResolver.measurement(in: "1 portion"))
    }
    func testRejectsInvalidNumbers() {
        XCTAssertFalse(Nutrition(calories: .infinity).isValid)
        XCTAssertFalse(Nutrition(protein: -1).isValid)
        XCTAssertFalse(Nutrition(fat: .nan).isValid)
        XCTAssertTrue(Nutrition.zero.isValid)
    }
    func testGoalCalculationAndDirection() {
        var profile = UserProfile(); profile.age = 20; profile.height = 189; profile.weight = 80; profile.activity = 1.55
        let maintain = GoalCalculator.suggested(for: profile)
        profile.direction = .gain
        let gain = GoalCalculator.suggested(for: profile)
        XCTAssertEqual(gain.calories - maintain.calories, 250, accuracy: 1)
        XCTAssertEqual(gain.protein, 144)
        XCTAssertEqual(gain.protein * 4 + gain.carbs * 4 + gain.fat * 9, gain.calories, accuracy: 3)
    }
    func testCalendarAssignmentAndStreakAcrossDaylightSaving() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        func date(_ day: Int, _ hour: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))! }
        XCTAssertEqual(MealSlot.suggested(at: date(29, 8), calendar: calendar), .breakfast)
        XCTAssertEqual(MealSlot.suggested(at: date(29, 12), calendar: calendar), .lunch)
        XCTAssertEqual(MealSlot.suggested(at: date(29, 19), calendar: calendar), .dinner)
        let entries = [27,28,29].map { FoodEntry(name: "Meal", nutrition: values, date: date($0, 12)) }
        XCTAssertEqual(GoalCalculator.trackingStreak(entries: entries, now: date(30, 10), calendar: calendar), 3)
    }
    func testArchiveRoundTripAndDuplicateRejection() throws {
        let entry = FoodEntry(name: "Meal", nutrition: values)
        let archive = Archive(entries: [entry])
        let data = try JSONEncoder().encode(archive)
        XCTAssertEqual(try JSONDecoder().decode(Archive.self, from: data).validated().entries, [entry])
        XCTAssertThrowsError(try Archive(entries: [entry, entry]).validated())
        var future = archive; future.schemaVersion = 2
        XCTAssertThrowsError(try future.validated())
    }
    func testAIContractHasStrictSchemaAndNoProfile() throws {
        let data = try AIContract.body(text: "zwei Eier", imageData: Data([1, 2, 3]))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["store"] as? Bool, false)
        XCTAssertNil(root["profile"])
        let text = try XCTUnwrap(root["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["strict"] as? Bool, true)
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual(Set(schema["required"] as? [String] ?? []), Set(properties.keys))
    }
    func testAIResponseAndRefusal() throws {
        let meal: [String: Any] = ["is_food": true, "name": "Eier", "calories": 160, "protein": 13, "carbs": 1, "fat": 11, "portion": "2 Eier", "note": ""]
        let json = String(data: try JSONSerialization.data(withJSONObject: meal), encoding: .utf8)!
        let envelope: [String: Any] = ["status": "completed", "output": [["content": [["type": "output_text", "text": json]]]]]
        let result = try AIContract.parse(JSONSerialization.data(withJSONObject: envelope))
        XCTAssertEqual(try result.entry(date: Date(), slot: .breakfast, source: .photo).nutrition.protein, 13)
        let refusal: [String: Any] = ["status": "completed", "output": [["content": [["type": "refusal"]]]]]
        XCTAssertThrowsError(try AIContract.parse(JSONSerialization.data(withJSONObject: refusal)))
        let incomplete: [String: Any] = ["status": "incomplete", "output": [["content": [["type": "output_text", "text": json]]]]]
        XCTAssertThrowsError(try AIContract.parse(JSONSerialization.data(withJSONObject: incomplete)))
    }
    func testNotFoodCannotCreateEntry() throws {
        let json = #"{"is_food":false,"name":"","calories":0,"protein":0,"carbs":0,"fat":0,"portion":"","note":""}"#
        let result = try JSONDecoder().decode(MealEstimate.self, from: Data(json.utf8))
        XCTAssertThrowsError(try result.entry(date: Date(), slot: .snack, source: .photo))
    }
}
