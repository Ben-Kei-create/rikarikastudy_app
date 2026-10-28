import XCTest

/// Crossing Lv.31 during a run opens space: the result screen announces it.
final class StageUnlockUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// `-debugXP` only ever raises XP, and the simulator keeps progress between runs: wipe it first through
    /// the app's own "進行状況を初期化" so this test always starts from zero.
    private func resetProgress() {
        let app = XCUIApplication()
        app.launchArguments = ["-debugNoAds", "YES", "-settings.bgm", "NO", "-settings.sfx", "NO", "-settings.effects", "NO", "-settings.haptics", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["せってい"].waitForExistence(timeout: 8))
        app.buttons["せってい"].tap()
        let reset = app.buttons["進行状況を初期化"]
        XCTAssertTrue(reset.waitForExistence(timeout: 4)); reset.tap()
        let confirm = app.buttons["初期化する"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 4)); confirm.tap()
        sleep(1)
        app.terminate()
    }

    func testResultAnnouncesSpaceWhenLevel31IsReached() {
        resetProgress()
        let app = XCUIApplication()
        // 10 XP below the Lv.31 threshold (12,420): the first correct answer crosses it.
        app.launchArguments = ["-debugNoAds", "YES", "-debugXP", "12410", "-debugCorrectIsA", "YES",
                               "-settings.bgm", "NO", "-settings.sfx", "NO", "-settings.effects", "NO", "-settings.haptics", "NO"]
        app.launch()
        app.buttons["スタート"].tap()
        var n = 0
        while !app.buttons["もう一度挑戦"].exists && n < 30 {
            n += 1
            let a = app.buttons.matching(NSPredicate(format: "label CONTAINS 'A'")).firstMatch
            XCTAssertTrue(a.waitForExistence(timeout: 6)); a.tap()
            let next = app.buttons.matching(NSPredicate(format: "label == '次の問題へ' OR label == '結果を見る'")).firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 6)); next.tap()
        }
        XCTAssertTrue(app.buttons["もう一度挑戦"].waitForExistence(timeout: 6))
        let banner = app.descendants(matching: .any)["stage-unlocked"]
        XCTAssertTrue(banner.waitForExistence(timeout: 4), "space unlock banner is shown")
        XCTAssertTrue(banner.label.contains("宇宙"))
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "space-unlocked"; a.lifetime = .keepAlways; add(a)
        app.buttons["ホームに戻る"].tap()
        // Home now lists space as playable.
        XCTAssertTrue(app.buttons["stage-sky"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["stage-sky"].isEnabled)
    }

    func testSpaceStageIsPlayableFromLevel35() {
        let app = XCUIApplication()
        app.launchArguments = ["-debugNoAds", "YES", "-debugXP", "15000", "-debugCorrectIsA", "YES", "-debugFigureFirst", "YES",
                               "-settings.bgm", "NO", "-settings.sfx", "NO", "-settings.effects", "NO", "-settings.haptics", "NO"]
        app.launch()
        app.buttons["スタート"].tap()
        let progress = app.staticTexts["progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 6))
        XCTAssertTrue(progress.label.hasSuffix("/ 20問"), "space runs have 20 questions: \(progress.label)")
        let figure = app.otherElements["figure"]
        XCTAssertTrue(figure.waitForExistence(timeout: 4), "the first space question carries a figure")
        let a = app.buttons.matching(NSPredicate(format: "label CONTAINS 'A'")).firstMatch
        XCTAssertTrue(a.isHittable)
    }
}
