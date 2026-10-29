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
            return "\(title)図。" + Self.diagramNarration(name ?? "")
        }
    }

    /// What a sighted reader takes from each diagram, without stating the answer to the question.
    static func diagramNarration(_ name: String) -> String {
        switch name {
        case "ocean_zones":
            return "海の深さを上から下へ3つに分けた図。上から、Aは水深0mから200mまで、Bは200mから1000mまで、Cは1000mより深い層。上のAには太陽の光が当たっている。"
        case "trench":
            return "プレートの境目の断面図。左の海洋プレートが、右の大陸プレートの下へ斜めに沈みこんでいる。Aは、海洋プレートが曲がって沈みはじめる、海底の深い溝の部分。Bは、沈みこんでいくプレートの部分。Cは、右側の大陸にある山で、頂上が海面より上に出ている。"
        case "ridge":
            return "海底の断面図。中央に海底の山脈があり、その下から高温のマグマが上がっている。Aは、中央の海底山脈の頂上。Bは、山脈の下を上がるマグマ。Cは、左側のプレートで、中央から左へ遠ざかる向きの矢印がついている。右側のプレートは、右へ遠ざかる矢印がついている。"
        case "food_chain":
            return "海の食物連鎖の図。左から右へ、A、B、C、Dの順に並び、矢印は左から右へ向かう。右へいくほど生物は大きくなる。矢印は、食べられるほうから、食べるほうへ向いている。"
        case "water_pressure":
            return "水そうの断面図。水面に近い順に、A、B、Cの3か所があり、それぞれ水が側面の壁を押す矢印がついている。矢印の長さは、Aが最も短く、Bは中くらい、Cが最も長い。Cが最も深い位置。"
        case "moon_phases":
            return "月の位置の図。地球の北極側から見た図で、中心に地球がある。太陽の光は右から左へ当たっている。月は地球のまわりの円上の8か所、AからHにある。Aは地球から見て太陽の側にあたる右の位置。そこから反時計回りに、B、C、D、Eと進み、Eは太陽と反対側の左の位置。Cは真上、Gは真下の位置。どの月も、太陽に向いた右の半分が光っている。"
        case "earth_orbit":
            return "地球の公転の図。北極側から見た図で、中央に太陽がある。地球は太陽のまわりの円上の4か所、A、B、C、Dにある。Aは太陽の左、Bは下、Cは右、Dは上。地球は反時計回りに、AからB、C、Dの順に進む。どの位置でも、地軸は同じ向きに、上の右がわへ傾いていて、北極は右上にある。"
        default:
            return "A、B、Cなどの記号で部分が示されています。"
        }
    }

    private static func num(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}
