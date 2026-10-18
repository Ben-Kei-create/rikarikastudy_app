import UIKit

/// Tactile feedback for answers. Kept behind one type so tests and previews stay silent.
@MainActor
enum Haptics {
    /// Test/preview kill switch; the user setting is `AppSettings.hapticsEnabled`.
    static var isEnabled = true
    private static var on: Bool { isEnabled && AppSettings.shared.hapticsEnabled }

    /// Correct answer: a firm hit as the dive starts, then a softer second tap when it lands.
    static func correct() {
        guard on else { return }
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        impact.prepare()
        impact.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
        }
    }

    static func wrong() {
        guard on else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func timeout() {
        guard on else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Light tick for the last seconds of a question.
    static func tick() {
        guard on else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5)
    }
}
