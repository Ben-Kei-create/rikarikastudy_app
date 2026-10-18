import SwiftUI

struct SettingsView: View {
    @Bindable var settings = AppSettings.shared
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
            }
            .navigationTitle("せってい")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("とじる") { dismiss() } } }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.light)
    }

    private func row(_ title: String, _ icon: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Label(title, systemImage: icon) }
            .tint(Theme.ember)
    }
}
