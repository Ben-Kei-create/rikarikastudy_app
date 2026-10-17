import Foundation
import Observation

/// Vertical motion for the strata world. `position` is the on-screen ("visual") depth in pt.
/// The player's permanent progress is a separate target (see `permanentPosition`); thinking, wrong
/// answers and boosts only move the visual position around it and always converge back to it.
@MainActor
@Observable
final class WorldMotionController {
    static let sectionCount = 10
    /// The artwork is ~1:3, so each section is 3x the screen width tall: art is never cropped at the
    /// joins, whatever the device width. Positions are stored as pt and rescaled if the width changes.
    static let sectionAspect: Double = 3
    private(set) var sectionHeight: Double = 1200
    var worldHeight: Double { Double(Self.sectionCount) * sectionHeight }
    /// Resting depth at Lv.1 (room above for drift + fall) and at Lv.30 (room below for the final surge).
    /// Start: room for the max thinking drift (40%) plus the longest fall (440pt / 60%). End: the minimum boost.
    static let startMargin: Double = 740
    static let endMargin: Double = 520
    /// Thinking drift never uses more than this share of the headroom, so a fall always has room left.
    static let driftHeadroomShare: Double = 0.4

    private(set) var position: Double = 0
    private(set) var velocity: Double = 0

    @ObservationIgnored private var viewport: Double = 800
    @ObservationIgnored private var thinking = false
    @ObservationIgnored private var thinkElapsed: Double = 0
    @ObservationIgnored private var thinkDuration: Double = 15
    @ObservationIgnored private var thinkDrift: Double = 0
    @ObservationIgnored private var thinkBudget: Double = 0
    @ObservationIgnored private var move: Move?

    private struct Move {
        var elapsed = 0.0
        let windUp: Double      // anticipation dip before the surge
        let rampTime: Double    // acceleration
        var peak: Double        // peak speed (pt/s)
        let damping: Double     // exponential decay rate
        let sign: Double
        var target: Double
        var then: Double?       // follow-up settle target (overshoot -> permanent position)
    }

    var maxPosition: Double { max(worldHeight - viewport, 0) }

    func setViewport(_ h: Double, width: Double) {
        let newSection = max(width, 1) * Self.sectionAspect
        if abs(newSection - sectionHeight) > 0.5 {           // width changed: keep the same place in the world
            let k = newSection / sectionHeight
            position *= k
            if var m = move { m.target *= k; m.peak *= k; m.then = m.then.map { $0 * k }; move = m }
            sectionHeight = newSection
        }
        viewport = max(h, 1)
        position = clamp(position)
        // Targets computed for the old size could now lie outside the artwork.
        if var m = move { m.target = clamp(m.target); m.then = m.then.map(clamp); move = m }
    }

    /// Permanent resting depth for a 0...1 progress fraction (Lv.1 -> 0, Lv.30 -> bottom of the world).
    func permanentPosition(fraction: Double) -> Double {
        let f = min(max(fraction, 0), 1)
        let start = min(Self.startMargin, maxPosition)
        let end = max(start, maxPosition - Self.endMargin)
        return start + (end - start) * f
    }

    func jump(to p: Double) { position = clamp(p); velocity = 0; move = nil }

    /// `rest` is the permanent depth the world is converging to (the drift budget is based on it,
    /// not on the transient position, which may still be mid-settle).
    func startThinking(duration: Double, rest: Double) {
        thinking = true; thinkElapsed = 0; thinkDuration = duration; thinkDrift = 0
        thinkBudget = clamp(rest) * Self.driftHeadroomShare
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
                        position = clamp(m.target); velocity = 0; move = nil
                        if let next = m.then { move = makeMove(to: next, windUp: 0, ramp: 0.3, damping: 3.2) }
                        return
                    }
                }
            }
            move = m
        } else if thinking {
            thinkElapsed += dt
            let t = min(thinkElapsed / thinkDuration, 1)
            // Very slow at first, accelerating; total drift is capped by the headroom above us.
            let raw = 4 + 70 * t * t
            v = -min(raw, max(0, thinkBudget - thinkDrift) / max(dt, 0.001))
            thinkDrift += -v * dt
        }
        velocity = v
        position = clamp(position + v * dt)
    }

    /// Hard bounds are the artwork edges, so no "outside the image" area is ever visible.
    private func clamp(_ p: Double) -> Double { min(max(p, 0), maxPosition) }
}
