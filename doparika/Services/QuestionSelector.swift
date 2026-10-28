import Foundation

/// Builds a session: a few review questions (only ones still answered wrong), the rest random unseen ones.
/// With no open mistakes every question is new.
struct QuestionSelector {
    /// Smallest session; the longest (Lv.20+) is 20.
    static let sessionSize = 10
    /// Reviews never take more than this share of a session, so most questions stay new.
    static let maxReviewShare = 0.3

    struct History {
        let questionID: String
        let wrongCount: Int
        let lastCorrect: Bool
        let lastWrongAt: Date?
        let lastWrongLevel: Int
        let lastAnsweredAt: Date
    }

    /// `all` is the stage being played. `fallback` (questions of earlier stages) is only used once the
    /// stage's own unanswered questions run out, so a stage with a small question bank stays fully playable.
    static func select(all: [Question], history: [History], currentLevel: Int,
                       size: Int = sessionSize, fallback: [Question] = []) -> [Question] {
        let ownIDs = Set(all.map(\.id))
        let pool = all + fallback.filter { f in !ownIDs.contains(f.id) }
        let byID = Dictionary(uniqueKeysWithValues: pool.map { ($0.id, $0) })
        let answered = history.filter { byID[$0.questionID] != nil }
        let answeredIDs = Set(answered.map(\.questionID))
        // New questions are drawn at random from everything not yet answered (not in ID order);
        // the stage's own questions come before any fallback ones.
        let unseen = all.filter { !answeredIDs.contains($0.id) }.shuffled()
            + fallback.filter { f in !answeredIDs.contains(f.id) && !ownIDs.contains(f.id) }.shuffled()

        // Priority: 1. previous session's mistakes  2. recent mistakes
        // 3. repeat offenders  4. previously correct.
        var ranked: [String] = []
        func add(_ items: [History]) {
            for h in items where !ranked.contains(h.questionID) { ranked.append(h.questionID) }
        }
        // Mistakes not yet answered correctly since (those that were drop to the "previously correct" tier).
        let wrong = answered.filter { $0.wrongCount > 0 && !$0.lastCorrect }
        add(wrong.filter { $0.lastWrongLevel == currentLevel - 1 }
            .sorted { ($0.lastWrongAt ?? .distantPast) > ($1.lastWrongAt ?? .distantPast) })
        add(wrong.sorted { ($0.lastWrongAt ?? .distantPast) > ($1.lastWrongAt ?? .distantPast) })
        add(wrong.sorted { $0.wrongCount > $1.wrongCount })
        add(answered.filter { $0.lastCorrect }.sorted { $0.lastAnsweredAt < $1.lastAnsweredAt })

        let open = Set(wrong.map(\.questionID))
        let cap = max(1, Int(Double(size) * maxReviewShare))
        let reviewCount = unseen.isEmpty ? min(ranked.count, size)
                                         : min(ranked.filter(open.contains).count, cap)
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
