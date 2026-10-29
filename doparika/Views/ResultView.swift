import SwiftUI

struct ResultView: View {
    let model: AppModel
    let engine: QuizEngine
    /// Level before this run; a stage whose first level lies in (startLevel, current level] just opened.
    var startLevel: Int = 1
    let onRestart: () -> Void
    let onHome: () -> Void
    /// Starts a run in another stage (used by the "go to the new stage" button).
    var onStartStage: (Stage) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    /// A stage that opened because of this run (e.g. space at Lv.31).
    private var newlyOpenedStage: Stage? {
        model.unlockedStages.first {
            let first = $0.config.levels.lowerBound
            return first > 1 && first > startLevel && first <= model.levelInfo.level
        }
    }

    private func stageUnlockBanner(_ stage: Stage) -> some View {
        VStack(spacing: 4) {
            Image(stage == .sky ? "stage_space_title" : "stage_deepsea_title")
                .resizable().scaledToFit().frame(height: 70)
            Text("\(stage.title)ステージが解放されました！")
                .font(.mplus(.subheadline, .black)).foregroundStyle(.white).shadow(color: .black, radius: 3)
            Text("ホームのステージ一覧から選べます").font(.mplus(.caption, .bold)).foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black, radius: 3)
        }
        .padding(.vertical, 8)
        .scaleEffect(animate && !shown ? 0.6 : 1).opacity(animate && !shown ? 0 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stage.title)ステージが解放されました。ホームのステージ一覧から選べます。")
        .accessibilityIdentifier("stage-unlocked")
    }

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
                    .font(.mplus(fixed: 34, .black))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 4)
            }
            VStack(spacing: 2) {
                Text("RANK").font(.mplus(.caption, .heavy)).foregroundStyle(.white.opacity(0.9)).shadow(color: .black, radius: 3)
                Image(rank.imageName).resizable().scaledToFit().frame(height: 120)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                    .scaleEffect(animate && !shown ? 0.3 : 1)
                    .rotationEffect(.degrees(animate && !shown ? -25 : 0))
                    .opacity(animate && !shown ? 0 : 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("ランク \(rank.letter)")
            .accessibilityIdentifier("rank")
            if let stage = newlyOpenedStage {
                stageUnlockBanner(stage)
                // Right under the announcement, so it is visible without scrolling: straight into the new
                // stage. Replaying the old one is the quieter choice at the bottom.
                Button("\(stage.title)へ進む") { model.presentAdIfDue { onStartStage(stage) } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.adInFlight)
                    .accessibilityIdentifier("go-new-stage")
            }
            VStack(spacing: 12) {
                Text("SCORE").font(.mplus(.caption, .bold))
                Text("\(engine.correctCount) / \(engine.total)")
                    .font(.mplus(fixed: 52, .black))
                Divider()
                Text("獲得XP").font(.mplus(.caption, .bold))
                Text("+\(engine.earnedXP)").font(.mplus(fixed: 30, .black))
                    .foregroundStyle(Theme.ember)
                HStack {
                    Text("最大コンボ").font(.mplus(.caption, .bold))
                    Spacer()
                    Text("\(engine.maxCombo)").font(.mplus(.headline, .black))
                }
                HStack {
                    Text("現在のレベル").font(.mplus(.caption, .bold))
                    Spacer()
                    Text("Lv.\(info.level)").font(.mplus(.headline, .black))
                }
                ProgressView(value: info.fraction).tint(Theme.ember)
                Text(info.isMax ? "最高レベルです!" : "あと \(info.remaining) XP で Lv.\(info.level + 1)")
                    .font(.mplus(.footnote))
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .parchmentPanel(opacity: 0.92)
            HStack(spacing: 12) {
                Button("もう一度挑戦") { model.presentAdIfDue(then: onRestart) }.buttonStyle(PrimaryButtonStyle())
                    .disabled(model.adInFlight)
                Button("ホームに戻る") { model.presentAdIfDue(then: onHome) }.buttonStyle(PrimaryButtonStyle(tint: Theme.parchment))
                    .disabled(model.adInFlight)
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
