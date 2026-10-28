import Foundation

/// Lv is derived purely from cumulative XP. The cap follows the stages shipped in this build.
enum LevelCalculator {
    /// The last level of the last stage that is shipped (30 Earth only, 60 with space, 100 with the deep sea).
    static var maxLevel: Int { FeatureFlags.availableStages.last?.config.levels.upperBound ?? 30 }

    /// The stage a player of this level is currently in (Lv.1-30 Earth, 31-60 space, 61+ deep sea).
    static func stage(forLevel level: Int) -> Stage {
        Stage.allCases.first { $0.config.levels.contains(level) } ?? .sea
    }

    /// XP needed to go from `level` to `level + 1`. Tuned so Lv.30 takes roughly 600 correct answers
    /// (20 XP each): about two thirds of the ~900 questions.
    static func xpToNext(from level: Int) -> Int { 240 + 12 * (level - 1) }

    /// Cumulative XP at which `level` is reached.
    static func xpThreshold(for level: Int) -> Int {
        guard level > 1 else { return 0 }
        return (1..<level).reduce(0) { $0 + xpToNext(from: $1) }
    }

    static var maxXP: Int { xpThreshold(for: maxLevel) }

    static func level(forXP xp: Int) -> Int {
        var lv = 1
        while lv < maxLevel, xp >= xpThreshold(for: lv + 1) { lv += 1 }
        return lv
    }

    struct Info {
        let level: Int
        let xpIntoLevel: Int
        let xpForLevel: Int   // 0 at max level
        var remaining: Int { max(0, xpForLevel - xpIntoLevel) }
        var fraction: Double { xpForLevel == 0 ? 1 : Double(xpIntoLevel) / Double(xpForLevel) }
        var isMax: Bool { xpForLevel == 0 }
    }

    static func info(forXP xp: Int) -> Info {
        let lv = level(forXP: xp)
        if lv >= maxLevel { return Info(level: lv, xpIntoLevel: 0, xpForLevel: 0) }
        return Info(level: lv, xpIntoLevel: xp - xpThreshold(for: lv), xpForLevel: xpToNext(from: lv))
    }
}
