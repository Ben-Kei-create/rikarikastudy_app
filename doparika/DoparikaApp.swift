import SwiftUI
import SwiftData

@main
struct DoparikaApp: App {
    let container: ModelContainer = {
        do {
            return try ModelContainer(for: PlayerProgress.self, QuestionRecord.self)
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }
    }()

    init() { AppFontAppearance.install() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.font, .mplus(.body))     // default for every Text without its own font
                .background(TouchEffectInstaller())
                .preferredColorScheme(.dark)
                .task { AudioSessionSetup.configureOnce(); SoundPlayer.shared.preload() }
        }
        .modelContainer(container)
    }
}
