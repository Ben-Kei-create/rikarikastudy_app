import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppModel {
    let repository: QuestionRepository
    let store: PlayerProgressStore
    let ads: AdManaging = NoopAdManager()

    private(set) var totalXP: Int
    private(set) var unlockedIDs: Set<String>

    init(context: ModelContext, repository: QuestionRepository? = nil) {
        self.repository = repository ?? QuestionRepository()
        self.store = PlayerProgressStore(context: context)
        self.totalXP = store.totalXP
        self.unlockedIDs = Set(store.records().map(\.questionID))
    }

    var levelInfo: LevelCalculator.Info { LevelCalculator.info(forXP: totalXP) }

    /// 0...1 progress through the whole release-1 world, used for the starting depth.
    var worldProgress: Double { min(1, Double(totalXP) / Double(max(LevelCalculator.maxXP, 1))) }

    var canStartSession: Bool { repository.loadError == nil }

    func makeSession() -> [Question] {
        let history = store.records().map {
            QuestionSelector.History(questionID: $0.questionID, wrongCount: $0.wrongCount,
                                     lastCorrect: $0.lastCorrect, lastWrongAt: $0.lastWrongAt,
                                     lastWrongLevel: $0.lastWrongLevel, lastAnsweredAt: $0.lastAnsweredAt)
        }
        return QuestionSelector.select(all: repository.questions(for: .mountain), history: history,
                                       currentLevel: levelInfo.level)
    }

    func record(question: Question, correct: Bool) {
        store.recordAnswer(questionID: question.id, correct: correct)
        unlockedIDs.insert(question.id)
        if correct {
            store.addXP(QuizEngine.xpPerCorrect)
            totalXP = store.totalXP
        }
    }

    func finishSession() {
        store.completeSession()
        totalXP = store.totalXP
    }
}
