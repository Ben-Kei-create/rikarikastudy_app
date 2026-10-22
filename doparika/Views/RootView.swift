import SwiftUI
import SwiftData

enum Route: Hashable { case quiz(Stage), collection }

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var model: AppModel?
    @State private var path: [Route] = []

    var body: some View {
        Group {
            if let model {
                NavigationStack(path: $path) {
                    HomeView(model: model, path: $path)
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .quiz(let stage): QuizView(model: model, stage: stage, path: $path)
                            case .collection: CollectionView(model: model)
                            }
                        }
                }
            } else {
                Theme.night.ignoresSafeArea()
            }
        }
        .task { if model == nil { model = AppModel(context: context) } }
    }
}
