import XCTest
import SwiftData
@testable import doparika

@MainActor
final class PersistenceAndSelectionTests: XCTestCase {
    func testXPUnlockedAndWrongHistorySurviveReopen() throws {
        let env = try TestEnv()
        let q = env.model.repository.questions(for: .mountain)
        env.model.record(question: q[0], correct: true)
        env.model.record(question: q[1], correct: false)
        env.model.finishSession()
        // "Restart": a fresh AppModel over the same store.
        let reopened = AppModel(context: env.container.mainContext)
        XCTAssertEqual(reopened.totalXP, QuizEngine.xpPerCorrect)
        XCTAssertEqual(reopened.unlockedIDs, [q[0].id, q[1].id])
        let rec = reopened.store.records().first { $0.questionID == q[1].id }
        XCTAssertEqual(rec?.wrongCount, 1)
        XCTAssertEqual(reopened.store.sessionsCompleted, 1)
    }

    func testXPIsUncappedButLevelIsCapped() throws {
        let env = try TestEnv(xp: LevelCalculator.maxXP + 500)
        XCTAssertEqual(env.model.totalXP, LevelCalculator.maxXP + 500)
        XCTAssertEqual(env.model.levelInfo.level, LevelCalculator.maxLevel)
        XCTAssertLessThanOrEqual(env.model.levelFraction, 1)
    }

    func testSessionHasFiveUniqueQuestionsAndMixesReview() throws {
        let env = try TestEnv()
        let qs = env.model.repository.questions(for: .mountain)
        for q in qs.prefix(8) { env.model.record(question: q, correct: false) }
        let set = env.model.makeSession()
        XCTAssertEqual(set.count, env.model.sessionLength)
        XCTAssertEqual(Set(set.map(\.id)).count, set.count)
        let reviewIDs = Set(qs.prefix(8).map(\.id))
        let reviews = set.filter { reviewIDs.contains($0.id) }.count
        XCTAssertGreaterThanOrEqual(reviews, 1)
        XCTAssertLessThanOrEqual(reviews, Int(Double(env.model.sessionLength) * QuestionSelector.maxReviewShare))
    }

    func testLevel30TakesRoughlySixHundredCorrectAnswers() {
        let correct = LevelCalculator.xpThreshold(for: 30) / QuizEngine.xpPerCorrect   // Lv.30 = end of Earth
        XCTAssertTrue((550...650).contains(correct), "Lv.30 needs \(correct) correct answers")
    }

    func testNewQuestionsAreRandomNotInIDOrder() throws {
        let env = try TestEnv()
        let firstTen = Set(env.model.repository.questions(for: .mountain).prefix(env.model.sessionLength).map(\.id))
        let ids = Set(env.model.makeSession().map(\.id))
        XCTAssertNotEqual(ids, firstTen, "a fresh session must not just be the first IDs in order")
        let other = Set(env.model.makeSession().map(\.id))
        XCTAssertNotEqual(ids, other, "two fresh sessions should differ")
    }

    func testCollectionFillsAtRandomPlacesNotFromTheTop() throws {
        let env = try TestEnv()
        for _ in 0..<3 { for q in env.model.makeSession() { env.model.record(question: q, correct: true) } }
        let rows = CollectionService.rows(for: .mountain, questions: env.model.repository.questions,
                                          unlockedIDs: env.model.unlockedIDs)
        XCTAssertEqual(rows.count, env.model.repository.questions(for: .mountain).count, "every ID is listed")
        let unlockedIdx = rows.indices.filter { rows[$0].question != nil }
        XCTAssertEqual(unlockedIdx.count, 30)
        XCTAssertNotEqual(unlockedIdx, Array(0..<30), "unlocked entries must be scattered by ID, not the first 30 rows")
    }

    func testNoMistakesMeansEverythingIsNew() throws {
        let env = try TestEnv()
        let qs = env.model.repository.questions(for: .mountain)
        for q in qs.prefix(8) { env.model.record(question: q, correct: true) }
        let seen = Set(qs.prefix(8).map(\.id))
        XCTAssertTrue(env.model.makeSession().allSatisfy { !seen.contains($0.id) })
    }

    func testResetClearsXPAndHistory() throws {
        let env = try TestEnv()
        let q = env.model.repository.questions(for: .mountain)[0]
        env.model.record(question: q, correct: true)
        env.model.resetProgress()
        XCTAssertEqual(env.model.totalXP, 0)
        XCTAssertTrue(env.model.unlockedIDs.isEmpty)
        XCTAssertEqual(env.model.store.sessionsCompleted, 0)
    }

    func testRepositoryIDsAreFivePaddedAndUnique() {
        let repo = QuestionRepository()
        XCTAssertNil(repo.loadError)
        XCTAssertTrue(repo.questions.allSatisfy { $0.id.count == 5 && $0.id.allSatisfy(\.isNumber) })
        XCTAssertEqual(Set(repo.questions.map(\.id)).count, repo.questions.count)
        XCTAssertTrue(repo.questions.allSatisfy { $0.choices.count == 2 })
    }
}

@MainActor
final class PoolFallbackTests: XCTestCase {
    override func tearDown() { FeatureFlags.testOverride = nil }

    func testASmallStageBankIsTopUpFromEarlierStagesAndNeverRunsDry() throws {
        FeatureFlags.testOverride = nil          // Earth + space
        let env = try TestEnv(xp: LevelCalculator.xpThreshold(for: 31))
        let sky = env.model.repository.questions(for: .sky)
        // Answer every space question so none are left unanswered.
        for q in sky { env.model.record(question: q, correct: true) }
        let session = env.model.makeSession()
        XCTAssertEqual(session.count, env.model.sessionLength(for: .sky), "still a full session")
        XCTAssertTrue(session.contains { $0.stage == .mountain }, "borrowed Earth questions")
        XCTAssertFalse(session.contains { $0.stage == .sea }, "never the hidden deep sea")
        XCTAssertEqual(Set(session.map(\.id)).count, session.count)
        let own = session.filter { $0.stage == .sky }.count
        XCTAssertGreaterThanOrEqual(own, Int((Double(session.count) * QuestionSelector.minStageShare).rounded(.up)),
                                    "the stage keeps its minimum share of the session even when its bank is used up")
        XCTAssertLessThanOrEqual(session.count - own, session.count - Int((Double(session.count) * QuestionSelector.minStageShare).rounded(.up)))
    }

    func testStageShareHoldsForEverySessionLength() throws {
        FeatureFlags.testOverride = nil
        let env = try TestEnv(xp: LevelCalculator.xpThreshold(for: 31))
        let sky = env.model.repository.questions(for: .sky)
        for q in sky { env.model.record(question: q, correct: true) }
        let earth = env.model.repository.questions(for: .mountain)
        let pool = QuestionSelector.select(all: sky, history: env.model.store.records().map {
            QuestionSelector.History(questionID: $0.questionID, wrongCount: $0.wrongCount, lastCorrect: $0.lastCorrect,
                                     lastWrongAt: $0.lastWrongAt, lastWrongLevel: $0.lastWrongLevel, lastAnsweredAt: $0.lastAnsweredAt)
        }, currentLevel: 35, size: 10, fallback: earth)
        XCTAssertGreaterThanOrEqual(pool.filter { $0.stage == .sky }.count, 7, "7 of 10")
    }

    func testSpaceQuestionsComeFirstWhileTheyLast() throws {
        FeatureFlags.testOverride = nil
        let env = try TestEnv(xp: LevelCalculator.xpThreshold(for: 31))
        let session = env.model.makeSession()
        let sky = env.model.repository.questions(for: .sky).count
        if sky >= session.count { XCTAssertTrue(session.allSatisfy { $0.stage == .sky }) }
    }

    func testEarthSessionsDoNotBorrowFromLaterStages() throws {
        FeatureFlags.testOverride = nil
        let env = try TestEnv()
        XCTAssertTrue(env.model.makeSession().allSatisfy { $0.stage == .mountain })
    }
}

@MainActor
final class StageDataHealthTests: XCTestCase {
    override func tearDown() { FeatureFlags.testOverride = nil }

    private func bundled(_ stage: Stage) -> Data? {
        Bundle.main.url(forResource: stage.questionsResource, withExtension: "json").flatMap { try? Data(contentsOf: $0) }
    }

    private func repo(sky: Data?) -> QuestionRepository {
        QuestionRepository(loader: { $0 == .sky ? sky : self.bundled($0) })
    }

    func testRealDataIsHealthyForEveryStage() {
        let r = QuestionRepository()
        for s in Stage.allCases { XCTAssertTrue(r.isPlayable(s), "\(s): \(r.stageErrors[s] ?? "")") }
        XCTAssertNil(r.loadError)
    }

    func testMissingBrokenInvalidOrTooSmallSpaceBankStopsOnlySpace() {
        let cases: [(String, Data?)] = [
            ("missing", nil),
            ("corrupt", Data("not json".utf8)),
            ("all invalid", Data(#"[{"id":"1","stage":"sky","grade":3,"subject":"earth","difficulty":1,"question":"q","choices":[{"id":"A","text":"a"}],"correctChoiceId":"A","explanation":"e"}]"#.utf8)),
            ("too few", Data("[]".utf8)),
        ]
        for (name, data) in cases {
            let r = repo(sky: data)
            XCTAssertFalse(r.isPlayable(.sky), name)
            XCTAssertNotNil(r.stageErrors[.sky], name)
            XCTAssertTrue(r.isPlayable(.mountain), "Earth is untouched (\(name))")
            XCTAssertNil(r.loadError, "the app itself still starts (\(name))")
        }
    }

    func testAPlayerAtLevel35StaysOnEarthWhenSpaceCannotLoad() throws {
        FeatureFlags.testOverride = nil
        let env = try TestEnv(xp: LevelCalculator.xpThreshold(for: 35))
        let model = AppModel(context: env.container.mainContext, repository: repo(sky: nil))
        XCTAssertEqual(model.levelInfo.level, 35)
        XCTAssertEqual(model.currentStage, .mountain)
        XCTAssertEqual(model.unlockedStages, [.mountain])
        XCTAssertEqual(model.stagesWithoutQuestions, [.sky])
        XCTAssertTrue(model.makeSession().allSatisfy { $0.stage == .mountain })
        XCTAssertEqual(model.xpPerCorrect(for: .mountain), QuizEngine.xpPerCorrect, "Earth pays full XP while space is unavailable")
    }
}


@MainActor
final class OnDiskPersistenceTests: XCTestCase {
    /// A real file store reopened by a fresh container (what an update or a relaunch does), not the same context.
    func testProgressSurvivesReopeningTheSameStoreFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("doparika-\(UUID().uuidString).store")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let schema: [any PersistentModel.Type] = [PlayerProgress.self, QuestionRecord.self]
        var answered: [String] = []
        do {
            let c1 = try ModelContainer(for: Schema(schema), configurations: ModelConfiguration(url: url))
            let m1 = AppModel(context: c1.mainContext)
            let qs = m1.repository.questions(for: .mountain)
            m1.record(question: qs[0], correct: true)
            m1.record(question: qs[1], correct: false)
            m1.record(question: qs[2], correct: true)
            m1.finishSession()
            answered = [qs[0].id, qs[1].id, qs[2].id]
            try c1.mainContext.save()
        }
        let c2 = try ModelContainer(for: Schema(schema), configurations: ModelConfiguration(url: url))
        let m2 = AppModel(context: c2.mainContext)
        XCTAssertEqual(m2.totalXP, 2 * QuizEngine.xpPerCorrect)
        XCTAssertEqual(m2.unlockedIDs, Set(answered))
        XCTAssertEqual(m2.store.sessionsCompleted, 1)
        let wrong = m2.store.records().first { $0.questionID == answered[1] }
        XCTAssertEqual(wrong?.wrongCount, 1)
    }
}
