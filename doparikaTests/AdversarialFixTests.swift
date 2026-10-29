import XCTest
@testable import doparika

@MainActor
final class AdversarialFixTests: XCTestCase {
    override func tearDown() { FeatureFlags.testOverride = nil }

    private func qs(_ stage: Stage, _ prefix: String, _ n: Int) -> [Question] {
        (0..<n).map { i in
            Question(id: "\(prefix)\(i)", stage: stage, grade: 3, subject: "earth", difficulty: 1, question: "q", 
                     choices: [Choice(id: "A", text: "a"), Choice(id: "B", text: "b")],
                     correctChoiceId: "A", explanation: "e", figure: nil)
        }
    }

    // Time played before a pause counts even if no frame settled it.
    func testPauseSettlesUnaccountedTime() throws {
        FeatureFlags.testOverride = nil
        let env = try TestEnv()
        let clock = FakeClock()
        let s = env.session(clock: clock)
        s.configure(viewportHeight: 800, width: 400)
        clock.advance(15.1)
        s.paused = true
        clock.advance(3600)
        s.paused = false
        XCTAssertEqual(s.engine.phase, .resolved(.timeout))
        XCTAssertEqual(s.engine.earnedXP, 0)
    }

    func testPausedHourStillNotCountedAndDoublePauseIsNotDoubleSettled() throws {
        let env = try TestEnv()
        let clock = FakeClock()
        let s = env.session(clock: clock)
        s.configure(viewportHeight: 800, width: 400)
        clock.advance(5)
        s.paused = true
        s.userPaused = true
        clock.advance(3600)
        s.userPaused = false
        s.paused = false
        clock.advance(1)
        s.advance()
        XCTAssertEqual(s.engine.phase, .answering)
        XCTAssertEqual(s.engine.remaining, QuizEngine.timeLimit - 5, accuracy: 0.05)
    }

    // All answered: the stage keeps its share.
    func testStageShareHoldsWhenEverythingIsAnswered() {
        let own = qs(.sky, "s", 30), other = qs(.mountain, "m", 300)
        let now = Date()
        let history = (own + other).enumerated().map { i, q in
            QuestionSelector.History(questionID: q.id, wrongCount: 0, lastCorrect: true, lastWrongAt: nil,
                                     lastWrongLevel: 0, lastAnsweredAt: now.addingTimeInterval(Double(i)))
        }
        for _ in 0..<20 {
            let pick = QuestionSelector.select(all: own, history: history, currentLevel: 40, size: 20, fallback: other)
            XCTAssertEqual(pick.count, 20)
            XCTAssertGreaterThanOrEqual(pick.filter { $0.stage == .sky }.count, 14)
        }
    }

    // Duplicate IDs cannot make an empty stage look playable.
    func testDuplicateIDsAreCountedAfterDeduplication() throws {
        let bundled: (Stage) -> Data? = { s in
            Bundle.main.url(forResource: s.questionsResource, withExtension: "json").flatMap { try? Data(contentsOf: $0) }
        }
        let one = try JSONEncoder().encode(Array(repeating: qs(.sky, "dup", 1)[0], count: 25))
        let r = QuestionRepository(loader: { $0 == .sky ? one : bundled($0) })
        XCTAssertFalse(r.isPlayable(.sky))
        XCTAssertTrue(r.isPlayable(.mountain))
        XCTAssertEqual(r.questions(for: .sky).count, 1)
    }

    // A stage the player has not reached cannot be started directly.
    func testUnreachedStageRequestFallsBackToCurrent() throws {
        FeatureFlags.testOverride = nil
        let env = try TestEnv()
        XCTAssertEqual(env.model.resolvedStage(.sky), .mountain)
        XCTAssertTrue(env.model.makeSession(stage: .sky).allSatisfy { $0.stage == .mountain })
        XCTAssertEqual(env.session(clock: FakeClock()).stage, .mountain)
        let high = try TestEnv(xp: LevelCalculator.xpThreshold(for: 31))
        XCTAssertEqual(high.model.resolvedStage(.sky), .sky)
        XCTAssertEqual(high.model.resolvedStage(.sea), .sky, "hidden stage is never started")
    }

    // One tap, one transition while an ad is pending.
    func testResultActionsAreSingleWhileAdPending() throws {
        final class SlowAds: AdManaging {
            var pending: ((Bool) -> Void)?
            func showRewarded(completion: @escaping (Bool) -> Void) { completion(false) }
            func showInterstitial(completion: @escaping (Bool) -> Void) { pending = completion }
        }
        let ads = SlowAds(), env = try TestEnv()
        env.model.ads = ads
        env.model.adScheduler = AdScheduler(defaults: UserDefaults(suiteName: "adv-\(UUID().uuidString)")!)
        for _ in 0..<10 { env.model.finishSession() }
        var calls = 0
        env.model.presentAdIfDue { calls += 1 }
        env.model.presentAdIfDue { calls += 1 }
        XCTAssertTrue(env.model.adInFlight)
        XCTAssertEqual(calls, 0)
        ads.pending?(true)
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(env.model.adInFlight)
    }
}
