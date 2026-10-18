import AVFoundation

/// Looping background music with fades. One track at a time; switching cross-fades by fading out the old one.
@MainActor
final class MusicPlayer {
    static let shared = MusicPlayer()

    enum Track: String, CaseIterable {
        case home = "bgm_home"
        case earth = "bgm_earth", earth2 = "bgm_earth2"
        case space1 = "bgm_space1", space2 = "bgm_space2"   // space stage (not wired yet)

        /// The earth stage alternates between its two tracks from run to run.
        static var earthStage: [Track] { [.earth, .earth2] }
    }

    private var player: AVAudioPlayer?
    private(set) var current: Track?
    /// Music sits well under the sound effects.
    var baseVolume: Float = 0.45

    var isMuted: Bool { !AppSettings.shared.bgmEnabled }

    func play(_ track: Track, fadeIn: TimeInterval = 1.2) {
        guard !isMuted else { return }
        if current == track, player?.isPlaying == true { return }
        stop(fadeOut: 0.4)
        guard let url = Bundle.main.url(forResource: track.rawValue, withExtension: "m4a"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        AudioSessionSetup.configureOnce()
        p.numberOfLoops = -1
        p.volume = 0
        p.prepareToPlay()
        p.play()
        p.setVolume(baseVolume, fadeDuration: fadeIn)
        player = p
        current = track
    }

    func stop(fadeOut: TimeInterval = 0.8) {
        guard let p = player else { return }
        player = nil; current = nil
        p.setVolume(0, fadeDuration: fadeOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeOut + 0.05) { p.stop() }
    }

    /// Called when the BGM setting flips: stop now, or resume the track that should be playing.
    func settingsChanged() {
        if isMuted { stop(fadeOut: 0.2) } else if let want = wanted { play(want) }
    }

    /// The track the current screen wants, remembered so turning BGM back on resumes it.
    private(set) var wanted: Track?
    func request(_ track: Track) { wanted = track; play(track) }

    /// Duck under a voice line / effect, then come back.
    func duck(to level: Float = 0.2, for seconds: TimeInterval = 1.4) {
        guard let p = player else { return }
        p.setVolume(baseVolume * level, fadeDuration: 0.15)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self, weak p] in
            guard let self, let p, p === self.player else { return }
            p.setVolume(self.baseVolume, fadeDuration: 0.6)
        }
    }
}
