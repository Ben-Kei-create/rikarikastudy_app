import Foundation

/// A table, graph or diagram shown with a question. Everything is drawn natively from data, so there are
/// no image files and the figure always matches the app's fonts, colours and Dynamic Type.
struct Figure: Codable, Hashable {
    enum Kind: String, Codable { case table, chart, diagram }
    enum ChartType: String, Codable { case line, bar }

    let kind: Kind
    /// Short title under the figure. Optional.
    let caption: String?

    // table
    let headers: [String]?
    let rows: [[String]]?

    // chart (line: xs/ys numeric points; bar: categories/values)
    let chartType: ChartType?
    let xLabel: String?
    let yLabel: String?
    let xs: [Double]?
    let ys: [Double]?
    let categories: [String]?
    let values: [Double]?

    // diagram: one of `Figure.diagramNames`
    let name: String?

    /// Built-in diagrams (see FigureView). Every diagram marks its parts with the letters A, B, C...
    static let diagramNames: Set<String> = ["ocean_zones", "trench", "ridge", "food_chain", "water_pressure",
                                         "moon_phases", "earth_orbit"]

    var isValid: Bool {
        switch kind {
        case .table:
            guard let headers, let rows, !headers.isEmpty, !rows.isEmpty, headers.count <= 5 else { return false }
            return rows.allSatisfy { $0.count == headers.count }
        case .chart:
            guard let chartType else { return false }
            switch chartType {
            case .line:
                guard let xs, let ys else { return false }
                return xs.count == ys.count && xs.count >= 2
            case .bar:
                guard let categories, let values else { return false }
                return categories.count == values.count && categories.count >= 2
            }
        case .diagram:
            guard let name else { return false }
            return Self.diagramNames.contains(name)
        }
    }

    /// Read aloud by VoiceOver in place of the drawing.
    var accessibilityDescription: String {
        let title = caption.map { "\($0)。" } ?? ""
        switch kind {
        case .table:
            let head = (headers ?? []).joined(separator: "、")
            let body = (rows ?? []).map { $0.joined(separator: "、") }.joined(separator: "。")
            return "\(title)表。項目は\(head)。\(body)"
        case .chart:
            if chartType == .line, let xs, let ys {
                let pts = zip(xs, ys).map { "\(xLabel ?? "横")\(Self.num($0))で\(yLabel ?? "縦")\(Self.num($1))" }
                return "\(title)グラフ。" + pts.joined(separator: "。")
            }
            let pts = zip(categories ?? [], values ?? []).map { "\($0)は\(Self.num($1))" }
            return "\(title)棒グラフ。" + pts.joined(separator: "。")
        case .diagram:
            return "\(title)図。A、B、Cなどの記号で部分が示されています。"
        }
    }

    private static func num(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}
