import SwiftUI

struct HomeView: View {
    let model: AppModel
    @Binding var path: [Route]
    @State private var motion = WorldMotionController()
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
                        Text("知識で、\n地球の中心をめざせ。")
                            .font(.system(size: 22, weight: .heavy, design: .serif))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                            .opacity(rest)
                        logo
                        Text("問題で、世界をうごかす地球アプリ")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .opacity(rest)
                    }
                    .padding(.top, 24)

                    Group {
                    GlobeView(spins: AppSettings.shared.effectsEnabled)
                        .frame(width: 150, height: 150)
                        .opacity(rest)
                        .accessibilityHidden(true)

                    levelCard

                    VStack(spacing: 12) {
                        Button("スタート") { path.append(.quiz) }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(model.repository.loadError != nil)
                        Button("コレクション") { path.append(.collection) }
                            .buttonStyle(PrimaryButtonStyle(tint: Theme.parchment))
                        if let err = model.repository.loadError {
                            Text(err).font(.footnote).foregroundStyle(Theme.bad)
                        }
                    }

                    stageRoadmap
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
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .padding(.trailing, 16).padding(.top, 8)
            .accessibilityLabel("せってい")
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .overlay { Color.white.opacity(flash).ignoresSafeArea().allowsHitTesting(false) }
        .offset(x: shake)
        .navigationBarHidden(true)
        .onAppear {
            motion.jump(to: 0)
            MusicPlayer.shared.request(.home)
            playIntro()
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
        guard !Self.introPlayed, AppSettings.shared.effectsEnabled else {
            Self.introPlayed = true
            logoScale = 1; logoDrop = 0; logoOpacity = 1; rest = 1; shineX = 1.3
            startPulse()
            return
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
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { pulse = 1.03 }
    }

    private var levelCard: some View {
        let info = model.levelInfo
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Lv.\(info.level)").font(.system(size: 28, weight: .black, design: .rounded))
                Spacer()
                Text(info.isMax ? "MAX" : "あと \(info.remaining) XP で Lv.\(info.level + 1)")
                    .font(.footnote.weight(.semibold))
            }
            ProgressView(value: info.fraction).tint(Theme.ember)
        }
        .foregroundStyle(Theme.ink)
        .parchmentPanel()
        .accessibilityElement(children: .combine)
    }

    private var stageRoadmap: some View {
        VStack(alignment: .leading, spacing: 10) {
            stageRow(icon: "globe.asia.australia.fill", title: "地球・地中", detail: "Lv.1 - 30（配信中）", locked: false)
            stageRow(icon: "cloud.fill", title: "宇宙", detail: "近日公開", locked: true)
            stageRow(icon: "water.waves", title: "深海", detail: "近日公開", locked: true)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
    }

    private func stageRow(icon: String, title: String, detail: String, locked: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: locked ? "lock.fill" : icon)
                .frame(width: 28)
                .foregroundStyle(locked ? .white.opacity(0.6) : Theme.ember)
            Text(title).font(.headline)
            Spacer()
            Text(detail).font(.footnote).foregroundStyle(.white.opacity(0.7))
        }
    }
}
