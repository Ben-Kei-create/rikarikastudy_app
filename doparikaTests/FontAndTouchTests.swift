import XCTest
import SwiftUI
@testable import doparika

@MainActor
final class FontAndTouchTests: XCTestCase {
    func testBundledFontsLoadUnderTheirPostScriptNames() {
        for w: Font.Weight in [.regular, .bold, .black] {
            let name = AppFont.postScriptName(for: w)
            XCTAssertNotNil(UIFont(name: name, size: 12), "\(name) is not registered (UIAppFonts)")
        }
    }

    func testEveryWeightMapsOntoABundledFont() {
        let bundled: Set<String> = ["RoundedMplus1c-Regular", "RoundedMplus1c-Bold", "RoundedMplus1c-Black"]
        for w: Font.Weight in [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black] {
            XCTAssertTrue(bundled.contains(AppFont.postScriptName(for: w)))
        }
        XCTAssertEqual(AppFont.postScriptName(for: .bold), "RoundedMplus1c-Bold")
        XCTAssertEqual(AppFont.postScriptName(for: .black), "RoundedMplus1c-Black")
    }

    func testJapaneseGlyphsComeFromTheBundledFont() {
        let f = AppFont.uiFont(size: 17, weight: .bold)
        XCTAssertEqual(f.fontName, "RoundedMplus1c-Bold")
        for ch in ["正", "解", "ド", "パ", "○", "×", "連"] {
            let set = CTFontCopyCharacterSet(f)
            XCTAssertTrue(CFCharacterSetIsLongCharacterMember(set, ch.unicodeScalars.first!.value), "\(ch) missing")
        }
    }

    func testTouchEffectFollowsTheEffectsSwitchAndAdSuppression() {
        let t = TouchEffects.shared
        t.enabledOverride = nil
        let saved = AppSettings.shared.effectsEnabled
        defer { AppSettings.shared.effectsEnabled = saved; t.suppressed = false; t.enabledOverride = nil }
        AppSettings.shared.effectsEnabled = false
        XCTAssertFalse(t.isEnabled)
        AppSettings.shared.effectsEnabled = true
        t.suppressed = true
        XCTAssertFalse(t.isEnabled, "never draw over an ad")
        t.suppressed = false
        XCTAssertEqual(t.isEnabled, !UIAccessibility.isReduceMotionEnabled)
    }

    func testBurstWithoutAWindowIsHarmless() {
        TouchEffects.shared.enabledOverride = true
        defer { TouchEffects.shared.enabledOverride = nil }
        TouchEffects.shared.burst(at: CGPoint(x: 10, y: 10))   // not installed: must simply do nothing
    }
}
