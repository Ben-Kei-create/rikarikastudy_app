import XCTest

final class SettingsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["せってい"].tap()
        XCTAssertTrue(app.navigationBars["せってい"].waitForExistence(timeout: 3))
    }

    func testTogglesSwitchOffAndStaySavedAfterRelaunch() {
        let titles = ["BGM", "効果音・ボイス", "演出（振動・光・スタンプ）", "ハプティクス（端末の振動）"]
        let app = XCUIApplication()
        app.launchArguments = ["-settings.bgm", "YES", "-settings.sfx", "YES",
                               "-settings.effects", "YES", "-settings.haptics", "YES"]
        app.launch()
        openSettings(app)
        for t in titles {
            let sw = app.switches[t]
            XCTAssertTrue(sw.waitForExistence(timeout: 3), t)
            XCTAssertEqual(sw.value as? String, "1", "\(t) should start ON")
        }
        // Turn off 演出 and 効果音 only.
        // Tap the switch itself (right end of the row); a Toggle row's centre is only its label.
        for t in [titles[1], titles[2]] {
            app.switches[t].coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        sleep(1)
        XCTAssertEqual(app.switches[titles[1]].value as? String, "0")
        XCTAssertEqual(app.switches[titles[2]].value as? String, "0")
        XCTAssertEqual(app.switches[titles[0]].value as? String, "1")
        XCTAssertEqual(app.switches[titles[3]].value as? String, "1")
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "settings-toggled"; a.lifetime = .keepAlways; add(a)

        // Relaunch WITHOUT the override arguments: saved values must come back.
        app.terminate()
        let again = XCUIApplication()
        again.launch()
        openSettings(again)
        XCTAssertEqual(again.switches[titles[1]].value as? String, "0", "効果音 stays OFF")
        XCTAssertEqual(again.switches[titles[2]].value as? String, "0", "演出 stays OFF")
        XCTAssertEqual(again.switches[titles[0]].value as? String, "1", "BGM stays ON")
        XCTAssertEqual(again.switches[titles[3]].value as? String, "1", "ハプティクス stays ON")
    }
}
