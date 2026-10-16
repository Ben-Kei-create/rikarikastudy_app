import SwiftUI

enum Theme {
    static let parchment = Color(red: 0.96, green: 0.92, blue: 0.82)
    static let parchmentDark = Color(red: 0.86, green: 0.78, blue: 0.62)
    static let ink = Color(red: 0.24, green: 0.15, blue: 0.09)
    static let ember = Color(red: 1.0, green: 0.62, blue: 0.16)
    static let good = Color(red: 0.2, green: 0.8, blue: 0.3)
    static let bad = Color(red: 0.95, green: 0.25, blue: 0.2)
    static let night = Color(red: 0.07, green: 0.05, blue: 0.06)
}

struct ParchmentPanel: ViewModifier {
    var opacity: Double = 0.86
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(Theme.parchment.opacity(opacity), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.parchmentDark.opacity(0.9), lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}

extension View {
    func parchmentPanel(opacity: Double = 0.86) -> some View { modifier(ParchmentPanel(opacity: opacity)) }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.ember
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(LinearGradient(colors: [tint, tint.opacity(0.75)], startPoint: .top, endPoint: .bottom),
                        in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1.5))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
