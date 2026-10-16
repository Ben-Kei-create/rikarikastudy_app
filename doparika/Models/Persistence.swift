import Foundation
import SwiftData

@Model
final class PlayerProgress {
    var totalXP: Int = 0
    var sessionsCompleted: Int = 0

    init() {}
}

@Model
final class QuestionRecord {
    @Attribute(.unique) var questionID: String
    var attempts: Int = 0
    var correctCount: Int = 0
    var wrongCount: Int = 0
    var lastCorrect: Bool = false
    var lastAnsweredAt: Date = Date.distantPast
    var lastWrongAt: Date?
    /// Player level when last answered wrong; used to find "previous level" mistakes.
    var lastWrongLevel: Int = -1

    init(questionID: String) {
        self.questionID = questionID
    }
}
