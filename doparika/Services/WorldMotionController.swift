import Foundation
import Observation

/// Vertical motion for the strata world. `position` is the on-screen ("visual") depth in pt.
/// The player's permanent progress is a separate target (see `permanentPosition`); thinking, wrong
/// answers and boosts only move the visual position around it and always converge back to it.
@MainActor
@Observable
final class WorldMotionController {
    static let sectionCount = 10
    static let sectionHeight: Double = 1200   // ~1:3 art at 402pt width; independent of pixel size
    static var worldHeight: Double { Double(sectionCount) * sectionHeight }
    /// Depth shown at 0 XP; leaves room above so early drift/falls stay inside the artwork.
    static let startMargin: Double = 450

    private(set) var position: Double = 0
    private(set) var velocity: Double = 0

    @ObservationIgnored private var viewport: Double = 800
    @ObservationIgnored private var thinking = false
    @ObservationIgnored private var thinkElapsed: Double = 0
    @ObservationIgnored private var thinkDuration: Double = 15
    @ObservationIgnored private var move: Move?

    private struct Move {
        var elapsed = 0.0
        let windUp: Double      // anticipation dip before the surge
        let rampTime: Double    // acceleration
        let peak: Double        // peak speed (pt/s)
        let damping: Double     // exponential decay rate
        let sign: Double
        let target: Double
        var then: Double?       // follow-up settle target (overshoot -> permanent position)
    }

    var maxPosition: Double { max(Self.worldHeight - viewport, 0) }

    func setViewport(_ h: Double) { viewport = max(h, 1); position = clamp(position) }

    /// Permanent resting depth for a 0...1 progress fraction (Lv.1 -> 0, Lv.30 -> bottom of the world).
    func permanentPosition(fraction: Double) -> Double {
        let f = min(max(fraction, 0), 1)
        let start = min(Self.startMargin, maxPosition)
        return start + (maxPosition - start) * f
    }

    func jump(to p: Double) { position = clamp(p); velocity = 0; move = nil }

    func startThinking(duration: Double) {
        thinking = true; thinkElapsed = 0; thinkDuration = duration
    }
    func stopThinking() { thinking = false }

    /// Correct answer: wind-up, hard surge past the new resting point, then a gentle settle onto it.
    /// The surge always travels at least `minTravel` so a small XP gain still feels like a big jump.
    func boost(to permanent: Double, minTravel: Double = 520) {
        thinking = false
        let rest = clamp(permanent)
        let travel = rest - position
        let overshoot = max(140, minTravel - travel)
        let peakTarget = clamp(rest + overshoot)
        move = makeMove(to: peakTarget, windUp: 0.18, ramp: 0.22, damping: 2.4,
                        then: abs(peakTarget - rest) > 4 ? rest : nil)
    }

    /// Wrong / timeout: visual drop only; permanent progress is untouched.
    func fall(distance: Double) {
        thinking = false
        move = makeMove(to: clamp(position - distance), windUp: 0.05, ramp: 0.3, damping: 2.2)
    }

    /// Gentle convergence to the permanent position (between questions, end of session).
    func settle(to permanent: Double) {
        let rest = clamp(permanent)
        guard abs(rest - position) > 1 else { position = rest; move = nil; return }
        move = makeMove(to: rest, windUp: 0, ramp: 0.35, damping: 3.5)
    }

    private func makeMove(to target: Double, windUp: Double, ramp: Double, damping: Double,
                          then: Double? = nil) -> Move {
        let distance = target - position
        let travelFactor = ramp / 2 + 1 / damping   // distance = peak * travelFactor
        return Move(windUp: windUp, rampTime: ramp, peak: abs(distance) / travelFactor, damping: damping,
                    sign: distance >= 0 ? 1 : -1, target: target, then: then)
    }

    func step(_ dt: Double) {
        let dt = min(dt, 1.0 / 20)
        var v = 0.0
        if var m = move {
            m.elapsed += dt
            if m.elapsed < m.windUp {
                v = -m.sign * 15 * (m.elapsed / m.windUp)            // tiny anticipation dip
            } else {
                let t = m.elapsed - m.windUp
                if t < m.rampTime {
                    let k = t / m.rampTime
                    v = m.sign * m.peak * k * k * (3 - 2 * k)         // smoothstep ramp: not instant top speed
                } else {
                    let tail = m.peak * exp(-m.damping * (t - m.rampTime))
                    v = m.sign * tail
                    if tail < 8 {                                     // landed: snap the last few pt
                        position = m.target; velocity = 0; move = nil
                        if let next = m.then { move = makeMove(to: next, windUp: 0, ramp: 0.3, damping: 3.2) }
                        return
                    }
                }
            }
            move = m
        } else if thinking {
            thinkElapsed += dt
            let t = min(thinkElapsed / thinkDuration, 1)
            v = -(4 + 70 * t * t)            // very slow at first, accelerating
        }
        velocity = v
        position = clamp(position + v * dt)
    }

    /// Hard bounds are the artwork edges, so no "outside the image" area is ever visible.
    private func clamp(_ p: Double) -> Double { min(max(p, 0), maxPosition) }
}
