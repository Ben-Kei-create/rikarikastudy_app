import Foundation

final class QuestionRepository {
    private(set) var questions: [Question] = []
    private var byID: [String: Question] = [:]
    private(set) var loadError: String?

    /// Loads every stage's question file. Only the Earth file is mandatory; a missing or broken
    /// 宇宙 / 深海 file just leaves that stage empty (those stages are hidden in release 1).
    init(bundle: Bundle = .main, resource: String = "questions_mountain") {
        var all: [Question] = []
        for stage in Stage.allCases {
            let name = stage == .mountain ? resource : stage.questionsResource
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                if stage == .mountain { loadError = "問題データが見つかりません" }
                continue
            }
            do {
                let decoded = try JSONDecoder().decode([Question].self, from: Data(contentsOf: url))
                all += decoded.filter { $0.isValid && $0.stage == stage }
            } catch {
                if stage == .mountain { loadError = "問題データを読み込めませんでした" }
            }
        }
        var seen = Set<String>()
        questions = all.filter { seen.insert($0.id).inserted }.sorted { $0.id < $1.id }
        byID = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
        if loadError == nil, questions(for: .mountain).count < QuestionSelector.sessionSize {
            loadError = "問題データが不足しています"
        }
    }

    func question(id: String) -> Question? { byID[id] }
    func questions(for stage: Stage) -> [Question] { questions.filter { $0.stage == stage } }
}
