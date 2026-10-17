import SwiftUI

/// Drifting dust/embers and speed streaks laid over the strata background.
/// Positions are derived from the world's `position`, so the particles ride along with every surge and fall.
struct AmbientEffects: View {
    let motion: WorldMotionController
    private static let count = 46

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let pos = motion.position
                let v = motion.velocity                          // + = world moving down on screen (rising)
                let streak = min(abs(v) * 0.035, 90)
                let span = size.height + 120
                for i in 0..<Self.count {
                    let r1 = Self.unit(i, 1), r2 = Self.unit(i, 2), r3 = Self.unit(i, 3)
                    let depth = 0.35 + r3 * 1.1                  // parallax: near particles move more
                    let x = r1 * size.width + sin(t * 0.6 + r2 * 6.28) * 12
                    var y = (r2 * span - t * (5 + 16 * r2) * depth + pos * depth).truncatingRemainder(dividingBy: span)
                    if y < 0 { y += span }
                    y -= 60
                    let radius = 1.1 + r3 * 2.6
                    let color = Color(red: 1, green: 0.78 - 0.3 * r2, blue: 0.42 - 0.2 * r1)
                        .opacity(0.25 + 0.5 * r1)
                    if streak > 6 {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: y - (v > 0 ? streak * depth : -streak * depth)))
                        p.addLine(to: CGPoint(x: x, y: y))
                        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: radius * 0.9, lineCap: .round))
                    } else {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                                 with: .color(color))
                    }
                }
                // Long thin speed lines during a surge.
                if streak > 25 {
                    let alpha = min((streak - 25) / 60, 0.5)
                    for i in 0..<14 {
                        let x = Self.unit(i, 7) * size.width
                        let y0 = Self.unit(i, 8) * size.height
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: y0))
                        p.addLine(to: CGPoint(x: x, y: y0 + (v > 0 ? 1 : -1) * (80 + streak * 3)))
                        ctx.stroke(p, with: .color(.white.opacity(alpha * (0.4 + 0.6 * Self.unit(i, 9)))),
                                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func unit(_ i: Int, _ salt: Int) -> Double {
        var h = UInt64(i &* 73856093 ^ salt &* 19349663) &* 2654435761
        h ^= h >> 15; h = h &* 2246822519; h ^= h >> 13
        return Double(h % 10_000) / 10_000
    }
}

/// Red edge glow that grows and pulses as the timer runs low.
struct LowTimeVignette: View {
    let engine: QuizEngine
    var body: some View {
        let low = engine.phase == .answering && engine.remaining < 5
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let danger = low ? (5 - engine.remaining) / 5 : 0
            let pulse = 0.7 + 0.3 * sin(t * 8)
            RadialGradient(colors: [.clear, Theme.bad.opacity(0.6 * danger * pulse)],
                           center: .center, startRadius: 160, endRadius: 520)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }
}

/// Stars flying outward plus a golden flash, for a correct answer.
struct SparkleBurst: View {
    @State private var progress = 0.0
    private static let rays = 16

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.ember.opacity(0.75), .clear], center: .center,
                                     startRadius: 0, endRadius: 260))
                .frame(width: 520, height: 520)
                .scaleEffect(0.4 + progress)
                .opacity(1 - progress)
            ForEach(0..<Self.rays, id: \.self) { i in
                let angle = Double(i) / Double(Self.rays) * 2 * .pi + Double(i % 3) * 0.12
                let reach = 90 + 150 * Double(i % 4) / 3 + 110 * progress
                Image(systemName: i % 2 == 0 ? "star.fill" : "sparkle")
                    .font(.system(size: CGFloat(26 - 14 * progress) - CGFloat(i % 3) * 3))
                    .foregroundStyle(i % 2 == 0 ? Theme.ember : Color.white)
                    .shadow(color: Theme.ember, radius: 6)
                    .offset(x: cos(angle) * reach * progress * 1.6, y: sin(angle) * reach * progress * 1.6)
                    .rotationEffect(.degrees(progress * 180))
                    .opacity(1 - progress * progress)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { withAnimation(.easeOut(duration: 0.95)) { progress = 1 } }
    }
}
