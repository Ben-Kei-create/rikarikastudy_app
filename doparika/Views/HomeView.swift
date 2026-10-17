import SwiftUI

struct HomeView: View {
    let model: AppModel
    @Binding var path: [Route]
    @State private var motion = WorldMotionController()

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
                    VStack(spacing: 6) {
                        Text("知識で、\n地層を突き上げる。")
                            .font(.system(size: 22, weight: .heavy, design: .serif))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                        Text("ドパリカ!")
                            .font(.system(size: 64, weight: .black, design: .rounded))
                            .foregroundStyle(LinearGradient(colors: [Theme.parchment, Theme.ember],
                                                            startPoint: .top, endPoint: .bottom))
                            .shadow(color: .black, radius: 6, y: 4)
                            .rotationEffect(.degrees(-4))
                            .accessibilityLabel("ドパリカ")
                        Text("問題で、世界をうごかす地球アプリ")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.top, 24)

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
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .navigationBarHidden(true)
        .onAppear { motion.jump(to: motion.permanentPosition(fraction: model.levelFraction)) }
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
            stageRow(icon: "mountain.2.fill", title: "山・地層", detail: "Lv.1 - 30（配信中）", locked: false)
            stageRow(icon: "cloud.fill", title: "空", detail: "近日公開", locked: true)
            stageRow(icon: "water.waves", title: "海", detail: "近日公開", locked: true)
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
