import AVFoundation

/// Short sound effects, loaded once and played on demand. Silent switch is respected (ambient session).
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    enum Sfx: String, CaseIterable {
        case correctVoice = "correct_voice", correctChime = "correct_chime", wrong, timeoutVoice = "timeout_voice"
        case countdown, finishVoice = "finish_voice"
        case dig1 = "dig_1", dig2 = "dig_2", dig3 = "dig_3", dig4 = "dig_4"
        case break1 = "break_1", break2 = "break_2"
        // Deep-sea stage (not used by the earth stage yet).
        case seaRush = "sea_rush", seaAmbient = "sea_ambient", seaDrown = "sea_drown"
        case seaBubbles1 = "sea_bubbles_1", seaBubbles2 = "sea_bubbles_2", seaBubbles3 = "sea_bubbles_3"

        static let digs: [Sfx] = [.dig1, .dig2, .dig3, .dig4]
        static let breaks: [Sfx] = [.break1, .break2]
    }

    /// Sound effects follow the settings switch (kept as `isMuted` so call sites and tests stay simple).
    /// Test override: nil = follow the user's setting; true/false = force sound on/off regardless of
    /// whatever the simulator or device has saved. Unit tests use it so they never play audio.
    static var testOverride: Bool?
    var isMuted: Bool { !(Self.testOverride ?? AppSettings.shared.sfxEnabled) }

    /// Every play/stop request in order, whether or not it was audible (tests assert on this).
    enum Event: Equatable { case play(Sfx), stop(Sfx), stopAll }
    private(set) var events: [Event] = []
    func clearEvents() { events.removeAll() }

    private var data: [Sfx: Data] = [:]
    private var durations: [Sfx: TimeInterval] = [:]
    private var playing: [AVAudioPlayer] = []
    private var configured = false
    private(set) var playCount = 0   // for tests

    func preload() {
        configureSession()
        for s in Sfx.allCases where data[s] == nil {
            if let url = Bundle.main.url(forResource: s.rawValue, withExtension: "mp3"),
               let d = try? Data(contentsOf: url) { data[s] = d }
        }
    }

    @discardableResult
    func play(_ s: Sfx, volume: Float = 1) -> AVAudioPlayer? {
        events.append(.play(s))
        guard !isMuted else { return nil }
        if data[s] == nil { preload() }
        guard let d = data[s], let p = try? AVAudioPlayer(data: d) else { return nil }
        p.volume = volume
        playing.removeAll { !$0.isPlaying }
        playing.append(p)
        p.play()
        playCount += 1
        return p
    }

    func playRandom(_ group: [Sfx], volume: Float = 1) { if let s = group.randomElement() { play(s, volume: volume) } }

    /// Length of a bundled sound in seconds (0 if it cannot be decoded).
    func duration(of s: Sfx) -> TimeInterval {
        if let d = durations[s] { return d }
        if data[s] == nil { preload() }
        let d = data[s].flatMap { try? AVAudioPlayer(data: $0).duration } ?? 0
        durations[s] = d
        return d
    }

    func stop(_ s: Sfx) {
        events.append(.stop(s))
        guard let d = data[s] else { return }
        for p in playing where p.data == d { p.stop() }
    }

    func stopAll() { events.append(.stopAll); playing.forEach { $0.stop() }; playing.removeAll() }

    private func configureSession() {
        guard !configured else { return }
        configured = true
        AudioSessionSetup.configureOnce()
    }
}
