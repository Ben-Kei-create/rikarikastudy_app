import XCTest

/// The app is portrait-only: rotating the device must not change the layout.
final class PortraitLockUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-debugXP", "0"]
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testRotatingTheDeviceKeepsPortraitAndQuizWorks() {
        let app = launch()
        app.buttons["スタート"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "第1問")).firstMatch.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        let w = app.windows.firstMatch.frame
        XCTAssertGreaterThan(w.height, w.width, "app must stay portrait, got \(w)")
        attach(app, "after-rotate-attempt")
        let choiceA = app.buttons.matching(NSPredicate(format: "label CONTAINS 'A'")).firstMatch
        XCTAssertTrue(choiceA.waitForExistence(timeout: 3))
        choiceA.tap()
        let next = app.buttons["次の問題へ"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        XCTAssertTrue(next.isHittable)
        attach(app, "explanation")
        next.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "第2問")).firstMatch.waitForExistence(timeout: 3))
    }
}
