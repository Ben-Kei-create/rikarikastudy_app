import SwiftUI
import Charts

/// Stacked bars per field: correct + wrong = every answer given. Sits under the collection list.
struct AnswerStatsView: View {
    let stats: [SubjectStat]

    private var correct: Int { stats.reduce(0) { $0 + $1.correct } }
    private var total: Int { stats.reduce(0) { $0 + $1.total } }
    private var rate: Int { total == 0 ? 0 : Int((Double(correct) / Double(total) * 100).rounded()) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("これまでの回答").font(.mplus(.footnote, .black))
                Spacer()
                Text("\(total)問").font(.mplus(.headline, .black))
                Text("正解率 \(rate)%").font(.mplus(.caption, .bold)).foregroundStyle(Theme.ink.opacity(0.7))
            }
            if total == 0 {
                Text("問題に答えると、ここに棒グラフが育ちます")
                    .font(.mplus(.caption, .bold)).foregroundStyle(Theme.ink.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                Chart {
                    ForEach(stats) { s in
                        BarMark(x: .value("分野", SubjectStat.label(s.subject)), y: .value("回数", s.correct))
                            .foregroundStyle(by: .value("結果", "正解"))
                        BarMark(x: .value("分野", SubjectStat.label(s.subject)), y: .value("回数", s.wrong))
                            .foregroundStyle(by: .value("結果", "不正解"))
                    }
                }
                .chartForegroundStyleScale(["正解": Theme.ember, "不正解": Theme.ink.opacity(0.35)])
                .chartLegend(position: .top, alignment: .trailing)
                .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel().font(.mplus(.caption2, .bold)) } }
                .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.mplus(.caption, .bold)) } }
                .frame(height: 120)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.parchment.shadow(.drop(color: .black.opacity(0.15), radius: 4, y: -2)))
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("これまでの回答 \(total)問、正解率 \(rate)パーセント。" + stats.map {
            "\(SubjectStat.label($0.subject)) 正解\($0.correct) 不正解\($0.wrong)" }.joined(separator: "、"))
        .accessibilityIdentifier("answer-stats")
    }
}
