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

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .task { AudioSessionSetup.configureOnce(); SoundPlayer.shared.preload() }
        }
        .modelContainer(container)
    }
}
