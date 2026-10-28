import Foundation

/// Release switches: which stages this build ships. Release 1 shipped Earth only; the next release adds
/// space (宇宙, Lv.31-60); the deep sea (深海, Lv.61-100) is implemented but still hidden.
enum FeatureFlags {
    /// To ship the deep sea later, add `.sea` here (nothing else is needed): the level cap, stage list,
    /// stage select and collection tabs all follow this list.
    static let shippedStages: [Stage] = [.mountain, .sky]

    /// Tests force the stage list: true = every stage, false = Earth only; nil = follow `shippedStages`.
    static var testOverride: Bool?

    /// Stages the player can see and play right now, in level order.
    static var availableStages: [Stage] {
        if let forced = testOverride { return forced ? Stage.allCases : [.mountain] }
        #if DEBUG
        // QA aid: `-debugStages YES` turns every stage on in debug builds only.
        if UserDefaults.standard.bool(forKey: "debugStages") { return Stage.allCases }
        #endif
        return Stage.allCases.filter { shippedStages.contains($0) }
    }

    /// True once there is more than Earth to choose from (stage select, collection tabs).
    static var extraStagesEnabled: Bool { availableStages.count > 1 }
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
