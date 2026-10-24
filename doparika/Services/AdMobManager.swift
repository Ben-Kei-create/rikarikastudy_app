import UIKit
import GoogleMobileAds
import UserMessagingPlatform

/// AdMob IDs. Debug builds use Google's TEST interstitial so developers never tap or load real ads
/// (invalid traffic can get an AdMob account suspended); only release builds use the real unit.
enum AdConfig {
    static let appID = "ca-app-pub-4859622277330192~2902136055"   // also in Config/Extra-Info.plist
    static var interstitialUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/4411468910"
        #else
        return "ca-app-pub-4859622277330192/9219383961"
        #endif
    }

    /// Off for unit-test hosts and for UI tests that pass `-debugNoAds YES`.
    static var enabled: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return false }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debugNoAds") { return false }
        #endif
        return true
    }
}

/// Full-screen ads through Google Mobile Ads. Consent (Google UMP) is asked first where required;
/// there is no ATT prompt, so ads are not personalised with the advertising ID.
@MainActor
final class AdMobManager: NSObject, AdManaging, FullScreenContentDelegate {
    static let shared = AdMobManager()

    private var interstitial: InterstitialAd?
    private var loading = false
    private var started = false
    private var onClose: ((Bool) -> Void)?

    /// Asks for consent if needed, then starts the SDK and loads the first ad. Call once at launch.
    func start() {
        guard AdConfig.enabled, !started else { return }
        started = true
        ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { [weak self] _ in
            Task { @MainActor in
                // Shows Google's consent form only where the law requires it (e.g. EEA/UK).
                try? await ConsentForm.loadAndPresentIfRequired(from: Self.topViewController())
                self?.startSDKIfAllowed()
            }
        }
        startSDKIfAllowed()      // a previous session's consent may already allow ads
    }

    private var sdkStarted = false
    private func startSDKIfAllowed() {
        guard !sdkStarted, ConsentInformation.shared.canRequestAds else { return }
        sdkStarted = true
        MobileAds.shared.start(completionHandler: nil)
        preload()
    }

    private func preload() {
        guard sdkStarted, interstitial == nil, !loading else { return }
        loading = true
        InterstitialAd.load(with: AdConfig.interstitialUnitID, request: Request()) { [weak self] ad, _ in
            Task { @MainActor in
                guard let self else { return }
                self.loading = false
                ad?.fullScreenContentDelegate = self
                self.interstitial = ad
            }
        }
    }

    func showRewarded(completion: @escaping (Bool) -> Void) { completion(false) }

    func showInterstitial(completion: @escaping (Bool) -> Void) {
        guard AdConfig.enabled, let ad = interstitial, let vc = Self.topViewController() else {
            preload()
            completion(false)
            return
        }
        interstitial = nil
        onClose = completion
        MusicPlayer.shared.stop(fadeOut: 0.2)          // the ad has its own sound
        ad.present(from: vc)
    }

    // MARK: FullScreenContentDelegate

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.finish(shown: true) }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in self.finish(shown: false) }
    }

    private func finish(shown: Bool) {
        MusicPlayer.shared.settingsChanged()           // bring the stage music back
        let done = onClose
        onClose = nil
        done?(shown)
        preload()
    }

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
