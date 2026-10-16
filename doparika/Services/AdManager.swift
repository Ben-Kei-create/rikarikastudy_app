import Foundation

/// Placeholder. AdMob integration is a later phase; keep callers behind this protocol.
protocol AdManaging {
    func showRewarded(completion: @escaping (Bool) -> Void)
}

struct NoopAdManager: AdManaging {
    func showRewarded(completion: @escaping (Bool) -> Void) { completion(false) }
}
