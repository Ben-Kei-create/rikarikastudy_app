import SwiftUI

/// Draws only visible sections, preferring catalog artwork with a procedural fallback.
/// Artwork is aspect-filled into fixed world frames, independent of its pixel dimensions.
struct WorldBackgroundView: View {
    let motion: WorldMotionController
    @Environment(\.displayScale) private var displayScale

    private static let palette: [(Color, Color)] = [
        (Color(red: 0.30, green: 0.20, blue: 0.12), Color(red: 0.40, green: 0.28, blue: 0.16)), // 表土・根
        (Color(red: 0.52, green: 0.42, blue: 0.30), Color(red: 0.62, green: 0.50, blue: 0.36)), // 砂礫
        (Color(red: 0.62, green: 0.46, blue: 0.28), Color(red: 0.72, green: 0.54, blue: 0.32)), // 堆積層
        (Color(red: 0.74, green: 0.58, blue: 0.38), Color(red: 0.82, green: 0.66, blue: 0.44)), // 砂岩
        (Color(red: 0.42, green: 0.38, blue: 0.36), Color(red: 0.52, green: 0.46, blue: 0.42)), // 泥岩
        (Color(red: 0.55, green: 0.40, blue: 0.30), Color(red: 0.68, green: 0.50, blue: 0.36)), // 化石層
        (Color(red: 0.62, green: 0.28, blue: 0.20), Color(red: 0.78, green: 0.40, blue: 0.24)), // 褶曲
        (Color(red: 0.50, green: 0.22, blue: 0.18), Color(red: 0.64, green: 0.30, blue: 0.20)), // 断層
        (Color(red: 0.55, green: 0.15, blue: 0.10), Color(red: 0.90, green: 0.35, blue: 0.10)), // 火成岩
        (Color(red: 0.22, green: 0.12, blue: 0.12), Color(red: 0.34, green: 0.18, blue: 0.16)), // 巨大岩盤
    ]

    /// Fraction of each artwork's top (sky/horizon) hidden so sections join as one continuous ground.
    private static let topCrop: [Double] = [0, 0.10, 0.12, 0.12, 0, 0, 0.09, 0.12, 0, 0]

    var body: some View {
        GeometryReader { geo in
            Canvas(rendersAsynchronously: false) { ctx, size in
                let pos = motion.position
                let h = WorldMotionController.sectionHeight
                let first = max(0, Int(floor(pos / h)))
                let last = min(WorldMotionController.sectionCount - 1, Int(floor((pos + size.height) / h)))
                guard first <= last else { return }
                for s in first...last {
                    let frame = WorldSectionLayout.frame(index: s, position: pos,
                                                         width: size.width, displayScale: displayScale)
                    drawSection(ctx, index: s, frame: frame, size: size)
                }
            }
            .onAppear { motion.setViewport(geo.size.height) }
            .onChange(of: geo.size.height) { _, new in motion.setViewport(new) }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func drawSection(_ context: GraphicsContext, index s: Int, frame: CGRect, size: CGSize) {
        var ctx = context
        ctx.clip(to: Path(frame))
        let top = frame.minY
        let h = WorldMotionController.sectionHeight
        let (a, b) = Self.palette[s]
        let artName = String(format: "section_%02d", s + 1)
        if let artwork = UIImage(named: artName) {
            let image = ctx.resolve(Image(uiImage: artwork))
            ctx.draw(image, in: WorldSectionLayout.aspectFillRect(imageSize: image.size, in: frame,
                                                                   topCrop: Self.topCrop[s]))
            return
        }
        let rect = frame
        ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [a, b, a]),
                                                   startPoint: CGPoint(x: 0, y: top),
                                                   endPoint: CGPoint(x: 0, y: top + h)))
        // Wavy strata bands.
        let bandH = 90.0
        var y = (floor(max(-top, 0) / bandH)) * bandH
        while y < h && top + y < size.height {
            let k = Int(y / bandH)
            let wave = 10 + Double((k * 7 + s * 3) % 18)
            let phase = Double((k * 13 + s * 5) % 31)
            let tint: Color = k % 2 == 0 ? .black.opacity(0.12) : .white.opacity(0.07)
            var p = Path()
            p.move(to: CGPoint(x: 0, y: top + y))
            var x = 0.0
            while x <= size.width + 20 {
                let fold = s == 6 ? 40.0 : 1.0   // 褶曲: exaggerated folding
                p.addLine(to: CGPoint(x: x, y: top + y + sin((x + phase * 20) / 55) * wave * fold / (s == 6 ? 2 : 1)))
                x += 20
            }
            p.addLine(to: CGPoint(x: size.width, y: top + y + bandH))
            p.addLine(to: CGPoint(x: 0, y: top + y + bandH))
            p.closeSubpath()
            ctx.fill(p, with: .color(tint))
            y += bandH
        }
        // Speckles (grains / fossils) from a hashed grid so they stay put while scrolling.
        let cell = 70.0
        var gy = floor(max(-top, 0) / cell) * cell
        while gy < h && top + gy < size.height {
            for gx in stride(from: 0.0, to: size.width, by: cell) {
                let r = Self.hash(s, Int(gx), Int(gy))
                if r % 5 == 0 {
                    let w = 4.0 + Double(r % 11)
                    let ox = Double((r >> 4) % 50), oy = Double((r >> 8) % 50)
                    let rect = CGRect(x: gx + ox, y: top + gy + oy, width: w, height: w * 0.7)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.black.opacity(0.18)))
                }
                if s == 5 && r % 23 == 0 { // 化石層: ammonite swirl
                    var sp = Path()
                    let c = CGPoint(x: gx + 35, y: top + gy + 35)
                    for i in 0...40 {
                        let t = Double(i) / 40 * 5 * .pi
                        let rad = 2 + t * 2.2
                        let pt = CGPoint(x: c.x + cos(t) * rad, y: c.y + sin(t) * rad)
                        i == 0 ? sp.move(to: pt) : sp.addLine(to: pt)
                    }
                    ctx.stroke(sp, with: .color(.white.opacity(0.35)), lineWidth: 2)
                }
            }
            gy += cell
        }
        if s == 7 { // 断層: diagonal fault line
            var f = Path()
            f.move(to: CGPoint(x: size.width * 0.15, y: top + 300))
            f.addLine(to: CGPoint(x: size.width * 0.85, y: top + 1500))
            ctx.stroke(f, with: .color(.black.opacity(0.55)), lineWidth: 5)
        }
        if s == 8 { // 火成岩: magma glow
            let r = CGRect(x: -40, y: top + h * 0.5, width: size.width + 80, height: 180)
            ctx.fill(Path(ellipseIn: r), with: .color(Color.orange.opacity(0.25)))
        }
    }

    private static func hash(_ a: Int, _ b: Int, _ c: Int) -> Int {
        var h = a &* 73856093 ^ b &* 19349663 ^ c &* 83492791
        h = (h ^ (h >> 13)) &* 1274126177
        return abs(h ^ (h >> 16))
    }
}
