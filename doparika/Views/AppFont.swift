import SwiftUI
import UIKit

/// The app's single typeface: M PLUS Rounded 1c (SIL OFL, see MPLUSRounded1c-OFL.txt in Resources/Fonts).
/// Three weights are bundled; every SwiftUI weight maps onto the nearest one.
enum AppFont {
    static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .black, .heavy: return "RoundedMplus1c-Black"
        case .semibold, .bold: return "RoundedMplus1c-Bold"
        default: return "RoundedMplus1c-Regular"        // ultraLight ... medium
        }
    }

    /// Point size of each text style at the default Dynamic Type setting.
    static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }

    static func uiFont(size: CGFloat, weight: Font.Weight) -> UIFont {
        UIFont(name: postScriptName(for: weight), size: size) ?? .systemFont(ofSize: size)
    }
}

extension Font {
    /// A text style in M PLUS Rounded 1c; scales with Dynamic Type like the system style.
    static func mplus(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .custom(AppFont.postScriptName(for: weight), size: AppFont.baseSize(style), relativeTo: style)
    }

    /// A fixed point size (does not follow Dynamic Type), for display text such as big numbers.
    static func mplus(fixed size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(AppFont.postScriptName(for: weight), fixedSize: size)
    }

    /// A size that grows with Dynamic Type relative to `style`.
    static func mplus(size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(AppFont.postScriptName(for: weight), size: size, relativeTo: style)
    }
}

/// UIKit-drawn text (navigation bars, segmented pickers, bar buttons) cannot read SwiftUI's font.
@MainActor
enum AppFontAppearance {
    static func install() {
        let bold = AppFont.uiFont(size: 17, weight: .bold)
        let nav = UINavigationBar.appearance()
        nav.titleTextAttributes = [.font: bold]
        nav.largeTitleTextAttributes = [.font: AppFont.uiFont(size: 34, weight: .black)]
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: AppFont.uiFont(size: 17, weight: .bold)], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: AppFont.uiFont(size: 14, weight: .bold)], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: AppFont.uiFont(size: 14, weight: .bold)], for: .selected)
    }
}
