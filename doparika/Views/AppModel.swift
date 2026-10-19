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
        #if DEBUG
        // QA aid: `-debugXP <n>` raises stored XP to n so late-world sections can be inspected.
        let xp = UserDefaults.standard.integer(forKey: "debugXP")
        if xp > store.totalXP {
            store.addXP(xp - store.totalXP)
        }
        #endif
        self.totalXP = store.totalXP
        self.unlockedIDs = Set(store.records().map(\.questionID))
    }

    func reloadFromStore() {
        totalXP = store.totalXP
        unlockedIDs = Set(store.records().map(\.questionID))
    }

    var levelInfo: LevelCalculator.Info { LevelCalculator.info(forXP: totalXP) }

    /// 0...1 progress through Lv.1...30 (level plus progress inside the level).
    var levelFraction: Double {
        let info = levelInfo
        let lv = info.isMax ? Double(LevelCalculator.maxLevel) : Double(info.level) + info.fraction
        return (lv - 1) / Double(LevelCalculator.maxLevel - 1)
    }

    var worldProgress: Double { min(1, Double(totalXP) / Double(max(LevelCalculator.maxXP, 1))) }

    var canStartSession: Bool { repository.loadError == nil }

    /// Lv.1-20: 10 questions (images 001-010). Lv.21-30: 20 questions (images 001-020).
    var sessionLength: Int { levelInfo.level > 20 ? 20 : 10 }

    func makeSession() -> [Question] {
        let history = store.records().map {
            QuestionSelector.History(questionID: $0.questionID, wrongCount: $0.wrongCount,
                                     lastCorrect: $0.lastCorrect, lastWrongAt: $0.lastWrongAt,
                                     lastWrongLevel: $0.lastWrongLevel, lastAnsweredAt: $0.lastAnsweredAt)
        }
        var picked = QuestionSelector.select(all: repository.questions(for: .mountain), history: history,
                                             currentLevel: levelInfo.level, size: sessionLength)
        #if DEBUG
        // QA aid: `-debugCorrectIsA YES` always makes choice A the right one, so UI tests can answer correctly.
        if UserDefaults.standard.bool(forKey: "debugCorrectIsA") {
            picked = picked.map { q in
                guard q.correctChoiceId != "A", q.choices.count == 2 else { return q }
                let swapped = [Choice(id: "A", text: q.choices[1].text), Choice(id: "B", text: q.choices[0].text)]
                return Question(id: q.id, stage: q.stage, grade: q.grade, subject: q.subject, difficulty: q.difficulty,
                                question: q.question, choices: swapped, correctChoiceId: "A", explanation: q.explanation)
            }
        }
        // QA aid: `-debugLongestFirst YES` puts the longest question and the longest explanation first.
        if UserDefaults.standard.bool(forKey: "debugLongestFirst") {
            let all = repository.questions(for: .mountain)
            let longQ = all.max { $0.question.count + $0.choices.map(\.text.count).max()! < $1.question.count + $1.choices.map(\.text.count).max()! }
            let longE = all.max { $0.explanation.count < $1.explanation.count }
            let front = [longQ, longE].compactMap { $0 }
            picked = front + picked.filter { p in !front.contains { $0.id == p.id } }
            picked = Array(picked.prefix(sessionLength))
        }
        #endif
        return picked
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
