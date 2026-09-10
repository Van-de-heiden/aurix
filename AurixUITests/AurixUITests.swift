import XCTest

final class AurixUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testWelcomeAndFirstQuestion() {
        let app = XCUIApplication()
        app.launchArguments = ["-screenshots-welcome"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.start"].waitForExistence(timeout: 10))
        capture("01-welcome")
        app.buttons["onboarding.start"].tap()
        XCTAssertTrue(app.textFields["Dein Vorname"].waitForExistence(timeout: 5))
        capture("02-onboarding")
    }
    func testDashboardAndManualCapture() {
        let app = XCUIApplication()
        app.launchArguments = ["-screenshots-dashboard"]
        app.launch()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(tabs.frame.minY, app.frame.height * 0.8)
        XCTAssertGreaterThan(tabs.frame.maxY, app.frame.maxY - 60)
        capture("03-dashboard")
        tabs.buttons["Meine Meals"].tap()
        XCTAssertTrue(app.navigationBars["Meine Meals"].waitForExistence(timeout: 5))
        tabs.buttons["Erfassen"].tap()
        XCTAssertTrue(app.buttons["capture.Manuell"].waitForExistence(timeout: 5))
        app.buttons["capture.Manuell"].tap()
        capture("04-manual")
        let name = app.textFields["Was hast du gegessen?"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Test Meal")
        if app.buttons["Fertig"].exists { app.buttons["Fertig"].firstMatch.tap() }
        let save = app.buttons["Jetzt erfassen"]
        if !save.isHittable { app.swipeUp() }
        save.tap()
        XCTAssertTrue(app.staticTexts["Dein Tag, Maurus."].waitForExistence(timeout: 5))
        // Saving from the capture tab returns to the diary with the new entry.
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Test Meal"].firstMatch.waitForExistence(timeout: 5))
        capture("05-saved")
        tabs.buttons["Meine Meals"].tap()
        app.staticTexts["Test Meal"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Rückgängig"].waitForExistence(timeout: 5))
        app.buttons["Rückgängig"].tap()
        // The slot-specific shortcut still opens capture as a dismissible sheet.
        let breakfast = app.buttons["Zum Morgenessen hinzufügen"]
        if !breakfast.isHittable { app.swipeUp() }
        breakfast.tap()
        XCTAssertTrue(app.buttons["Schliessen"].waitForExistence(timeout: 5))
        app.buttons["Schliessen"].tap()
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
    }
    func testWeightWheelsAndOnboardingCompletion() {
        let app = XCUIApplication()
        app.launchArguments = ["-screenshots-welcome"]
        app.launch()
        app.buttons["onboarding.start"].tap()
        let name = app.textFields["Dein Vorname"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Maurus")
        let next = app.buttons["onboarding.next"]
        next.tap() // Goal
        next.tap() // Age
        next.tap() // Height
        next.tap() // Current weight
        XCTAssertTrue(app.staticTexts["Was wiegst du aktuell?"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.pickerWheels.count, 2)
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "82")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: ".5")
        capture("06-weight-wheels")
        next.tap() // Formula
        app.buttons["Zurück"].tap()
        XCTAssertEqual(app.pickerWheels.element(boundBy: 0).value as? String, "82")
        XCTAssertEqual(app.pickerWheels.element(boundBy: 1).value as? String, ".5")
        // The upper limit stays at 200 kg; returning below it restores both fractions.
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "200")
        XCTAssertEqual(app.pickerWheels.element(boundBy: 1).value as? String, ".0")
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "82")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: ".5")
        next.tap() // Formula
        next.tap() // Activity
        next.tap() // Target weight
        XCTAssertTrue(app.staticTexts["Wo möchtest du hin?"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.pickerWheels.count, 2)
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "85")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: ".5")
        next.tap() // Suggested goals
        next.tap() // Save and finish
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Dein Tag, Maurus."].exists)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
