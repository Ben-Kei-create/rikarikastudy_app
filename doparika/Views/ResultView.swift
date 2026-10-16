import SwiftUI

struct ResultView: View {
    let model: AppModel
    let engine: QuizEngine
    let onRestart: () -> Void
    let onHome: () -> Void

    var body: some View {
        let info = model.levelInfo
        let perfect = engine.correctCount == engine.total
        VStack(spacing: 18) {
            Text(perfect ? "満点!" : "\(engine.total)問終了!")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(perfect ? Theme.ember : .white)
                .shadow(color: .black, radius: 4)
            VStack(spacing: 12) {
                Text("SCORE").font(.caption.weight(.bold))
                Text("\(engine.correctCount) / \(engine.total)")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                Divider()
                Text("獲得XP").font(.caption.weight(.bold))
                Text("+\(engine.earnedXP)").font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.ember)
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
                Button("もう一度挑戦", action: onRestart).buttonStyle(PrimaryButtonStyle())
                Button("ホームに戻る", action: onHome).buttonStyle(PrimaryButtonStyle(tint: Theme.parchment))
            }
        }
        .padding(20)
    }
}
