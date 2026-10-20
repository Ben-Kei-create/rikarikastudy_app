import XCTest
@testable import doparika

/// Which sounds a quiz run requests, and how the music duck behaves around them.
@MainActor
final class AudioFlowTests: XCTestCase {
    override func tearDown() { SoundPlayer.testOverride = false }

    private func started(_ env: TestEnv, _ clock: FakeClock) -> QuizSession {
        let s = env.session(clock: clock)
        s.configure(viewportHeight: 874, width: 402)
        SoundPlayer.shared.clearEvents()
        return s
    }

    private func wrongID(_ s: QuizSession) -> String {
        s.engine.current.choices.first { $0.id != s.engine.current.correctChoiceId }!.id
    }

    func testCorrectAnswerPlaysVoiceAndChimeOnly() throws {
        let clock = FakeClock(), env = try TestEnv()
        let s = started(env, clock)
        s.answer(s.engine.current.correctChoiceId)
        let plays = SoundPlayer.shared.events.compactMap { e -> SoundPlayer.Sfx? in
            if case .play(let x) = e { return x } else { return nil }
        }
        XCTAssertEqual(plays, [.correctVoice, .correctChime])
        // The dig / wall-break sounds must not come back later either.
        let later = expectation(description: "1.2s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { later.fulfill() }
        wait(for: [later], timeout: 3)
        let all = SoundPlayer.shared.events.compactMap { e -> SoundPlayer.Sfx? in
            if case .play(let x) = e { return x } else { return nil }
        }
        XCTAssertEqual(all, [.correctVoice, .correctChime])
    }

    func testWrongAnswerPlaysNoCorrectSounds() throws {
        let clock = FakeClock(), env = try TestEnv()
        let s = started(env, clock)
        s.answer(wrongID(s))
        XCTAssertTrue(SoundPlayer.shared.events.contains(.play(.wrong)))
        XCTAssertFalse(SoundPlayer.shared.events.contains(.play(.correctChime)))
        XCTAssertFalse(SoundPlayer.shared.events.contains(.play(.correctVoice)))
    }

    func testDoubleAnswerDoesNotPlayTwice() throws {
        let clock = FakeClock(), env = try TestEnv()
        let s = started(env, clock)
        s.answer(s.engine.current.correctChoiceId)
        s.answer(s.engine.current.correctChoiceId)
        XCTAssertEqual(SoundPlayer.shared.events.filter { $0 == .play(.correctChime) }.count, 1)
    }

    func testTimeoutStopsCountdownBeforeItsOwnVoice() throws {
        let clock = FakeClock(), env = try TestEnv()
        let s = started(env, clock)
        clock.advance(QuizEngine.timeLimit - 1); s.advance()          // countdown running
        clock.advance(2); s.advance()                                 // deadline passes
        XCTAssertEqual(s.engine.phase, .resolved(.timeout))
        let ev = SoundPlayer.shared.events
        let stop = try XCTUnwrap(ev.lastIndex(of: .stop(.countdown)))
        let voice = try XCTUnwrap(ev.lastIndex(of: .play(.timeoutVoice)))
        XCTAssertLessThan(stop, voice)
    }

    func testNextQuestionSilencesPreviousSounds() throws {
        let clock = FakeClock(), env = try TestEnv()
        let s = started(env, clock)
        s.answer(s.engine.current.correctChoiceId)
        s.next()
        XCTAssertEqual(SoundPlayer.shared.events.last, .stopAll)
    }

    func testCountdownRestartsAfterBackgroundForTheTimeLeft() throws {
        let clock = FakeClock(), env = try TestEnv()
        let s = started(env, clock)
        clock.advance(QuizEngine.timeLimit - 2); s.advance()          // 2 s left: countdown starts
        XCTAssertEqual(SoundPlayer.shared.events.filter { $0 == .play(.countdown) }.count, 1)
        s.paused = true                                               // Background: everything is silenced
        XCTAssertEqual(SoundPlayer.shared.events.last, .stopAll)
        clock.advance(60)
        s.paused = false
        s.advance(); clock.advance(0.1); s.advance()
        XCTAssertEqual(SoundPlayer.shared.events.filter { $0 == .play(.countdown) }.count, 2)
        XCTAssertEqual(s.engine.remaining, 1.9, accuracy: 0.05)       // the suspended minute was not counted
    }

    func testUserPauseFreezesTheClockAndHidesNothingFromTheEngine() throws {
        let clock = FakeClock(), env = try TestEnv()
        let s = started(env, clock)
        clock.advance(3); s.advance()
        s.userPaused = true
        clock.advance(20); s.advance()
        s.userPaused = false
        s.advance(); clock.advance(1); s.advance()
        XCTAssertEqual(s.engine.remaining, QuizEngine.timeLimit - 4, accuracy: 0.05)
        XCTAssertEqual(s.engine.phase, .answering)
    }

    func testSystemAndUserPauseAreIndependent() throws {
        let clock = FakeClock(), env = try TestEnv()
        let s = started(env, clock)
        s.userPaused = true
        s.paused = true; s.paused = false          // app went to Background and came back
        XCTAssertTrue(s.isPaused, "returning to the foreground must not undo the player's pause")
    }

    // MARK: music duck

    func testNewerDuckIsNotCutShortByOlderOne() {
        let m = MusicPlayer.shared
        m.duck(for: 0.2)
        m.duck(for: 0.8)                            // replaces the first
        let e = expectation(description: "after the first duck would have ended")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { e.fulfill() }
        wait(for: [e], timeout: 3)
        XCTAssertTrue(m.isDucked, "the older duck's restore must not release the newer duck")
        m.cancelDuck()
        XCTAssertFalse(m.isDucked)
    }

    func testDuckEventuallyReleases() {
        let m = MusicPlayer.shared
        m.duck(for: 0.1)
        let e = expectation(description: "released")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { e.fulfill() }
        wait(for: [e], timeout: 3)
        XCTAssertFalse(m.isDucked)
    }

    func testSoundFilesDecodeWithRealDurations() {
        for s in [SoundPlayer.Sfx.correctVoice, .correctChime, .countdown, .timeoutVoice, .wrong] {
            XCTAssertGreaterThan(SoundPlayer.shared.duration(of: s), 0.3, "\(s) failed to decode")
        }
    }
}
