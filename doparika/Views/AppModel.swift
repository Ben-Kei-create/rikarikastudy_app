import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppModel {
    let repository: QuestionRepository
    let store: PlayerProgressStore
    var ads: AdManaging = NoopAdManager()
    var adScheduler = AdScheduler()
    /// One-time flags (update notice, space-clear celebration). Cleared by a progress reset.
    var flags: UserDefaults = .standard

    private(set) var totalXP: Int
    private(set) var unlockedIDs: Set<String>

    init(context: ModelContext, repository: QuestionRepository? = nil) {
        self.repository = repository ?? QuestionRepository()
        self.store = PlayerProgressStore(context: context)
        #if DEBUG
        // QA aid: `-debugPlays <n>` raises the finished-plays counter to n (e.g. 9: the next finished run is the 10th).
        let plays = UserDefaults.standard.integer(forKey: "debugPlays")
        while store.sessionsCompleted < plays { store.completeSession() }
        // QA aid: `-debugUnlock <n>` answers n random Earth questions so the collection looks played (screenshots).
        let unlock = UserDefaults.standard.integer(forKey: "debugUnlock")
        if unlock > 0, store.records().count < unlock {
            for q in self.repository.questions(for: .mountain).shuffled().prefix(unlock) { store.recordAnswer(questionID: q.id, correct: true) }
        }
        // QA aid: `-debugXP <n>` raises stored XP to n so late-world sections can be inspected.
        let xp = UserDefaults.standard.integer(forKey: "debugXP")
        if xp > store.totalXP {
            store.addXP(xp - store.totalXP)
        }
        #endif
        self.totalXP = store.totalXP
        self.unlockedIDs = Set(store.records().map(\.questionID))
    }

    func reloadFromStore() {
        totalXP = store.totalXP
        unlockedIDs = Set(store.records().map(\.questionID))
    }

    /// Runs `next` after the full-screen ad that is due every 10 finished plays (or at once if none is due).
    /// A due ad that could not be shown (no SDK / not loaded) stays due and is tried again at the next break.
    /// While an ad is on its way the result screen's buttons are off, and further requests are ignored,
    /// so one tap yields one transition.
    private(set) var adInFlight = false

    func presentAdIfDue(then next: @escaping () -> Void) {
        guard !adInFlight else { return }
        let plays = store.sessionsCompleted
        guard adScheduler.isDue(playsCompleted: plays) else { next(); return }
        adInFlight = true
        ads.showInterstitial { [weak self] shown in
            if shown { self?.adScheduler.markShown(playsCompleted: plays) }
            self?.adInFlight = false
            next()
        }
    }

    // MARK: One-time messages

    private static let noticeKey = "spaceUpdateNoticeSeen"
    private static let clearKey = "spaceClearCelebrated"
    static var spaceClearLevel: Int { Stage.sky.config.levels.upperBound }

    enum UpdateNotice: Equatable {
        case coming(levelsToGo: Int)    // below Lv.30
        case atEarthEnd(xpToGo: Int)    // Lv.30 reached, space not yet
        case spaceOpen                  // already inside space
        case spaceCleared               // already at the top of space
    }

    /// The "space has arrived" message for a player who had saved progress before this update; nil for new
    /// players and once it has been dismissed.
    func pendingUpdateNotice() -> UpdateNotice? {
        guard FeatureFlags.availableStages.contains(.sky), repository.isPlayable(.sky),
              !flags.bool(forKey: Self.noticeKey) else { return nil }
        if totalXP == 0 && store.sessionsCompleted == 0 { return nil }
        let level = levelInfo.level
        if level >= Self.spaceClearLevel { return .spaceCleared }
        if level >= Stage.sky.config.levels.lowerBound { return .spaceOpen }
        if level >= Stage.mountain.config.levels.upperBound {
            return .atEarthEnd(xpToGo: LevelCalculator.xpThreshold(for: Stage.sky.config.levels.lowerBound) - totalXP)
        }
        return .coming(levelsToGo: Stage.sky.config.levels.lowerBound - level)
    }

    func dismissUpdateNotice() {
        // A player who is already at the top of space has been told; no surprise celebration later.
        if levelInfo.level >= Self.spaceClearLevel { flags.set(true, forKey: Self.clearKey) }
        flags.set(true, forKey: Self.noticeKey)
    }

    /// True once, when a run takes the player to the top of space (Lv.60).
    func claimSpaceClear(startLevel: Int) -> Bool {
        guard startLevel < Self.spaceClearLevel, levelInfo.level >= Self.spaceClearLevel,
              !flags.bool(forKey: Self.clearKey) else { return false }
        flags.set(true, forKey: Self.clearKey)
        return true
    }

    /// Correct / wrong answers per field, from the saved records.
    func subjectStats() -> [SubjectStat] {
        var counts: [String: (correct: Int, wrong: Int)] = [:]
        for r in store.records() { counts[r.questionID] = (r.correctCount, r.wrongCount) }
        return CollectionService.subjectStats(questions: repository.questions, counts: counts)
    }

    func resetProgress() {
        flags.removeObject(forKey: Self.noticeKey)
        flags.removeObject(forKey: Self.clearKey)
        adScheduler.reset()
        store.resetAll()
        reloadFromStore()
    }

    var levelInfo: LevelCalculator.Info { LevelCalculator.info(forXP: totalXP) }

    /// 0...1 progress through Lv.1...30 (level plus progress inside the level).
    var levelFraction: Double {
        let info = levelInfo
        let lv = info.isMax ? Double(LevelCalculator.maxLevel) : Double(info.level) + info.fraction
        return (lv - 1) / Double(LevelCalculator.maxLevel - 1)
    }

    var worldProgress: Double { min(1, Double(totalXP) / Double(max(LevelCalculator.maxXP, 1))) }

    /// Stages the player's level has reached but whose questions cannot be loaded (shown as "準備中").
    var stagesWithoutQuestions: [Stage] {
        FeatureFlags.availableStages.filter { levelInfo.level >= $0.config.levels.lowerBound && !repository.isPlayable($0) }
    }

    var canStartSession: Bool { repository.loadError == nil }

    /// The stage the player's current level belongs to.
    /// The stage the player's level belongs to; if that stage's question bank is unusable the player is
    /// kept on the latest stage that works, so a bad data file in one stage never blocks the game.
    var currentStage: Stage {
        let level = levelInfo.level
        return FeatureFlags.availableStages.last { $0.config.levels.lowerBound <= level && repository.isPlayable($0) } ?? .mountain
    }

    /// Stages that are visible AND reached by level. A stage opens when the player reaches its first level.
    var unlockedStages: [Stage] {
        FeatureFlags.availableStages.filter { levelInfo.level >= $0.config.levels.lowerBound && repository.isPlayable($0) }
    }

    /// Replaying an earlier stage pays half XP; the current stage pays in full.
    func xpPerCorrect(for stage: Stage) -> Int {
        stage == currentStage ? QuizEngine.xpPerCorrect : QuizEngine.xpPerCorrect / 2
    }

    /// Earth: Lv.1-20 = 10 questions (images 001-010), Lv.21+ = 20. Space: 20. Deep sea: 20, and 30 from Lv.81.
    func sessionLength(for stage: Stage) -> Int {
        switch stage {
        case .mountain: return levelInfo.level > 20 ? 20 : 10
        case .sky: return 20
        case .sea: return levelInfo.level > 80 ? 30 : 20
        }
    }
    var sessionLength: Int { sessionLength(for: currentStage) }

    /// The stage to play: the requested one only if the player has reached it and its data is playable,
    /// otherwise the current stage.
    func resolvedStage(_ requested: Stage?) -> Stage {
        guard let requested, unlockedStages.contains(requested) else { return currentStage }
        return requested
    }

    func makeSession(stage: Stage? = nil) -> [Question] {
        let stage = resolvedStage(stage)
        let length = sessionLength(for: stage)
        let history = store.records().map {
            QuestionSelector.History(questionID: $0.questionID, wrongCount: $0.wrongCount,
                                     lastCorrect: $0.lastCorrect, lastWrongAt: $0.lastWrongAt,
                                     lastWrongLevel: $0.lastWrongLevel, lastAnsweredAt: $0.lastAnsweredAt)
        }
        // A stage with a small bank borrows unanswered questions from the stages before it.
        let earlier = FeatureFlags.availableStages.filter { $0.config.levels.lowerBound < stage.config.levels.lowerBound }
        let fallback = earlier.flatMap { repository.questions(for: $0) }
        var picked = QuestionSelector.select(all: repository.questions(for: stage), history: history,
                                             currentLevel: levelInfo.level, size: length, fallback: fallback)
        #if DEBUG
        // QA aid: `-debugCorrectIsA YES` always makes choice A the right one, so UI tests can answer correctly.
        if UserDefaults.standard.bool(forKey: "debugCorrectIsA") {
            picked = picked.map { q in
                guard q.correctChoiceId != "A", q.choices.count == 2 else { return q }
                let swapped = [Choice(id: "A", text: q.choices[1].text), Choice(id: "B", text: q.choices[0].text)]
                return Question(id: q.id, stage: q.stage, grade: q.grade, subject: q.subject, difficulty: q.difficulty,
                                question: q.question, choices: swapped, correctChoiceId: "A", explanation: q.explanation,
                                figure: q.figure)
            }
        }
        // QA aid: `-debugLongestFirst YES` puts the longest question and the longest explanation first.
        if UserDefaults.standard.bool(forKey: "debugLongestFirst") {
            let all = repository.questions(for: stage)
            let longQ = all.max { $0.question.count + $0.choices.map(\.text.count).max()! < $1.question.count + $1.choices.map(\.text.count).max()! }
            let longE = all.max { $0.explanation.count < $1.explanation.count }
            let front = [longQ, longE].compactMap { $0 }
            picked = front + picked.filter { p in !front.contains { $0.id == p.id } }
            picked = Array(picked.prefix(length))
        }
        // QA aid: `-debugFigureFirst YES` puts the questions that carry a table / graph / diagram first.
        if UserDefaults.standard.bool(forKey: "debugFigureFirst") {
            let figs = repository.questions(for: stage).filter { $0.figure != nil }.shuffled().prefix(length)
            picked = Array(figs) + picked.filter { p in !figs.contains { $0.id == p.id } }
            picked = Array(picked.prefix(length))
        }
        #endif
        return picked
    }

    func record(question: Question, correct: Bool, xp: Int = QuizEngine.xpPerCorrect) {
        store.recordAnswer(questionID: question.id, correct: correct)
        unlockedIDs.insert(question.id)
        if correct {
            store.addXP(xp)
            totalXP = store.totalXP
        }
    }

    func finishSession() {
        store.completeSession()
        totalXP = store.totalXP
    }
}
