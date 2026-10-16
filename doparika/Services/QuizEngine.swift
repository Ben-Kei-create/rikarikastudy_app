import Foundation
import Observation

enum QuizPhase: Equatable {
    case answering
    case resolved(Resolution)
    case finished
}

enum Resolution: Equatable {
    case correct(choiceID: String)
    case wrong(chosenID: String)
    case timeout
}

/// Pure game-state machine: no UI, no persistence. Time is injected via `tick(dt)`.
/// All transitions are guarded by `phase`, so double-taps and timeout/answer races resolve once.
@MainActor
@Observable
final class QuizEngine {
    static let timeLimit: Double = 15
    static let xpPerCorrect = 20

    let questions: [Question]
    private(set) var index = 0
    private(set) var phase: QuizPhase = .answering
    private(set) var remaining: Double = QuizEngine.timeLimit
    private(set) var correctCount = 0
    private(set) var earnedXP = 0
    private(set) var lastXPGain = 0

    /// Called exactly once per question when it resolves.
    @ObservationIgnored var onResolved: ((Question, Resolution) -> Void)?

    init(questions: [Question]) { self.questions = questions }

    var current: Question { questions[index] }
    var total: Int { questions.count }
    var isLast: Bool { index >= questions.count - 1 }

    func answer(choiceID: String) {
        guard phase == .answering, current.choices.contains(where: { $0.id == choiceID }) else { return }
        resolve(choiceID == current.correctChoiceId
                ? .correct(choiceID: choiceID) : .wrong(chosenID: choiceID))
    }

    func tick(_ dt: Double) {
        guard phase == .answering else { return }
        remaining = max(0, remaining - dt)
        if remaining <= 0 { resolve(.timeout) }
    }

    func next() {
        guard case .resolved = phase else { return }
        if isLast { phase = .finished; return }
        index += 1
        remaining = Self.timeLimit
        lastXPGain = 0
        phase = .answering
    }

    private func resolve(_ r: Resolution) {
        guard phase == .answering else { return }
        phase = .resolved(r)
        if case .correct = r {
            correctCount += 1
            lastXPGain = Self.xpPerCorrect
            earnedXP += Self.xpPerCorrect
        } else { lastXPGain = 0 }
        onResolved?(current, r)
    }
}
