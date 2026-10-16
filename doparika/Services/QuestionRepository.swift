import Foundation

final class QuestionRepository {
    private(set) var questions: [Question] = []
    private var byID: [String: Question] = [:]
    private(set) var loadError: String?

    init(bundle: Bundle = .main, resource: String = "questions_mountain") {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else {
            loadError = "問題データが見つかりません"
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([Question].self, from: data)
            let valid = decoded.filter(\.isValid)
            var seen = Set<String>()
            questions = valid.filter { seen.insert($0.id).inserted }.sorted { $0.id < $1.id }
            byID = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
            if questions(for: .mountain).count < QuestionSelector.sessionSize {
                loadError = "問題データが不足しています"
            }
        } catch {
            loadError = "問題データを読み込めませんでした"
        }
    }

    func question(id: String) -> Question? { byID[id] }
    func questions(for stage: Stage) -> [Question] { questions.filter { $0.stage == stage } }
}
