import Foundation
import Observation

/// User-facing on/off switches, persisted in UserDefaults. Everything defaults to ON.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let bgm = "settings.bgm", sfx = "settings.sfx"
        static let effects = "settings.effects", haptics = "settings.haptics"
        static let legacyMute = "soundMuted"          // older single mute switch
    }

    var bgmEnabled: Bool { didSet { save(bgmEnabled, Key.bgm); MusicPlayer.shared.settingsChanged() } }
    var sfxEnabled: Bool { didSet { save(sfxEnabled, Key.sfx); if !sfxEnabled { SoundPlayer.shared.stopAll() } } }
    /// Visual extras: background rumble, particles, speed lines, sparkles, ○/× stamps, launch intro.
    var effectsEnabled: Bool { didSet { save(effectsEnabled, Key.effects) } }
    var hapticsEnabled: Bool { didSet { save(hapticsEnabled, Key.haptics) } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func read(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
        // Carry over the old mute switch: muted meant sound effects and music were both off.
        let legacyMuted = defaults.bool(forKey: Key.legacyMute)
        bgmEnabled = defaults.object(forKey: Key.bgm) as? Bool ?? !legacyMuted
        sfxEnabled = defaults.object(forKey: Key.sfx) as? Bool ?? !legacyMuted
        effectsEnabled = read(Key.effects)
        hapticsEnabled = read(Key.haptics)
    }

    private func save(_ value: Bool, _ key: String) { defaults.set(value, forKey: key) }
}
