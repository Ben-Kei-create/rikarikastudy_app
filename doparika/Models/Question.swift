import Foundation

enum Stage: String, Codable, CaseIterable {
    case mountain, sky, sea

    var title: String {
        switch self {
        case .mountain: return "地球"   // raw value stays "mountain": stored IDs/JSON never change
        case .sky: return "空"
        case .sea: return "海"
        }
    }
}

struct Choice: Codable, Hashable, Identifiable {
    let id: String
    let text: String
}

struct Question: Codable, Hashable, Identifiable {
    let id: String
    let stage: Stage
    let grade: Int
    let subject: String
    let difficulty: Int
    let question: String
    let choices: [Choice]
    let correctChoiceId: String
    let explanation: String

    var correctText: String {
        choices.first { $0.id == correctChoiceId }?.text ?? ""
    }

    /// Structurally valid: two+ choices, unique ids, correct id present.
    var isValid: Bool {
        choices.count >= 2
            && Set(choices.map(\.id)).count == choices.count
            && choices.contains { $0.id == correctChoiceId }
            && !question.isEmpty
    }
}
