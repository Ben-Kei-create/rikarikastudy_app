import Foundation

struct CollectionRow: Identifiable {
    let id: String
    let question: Question?   // nil == locked ("????")
}

enum CollectionService {
    static let placeholderRows = 20

    /// Rows for a stage tab. Locked rows show only a limited look-ahead so the total stays hidden.
    static func rows(for stage: Stage, questions: [Question], unlockedIDs: Set<String>) -> [CollectionRow] {
        guard stage == .mountain else {
            return (1...placeholderRows).map { CollectionRow(id: String(format: "%05d", $0) + stage.rawValue, question: nil) }
        }
        let stageQs = questions.filter { $0.stage == stage }
        let lastUnlocked = stageQs.lastIndex { unlockedIDs.contains($0.id) } ?? -1
        let shown = min(stageQs.count, max(placeholderRows, lastUnlocked + 1 + 10))
        return stageQs.prefix(shown).map {
            CollectionRow(id: $0.id, question: unlockedIDs.contains($0.id) ? $0 : nil)
        }
    }
}
