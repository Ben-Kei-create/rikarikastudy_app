import Foundation

/// Release switches. Release 1 ships the Earth stage only; 宇宙 and 深海 are fully implemented but hidden.
enum FeatureFlags {
    /// Release 2: flip this to `true` (nothing else is needed) to enable 宇宙 (Lv.31-60) and 深海 (Lv.61-100).
    static let extraStagesShipped = false

    /// Tests force the flag on/off; nil = follow the real setting.
    static var testOverride: Bool?

    static var extraStagesEnabled: Bool {
        if let forced = testOverride { return forced }
        #if DEBUG
        // QA aid: `-debugStages YES` turns the extra stages on in debug builds only.
        if UserDefaults.standard.bool(forKey: "debugStages") { return true }
        #endif
        return extraStagesShipped
    }

    /// Stages the player can see and play right now.
    static var availableStages: [Stage] { extraStagesEnabled ? Stage.allCases : [.mountain] }
}

enum StageDirection {
    /// Correct answers dive deeper (Earth, deep sea): image 001 starts at the top of the world.
    case descend
    /// Correct answers climb upward (space): image 001 is the ground at the bottom, the world flows downward.
    case ascend
}

/// Everything that differs between the three stages, in one place.
struct StageConfig {
    let stage: Stage
    /// Asset names are `<prefix>001`, `<prefix>002`, ...
    let imagePrefix: String
    let imageCount: Int
    let direction: StageDirection
    /// Player levels that belong to this stage.
    let levels: ClosedRange<Int>
    let music: [MusicPlayer.Track]
}

extension Stage {
    var config: StageConfig {
        switch self {
        case .mountain:
            return StageConfig(stage: self, imagePrefix: "earth_", imageCount: 20, direction: .descend,
                               levels: 1...30, music: [.earth, .earth2])
        case .sky:
            return StageConfig(stage: self, imagePrefix: "space_", imageCount: 20, direction: .ascend,
                               levels: 31...60, music: [.space1, .space2])
        case .sea:
            // No dedicated deep-sea track yet: the calm home track is used until one is produced.
            return StageConfig(stage: self, imagePrefix: "sea_", imageCount: 30, direction: .descend,
                               levels: 61...100, music: [.home])
        }
    }

    /// Resource name of this stage's question file (`questions_<raw value>.json`).
    var questionsResource: String { "questions_\(rawValue)" }
}
