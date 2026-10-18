import AVFoundation

/// Configures the shared audio session exactly once, off the main thread.
/// `setCategory`/`setActive` can block, so they must never run on the UI thread or on every sound.
enum AudioSessionSetup {
    private static let queue = DispatchQueue(label: "doparika.audio-session", qos: .userInitiated)
    nonisolated(unsafe) private static var started = false

    /// Safe to call as often as you like; only the first call does any work.
    static func configureOnce() {
        queue.async {
            guard !started else { return }
            started = true
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true)
        }
    }
}
