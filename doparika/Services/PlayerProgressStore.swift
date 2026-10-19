import Foundation
import SwiftData

/// Owns persistence (XP, level, per-question history). UI never touches ModelContext for game state.
@MainActor
final class PlayerProgressStore {
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    private func progress() -> PlayerProgress {
        if let p = try? context.fetch(FetchDescriptor<PlayerProgress>()).first { return p }
        let p = PlayerProgress()
        context.insert(p)
        return p
    }

    var totalXP: Int { progress().totalXP }
    var sessionsCompleted: Int { progress().sessionsCompleted }

    func addXP(_ amount: Int) {
        let p = progress()
        p.totalXP += max(0, amount)   // uncapped; Lv and world progress are capped elsewhere
        save()
    }

    func completeSession() {
        progress().sessionsCompleted += 1
        save()
    }

    func records() -> [QuestionRecord] {
        (try? context.fetch(FetchDescriptor<QuestionRecord>())) ?? []
    }

    func recordAnswer(questionID: String, correct: Bool) {
        let level = LevelCalculator.level(forXP: totalXP)
        let id = questionID
        let existing = try? context.fetch(
            FetchDescriptor<QuestionRecord>(predicate: #Predicate { $0.questionID == id })).first
        let r = existing ?? QuestionRecord(questionID: id)
        if existing == nil { context.insert(r) }
        r.attempts += 1
        r.lastCorrect = correct
        r.lastAnsweredAt = Date()
        if correct { r.correctCount += 1 } else {
            r.wrongCount += 1
            r.lastWrongAt = Date()
            r.lastWrongLevel = level
        }
        save()
    }

    /// Wipes XP, session count and every question record.
    func resetAll() {
        for r in records() { context.delete(r) }
        let p = progress()
        p.totalXP = 0
        p.sessionsCompleted = 0
        save()
    }

    private func save() { try? context.save() }
}
