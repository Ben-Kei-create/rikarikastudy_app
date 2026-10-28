import XCTest
import UIKit
@testable import doparika

/// 宇宙 / 深海: implemented, but hidden until the release-2 flag is on.
@MainActor
final class StageTests: XCTestCase {
    override func tearDown() { FeatureFlags.testOverride = nil }

    // MARK: release 1 (flag off)

    func testThisReleaseShipsEarthAndSpaceButNotTheDeepSea() {
        FeatureFlags.testOverride = nil
        XCTAssertEqual(FeatureFlags.shippedStages, [.mountain, .sky])
        XCTAssertEqual(FeatureFlags.availableStages, [.mountain, .sky])
        XCTAssertFalse(FeatureFlags.availableStages.contains(.sea), "the deep sea stays hidden")
        XCTAssertEqual(LevelCalculator.maxLevel, 60)
    }

    func testSpaceOpensAtLevel31AndTheCapIs60() throws {
        FeatureFlags.testOverride = nil
        let at30 = try TestEnv(xp: LevelCalculator.xpThreshold(for: 30))
        XCTAssertEqual(at30.model.unlockedStages, [.mountain])
        let at31 = try TestEnv(xp: LevelCalculator.xpThreshold(for: 31))
        XCTAssertEqual(at31.model.currentStage, .sky)
        XCTAssertEqual(at31.model.unlockedStages, [.mountain, .sky])
        let beyond = try TestEnv(xp: 10_000_000)
        XCTAssertEqual(beyond.model.levelInfo.level, 60)
        XCTAssertEqual(beyond.model.currentStage, .sky, "never into the hidden deep sea")
        XCTAssertTrue(beyond.model.levelInfo.isMax)
    }

    func testFlagOffKeepsLevelCappedAndStageEarth() throws {
        FeatureFlags.testOverride = false
        let env = try TestEnv(xp: 1_000_000)
        XCTAssertEqual(env.model.levelInfo.level, 30)
        XCTAssertEqual(env.model.currentStage, .mountain)
        XCTAssertEqual(env.model.unlockedStages, [.mountain])
        XCTAssertTrue(env.model.makeSession().allSatisfy { $0.stage == .mountain })
    }

    func testCollectionListsOnlyEarthWhenFlagOff() {
        FeatureFlags.testOverride = false
        XCTAssertEqual(FeatureFlags.availableStages.count, 1)   // CollectionView hides the tab picker
    }

    // MARK: data & assets (always checked, so release 2 is ready)

    func testEveryStageHasQuestionsWithUniqueIDsAcrossStages() {
        let repo = QuestionRepository()
        XCTAssertNil(repo.loadError)
        for s in Stage.allCases {
            let qs = repo.questions(for: s)
            XCTAssertGreaterThanOrEqual(qs.count, 30, "\(s) has too few questions")
            XCTAssertTrue(qs.allSatisfy { $0.stage == s && $0.choices.count == 2 })
        }
        let total = Stage.allCases.reduce(0) { $0 + repo.questions(for: $1).count }
        XCTAssertEqual(repo.questions.count, total)
        XCTAssertEqual(Set(repo.questions.map(\.id)).count, repo.questions.count)
    }

    func testStageArtworkIsBundled() {
        for s in Stage.allCases {
            let c = s.config
            for i in 1...c.imageCount {
                XCTAssertNotNil(UIImage(named: String(format: c.imagePrefix + "%03d", i)), "\(c.imagePrefix)\(i) missing")
            }
        }
    }

    func testStageMusicTracksExist() {
        for s in Stage.allCases {
            XCTAssertFalse(s.config.music.isEmpty)
            for t in s.config.music { XCTAssertNotNil(Bundle.main.url(forResource: t.rawValue, withExtension: "m4a")) }
        }
    }

    // MARK: release 2 (flag on)

    func testLevelsMapToStages() {
        for (lv, st) in [(1, Stage.mountain), (30, .mountain), (31, .sky), (60, .sky), (61, .sea), (100, .sea)] {
            XCTAssertEqual(LevelCalculator.stage(forLevel: lv), st, "Lv.\(lv)")
        }
    }

    func testFlagOnRaisesCapToLevel100AndUnlocksByLevel() throws {
        FeatureFlags.testOverride = true
        XCTAssertEqual(LevelCalculator.maxLevel, 100)
        let at30 = try TestEnv(xp: LevelCalculator.xpThreshold(for: 30))
        XCTAssertEqual(at30.model.unlockedStages, [.mountain])
        let at31 = try TestEnv(xp: LevelCalculator.xpThreshold(for: 31))
        XCTAssertEqual(at31.model.currentStage, .sky)
        XCTAssertEqual(at31.model.unlockedStages, [.mountain, .sky])
        let at61 = try TestEnv(xp: LevelCalculator.xpThreshold(for: 61))
        XCTAssertEqual(at61.model.unlockedStages, Stage.allCases)
    }

    func testSessionUsesTheChosenStagesQuestionsAndHalfXPForEarlierStages() throws {
        FeatureFlags.testOverride = true
        let env = try TestEnv(xp: LevelCalculator.xpThreshold(for: 31))
        XCTAssertTrue(env.model.makeSession().allSatisfy { $0.stage == .sky })
        XCTAssertTrue(env.model.makeSession(stage: .mountain).allSatisfy { $0.stage == .mountain })
        XCTAssertEqual(env.model.xpPerCorrect(for: .sky), QuizEngine.xpPerCorrect)
        XCTAssertEqual(env.model.xpPerCorrect(for: .mountain), QuizEngine.xpPerCorrect / 2)

        let clock = FakeClock()
        let practice = QuizSession(model: env.model, stage: .mountain, now: { clock.now() })
        practice.configure(viewportHeight: 874, width: 402)
        let before = env.model.totalXP
        practice.answer(practice.engine.current.correctChoiceId)
        XCTAssertEqual(env.model.totalXP - before, QuizEngine.xpPerCorrect / 2)
        XCTAssertEqual(practice.engine.lastXPGain, QuizEngine.xpPerCorrect / 2)
    }

    func testSessionLengthsPerStage() throws {
        FeatureFlags.testOverride = true
        let sky = try TestEnv(xp: LevelCalculator.xpThreshold(for: 31))
        XCTAssertEqual(sky.model.sessionLength(for: .sky), 20)
        let sea = try TestEnv(xp: LevelCalculator.xpThreshold(for: 70))
        XCTAssertEqual(sea.model.sessionLength(for: .sea), 20)
        let deep = try TestEnv(xp: LevelCalculator.xpThreshold(for: 85))
        XCTAssertEqual(deep.model.sessionLength(for: .sea), 30)
    }

    func testMotionFollowsTheStage() {
        let m = WorldMotionController()
        m.configure(stage: .sky, questionCount: 20)
        m.setViewport(874, width: 402)
        XCTAssertEqual(m.direction, .ascend)
        XCTAssertEqual(m.stageImageCount, 20)
        m.configure(stage: .sea, questionCount: 30)      // the deep sea has 30 images, more than Earth's 20
        XCTAssertEqual(m.direction, .descend)
        XCTAssertEqual(m.stageImageCount, 30)
        XCTAssertEqual(m.restingDepth(afterCorrect: 29), 29 * m.sectionStep, accuracy: 0.001)
        m.configure(stage: .mountain, questionCount: 30) // clamped to Earth's 20 images
        XCTAssertEqual(m.restingDepth(afterCorrect: 19), 19 * m.sectionStep, accuracy: 0.001)
        XCTAssertLessThanOrEqual(m.goalDepth + 874, 19 * m.sectionStep + m.sectionHeight + 0.001)
    }

    func testSkyAndSeaRunsPlayThroughToTheEnd() throws {
        FeatureFlags.testOverride = true
        let env = try TestEnv(xp: LevelCalculator.xpThreshold(for: 61))
        for stage in [Stage.sky, .sea] {
            let clock = FakeClock()
            let s = QuizSession(model: env.model, stage: stage, now: { clock.now() })
            s.configure(viewportHeight: 874, width: 402)
            XCTAssertEqual(s.stage, stage)
            while s.engine.phase != .finished {
                s.answer(s.engine.current.correctChoiceId)
                for _ in 0..<40 { clock.advance(0.05); s.advance() }   // let the dive land
                s.next()
            }
            XCTAssertEqual(s.engine.correctCount, s.engine.total)
            for _ in 0..<40 { clock.advance(0.05); s.advance() }
            XCTAssertEqual(s.motion.depth, s.motion.restingDepth(afterCorrect: s.engine.total), accuracy: 1)
        }
    }

    func testCollectionRowsPerStage() {
        let repo = QuestionRepository()
        let one = repo.questions(for: .sea)[0]
        let rows = CollectionService.rows(for: .sea, questions: repo.questions, unlockedIDs: [one.id])
        XCTAssertEqual(rows.count, repo.questions(for: .sea).count)
        XCTAssertEqual(rows.filter { $0.question != nil }.map(\.id), [one.id])
        XCTAssertTrue(rows.allSatisfy { r in repo.questions(for: .sea).contains { $0.id == r.id } })
    }
}

@MainActor
final class StageUnlockTests: XCTestCase {
    override func tearDown() { FeatureFlags.testOverride = nil }

    func testSessionRemembersTheLevelItStartedAt() throws {
        FeatureFlags.testOverride = nil
        let env = try TestEnv(xp: LevelCalculator.xpThreshold(for: 30) + 10)
        let s = QuizSession(model: env.model)
        XCTAssertEqual(s.startLevel, 30)
        XCTAssertEqual(s.stage, .mountain)
    }

    func testStageArtworkForTheUnlockBannerIsBundled() {
        XCTAssertNotNil(UIImage(named: "stage_space_title"))
        XCTAssertNotNil(UIImage(named: "stage_deepsea_title"))
    }

    func testCrossingLevel31OpensSpaceDuringARun() throws {
        FeatureFlags.testOverride = nil
        // 10 XP below the Lv.31 threshold; one correct answer (20 XP) crosses it.
        let env = try TestEnv(xp: LevelCalculator.xpThreshold(for: 31) - 10)
        let clock = FakeClock()
        let s = QuizSession(model: env.model, now: { clock.now() })
        s.configure(viewportHeight: 874, width: 402)
        XCTAssertEqual(s.startLevel, 30)
        s.answer(s.engine.current.correctChoiceId)
        XCTAssertEqual(env.model.levelInfo.level, 31)
        let opened = FeatureFlags.availableStages.first { $0.config.levels.lowerBound > s.startLevel && $0.config.levels.lowerBound <= env.model.levelInfo.level }
        XCTAssertEqual(opened, .sky)
    }
}
