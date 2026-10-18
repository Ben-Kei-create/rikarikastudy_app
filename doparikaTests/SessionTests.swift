import XCTest
@testable import doparika

@MainActor
final class SessionTests: XCTestCase {
    private func correctID(_ s: QuizSession) -> String { s.engine.current.correctChoiceId }

    func testAnswerAfterDeadlineIsTimeoutEvenIfTickerHasNotRun() throws {
        let clock = FakeClock(), env = try TestEnv()
        let s = env.session(clock: clock)
        s.configure(viewportHeight: 874, width: 402)
        clock.advance(QuizEngine.timeLimit + 0.3)          // main actor stalled past the deadline
        s.answer(correctID(s))
        XCTAssertEqual(s.engine.phase, .resolved(.timeout))
        XCTAssertEqual(s.engine.correctCount, 0)
        XCTAssertEqual(env.model.totalXP, 0)
    }

    func testAnswerBeforeDeadlineCounts() throws {
        let clock = FakeClock(), env = try TestEnv()
        let s = env.session(clock: clock)
        s.configure(viewportHeight: 874, width: 402)
        clock.advance(QuizEngine.timeLimit - 1)
        s.answer(correctID(s))
        XCTAssertEqual(s.engine.phase, .resolved(.correct(choiceID: correctID(s))))
        XCTAssertEqual(env.model.totalXP, QuizEngine.xpPerCorrect)
    }

    func testPausedIntervalIsNotCounted() throws {
        let clock = FakeClock(), env = try TestEnv()
        let s = env.session(clock: clock)
        s.configure(viewportHeight: 874, width: 402)
        clock.advance(2); s.advance()
        s.paused = true
        clock.advance(30)                                    // app suspended
        s.paused = false
        s.advance()                                          // first tick after resume
        XCTAssertEqual(s.engine.remaining, QuizEngine.timeLimit - 2, accuracy: 0.01)
        XCTAssertEqual(s.engine.phase, .answering)
    }

    func testStalledExplanationDoesNotShortenNextQuestion() throws {
        let clock = FakeClock(), env = try TestEnv()
        let s = env.session(clock: clock)
        s.configure(viewportHeight: 874, width: 402)
        let wrong = s.engine.current.choices.first { $0.id != correctID(s) }!.id
        s.answer(wrong)
        clock.advance(1)                                     // main actor stalled while explanation shown
        s.next()
        XCTAssertEqual(s.engine.remaining, QuizEngine.timeLimit, accuracy: 0.001)
        s.advance()
        XCTAssertEqual(s.engine.remaining, QuizEngine.timeLimit, accuracy: 0.05)
    }

    func testDoubleAnswerResolvesOnce() throws {
        let clock = FakeClock(), env = try TestEnv()
        let s = env.session(clock: clock)
        s.configure(viewportHeight: 874, width: 402)
        s.answer(correctID(s)); s.answer(correctID(s))
        XCTAssertEqual(env.model.totalXP, QuizEngine.xpPerCorrect)
        XCTAssertEqual(s.engine.correctCount, 1)
    }

    private func answerAll(_ s: QuizSession, clock: FakeClock, correct: Bool) {
        while s.engine.phase != .finished {
            let id = correct ? correctID(s) : s.engine.current.choices.first { $0.id != correctID(s) }!.id
            s.answer(id)
            for _ in 0..<150 { clock.advance(1.0 / 60); s.advance() }   // let the dive/fall finish
            s.next()
        }
    }

    func testSessionLengthFollowsLevel() throws {
        XCTAssertEqual(try TestEnv().session(clock: FakeClock()).engine.total, 10)
        let high = try TestEnv(xp: LevelCalculator.xpThreshold(for: 20))
        XCTAssertEqual(high.model.levelInfo.level, 20)
        XCTAssertEqual(high.session(clock: FakeClock()).engine.total, 20)
        let nineteen = try TestEnv(xp: LevelCalculator.xpThreshold(for: 19))
        XCTAssertEqual(nineteen.session(clock: FakeClock()).engine.total, 10)
    }

    func testEachCorrectAnswerDivesToTheNextImageTop() throws {
        let clock = FakeClock(), env = try TestEnv()
        let s = env.session(clock: clock)
        s.configure(viewportHeight: 874, width: 402)
        XCTAssertEqual(s.currentDepth, 0)
        for k in 1...3 {
            s.answer(correctID(s))
            for _ in 0..<150 { clock.advance(1.0 / 60); s.advance() }
            XCTAssertEqual(s.currentDepth, s.motion.sectionTop(k), accuracy: 1)
            s.next()
        }
    }

    func testPerfectRunEndsAtBottomOfLastImage() throws {
        let clock = FakeClock(), env = try TestEnv()
        let s = env.session(clock: clock)
        s.configure(viewportHeight: 874, width: 402)
        answerAll(s, clock: clock, correct: true)
        XCTAssertEqual(s.engine.correctCount, 10)
        XCTAssertEqual(s.currentDepth, s.motion.goalDepth, accuracy: 1)
    }

    func testWrongAnswersNeverAdvanceThePosition() throws {
        let clock = FakeClock(), env = try TestEnv()
        let s = env.session(clock: clock)
        s.configure(viewportHeight: 874, width: 402)
        answerAll(s, clock: clock, correct: false)
        XCTAssertEqual(s.currentDepth, 0, accuracy: 0.5)
    }

    func testRetryRisesFromWhereTheRunEndedInsteadOfWarping() throws {
        let clock = FakeClock(), env = try TestEnv()
        let first = env.session(clock: clock)
        first.configure(viewportHeight: 874, width: 402)
        answerAll(first, clock: clock, correct: true)
        let carried = first.currentDepth
        XCTAssertGreaterThan(carried, 5000)
        let retry = env.session(clock: clock, carry: carried)
        retry.configure(viewportHeight: 874, width: 402)
        XCTAssertEqual(retry.currentDepth, carried, accuracy: 0.001)       // no jump on start
        for _ in 0..<(60 * 8) { clock.advance(1.0 / 60); retry.advance() }
        XCTAssertEqual(retry.currentDepth, 0, accuracy: 1)                  // every run starts on the surface
    }

    func testTenConsecutiveRetriesKeepTimerRunning() throws {
        let clock = FakeClock(), env = try TestEnv()
        var session = env.session(clock: clock)
        session.configure(viewportHeight: 874, width: 402)
        for _ in 0..<10 {
            answerAll(session, clock: clock, correct: false)
            XCTAssertEqual(session.engine.phase, .finished)
            let carry = session.currentDepth
            session = env.session(clock: clock, carry: carry)
            session.configure(viewportHeight: 874, width: 402)
            XCTAssertEqual(session.currentDepth, carry, accuracy: 0.001)
            clock.advance(1); session.advance()
            XCTAssertEqual(session.engine.remaining, QuizEngine.timeLimit - 1, accuracy: 0.05)
        }
    }
}
