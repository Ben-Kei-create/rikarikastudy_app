import Foundation
import SwiftData
@testable import doparika

/// Mutable fake clock injected into QuizSession.
final class FakeClock {
    private let base = ContinuousClock().now
    private var offset: Duration = .zero
    func advance(_ seconds: Double) { offset += .milliseconds(Int((seconds * 1000).rounded())) }
    func now() -> ContinuousClock.Instant { base + offset }
}

@MainActor
struct TestEnv {
    let container: ModelContainer
    let model: AppModel

    init(xp: Int = 0) throws {
        container = try ModelContainer(
            for: PlayerProgress.self, QuestionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        model = AppModel(context: container.mainContext)
        if xp > 0 { model.store.addXP(xp) }
        model.reloadFromStore()
    }

    func session(clock: FakeClock, carry: Double? = nil) -> QuizSession {
        QuizSession(model: model, carryOverPosition: carry, now: { clock.now() })
    }
}
