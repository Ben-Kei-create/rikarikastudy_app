import Foundation

/// Full-screen ads sit behind this protocol. The real implementation (AdMob) plugs in here later;
/// until then `NoopAdManager` shows nothing.
protocol AdManaging {
    func showRewarded(completion: @escaping (Bool) -> Void)
    /// Shows a full-screen ad. `completion(true)` once an ad was actually shown and closed,
    /// `completion(false)` if none was shown (not loaded, offline, no SDK).
    func showInterstitial(completion: @escaping (Bool) -> Void)
}

struct NoopAdManager: AdManaging {
    func showRewarded(completion: @escaping (Bool) -> Void) { completion(false) }
    func showInterstitial(completion: @escaping (Bool) -> Void) { completion(false) }
}

/// "Every 10 plays, always one full-screen ad" (a play = one finished 10-30 question run, so roughly
/// 100 questions). Counts finished runs, so it survives relaunches.
struct AdScheduler {
    static let playsPerInterstitial = 10
    private let defaults: UserDefaults
    private static let key = "ads.lastShownAtPlay"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private var lastShown: Int { defaults.integer(forKey: Self.key) }

    /// True once `playsPerInterstitial` runs have been finished since the last ad that was actually shown.
    func isDue(playsCompleted: Int) -> Bool {
        playsCompleted - lastShown >= Self.playsPerInterstitial
    }

    func markShown(playsCompleted: Int) { defaults.set(playsCompleted, forKey: Self.key) }

    func reset() { defaults.removeObject(forKey: Self.key) }
}
