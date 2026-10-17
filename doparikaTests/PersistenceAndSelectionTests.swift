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
        XCTAssertEqual(set.count, QuestionSelector.sessionSize)
        XCTAssertEqual(Set(set.map(\.id)).count, set.count)
        let reviewIDs = Set(qs.prefix(8).map(\.id))
        XCTAssertGreaterThanOrEqual(set.filter { reviewIDs.contains($0.id) }.count, QuestionSelector.minReview)
    }

    func testRepositoryIDsAreFivePaddedAndUnique() {
        let repo = QuestionRepository()
        XCTAssertNil(repo.loadError)
        XCTAssertTrue(repo.questions.allSatisfy { $0.id.count == 5 && $0.id.allSatisfy(\.isNumber) })
        XCTAssertEqual(Set(repo.questions.map(\.id)).count, repo.questions.count)
        XCTAssertTrue(repo.questions.allSatisfy { $0.choices.count == 2 })
    }
}
