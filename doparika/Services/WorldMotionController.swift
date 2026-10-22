import Foundation
import Observation

/// Vertical motion for the earth stage. `depth` is how far the camera's top edge is below the top of
/// the first image (001), in pt: 0 = standing on the surface, larger = deeper underground.
///
/// - Start of a session: top of image 001.
/// - Correct answer: surge down and land exactly on the top of the next image
///   (all answers correct -> the very bottom of the last image).
/// - Thinking / wrong / time-out: the world drifts (or drops) back toward the surface, shaking.
@MainActor
@Observable
final class WorldMotionController {
    /// Images available in the earth stage (earth_001 ... earth_020).
    static let imageCount = 20
    /// The artwork is 1:3, so each image is 3x the screen width tall: art is never cropped at the joins,
    /// whatever the device width. Depths are stored as pt and rescaled if the width changes.
    static let sectionAspect: Double = 3
    /// Neighbouring images overlap by this fraction of their height; the overlap is cross-faded,
    /// so the join between two artworks is a soft dissolve instead of a hard edge.
    static let overlapFraction: Double = 0.12
    /// Most the world drifts back toward the surface during one question of thinking (pt).
    static let maxThinkingDrift: Double = 320
    /// Drop toward the surface on a wrong answer / time-out (pt).
    static let wrongFall: Double = 380
    static let timeoutFall: Double = 460
    /// On the surface (top of 001) there is nowhere to drift, so the world bobs gently up and down instead.
    static let surfaceBobRange: Double = 170
    static let surfaceBobPeriod: Double = 6

    private(set) var sectionHeight: Double = 1200
    /// Questions in the current session = how many images the run can reach.
    private(set) var questionCount: Int = 10

    var overlap: Double { sectionHeight * Self.overlapFraction }
    var sectionStep: Double { sectionHeight - overlap }

    private(set) var depth: Double = 0
    private(set) var velocity: Double = 0
    /// Vibration of the world (pt) and a phase that advances every frame; drives the rumble effect.
    /// System "Reduce Motion": the world jumps to its resting place instead of surging, drifting or shaking.
    @ObservationIgnored var reduceMotion = false
    private(set) var shake: Double = 0
    private(set) var shakePhase: Double = 0

    @ObservationIgnored private var viewport: Double = 800
    @ObservationIgnored private var thinking = false
    @ObservationIgnored private var thinkElapsed: Double = 0
    @ObservationIgnored private var thinkDuration: Double = 15
    @ObservationIgnored private var thinkDrift: Double = 0
    @ObservationIgnored private var bobbing = false
    @ObservationIgnored private var move: Move?

    private struct Move {
        var elapsed = 0.0
        let windUp: Double      // anticipation dip before the surge
        let rampTime: Double    // acceleration
        var peak: Double        // peak speed (pt/s)
        let damping: Double     // exponential decay rate
        let sign: Double
        var target: Double
    }

    // MARK: Geometry

    /// Camera depth at which the top of image `index` (0-based) is at the top of the screen.
    func sectionTop(_ index: Int) -> Double { Double(index) * sectionStep }

    /// Camera depth at which the bottom of the last reachable image meets the bottom of the screen.
    var goalDepth: Double {
        max(Double(questionCount - 1) * sectionStep + sectionHeight - viewport, 0)
    }
    var maxDepth: Double { goalDepth }

    /// Resting depth after `correct` right answers in this session.
    func restingDepth(afterCorrect correct: Int) -> Double {
        correct >= questionCount ? goalDepth : min(sectionTop(correct), goalDepth)
    }

    func configure(questionCount n: Int) {
        questionCount = min(max(n, 1), Self.imageCount)
        depth = clamp(depth)
    }

    func setViewport(_ h: Double, width: Double) {
        let newSection = max(width, 1) * Self.sectionAspect
        if abs(newSection - sectionHeight) > 0.5 {           // width changed: keep the same place in the world
            let k = newSection / sectionHeight
            depth *= k
            thinkDrift *= k
            if var m = move { m.target *= k; m.peak *= k; move = m }
            sectionHeight = newSection
        }
        viewport = max(h, 1)
        depth = clamp(depth)
        if var m = move { m.target = clamp(m.target); move = m }
    }

    // MARK: Commands

    func jump(to d: Double) { depth = clamp(d); velocity = 0; move = nil }

    func startThinking(duration: Double) {
        if reduceMotion { thinking = false; bobbing = false; return }     // the world stays still while thinking
        thinking = true; thinkElapsed = 0; thinkDuration = duration; thinkDrift = 0
        // At (or heading back to) the very top, bob slowly instead of drifting.
        bobbing = depth < 1 || (move.map { $0.target < 1 } ?? false)
    }
    func stopThinking() { thinking = false }

    /// Correct answer: a short wind-up, then a hard surge DOWN that lands exactly on `target`.
    func boost(to target: Double) {
        thinking = false
        if reduceMotion { jump(to: target); shake = 0; return }
        move = makeMove(to: clamp(target), windUp: 0.15, ramp: 0.2, damping: 5)
    }

    /// Wrong / timeout: drop back toward the surface.
    func fall(distance: Double) {
        thinking = false
        let target = clamp(depth - distance)
        if reduceMotion { jump(to: target); shake = 0; return }
        guard depth - target > 1 else { move = nil; return }
        move = makeMove(to: target, windUp: 0.05, ramp: 0.3, damping: 2.4)
    }

    /// Gentle travel to a resting depth (e.g. rising back to the surface for a retry).
    func settle(to d: Double) {
        let target = clamp(d)
        if reduceMotion { jump(to: target); return }
        guard abs(target - depth) > 1 else { depth = target; move = nil; return }
        move = makeMove(to: target, windUp: 0, ramp: 0.5, damping: 2.2)
    }

    private func makeMove(to target: Double, windUp: Double, ramp: Double, damping: Double) -> Move {
        let distance = target - depth
        let travelFactor = ramp / 2 + 1 / damping   // distance = peak * travelFactor
        return Move(windUp: windUp, rampTime: ramp, peak: abs(distance) / travelFactor, damping: damping,
                    sign: distance >= 0 ? 1 : -1, target: target)
    }

    // MARK: Frame step

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
                        depth = clamp(m.target); velocity = 0; move = nil
                        shake = 0; shakePhase += 1
                        return
                    }
                }
            }
            move = m
        } else if thinking && bobbing {
            thinkElapsed += dt
            // Slow down-and-back-up wave between the very top and `surfaceBobRange`; starts at the top.
            let wave = (1 - cos(2 * .pi * thinkElapsed / Self.surfaceBobPeriod)) / 2
            let target = Self.surfaceBobRange * wave
            v = (target - depth) / max(dt, 0.001)
        } else if thinking {
            thinkElapsed += dt
            let t = min(thinkElapsed / thinkDuration, 1)
            // Very slow at first, accelerating; drifts toward the surface, never past it or the per-question cap.
            let raw = 4 + 70 * t * t
            let room = max(0, min(Self.maxThinkingDrift - thinkDrift, depth))
            let speed = min(raw, room / max(dt, 0.001))
            v = -speed
            thinkDrift += speed * dt
        }
        velocity = v
        depth = clamp(depth + v * dt)
        // Rumble: grows while thinking, kicks hard during a surge, calms as it settles.
        var amp = 0.0
        if move != nil { amp = min(7, abs(v) / 200) }
        else if thinking { let t = min(thinkElapsed / thinkDuration, 1); amp = 0.6 + 3.0 * t * t }
        shake = amp
        shakePhase += 1
    }

    /// Hard bounds are the artwork edges, so no "outside the image" area is ever visible.
    private func clamp(_ p: Double) -> Double { min(max(p, 0), maxDepth) }
}
