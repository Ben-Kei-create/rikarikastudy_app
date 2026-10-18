import UIKit

/// Tactile feedback for answers. Kept behind one type so tests and previews stay silent.
@MainActor
enum Haptics {
    static var isEnabled = true

    /// Correct answer: a firm hit as the dive starts, then a softer second tap when it lands.
    static func correct() {
        guard isEnabled else { return }
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.prepare()
        impact.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
        }
    }

    static func wrong() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func timeout() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Light tick for the last seconds of a question.
    static func tick() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5)
    }
}
