import Foundation

/// Builds a 5-question session: review questions first by priority, rest are unseen (in ID order).
struct QuestionSelector {
    static let sessionSize = 5
    static let minReview = 2

    struct History {
        let questionID: String
        let wrongCount: Int
        let lastCorrect: Bool
        let lastWrongAt: Date?
        let lastWrongLevel: Int
        let lastAnsweredAt: Date
    }

    static func select(all: [Question], history: [History], currentLevel: Int,
                       size: Int = sessionSize) -> [Question] {
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let answered = history.filter { byID[$0.questionID] != nil }
        let answeredIDs = Set(answered.map(\.questionID))
        let unseen = all.filter { !answeredIDs.contains($0.id) }

        // Priority: 1. previous session's mistakes  2. recent mistakes
        // 3. repeat offenders  4. previously correct.
        var ranked: [String] = []
        func add(_ items: [History]) {
            for h in items where !ranked.contains(h.questionID) { ranked.append(h.questionID) }
        }
        let wrong = answered.filter { $0.wrongCount > 0 }
        add(wrong.filter { $0.lastWrongLevel == currentLevel - 1 }
            .sorted { ($0.lastWrongAt ?? .distantPast) > ($1.lastWrongAt ?? .distantPast) })
        add(wrong.sorted { ($0.lastWrongAt ?? .distantPast) > ($1.lastWrongAt ?? .distantPast) })
        add(wrong.sorted { $0.wrongCount > $1.wrongCount })
        add(answered.filter { $0.lastCorrect }.sorted { $0.lastAnsweredAt < $1.lastAnsweredAt })

        // Cap at the wrong-questions that exist but never starve new content entirely.
        let reviewTarget = min(ranked.count, max(minReview, min(size - 1, wrong.count)))
        let reviewCount = unseen.isEmpty ? min(ranked.count, size) : reviewTarget
        var picked: [Question] = ranked.prefix(reviewCount).compactMap { byID[$0] }
        picked += unseen.prefix(size - picked.count)
        // Not enough unseen: top up with remaining review questions.
        if picked.count < size {
            let have = Set(picked.map(\.id))
            picked += ranked.compactMap { byID[$0] }.filter { !have.contains($0.id) }.prefix(size - picked.count)
        }
        return picked.shuffled()
    }
}
