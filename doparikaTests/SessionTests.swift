import XCTest
import UIKit
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
        let high = try TestEnv(xp: LevelCalculator.xpThreshold(for: 21))
        XCTAssertEqual(high.model.levelInfo.level, 21)
        XCTAssertEqual(high.session(clock: FakeClock()).engine.total, 20)
        let twenty = try TestEnv(xp: LevelCalculator.xpThreshold(for: 20))
        XCTAssertEqual(twenty.model.levelInfo.level, 20)
        XCTAssertEqual(twenty.session(clock: FakeClock()).engine.total, 10)
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
        XCTAssertEqual(retry.currentDepth, carried, accuracy: 1)           // no jump on start
        for _ in 0..<(60 * 8) { clock.advance(1.0 / 60); retry.advance() }
        // Every run starts on the surface: back at the top of 001, bobbing within its top range.
        XCTAssertLessThanOrEqual(retry.currentDepth, WorldMotionController.surfaceBobRange + 1)
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
            XCTAssertEqual(session.currentDepth, carry, accuracy: 1)        // no visible jump
            clock.advance(1); session.advance()
            XCTAssertEqual(session.engine.remaining, QuizEngine.timeLimit - 1, accuracy: 0.05)
        }
    }
}

@MainActor
final class ComboAndRankTests: XCTestCase {
    private func engine(_ n: Int = 6) throws -> QuizEngine {
        let repo = QuestionRepository()
        return QuizEngine(questions: Array(repo.questions(for: .mountain).prefix(n)))
    }
    private func right(_ e: QuizEngine) { e.answer(choiceID: e.current.correctChoiceId) }
    private func wrong(_ e: QuizEngine) { e.answer(choiceID: e.current.choices.first { $0.id != e.current.correctChoiceId }!.id) }

    func testComboCountsConsecutiveCorrectAnswersAndTracksTheBest() throws {
        let e = try engine()
        right(e); e.next(); right(e); e.next(); right(e)
        XCTAssertEqual(e.combo, 3)
        e.next(); wrong(e)
        XCTAssertEqual(e.combo, 0, "a wrong answer breaks the streak")
        XCTAssertEqual(e.maxCombo, 3)
        e.next(); right(e); e.next(); right(e)
        XCTAssertEqual(e.combo, 2)
        XCTAssertEqual(e.maxCombo, 3, "the best streak is kept")
    }

    func testTimeoutBreaksTheCombo() throws {
        let e = try engine()
        right(e); e.next(); right(e)
        XCTAssertEqual(e.combo, 2)
        e.next(); e.tick(QuizEngine.timeLimit + 1)
        XCTAssertEqual(e.phase, .resolved(.timeout))
        XCTAssertEqual(e.combo, 0)
    }

    func testDoubleAnswerDoesNotCountTwice() throws {
        let e = try engine()
        right(e); right(e)
        XCTAssertEqual(e.combo, 1)
    }

    func testRankThresholds() {
        XCTAssertEqual(ResultRank.rank(correct: 10, total: 10), .s)
        XCTAssertEqual(ResultRank.rank(correct: 9, total: 10), .s)
        XCTAssertEqual(ResultRank.rank(correct: 8, total: 10), .a)
        XCTAssertEqual(ResultRank.rank(correct: 15, total: 20), .a)
        XCTAssertEqual(ResultRank.rank(correct: 7, total: 10), .b)
        XCTAssertEqual(ResultRank.rank(correct: 5, total: 10), .b)
        XCTAssertEqual(ResultRank.rank(correct: 4, total: 10), .c)
        XCTAssertEqual(ResultRank.rank(correct: 0, total: 10), .c)
        XCTAssertEqual(ResultRank.rank(correct: 0, total: 0), .c)
        XCTAssertEqual(ResultRank.rank(correct: 18, total: 20), .s)
        XCTAssertEqual(ResultRank.rank(correct: 17, total: 20), .a)
    }

    func testRankAndPerfectArtworkIsBundled() {
        for r in ResultRank.allCases { XCTAssertNotNil(UIImage(named: r.imageName), r.imageName) }
        XCTAssertNotNil(UIImage(named: "result_perfect"))
    }
}
