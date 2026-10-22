import Foundation

struct CollectionRow: Identifiable {
    let id: String
    let question: Question?   // nil == locked ("????")
}

enum CollectionService {
    static let placeholderRows = 20

    /// Rows for a stage tab. Every question of the stage is listed; locked ones read "????".
    static func rows(for stage: Stage, questions: [Question], unlockedIDs: Set<String>) -> [CollectionRow] {
        let stageQs = questions.filter { $0.stage == stage }
        guard !stageQs.isEmpty else {     // a stage without questions shows only locked placeholders
            return (1...placeholderRows).map { CollectionRow(id: String(format: "%05d", $0) + stage.rawValue, question: nil) }
        }
        return stageQs.map { CollectionRow(id: $0.id, question: unlockedIDs.contains($0.id) ? $0 : nil) }
    }
}
