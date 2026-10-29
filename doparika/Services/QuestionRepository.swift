import Foundation

final class QuestionRepository {
    private(set) var questions: [Question] = []
    private var byID: [String: Question] = [:]
    /// Set when the Earth bank (the one every player needs) is missing, broken or too small.
    private(set) var loadError: String?
    /// Per-stage problems; a stage listed here cannot be played (the others are not affected).
    private(set) var stageErrors: [Stage: String] = [:]

    /// A stage needs at least this many valid questions before it can be played.
    static func minimumQuestions(for stage: Stage) -> Int {
        stage == .mountain ? QuestionSelector.sessionSize : 20
    }

    /// `loader` returns a stage's raw JSON (nil = file missing). The Earth file is mandatory for the app;
    /// a missing, broken or too-small 宇宙 / 深海 bank only stops that stage.
    init(loader: (Stage) -> Data?) {
        var all: [Question] = []
        var seen = Set<String>()
        for stage in Stage.allCases {
            guard let data = loader(stage) else {
                stageErrors[stage] = "問題データが見つかりません"
                continue
            }
            do {
                let decoded = try JSONDecoder().decode([Question].self, from: data)
                let valid = decoded.filter { $0.isValid && $0.stage == stage }
                // Judge the stage by the questions that will really be playable: unique IDs, none already
                // taken by another stage. A repeated ID is a data error in its own right.
                var unique: [Question] = []
                for q in valid where seen.insert(q.id).inserted { unique.append(q) }
                all += unique
                if unique.count != valid.count {
                    stageErrors[stage] = "問題IDが重複しています"
                } else if unique.count < Self.minimumQuestions(for: stage) {
                    stageErrors[stage] = "問題データが不足しています"
                }
            } catch {
                stageErrors[stage] = "問題データを読み込めませんでした"
            }
        }
        questions = all.sorted { $0.id < $1.id }
        byID = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
        loadError = stageErrors[.mountain]
    }

    convenience init(bundle: Bundle = .main, resource: String = "questions_mountain") {
        self.init(loader: { stage in
            let name = stage == .mountain ? resource : stage.questionsResource
            return bundle.url(forResource: name, withExtension: "json").flatMap { try? Data(contentsOf: $0) }
        })
    }

    /// False when the stage's question bank is missing, unreadable or too small.
    func isPlayable(_ stage: Stage) -> Bool { stageErrors[stage] == nil }

    func question(id: String) -> Question? { byID[id] }
    func questions(for stage: Stage) -> [Question] { questions.filter { $0.stage == stage } }
}
