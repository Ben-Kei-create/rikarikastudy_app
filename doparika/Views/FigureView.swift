import SwiftUI
import Charts

/// Draws a question's table, graph or diagram. Always light-on-paper so it reads inside the parchment panel.
struct FigureView: View {
    let figure: Figure

    var body: some View {
        VStack(spacing: 6) {
            content
            if let caption = figure.caption {
                Text(caption).font(.mplus(.caption, .bold)).foregroundStyle(Theme.ink.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(figure.accessibilityDescription)
        .accessibilityIdentifier("figure")
    }

    @ViewBuilder private var content: some View {
        switch figure.kind {
        case .table: TableFigure(headers: figure.headers ?? [], rows: figure.rows ?? [])
        case .chart: ChartFigure(figure: figure)
        case .diagram: DiagramFigure(name: figure.name ?? "")
        }
    }
}

// MARK: table

private struct TableFigure: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                    Text(h).font(.mplus(.footnote, .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 7).padding(.horizontal, 4)
                        .background(Theme.ink.opacity(0.85))
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell).font(.mplus(.footnote, .bold)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 7).padding(.horizontal, 4)
                            .background(i % 2 == 0 ? Color.white.opacity(0.75) : Color.white.opacity(0.4))
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.ink.opacity(0.35), lineWidth: 1))
    }
}

// MARK: chart

private struct ChartFigure: View {
    let figure: Figure

    var body: some View {
        Group {
            if figure.chartType == .line { line } else { bars }
        }
        .foregroundStyle(Theme.ink)
        .frame(height: 170)
        .padding(10)
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
    }

    private var line: some View {
        Chart {
            ForEach(Array(zip(figure.xs ?? [], figure.ys ?? []).enumerated()), id: \.offset) { _, p in
                LineMark(x: .value(figure.xLabel ?? "x", p.0), y: .value(figure.yLabel ?? "y", p.1))
                    .foregroundStyle(Theme.ember).lineStyle(StrokeStyle(lineWidth: 3))
                PointMark(x: .value(figure.xLabel ?? "x", p.0), y: .value(figure.yLabel ?? "y", p.1))
                    .foregroundStyle(Theme.ink)
            }
        }
        .chartXAxisLabel(position: .bottom, alignment: .center) {
            Text(figure.xLabel ?? "").font(.mplus(.caption, .bold)).foregroundStyle(Theme.ink)
        }
        .chartYAxisLabel(position: .leading, alignment: .center) {
            Text(figure.yLabel ?? "").font(.mplus(.caption, .bold)).foregroundStyle(Theme.ink)
        }
        .chartXAxis { AxisMarks { _ in AxisGridLine(); AxisTick(); AxisValueLabel().font(.mplus(.caption2, .bold)).foregroundStyle(Theme.ink) } }
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisTick(); AxisValueLabel().font(.mplus(.caption2, .bold)).foregroundStyle(Theme.ink) } }
    }

    /// Horizontal bars: long category names stay readable.
    private var bars: some View {
        Chart {
            ForEach(Array(zip(figure.categories ?? [], figure.values ?? []).enumerated()), id: \.offset) { _, p in
                BarMark(x: .value(figure.yLabel ?? "値", p.1), y: .value("項目", p.0))
                    .foregroundStyle(Theme.ember)
            }
        }
        .chartXAxisLabel(position: .bottom, alignment: .center) {
            Text(figure.yLabel ?? "").font(.mplus(.caption, .bold)).foregroundStyle(Theme.ink)
        }
        .chartXAxis { AxisMarks { _ in AxisGridLine(); AxisTick(); AxisValueLabel().font(.mplus(.caption2, .bold)).foregroundStyle(Theme.ink) } }
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisValueLabel().font(.mplus(.caption2, .bold)).foregroundStyle(Theme.ink) } }
    }
}

// MARK: diagrams (letters A, B, C... mark the parts the question asks about)

private struct DiagramFigure: View {
    let name: String

    var body: some View {
        Canvas { ctx, size in
            switch name {
            case "ocean_zones": Diagrams.oceanZones(&ctx, size)
            case "trench": Diagrams.trench(&ctx, size)
            case "ridge": Diagrams.ridge(&ctx, size)
            case "food_chain": Diagrams.foodChain(&ctx, size)
            case "water_pressure": Diagrams.waterPressure(&ctx, size)
            case "moon_phases": Diagrams.moonPhases(&ctx, size)
            case "earth_orbit": Diagrams.earthOrbit(&ctx, size)
            default: break
            }
        }
        .frame(height: 190)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.ink.opacity(0.35), lineWidth: 1))
    }
}

private enum Diagrams {
    static let ink = Color(red: 0.24, green: 0.15, blue: 0.09)

    static func letter(_ ctx: inout GraphicsContext, _ s: String, at p: CGPoint) {
        let r: CGFloat = 13
        let circle = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        ctx.fill(circle, with: .color(.white))
        ctx.stroke(circle, with: .color(ink), lineWidth: 2)
        ctx.draw(Text(s).font(.system(size: 15, weight: .black, design: .rounded)).foregroundStyle(ink), at: p)
    }

    static func label(_ ctx: inout GraphicsContext, _ s: String, at p: CGPoint, anchor: UnitPoint = .center,
                      color: Color = ink, size: CGFloat = 12) {
        ctx.draw(Text(s).font(.system(size: size, weight: .bold, design: .rounded)).foregroundStyle(color), at: p, anchor: anchor)
    }

    static func arrow(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, color: Color = ink, width: CGFloat = 3) {
        var p = Path(); p.move(to: a); p.addLine(to: b)
        ctx.stroke(p, with: .color(color), lineWidth: width)
        let ang = atan2(b.y - a.y, b.x - a.x), h: CGFloat = 9
        var head = Path()
        head.move(to: b)
        head.addLine(to: CGPoint(x: b.x - h * cos(ang - .pi / 6), y: b.y - h * sin(ang - .pi / 6)))
        head.addLine(to: CGPoint(x: b.x - h * cos(ang + .pi / 6), y: b.y - h * sin(ang + .pi / 6)))
        head.closeSubpath()
        ctx.fill(head, with: .color(color))
    }

    // Depth column: A 0-200 m, B 200-1000 m, C 1000 m and deeper.
    static func oceanZones(_ ctx: inout GraphicsContext, _ s: CGSize) {
        let colX: CGFloat = 70, colW = s.width - 70 - 56
        let bands: [(CGFloat, CGFloat, Color, String)] = [
            (0, 0.28, Color(red: 0.31, green: 0.76, blue: 0.97), "A"),
            (0.28, 0.58, Color(red: 0.08, green: 0.40, blue: 0.75), "B"),
            (0.58, 1, Color(red: 0.05, green: 0.11, blue: 0.24), "C"),
        ]
        for (a, b, c, l) in bands {
            let r = CGRect(x: colX, y: a * s.height, width: colW, height: (b - a) * s.height)
            ctx.fill(Path(r), with: .color(c))
            letter(&ctx, l, at: CGPoint(x: r.midX, y: r.midY))
        }
        // sun and light rays reaching only the top band
        let sun = Path(ellipseIn: CGRect(x: colX + 14, y: 6, width: 18, height: 18))
        ctx.fill(sun, with: .color(Color(red: 1, green: 0.85, blue: 0.2)))
        for i in 0..<3 {
            let x = colX + 40 + CGFloat(i) * 22
            arrow(&ctx, from: CGPoint(x: x, y: 8), to: CGPoint(x: x, y: s.height * 0.22), color: Color.white.opacity(0.7), width: 2)
        }
        for (frac, text) in [(0.0, "0 m"), (0.28, "200 m"), (0.58, "1000 m")] {
            let y = frac * s.height
            var tick = Path(); tick.move(to: CGPoint(x: colX - 8, y: y + 0.5)); tick.addLine(to: CGPoint(x: colX, y: y + 0.5))
            ctx.stroke(tick, with: .color(ink), lineWidth: 2)
            label(&ctx, text, at: CGPoint(x: colX - 12, y: max(y, 9)), anchor: .trailing)
        }
        arrow(&ctx, from: CGPoint(x: s.width - 30, y: 14), to: CGPoint(x: s.width - 30, y: s.height - 14))
        label(&ctx, "深さ", at: CGPoint(x: s.width - 30, y: s.height / 2 - 8), anchor: .center, size: 11)
    }

    // Ocean plate sinks under a continental plate; volcano on the continent.
    static func trench(_ ctx: inout GraphicsContext, _ s: CGSize) {
        let w = s.width, h = s.height, sea = h * 0.28
        ctx.fill(Path(CGRect(x: 0, y: sea, width: w, height: h - sea)), with: .color(Color(red: 0.62, green: 0.84, blue: 0.95)))
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: sea)), with: .color(Color(red: 0.88, green: 0.95, blue: 0.99)))
        // continental plate (right)
        var cont = Path()
        cont.move(to: CGPoint(x: w * 0.58, y: sea - 8))
        cont.addLine(to: CGPoint(x: w, y: sea - 8)); cont.addLine(to: CGPoint(x: w, y: h))
        cont.addLine(to: CGPoint(x: w * 0.30, y: h)); cont.addLine(to: CGPoint(x: w * 0.46, y: h * 0.62))
        cont.addLine(to: CGPoint(x: w * 0.54, y: h * 0.40)); cont.closeSubpath()
        ctx.fill(cont, with: .color(Color(red: 0.72, green: 0.52, blue: 0.34)))
        // ocean plate (left) bending down
        var oc = Path()
        oc.move(to: CGPoint(x: 0, y: h * 0.50)); oc.addLine(to: CGPoint(x: w * 0.40, y: h * 0.50))
        oc.addLine(to: CGPoint(x: w * 0.62, y: h * 0.92)); oc.addLine(to: CGPoint(x: w * 0.50, y: h))
        oc.addLine(to: CGPoint(x: w * 0.30, y: h * 0.70)); oc.addLine(to: CGPoint(x: 0, y: h * 0.70)); oc.closeSubpath()
        ctx.fill(oc, with: .color(Color(red: 0.42, green: 0.48, blue: 0.58)))
        // volcano
        var v = Path()
        v.move(to: CGPoint(x: w * 0.78, y: sea - 8)); v.addLine(to: CGPoint(x: w * 0.86, y: sea - 40))
        v.addLine(to: CGPoint(x: w * 0.94, y: sea - 8)); v.closeSubpath()
        ctx.fill(v, with: .color(Color(red: 0.55, green: 0.36, blue: 0.22)))
        arrow(&ctx, from: CGPoint(x: w * 0.12, y: h * 0.60), to: CGPoint(x: w * 0.30, y: h * 0.60), color: .white)
        letter(&ctx, "A", at: CGPoint(x: w * 0.43, y: h * 0.42))     // the deep groove at the bend
        letter(&ctx, "B", at: CGPoint(x: w * 0.50, y: h * 0.76))     // the sinking plate
        letter(&ctx, "C", at: CGPoint(x: w * 0.72, y: sea - 22))     // the volcano (to its left)
        label(&ctx, "海面", at: CGPoint(x: 8, y: sea + 10), anchor: .leading, size: 11)
    }

    // Two plates move apart under a seafloor ridge; magma rises in the middle.
    static func ridge(_ ctx: inout GraphicsContext, _ s: CGSize) {
        let w = s.width, h = s.height
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(Color(red: 0.62, green: 0.84, blue: 0.95)))
        var floor = Path()
        floor.move(to: CGPoint(x: 0, y: h * 0.58))
        floor.addLine(to: CGPoint(x: w * 0.36, y: h * 0.58)); floor.addLine(to: CGPoint(x: w * 0.46, y: h * 0.40))
        floor.addLine(to: CGPoint(x: w * 0.50, y: h * 0.44)); floor.addLine(to: CGPoint(x: w * 0.54, y: h * 0.40))
        floor.addLine(to: CGPoint(x: w * 0.64, y: h * 0.58)); floor.addLine(to: CGPoint(x: w, y: h * 0.58))
        floor.addLine(to: CGPoint(x: w, y: h)); floor.addLine(to: CGPoint(x: 0, y: h)); floor.closeSubpath()
        ctx.fill(floor, with: .color(Color(red: 0.42, green: 0.48, blue: 0.58)))
        var magma = Path()
        magma.move(to: CGPoint(x: w * 0.47, y: h)); magma.addLine(to: CGPoint(x: w * 0.47, y: h * 0.62))
        magma.addLine(to: CGPoint(x: w * 0.50, y: h * 0.46)); magma.addLine(to: CGPoint(x: w * 0.53, y: h * 0.62))
        magma.addLine(to: CGPoint(x: w * 0.53, y: h)); magma.closeSubpath()
        ctx.fill(magma, with: .color(Color(red: 0.95, green: 0.45, blue: 0.1)))
        arrow(&ctx, from: CGPoint(x: w * 0.42, y: h * 0.78), to: CGPoint(x: w * 0.16, y: h * 0.78), color: .white)
        arrow(&ctx, from: CGPoint(x: w * 0.58, y: h * 0.78), to: CGPoint(x: w * 0.84, y: h * 0.78), color: .white)
        letter(&ctx, "A", at: CGPoint(x: w * 0.50, y: h * 0.28))     // the ridge
        letter(&ctx, "B", at: CGPoint(x: w * 0.50, y: h * 0.84))     // rising magma
        letter(&ctx, "C", at: CGPoint(x: w * 0.12, y: h * 0.68))     // plate moving away
    }

    // A -> B -> C -> D; each arrow points from the one eaten to the one that eats it.
    static func foodChain(_ ctx: inout GraphicsContext, _ s: CGSize) {
        let n = 4, boxW: CGFloat = 56, gap = (s.width - CGFloat(n) * boxW) / CGFloat(n + 1)
        let sizes: [CGFloat] = [20, 30, 42, 60]               // organisms get bigger along the chain
        let letters = ["A", "B", "C", "D"]
        let y = s.height * 0.46
        for i in 0..<n {
            let x = gap + CGFloat(i) * (boxW + gap) + boxW / 2
            let r = sizes[i]
            let body = Path(ellipseIn: CGRect(x: x - r / 2 - 2, y: y - r / 4, width: r + 4, height: r / 2 + 6))
            ctx.fill(body, with: .color(Color(red: 0.25 + 0.15 * CGFloat(i), green: 0.55, blue: 0.75 - 0.1 * CGFloat(i))))
            letter(&ctx, letters[i], at: CGPoint(x: x, y: s.height * 0.20))
            if i < n - 1 {
                arrow(&ctx, from: CGPoint(x: x + boxW / 2 + 4, y: y + 4), to: CGPoint(x: x + boxW + gap - boxW / 2 - 4, y: y + 4))
            }
        }
        label(&ctx, "食べられる ──▶ 食べる", at: CGPoint(x: s.width / 2, y: s.height * 0.86), size: 12)
    }

    // A tank with the same sideways push at three depths; a longer arrow means a bigger pressure.
    static func waterPressure(_ ctx: inout GraphicsContext, _ s: CGSize) {
        let w = s.width, h = s.height, left: CGFloat = 46, right = w - 46, top: CGFloat = 14, bottom = h - 14
        ctx.fill(Path(CGRect(x: left, y: top + 8, width: right - left, height: bottom - top - 8)),
                 with: .color(Color(red: 0.55, green: 0.80, blue: 0.95)))
        var tank = Path()
        tank.move(to: CGPoint(x: left, y: top)); tank.addLine(to: CGPoint(x: left, y: bottom))
        tank.addLine(to: CGPoint(x: right, y: bottom)); tank.addLine(to: CGPoint(x: right, y: top))
        ctx.stroke(tank, with: .color(ink), lineWidth: 4)
        let marks: [(String, CGFloat)] = [("A", 0.25), ("B", 0.55), ("C", 0.85)]
        for (l, f) in marks {
            let y = top + 8 + f * (bottom - top - 8)
            let len = 24 + f * 120                              // arrow length grows with depth
            arrow(&ctx, from: CGPoint(x: left + 8 + len, y: y), to: CGPoint(x: left + 8, y: y), color: Color(red: 0.8, green: 0.25, blue: 0.1), width: 4)
            letter(&ctx, l, at: CGPoint(x: left + 20 + len + 10, y: y))
        }
        label(&ctx, "水面", at: CGPoint(x: right - 6, y: top + 14), anchor: .trailing, size: 11)
    }

    // Moon around Earth seen from above the north pole; sunlight comes from the right.
    // A = new moon, then counter-clockwise: C first quarter, E full moon, G last quarter.
    static func moonPhases(_ ctx: inout GraphicsContext, _ s: CGSize) {
        let c = CGPoint(x: s.width * 0.40, y: s.height * 0.5)
        let orbit = min(s.height * 0.29, s.width * 0.26), moonR: CGFloat = 10
        var ring = Path(); ring.addEllipse(in: CGRect(x: c.x - orbit, y: c.y - orbit, width: 2 * orbit, height: 2 * orbit))
        ctx.stroke(ring, with: .color(ink.opacity(0.45)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        // sunlight
        for dy in [-52.0, 0.0, 52.0] {
            arrow(&ctx, from: CGPoint(x: s.width - 14, y: c.y + dy), to: CGPoint(x: c.x + orbit + 44, y: c.y + dy),
                  color: Color(red: 0.95, green: 0.65, blue: 0.1), width: 3)
        }
        label(&ctx, "太陽の光", at: CGPoint(x: s.width - 14, y: c.y - 70), anchor: .trailing, size: 11)
        // Earth
        let earth = Path(ellipseIn: CGRect(x: c.x - 15, y: c.y - 15, width: 30, height: 30))
        ctx.fill(earth, with: .color(Color(red: 0.25, green: 0.5, blue: 0.85)))
        label(&ctx, "地球", at: c, color: .white, size: 10)
        // moon at eight places, the half facing the sun is lit
        for k in 0..<8 {
            let a = -CGFloat(k) * .pi / 4
            let m = CGPoint(x: c.x + cos(a) * orbit, y: c.y + sin(a) * orbit)
            let disc = Path(ellipseIn: CGRect(x: m.x - moonR, y: m.y - moonR, width: 2 * moonR, height: 2 * moonR))
            ctx.fill(disc, with: .color(Color(red: 1, green: 0.93, blue: 0.55)))
            ctx.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: m.x - moonR - 1, y: m.y - moonR - 1, width: moonR + 1, height: 2 * moonR + 2)))
                layer.fill(disc, with: .color(Color(red: 0.22, green: 0.22, blue: 0.28)))
            }
            ctx.stroke(disc, with: .color(ink), lineWidth: 1.5)
            letter(&ctx, String(UnicodeScalar(65 + k)!), at: CGPoint(x: c.x + cos(a) * (orbit + 24), y: c.y + sin(a) * (orbit + 24)))
        }
    }

    // Earth around the sun seen from above the north pole (counter-clockwise).
    // A = north pole leans toward the sun, C = away; B and D are the equinoxes.
    static func earthOrbit(_ ctx: inout GraphicsContext, _ s: CGSize) {
        let c = CGPoint(x: s.width / 2, y: s.height * 0.5)
        let orbit = min(s.height * 0.27, s.width * 0.26)
        var ring = Path(); ring.addEllipse(in: CGRect(x: c.x - orbit, y: c.y - orbit, width: 2 * orbit, height: 2 * orbit))
        ctx.stroke(ring, with: .color(ink.opacity(0.45)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        let glow = Path(ellipseIn: CGRect(x: c.x - 26, y: c.y - 26, width: 52, height: 52))
        ctx.fill(glow, with: .color(Color(red: 1, green: 0.85, blue: 0.3).opacity(0.35)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 17, y: c.y - 17, width: 34, height: 34)), with: .color(Color(red: 1, green: 0.75, blue: 0.1)))
        label(&ctx, "太陽", at: c, size: 10)
        // orbit direction arrow between A and B
        let phi: CGFloat = 225 * .pi / 180
        let p = CGPoint(x: c.x + orbit * cos(phi), y: c.y - orbit * sin(phi))
        let t = CGPoint(x: -sin(phi), y: -cos(phi))
        arrow(&ctx, from: CGPoint(x: p.x - 9 * t.x, y: p.y - 9 * t.y), to: CGPoint(x: p.x + 9 * t.x, y: p.y + 9 * t.y), width: 3)
        let tilt: CGFloat = 23.4 * .pi / 180
        let places: [(String, CGPoint, CGPoint)] = [
            ("A", CGPoint(x: c.x - orbit, y: c.y), CGPoint(x: -1, y: 0)),
            ("B", CGPoint(x: c.x, y: c.y + orbit), CGPoint(x: -1, y: 0.35)),
            ("C", CGPoint(x: c.x + orbit, y: c.y), CGPoint(x: 1, y: 0)),
            ("D", CGPoint(x: c.x, y: c.y - orbit), CGPoint(x: -1, y: -0.35)),
        ]
        for (l, e, out) in places {
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - 11, y: e.y - 11, width: 22, height: 22)), with: .color(Color(red: 0.25, green: 0.5, blue: 0.85)))
            // the same tilt everywhere: the north pole leans to the upper right
            let axis = CGPoint(x: sin(tilt) * 20, y: -cos(tilt) * 20)
            var line = Path(); line.move(to: CGPoint(x: e.x - axis.x, y: e.y - axis.y)); line.addLine(to: CGPoint(x: e.x + axis.x, y: e.y + axis.y))
            ctx.stroke(line, with: .color(ink), lineWidth: 2.5)
            ctx.fill(Path(ellipseIn: CGRect(x: e.x + axis.x - 3.5, y: e.y + axis.y - 3.5, width: 7, height: 7)), with: .color(Color(red: 0.85, green: 0.15, blue: 0.1)))
            letter(&ctx, l, at: CGPoint(x: e.x + out.x * 25, y: e.y + out.y * 25))
        }
        label(&ctx, "● 北極", at: CGPoint(x: 8, y: s.height - 12), anchor: .leading, color: Color(red: 0.85, green: 0.15, blue: 0.1), size: 11)
    }
}
