import SwiftUI

struct HomeView: View {
    let model: AppModel
    @Binding var path: [Route]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = WorldMotionController()
    @State private var updateNotice: AppModel.UpdateNotice?
    // Launch intro: the logo slams in, the screen flashes, a shine sweeps across, then the rest fades up.
    private static var introPlayed = false
    @State private var logoScale = 2.6
    @State private var logoDrop = -260.0
    @State private var logoOpacity = 0.0
    @State private var flash = 0.0
    @State private var shineX = -0.5
    @State private var rest = 0.0
    @State private var pulse = 1.0
    @State private var shake = 0.0
    @State private var showSettings = false
    /// Chosen stage (only meaningful when extra stages are on and unlocked); nil = the current level's stage.
    @State private var selectedStage: Stage?

    var body: some View {
        ZStack {
            if UIImage(named: "home_bg") != nil {
                GeometryReader { geometry in
                    Image("home_bg")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
            } else {
                WorldBackgroundView(motion: motion)
            }
            LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.15), .black.opacity(0.7)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Text(Self.tagline(for: playStage))
                            .font(.mplus(fixed: 22, .heavy))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                            .opacity(rest)
                        logo
                        Text("問題で、世界をうごかす地球アプリ")
                            .font(.mplus(.footnote, .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .opacity(rest)
                    }
                    .padding(.top, 24)

                    Group {
                    GlobeView(spins: motionAllowed)
                        .frame(width: 150, height: 150)
                        .opacity(rest)
                        .accessibilityHidden(true)

                    levelCard

                    VStack(spacing: 12) {
                        Button("スタート") { path.append(.quiz(playStage)) }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(model.repository.loadError != nil)
                        Button("コレクション") { path.append(.collection) }
                            .buttonStyle(PrimaryButtonStyle(tint: Theme.parchment))
                        if let err = model.repository.loadError {
                            Text(err).font(.mplus(.footnote)).foregroundStyle(Theme.bad)
                        }
                    }

                    if FeatureFlags.extraStagesEnabled { stageRoadmap }   // hidden in release 1
                    }
                    .opacity(rest)
                    .offset(y: (1 - rest) * 36)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.mplus(.title3))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .padding(.trailing, 16).padding(.top, 8)
            .accessibilityLabel("せってい")
        }
        .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        .alert("宇宙ステージが登場！", isPresented: Binding(get: { updateNotice != nil }, set: { _ in })) {
            Button("OK") { model.dismissUpdateNotice(); updateNotice = nil }
        } message: {
            Text(Self.noticeText(updateNotice))
        }
        .overlay { Color.white.opacity(flash).ignoresSafeArea().allowsHitTesting(false) }
        .offset(x: shake)
        .navigationBarHidden(true)
        .onAppear {
            if updateNotice == nil { updateNotice = model.pendingUpdateNotice() }
            motion.jump(to: 0)
            MusicPlayer.shared.request(.home)
            playIntro()
        }
    }

    private static func noticeText(_ n: AppModel.UpdateNotice?) -> String {
        switch n {
        case .coming(let levels)?: return "Lv.31 から、宇宙ステージで遊べます。あと \(levels) レベルです。"
        case .atEarthEnd(let xp)?: return "地球ステージを走りきりました！あと \(xp) XP で、宇宙ステージが開きます。"
        case .spaceOpen?: return "Lv.31 に届いているので、宇宙ステージで遊べます。ステージ一覧から選んでください。"
        case .spaceCleared?: return "宇宙ステージも最高レベルに届いています。すごい！"
        case nil: return ""
        }
    }

    /// Decorative motion: off with the in-app switch or the system "Reduce Motion".
    private var motionAllowed: Bool { AppSettings.shared.effectsEnabled && !reduceMotion }

    /// The headline follows the stage that Start will play.
    private static func tagline(for stage: Stage) -> String {
        switch stage {
        case .mountain: return "知識で、\n地球の中心をめざせ。"
        case .sky: return "知識で、\n宇宙の果てをめざせ。"
        case .sea: return "知識で、\n深海の底をめざせ。"
        }
    }

    private var logo: some View {
        Image("logo")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 330)
            .overlay {
                GeometryReader { g in
                    LinearGradient(colors: [.clear, .white.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.35)
                        .offset(x: shineX * g.size.width)
                }
                .mask(Image("logo").resizable().scaledToFit())
            }
            .shadow(color: Theme.ember.opacity(0.55), radius: 18)
            .scaleEffect(logoScale * pulse)
            .offset(y: logoDrop)
            .opacity(logoOpacity)
            .accessibilityLabel("ドパリカ")
    }

    private func playIntro() {
        guard !Self.introPlayed, motionAllowed else {
            Self.introPlayed = true
            logoScale = 1; logoDrop = 0; logoOpacity = 1; rest = 1; shineX = 1.3
            return                      // no intro and no idle pulse when motion is switched off
        }
        Self.introPlayed = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { logoScale = 1; logoDrop = 0; logoOpacity = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {          // impact
            withAnimation(.easeOut(duration: 0.12)) { flash = 0.7 }
            withAnimation(.easeOut(duration: 0.5).delay(0.12)) { flash = 0 }
            withAnimation(.interpolatingSpring(stiffness: 900, damping: 5)) { shake = 7 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { withAnimation(.interpolatingSpring(stiffness: 900, damping: 8)) { shake = 0 } }
        }
        withAnimation(.easeInOut(duration: 0.9).delay(0.8)) { shineX = 1.3 }
        withAnimation(.easeOut(duration: 0.6).delay(0.75)) { rest = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { startPulse() }
    }

    private func startPulse() {
        guard motionAllowed else { return }
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { pulse = 1.03 }
    }

    private var levelCard: some View {
        let info = model.levelInfo
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Lv.\(info.level)").font(.mplus(fixed: 28, .black))
                Spacer()
                Text(info.isMax ? "MAX" : "あと \(info.remaining) XP で Lv.\(info.level + 1)")
                    .font(.mplus(.footnote, .semibold))
            }
            ProgressView(value: info.fraction).tint(Theme.ember)
        }
        .foregroundStyle(Theme.ink)
        .parchmentPanel()
        .accessibilityElement(children: .combine)
    }

    /// The stage the Start button plays: the player's pick if unlocked, else the current level's stage.
    private var playStage: Stage {
        if let s = selectedStage, model.unlockedStages.contains(s) { return s }
        return model.currentStage
    }

    private var stageRoadmap: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(FeatureFlags.availableStages, id: \.self) { stage in
                let unlocked = model.unlockedStages.contains(stage)
                let missing = model.stagesWithoutQuestions.contains(stage)
                Button { if unlocked { selectedStage = stage } } label: {
                    stageRow(icon: Self.icon(stage), title: stage.title,
                             detail: unlocked ? Self.detail(stage, current: model.currentStage)
                                              : (missing ? "準備中" : "Lv.\(stage.config.levels.lowerBound)で解放"),
                             locked: !unlocked, selected: unlocked && playStage == stage)
                }
                .buttonStyle(.plain)
                .disabled(!unlocked)
                .accessibilityIdentifier("stage-\(stage.rawValue)")
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
    }

    private static func icon(_ stage: Stage) -> String {
        switch stage {
        case .mountain: return "globe.asia.australia.fill"
        case .sky: return "sparkles"
        case .sea: return "water.waves"
        }
    }

    private static func detail(_ stage: Stage, current: Stage) -> String {
        let lv = "Lv.\(stage.config.levels.lowerBound) - \(stage.config.levels.upperBound)"
        return stage == current ? lv : "\(lv)（復習 XP×0.5）"
    }

    private func stageRow(icon: String, title: String, detail: String, locked: Bool, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: locked ? "lock.fill" : icon)
                .frame(width: 28)
                .foregroundStyle(locked ? .white.opacity(0.6) : Theme.ember)
            Text(title).font(.mplus(.headline))
            Spacer()
            Text(detail).font(.mplus(.footnote)).foregroundStyle(.white.opacity(0.7))
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ember) }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
