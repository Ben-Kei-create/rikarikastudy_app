import SwiftUI
import SwiftData

enum Route: Hashable { case quiz, collection }

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
                            case .quiz: QuizView(model: model, path: $path)
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
