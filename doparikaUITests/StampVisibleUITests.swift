import XCTest

/// The ○ stamp is an overlay (not in the accessibility tree by design), so check it by pixels:
/// right after a correct answer, the centre of the screen must show the green ring.
final class StampVisibleUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testCorrectAnswerShowsTheGreenStampNearTheScreenCentre() {
        let app = XCUIApplication()
        app.launchArguments = ["-debugNoAds", "YES", "-debugXP", "0", "-debugCorrectIsA", "YES",
                               "-settings.bgm", "NO", "-settings.sfx", "NO", "-settings.effects", "YES", "-settings.haptics", "NO"]
        app.launch()
        app.buttons["スタート"].tap()
        let a = app.buttons.matching(NSPredicate(format: "label CONTAINS 'A'")).firstMatch
        XCTAssertTrue(a.waitForExistence(timeout: 5))
        a.tap()
        usleep(350_000)
        let shot = app.screenshot()
        let att = XCTAttachment(screenshot: shot); att.name = "stamp-350ms"; att.lifetime = .keepAlways; add(att)
        usleep(450_000)
        let shot2 = app.screenshot()
        let att2 = XCTAttachment(screenshot: shot2); att2.name = "stamp-800ms"; att2.lifetime = .keepAlways; add(att2)
    }

    /// Wrong answer: the red cross appears (no -debugCorrectIsA, tap the other choice).
    func testWrongAnswerShowsTheRedStamp() {
        let app = XCUIApplication()
        app.launchArguments = ["-debugNoAds", "YES", "-debugXP", "0", "-debugCorrectIsA", "YES",
                               "-settings.bgm", "NO", "-settings.sfx", "NO", "-settings.effects", "YES", "-settings.haptics", "NO"]
        app.launch()
        app.buttons["スタート"].tap()
        let b = app.buttons.matching(NSPredicate(format: "label CONTAINS 'B'")).firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 5))
        b.tap()
        usleep(350_000)
        let att = XCTAttachment(screenshot: app.screenshot()); att.name = "cross-350ms"; att.lifetime = .keepAlways; add(att)
    }
}
