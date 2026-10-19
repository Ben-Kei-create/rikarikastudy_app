import SwiftUI

struct SettingsView: View {
    let model: AppModel
    @Bindable var settings = AppSettings.shared
    @State private var confirmReset = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("BGM", "music.note", $settings.bgmEnabled)
                    row("効果音・ボイス", "speaker.wave.2.fill", $settings.sfxEnabled)
                    row("演出（振動・光・スタンプ）", "sparkles", $settings.effectsEnabled)
                    row("ハプティクス（端末の振動）", "iphone.radiowaves.left.and.right", $settings.hapticsEnabled)
                } footer: {
                    Text("演出をオフにすると、背景のゆれ・粒子・スパークル・○×の表示・起動演出が止まります。")
                }
                Section {
                    Button("進行状況を初期化", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("XP・レベル・回答履歴・コレクションがすべて消えます。")
                }
            }
            .confirmationDialog("本当に初期化しますか？", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("初期化する", role: .destructive) { model.resetProgress(); dismiss() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この操作は取り消せません。")
            }
            .navigationTitle("せってい")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("とじる") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.light)
    }

    private func row(_ title: String, _ icon: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Label(title, systemImage: icon) }
            .tint(Theme.ember)
    }
}
