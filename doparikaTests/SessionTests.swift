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

    func testRetryInheritsVisiblePositionInsteadOfWarping() throws {
        let clock = FakeClock(), env = try TestEnv()
        let first = env.session(clock: clock)
        first.configure(viewportHeight: 874, width: 402)
        let wrong = first.engine.current.choices.first { $0.id != correctID(first) }!.id
        first.answer(wrong)
        for _ in 0..<6 { clock.advance(1.0 / 60); first.advance() }  // mid-fall
        let carried = first.currentPosition
        let retry = env.session(clock: clock, carry: carried)
        retry.configure(viewportHeight: 874, width: 402)
        XCTAssertEqual(retry.currentPosition, carried, accuracy: 0.001)   // no jump on start
        for _ in 0..<600 { clock.advance(1.0 / 60); retry.advance() }
        XCTAssertGreaterThan(retry.currentPosition, 0)
    }

    func testTenConsecutiveRetriesKeepTimerRunningAndPositionContinuous() throws {
        let clock = FakeClock(), env = try TestEnv()
        var session = env.session(clock: clock)
        session.configure(viewportHeight: 874, width: 402)
        for _ in 0..<10 {
            for _ in 0..<5 {
                let wrong = session.engine.current.choices.first { $0.id != correctID(session) }!.id
                session.answer(wrong); session.next()
            }
            XCTAssertEqual(session.engine.phase, .finished)
            let carry = session.currentPosition
            session = env.session(clock: clock, carry: carry)
            session.configure(viewportHeight: 874, width: 402)
            XCTAssertEqual(session.currentPosition, carry, accuracy: 0.001)
            clock.advance(1); session.advance()
            XCTAssertEqual(session.engine.remaining, QuizEngine.timeLimit - 1, accuracy: 0.05)
        }
    }
}
