import XCTest
@testable import AurixCore

final class BodyProgressTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return result
    }
    private func date(_ day: Int, hour: Int = 8) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }
    func testOldArchiveMigratesWithoutLosingDiary() throws {
        var profile = UserProfile(); profile.name = "Maurus"
        let entry = FoodEntry(name: "Meal", nutrition: Nutrition(calories: 300))
        let meal = SavedMeal(name: "Meal", nutrition: entry.nutrition)
        let old = Archive(profile: profile, entries: [entry], meals: [meal])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json["schemaVersion"] = 1; json.removeValue(forKey: "measurements")
        let migrated = try JSONDecoder().decode(Archive.self, from: JSONSerialization.data(withJSONObject: json)).validated()
        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(migrated.profile, profile)
        XCTAssertEqual(migrated.entries, [entry]); XCTAssertEqual(migrated.meals, [meal])
        XCTAssertTrue(migrated.measurements.isEmpty)
        json["schemaVersion"] = 2
        XCTAssertThrowsError(try JSONDecoder().decode(Archive.self, from: JSONSerialization.data(withJSONObject: json)))
        json["schemaVersion"] = 3
        XCTAssertThrowsError(try JSONDecoder().decode(Archive.self, from: JSONSerialization.data(withJSONObject: json)))
    }
    func testMeasurementRoundTripAndValidation() throws {
        let weight = BodyMeasurement(metric: .weight, value: 82.5, date: date(29))
        let waist = BodyMeasurement(metric: .waist, value: 85.5, date: date(29))
        let original = Archive(measurements: [weight, waist])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(Archive.self, from: encoder.encode(original)).validated().measurements, original.measurements)
        XCTAssertThrowsError(try Archive(measurements: [weight, weight]).validated())
        for value in [Double.nan, .infinity, -1, 0, 301] {
            XCTAssertFalse(BodyMeasurement(metric: .weight, value: value).isValid)
        }
        XCTAssertFalse(BodyMeasurement(metric: .waist, value: 251).isValid)
        XCTAssertTrue(BodyMeasurement(metric: .weight, value: 35).isValid)
        XCTAssertTrue(BodyMeasurement(metric: .weight, value: 300).isValid)
    }
    func testSaveUpdatesSameDayAndMovingDateRemovesOldValue() {
        let original = BodyMeasurement(metric: .weight, value: 80, date: date(28))
        let waist = BodyMeasurement(metric: .waist, value: 86, date: date(28))
        let replacement = BodyMeasurement(metric: .weight, value: 80.5, date: date(28, hour: 10))
        let saved = BodyProgress.upserting(replacement, into: [original, waist], calendar: calendar)
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved.first { $0.metric == .weight }?.id, original.id)
        XCTAssertEqual(saved.first { $0.metric == .weight }?.value, 80.5)
        var moved = saved.first { $0.metric == .weight }!; moved.date = date(29)
        let next = BodyProgress.upserting(moved, into: saved, calendar: calendar)
        XCTAssertEqual(next.filter { $0.metric == .weight }.count, 1)
        XCTAssertEqual(next.first { $0.metric == .weight }?.date, date(29))
    }
    func testMergePreservesLocalDayAndIsIdempotent() {
        let local = BodyMeasurement(metric: .weight, value: 80.5, date: date(28))
        let stale = BodyMeasurement(metric: .weight, value: 82, date: date(28, hour: 9))
        let other = BodyMeasurement(metric: .waist, value: 86, date: date(28))
        let incoming = [stale, other]
        let merged = BodyProgress.merging(incoming, into: [local], calendar: calendar)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first { $0.metric == .weight }?.value, 80.5)
        XCTAssertEqual(BodyProgress.merging(incoming, into: merged, calendar: calendar), merged)
    }
    func testCadenceUsesCalendarDaysAcrossDaylightSaving() {
        let weight = BodyMeasurement(metric: .weight, value: 80, date: date(28))
        let waist = BodyMeasurement(metric: .waist, value: 86, date: date(23))
        XCTAssertFalse(BodyProgress.isDue(.weight, measurements: [weight], now: date(28, hour: 20), calendar: calendar))
        XCTAssertTrue(BodyProgress.isDue(.weight, measurements: [weight], now: date(29), calendar: calendar))
        XCTAssertFalse(BodyProgress.isDue(.waist, measurements: [waist], now: date(29), calendar: calendar))
        XCTAssertTrue(BodyProgress.isDue(.waist, measurements: [waist], now: date(30), calendar: calendar))
    }
    func testWeeklyAverageUsesCalendarWindowNotSevenReadings() {
        let items = [(20, 100.0), (23, 80.0), (28, 82.0), (29, 84.0), (30, 86.0)].map {
            BodyMeasurement(metric: .weight, value: $0.1, date: date($0.0))
        }
        let points = BodyProgress.series(items, metric: .weight, through: date(30, hour: 12), calendar: calendar)
        let average = BodyProgress.rollingWeek(points, calendar: calendar)
        let last = average.last!
        XCTAssertEqual(last.count, 3)
        XCTAssertEqual(last.value, 84, accuracy: 0.001)
        XCTAssertEqual(points.count, 5) // Missing days are not invented.
        XCTAssertEqual(average.first?.count, 2)
        XCTAssertTrue(BodyProgress.rollingWeek(Array(points.prefix(1)), calendar: calendar).isEmpty)
    }
    func testSeriesUsesLatestDayValueAndExcludesFuture() {
        let values = [BodyMeasurement(metric: .weight, value: 80, date: date(28)),
                      BodyMeasurement(metric: .weight, value: 81, date: date(28, hour: 9)),
                      BodyMeasurement(metric: .weight, value: 82, date: date(30)),
                      BodyMeasurement(metric: .waist, value: 86, date: date(28))]
        let series = BodyProgress.series(values, metric: .weight, through: date(29), calendar: calendar)
        XCTAssertEqual(series.count, 1); XCTAssertEqual(series.first?.value, 81)
    }
    func testAIRejectsMissingPortionAndImpossibleMacroEnergy() throws {
        func result(_ calories: Int, portion: String) throws -> MealEstimate {
            let json: [String: Any] = ["is_food": true, "name": "Meal", "calories": calories, "protein": 100, "carbs": 100, "fat": 100, "portion": portion, "note": ""]
            return try JSONDecoder().decode(MealEstimate.self, from: JSONSerialization.data(withJSONObject: json))
        }
        XCTAssertThrowsError(try result(100, portion: "1 Portion").entry(date: Date(), slot: .lunch, source: .photo))
        XCTAssertThrowsError(try result(1700, portion: " ").entry(date: Date(), slot: .lunch, source: .photo))
        XCTAssertNoThrow(try result(1700, portion: "1 Portion").entry(date: Date(), slot: .lunch, source: .photo))
    }
    func testUsageEstimateCountsCachedTokensWithoutDoubleCounting() throws {
        let data = Data(#"{"usage":{"input_tokens":2000,"output_tokens":300,"input_tokens_details":{"cached_tokens":1000}}}"#.utf8)
        let receipt = try XCTUnwrap(AIUsage.receipt(from: data))
        XCTAssertEqual(receipt.estimatedUSD, 0.0058, accuracy: 0.0000001)
        XCTAssertNil(AIUsage.receipt(from: Data("{}".utf8)))
    }
}
