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
        XCTAssertTrue(app.buttons["capture.open"].waitForExistence(timeout: 10))
        capture("03-dashboard")
        app.buttons["capture.open"].tap()
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
        XCTAssertTrue(app.buttons["capture.open"].waitForExistence(timeout: 5))
        // Persisted entry is visible in the diary after the capture sheet dismisses.
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Test Meal"].firstMatch.waitForExistence(timeout: 5))
        capture("05-saved")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
