import SwiftUI

struct ResultView: View {
    let model: AppModel
    let engine: QuizEngine
    let onRestart: () -> Void
    let onHome: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var animate: Bool { AppSettings.shared.effectsEnabled && !reduceMotion }

    var body: some View {
        let info = model.levelInfo
        let perfect = engine.correctCount == engine.total
        let rank = ResultRank.rank(correct: engine.correctCount, total: engine.total)
        ScrollView {
        VStack(spacing: 14) {
            if perfect {
                // The trophy artwork already says "全問正解!".
                Image("result_perfect").resizable().scaledToFit().frame(maxHeight: 150)
                    .accessibilityLabel("全問正解")
            } else {
                Text("\(engine.total)問終了!")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 4)
            }
            VStack(spacing: 2) {
                Text("RANK").font(.caption.weight(.heavy)).foregroundStyle(.white.opacity(0.9)).shadow(color: .black, radius: 3)
                Image(rank.imageName).resizable().scaledToFit().frame(height: 120)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                    .scaleEffect(animate && !shown ? 0.3 : 1)
                    .rotationEffect(.degrees(animate && !shown ? -25 : 0))
                    .opacity(animate && !shown ? 0 : 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("ランク \(rank.letter)")
            .accessibilityIdentifier("rank")
            VStack(spacing: 12) {
                Text("SCORE").font(.caption.weight(.bold))
                Text("\(engine.correctCount) / \(engine.total)")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                Divider()
                Text("獲得XP").font(.caption.weight(.bold))
                Text("+\(engine.earnedXP)").font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.ember)
                HStack {
                    Text("最大コンボ").font(.caption.weight(.bold))
                    Spacer()
                    Text("\(engine.maxCombo)").font(.headline.weight(.black))
                }
                HStack {
                    Text("現在のレベル").font(.caption.weight(.bold))
                    Spacer()
                    Text("Lv.\(info.level)").font(.headline.weight(.black))
                }
                ProgressView(value: info.fraction).tint(Theme.ember)
                Text(info.isMax ? "最高レベルです!" : "あと \(info.remaining) XP で Lv.\(info.level + 1)")
                    .font(.footnote)
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .parchmentPanel(opacity: 0.92)
            HStack(spacing: 12) {
                Button("もう一度挑戦") { model.presentAdIfDue(then: onRestart) }.buttonStyle(PrimaryButtonStyle())
                Button("ホームに戻る") { model.presentAdIfDue(then: onHome) }.buttonStyle(PrimaryButtonStyle(tint: Theme.parchment))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            guard animate else { shown = true; return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.55).delay(0.25)) { shown = true }
        }
    }
}
