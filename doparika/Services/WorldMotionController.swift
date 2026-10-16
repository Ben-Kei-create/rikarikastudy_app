import Foundation
import Observation

/// Physics-based vertical motion for the strata world. `position` is distance climbed (pt).
/// Boost: brief wind-up, then strong acceleration, then smooth deceleration.
@MainActor
@Observable
final class WorldMotionController {
    static let sectionCount = 10
    static let sectionHeight: Double = 1800
    static var worldHeight: Double { Double(sectionCount) * sectionHeight }

    private(set) var position: Double = 0
    private(set) var velocity: Double = 0

    @ObservationIgnored private var viewport: Double = 800
    @ObservationIgnored private var thinking = false
    @ObservationIgnored private var thinkElapsed: Double = 0
    @ObservationIgnored private var thinkDuration: Double = 15
    @ObservationIgnored private var impulse: Impulse?

    private struct Impulse {
        var elapsed = 0.0
        let windUp: Double      // slow start
        let rampTime: Double    // acceleration
        let peak: Double        // peak velocity (pt/s)
        let damping: Double     // exponential decay rate
        let sign: Double
        var released = false
    }

    var maxPosition: Double { Self.worldHeight - viewport }

    func setViewport(_ h: Double) { viewport = max(h, 1); position = clamp(position) }
    /// Start depth for the player's progress; overscroll (see `overscroll`) keeps falls visible at the edges.
    func startPosition(progress: Double) -> Double {
        max(0, maxPosition) * min(max(progress, 0), 1)
    }
    func jump(to p: Double) { position = clamp(p); velocity = 0 }

    func startThinking(duration: Double) {
        thinking = true; thinkElapsed = 0; thinkDuration = duration; impulse = nil
    }
    func stopThinking() { thinking = false }

    /// Correct answer: big upward surge covering ~`distance` pt.
    func boost(distance: Double = 1100) {
        thinking = false
        let damping = 1.6
        impulse = Impulse(windUp: 0.18, rampTime: 0.22, peak: distance * damping * 1.25,
                          damping: damping, sign: 1)
    }

    /// Wrong / timeout: gentler fall back down.
    func fall(distance: Double = 380) {
        thinking = false
        let damping = 2.2
        impulse = Impulse(windUp: 0.05, rampTime: 0.3, peak: distance * damping * 1.2,
                          damping: damping, sign: -1)
    }

    func step(_ dt: Double) {
        let dt = min(dt, 1.0 / 20)
        var v = 0.0
        if thinking {
            thinkElapsed += dt
            let t = min(thinkElapsed / thinkDuration, 1)
            v = -(4 + 70 * t * t)            // very slow at first, accelerating
        }
        if var imp = impulse {
            imp.elapsed += dt
            if imp.elapsed < imp.windUp {
                v += -imp.sign * 15 * (imp.elapsed / imp.windUp)   // tiny anticipation dip
            } else {
                let t = imp.elapsed - imp.windUp
                if t < imp.rampTime {
                    let k = t / imp.rampTime
                    v += imp.sign * imp.peak * k * k * (3 - 2 * k) // smoothstep ramp
                } else {
                    imp.released = true
                    v += imp.sign * imp.peak * exp(-imp.damping * (t - imp.rampTime))
                    if abs(imp.peak * exp(-imp.damping * (t - imp.rampTime))) < 2 { impulse = nil }
                }
            }
            if impulse != nil { impulse = imp }
        }
        velocity = v
        position = clamp(position + v * dt)
    }

    /// Visual headroom beyond both ends of the world so motion never freezes at a boundary.
    static let overscroll: Double = 600

    private func clamp(_ p: Double) -> Double {
        min(max(p, -Self.overscroll), max(maxPosition, 0) + Self.overscroll)
    }
}
