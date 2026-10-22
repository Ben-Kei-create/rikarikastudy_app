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
        let correct = LevelCalculator.maxXP / QuizEngine.xpPerCorrect
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
