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

@MainActor
final class SpaceCurveAndNoticeTests: XCTestCase {
    override func tearDown() { FeatureFlags.testOverride = nil }

    func testSpaceLevelsCostFlat200AndTotal290Answers() {
        for lv in 31..<60 { XCTAssertEqual(LevelCalculator.xpToNext(from: lv), 200) }
        XCTAssertEqual(LevelCalculator.xpThreshold(for: 60) - LevelCalculator.xpThreshold(for: 31), 29 * 200)
        XCTAssertEqual(29 * 200 / QuizEngine.xpPerCorrect, 290)
        XCTAssertEqual(LevelCalculator.xpToNext(from: 29), 240 + 12 * 28, "Earth is unchanged")
        XCTAssertEqual(LevelCalculator.level(forXP: LevelCalculator.xpThreshold(for: 60)), 60)
    }

    func testNoticeDependsOnSavedXPAndShowsOnce() throws {
        FeatureFlags.testOverride = nil
        let fresh = try TestEnv()
        XCTAssertNil(fresh.model.pendingUpdateNotice(), "new player")
        let early = try TestEnv(xp: LevelCalculator.xpThreshold(for: 10))
        XCTAssertEqual(early.model.pendingUpdateNotice(), .coming(levelsToGo: 21))
        let end = try TestEnv(xp: LevelCalculator.xpThreshold(for: 30) + 5)
        XCTAssertEqual(end.model.pendingUpdateNotice(),
                       .atEarthEnd(xpToGo: LevelCalculator.xpThreshold(for: 31) - end.model.totalXP))
        let inSpace = try TestEnv(xp: LevelCalculator.xpThreshold(for: 40))
        XCTAssertEqual(inSpace.model.pendingUpdateNotice(), .spaceOpen)
        inSpace.model.dismissUpdateNotice()
        XCTAssertNil(inSpace.model.pendingUpdateNotice())
        let top = try TestEnv(xp: LevelCalculator.xpThreshold(for: 60))
        XCTAssertEqual(top.model.pendingUpdateNotice(), .spaceCleared)
        top.model.dismissUpdateNotice()
        XCTAssertFalse(top.model.claimSpaceClear(startLevel: 59), "already told: no surprise celebration")
    }

    func testSpaceClearCelebratesOnlyOnce() throws {
        FeatureFlags.testOverride = nil
        let env = try TestEnv(xp: LevelCalculator.xpThreshold(for: 60))
        XCTAssertFalse(env.model.claimSpaceClear(startLevel: 60), "not crossed in this run")
        XCTAssertTrue(env.model.claimSpaceClear(startLevel: 59))
        XCTAssertFalse(env.model.claimSpaceClear(startLevel: 59))
        env.model.resetProgress()
        XCTAssertNil(env.model.pendingUpdateNotice())
    }
}

@MainActor
final class AnswerStatsTests: XCTestCase {
    func testStatsSumCorrectAndWrongPerField() throws {
        let env = try TestEnv()
        XCTAssertEqual(env.model.subjectStats().map(\.total).reduce(0, +), 0)
        let qs = env.model.repository.questions(for: .mountain)
        let phys = qs.filter { $0.subject == "physics" }.prefix(3), bio = qs.first { $0.subject == "biology" }!
        phys.forEach { env.model.record(question: $0, correct: true, xp: 20) }
        env.model.record(question: phys.first!, correct: false, xp: 0)
        env.model.record(question: bio, correct: false, xp: 0)
        let stats = env.model.subjectStats()
        XCTAssertEqual(stats.map(\.subject), ["physics", "chemistry", "biology", "earth"])
        XCTAssertEqual(stats[0].correct, 3); XCTAssertEqual(stats[0].wrong, 1)
        XCTAssertEqual(stats[2].wrong, 1)
        XCTAssertEqual(stats.map(\.total).reduce(0, +), 5)
        env.model.resetProgress()
        XCTAssertEqual(env.model.subjectStats().map(\.total).reduce(0, +), 0)
    }
}
