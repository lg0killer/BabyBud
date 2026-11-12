import XCTest

final class BabyBuddyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["BABYBUDDY_UI_TEST_ID"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    private func createChild() {
        let create = app.buttons["Create child profile"]
        XCTAssertTrue(create.waitForExistence(timeout: 20))
        create.tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        enter("Robin Test", into: name)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Log feeding"].waitForExistence(timeout: 5))
    }

    private func enter(_ text: String, into field: XCUIElement) {
        let hittable = NSPredicate(format: "hittable == true")
        expectation(for: hittable, evaluatedWith: field)
        waitForExpectations(timeout: 10)
        field.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 5) { field.tap() }
        field.typeText(text)
    }

    func testLogCareAndRestoreSleepAfterRelaunch() {
        createChild()
        app.buttons["Log feeding"].tap()
        let amount = app.textFields["Amount (ml)"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        enter("90", into: amount)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Bottle feeding"].waitForExistence(timeout: 5))
        app.buttons["Log diaper"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Wet diaper"].waitForExistence(timeout: 5))
        app.buttons["Start sleep"].tap()
        XCTAssertTrue(app.buttons["End sleep"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["End sleep"].waitForExistence(timeout: 15))
        app.buttons["End sleep"].tap()
        XCTAssertTrue(app.buttons["Start sleep"].waitForExistence(timeout: 5))
        app.tabBars.buttons["History"].tap()
        XCTAssertEqual(app.staticTexts.matching(identifier: "Sleep").count, 1)
        XCTAssertTrue(app.staticTexts["Bottle feeding"].exists)
        XCTAssertTrue(app.staticTexts["Wet diaper"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "History after logging and relaunch"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testInvalidBottleAndCancelledEntryDoNotCreateRecords() {
        createChild()
        app.buttons["Log feeding"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Enter a bottle amount greater than zero."].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["No activities yet"].exists)
        app.tabBars.buttons["Family"].tap()
        XCTAssertTrue(app.staticTexts["Local testing build"].exists)
        XCTAssertFalse(app.buttons["Invite or manage caregivers"].isEnabled)
    }
}
