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

/// Answers per field (分野), all stages together, counted from the saved per-question records.
struct SubjectStat: Identifiable, Equatable {
    let subject: String
    let correct: Int
    let wrong: Int
    var id: String { subject }
    var total: Int { correct + wrong }

    static let order = ["physics", "chemistry", "biology", "earth"]
    static func label(_ subject: String) -> String {
        switch subject {
        case "physics": return "物理"
        case "chemistry": return "化学"
        case "biology": return "生物"
        case "earth": return "地学"
        default: return subject
        }
    }
}

extension CollectionService {
    /// Correct and wrong answers per field; the four fields always appear, in a fixed order.
    static func subjectStats(questions: [Question], counts: [String: (correct: Int, wrong: Int)]) -> [SubjectStat] {
        var sums: [String: (Int, Int)] = [:]
        for q in questions {
            guard let c = counts[q.id] else { continue }
            let s = sums[q.subject] ?? (0, 0)
            sums[q.subject] = (s.0 + c.correct, s.1 + c.wrong)
        }
        let known = SubjectStat.order + sums.keys.filter { !SubjectStat.order.contains($0) }.sorted()
        return known.map { SubjectStat(subject: $0, correct: sums[$0]?.0 ?? 0, wrong: sums[$0]?.1 ?? 0) }
    }
}
