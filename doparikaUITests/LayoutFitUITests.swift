import XCTest

/// Guards the layout against content wider than the screen (a long explanation once pushed the panels off-screen).
final class LayoutFitUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func assertInside(_ e: XCUIElement, _ window: CGRect, _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let f = e.frame
        XCTAssertGreaterThanOrEqual(f.minX, window.minX - 1, "\(what) leaks left: \(f)", file: file, line: line)
        XCTAssertLessThanOrEqual(f.maxX, window.maxX + 1, "\(what) leaks right: \(f) window \(window)", file: file, line: line)
    }

    /// Fully on screen vertically too, and actually tappable (not covered or clipped).
    private func assertReachable(_ e: XCUIElement, _ window: CGRect, _ what: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let f = e.frame
        XCTAssertGreaterThanOrEqual(f.minY, window.minY - 1, "\(what) leaks above: \(f)", file: file, line: line)
        XCTAssertLessThanOrEqual(f.maxY, window.maxY + 1, "\(what) leaks below: \(f) window \(window)", file: file, line: line)
        XCTAssertTrue(e.isHittable, "\(what) is not hittable", file: file, line: line)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testEveryQuestionAndAnswerStateFitsTheScreen() { run(extraArgs: []) }

    /// Larger Dynamic Type widens every line's natural width: the case most likely to break a layout.
    func testFitsWithLargeAccessibilityText() {
        run(extraArgs: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
    }

    func testFitsWithSmallerStandardText() {
        run(extraArgs: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXLarge"])
    }

    private func run(extraArgs: [String]) {
        let app = XCUIApplication()
        app.launchArguments = ["-debugNoAds", "YES", "-debugXP", "0", "-debugLongestFirst", "YES", "-settings.bgm", "NO", "-settings.sfx", "NO", "-settings.effects", "YES", "-settings.haptics", "NO"] + extraArgs
        app.launch()
        app.buttons["スタート"].tap()
        let window = app.windows.firstMatch.frame
        for n in 1...5 {
            XCTAssertTrue(app.staticTexts["progress"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["progress"].label.hasPrefix("第\(n)問"))
            let a = app.buttons.matching(NSPredicate(format: "label CONTAINS 'A'")).firstMatch
            XCTAssertTrue(a.waitForExistence(timeout: 3))
            assertInside(a, window, "choice A (q\(n))")
            attach(app, "q\(n)-asking")
            a.tap()
            let next = app.buttons["次の問題へ"]
            XCTAssertTrue(next.waitForExistence(timeout: 3))
            sleep(2)                                   // let the dive settle
            assertInside(next, window, "next button (q\(n))")
            assertReachable(next, window, "next button (q\(n))")
            assertInside(a, window, "choice A after answer (q\(n))")
            for t in app.staticTexts.allElementsBoundByIndex where t.exists && t.frame.height > 0 {
                assertInside(t, window, "text '\(t.label.prefix(12))' (q\(n))")
            }
            attach(app, "q\(n)-answered")
            next.tap()
        }
    }

    /// Large text, longest questions: after answering with the panel scrolled, the next question starts at
    /// its top (not half-scrolled with the clock already running), and the timer stays on one line.
    func testNextQuestionStartsAtTopAndTimerStaysOneLine() {
        let app = XCUIApplication()
        app.launchArguments = ["-debugNoAds", "YES", "-debugXP", "0", "-debugLongestFirst", "YES", "-settings.bgm", "NO", "-settings.sfx", "NO", "-settings.effects", "NO", "-settings.haptics", "NO",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        app.buttons["スタート"].tap()
        let progress = app.staticTexts["progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        let timerText = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '残り'")).firstMatch
        XCTAssertTrue(timerText.exists)
        XCTAssertLessThan(timerText.frame.height, 60, "timer wrapped onto several lines: \(timerText.frame)")
        // Answer B (forces scrolling to the bottom of the panel), then go on.
        let b = app.buttons.matching(NSPredicate(format: "label CONTAINS 'B'")).firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 3))
        b.tap()
        let next = app.buttons["次の問題へ"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        next.tap()
        XCTAssertTrue(progress.waitForExistence(timeout: 3))
        XCTAssertTrue(progress.label.hasPrefix("第2問"))
        // The first choice badge/text must be below the header, and the panel top must not be scrolled above it.
        let header = progress.frame
        let firstText = app.staticTexts.matching(NSPredicate(format: "NOT (label BEGINSWITH '第') AND NOT (label BEGINSWITH '残り')")).firstMatch
        XCTAssertTrue(firstText.exists)
        XCTAssertGreaterThanOrEqual(firstText.frame.minY, header.maxY - 1, "question starts above the header (scrolled): \(firstText.frame)")
        attach(app, "q2-top")
    }

    /// Largest text, 20-question run (two-digit numbers): progress, timer and pause stay fully on screen.
    func testHeaderFitsAtLargestTextOnQuestionTen() {
        let app = XCUIApplication()
        app.launchArguments = ["-debugNoAds", "YES", "-debugXP", "7080", "-debugCorrectIsA", "YES", "-settings.bgm", "NO", "-settings.sfx", "NO", "-settings.effects", "NO", "-settings.haptics", "NO",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["スタート"].tap()
        let window = app.windows.firstMatch.frame
        for n in 1...10 {
            let progress = app.staticTexts["progress"]
            XCTAssertTrue(progress.waitForExistence(timeout: 5))
            XCTAssertTrue(progress.label.hasPrefix("第\(n)問"), progress.label)
            let pause = app.buttons["pause"]
            for (name, e) in [("progress", progress), ("pause", pause)] {
                XCTAssertGreaterThanOrEqual(e.frame.minX, window.minX - 1, "\(name) leaks left on q\(n): \(e.frame)")
                XCTAssertLessThanOrEqual(e.frame.maxX, window.maxX + 1, "\(name) leaks right on q\(n): \(e.frame)")
            }
            if n == 10 { attach(app, "q10-header"); break }
            let a = app.buttons.matching(NSPredicate(format: "label CONTAINS 'A'")).firstMatch
            XCTAssertTrue(a.waitForExistence(timeout: 3))
            a.tap()
            let next = app.buttons["次の問題へ"]
            XCTAssertTrue(next.waitForExistence(timeout: 3))
            next.tap()
        }
    }

    /// Deep-sea questions with a table / graph / diagram: the figure and BOTH choices are visible and tappable
    /// without scrolling, and the next button stays on screen after answering.
    func testDeepSeaFigureQuestionsFitOnScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-debugNoAds", "YES", "-debugStages", "YES", "-debugXP", "40000", "-debugFigureFirst", "YES",
                               "-debugCorrectIsA", "YES", "-settings.bgm", "NO", "-settings.sfx", "NO", "-settings.effects", "NO", "-settings.haptics", "NO"]
        app.launch()
        app.buttons["スタート"].tap()
        let window = app.windows.firstMatch.frame
        for n in 1...6 {
            let figure = app.otherElements["figure"]
            XCTAssertTrue(figure.waitForExistence(timeout: 6), "question \(n) has a figure")
            let a = app.buttons.matching(NSPredicate(format: "label CONTAINS 'A'")).firstMatch
            let b = app.buttons.matching(NSPredicate(format: "label CONTAINS 'B'")).firstMatch
            XCTAssertTrue(a.waitForExistence(timeout: 3) && b.waitForExistence(timeout: 3))
            XCTAssertTrue(a.isHittable && b.isHittable, "both choices reachable without scrolling (q\(n))")
            XCTAssertLessThanOrEqual(b.frame.maxY, window.maxY, "choice B on screen (q\(n))")
            if n == 1 { attach(app, "sea-figure-q1") }
            a.tap()
            let next = app.buttons.matching(NSPredicate(format: "label == '次の問題へ' OR label == '結果を見る'")).firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 3))
            assertReachable(next, window, "next button (sea q\(n))")
            next.tap()
        }
    }

    /// The pause menu: it opens, hides the question, and resuming gives the question back.
    func testPauseMenuOpensAndResumes() {
        let app = XCUIApplication()
        app.launchArguments = ["-debugNoAds", "YES", "-debugXP", "0", "-settings.bgm", "NO", "-settings.sfx", "NO", "-settings.effects", "NO", "-settings.haptics", "NO"]
        app.launch()
        app.buttons["スタート"].tap()
        let pause = app.buttons["pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.tap()
        let resume = app.buttons["resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["ホームへもどる"].exists)
        attach(app, "paused")
        resume.tap()
        XCTAssertTrue(app.staticTexts["progress"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["progress"].label.hasPrefix("第1問"))
    }

    /// A correct answer plays the big ○ and sparkle burst; the layout must not widen while it is on screen.
    func testCorrectAnswerBurstDoesNotWidenTheLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["-debugNoAds", "YES", "-debugXP", "0", "-debugCorrectIsA", "YES", "-settings.bgm", "NO", "-settings.sfx", "NO", "-settings.effects", "YES", "-settings.haptics", "NO"]
        app.launch()
        app.buttons["スタート"].tap()
        let window = app.windows.firstMatch.frame
        let a = app.buttons.matching(NSPredicate(format: "label CONTAINS 'A'")).firstMatch
        XCTAssertTrue(a.waitForExistence(timeout: 5))
        a.tap()
        let next = app.buttons["次の問題へ"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        // Sample while the burst animates (0 - ~1.6 s) and after it has faded.
        usleep(150_000)
        attach(app, "burst-early")          // ~0.3 s after the tap: the stamp is at full size
        for i in 0..<8 {
            assertInside(next, window, "next button (burst t=\(i))")
            assertInside(a, window, "choice A (burst t=\(i))")
            if i == 2 { attach(app, "burst-mid") }
            usleep(250_000)
        }
        attach(app, "burst-end")
    }
}

