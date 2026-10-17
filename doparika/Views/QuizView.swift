import SwiftUI

/// Wires the pure QuizEngine to a frame ticker, the world motion and persistence.
@MainActor
@Observable
final class QuizSession {
    let engine: QuizEngine
    let motion = WorldMotionController()
    private let model: AppModel
    private var ticker: Task<Void, Never>?
    private var finishedRecorded = false
    var paused = false
    /// Section whose top the world rests on; each correct answer advances one section.
    private var anchor: Int

    init(model: AppModel) {
        self.model = model
        self.anchor = min(WorldMotionController.sectionCount - 1, (model.levelInfo.level - 1) / 3)
        self.engine = QuizEngine(questions: model.makeSession())
        precondition(!engine.questions.isEmpty, "session must have questions")
        engine.onResolved = { [weak self] q, r in self?.handle(q, r) }
    }

    func start(viewportHeight: Double) {
        motion.setViewport(viewportHeight)
        motion.jump(to: WorldMotionController.sectionTop(anchor))
        motion.startThinking(duration: QuizEngine.timeLimit)
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let now = clock.now
                if let self, self.paused { last = now; continue }
                let dt = Double((now - last).components.seconds)
                    + Double((now - last).components.attoseconds) / 1e18
                last = now
                guard let self, !self.paused else { continue }
                self.motion.step(dt)
                self.engine.tick(dt)
            }
        }
    }

    func stop() { ticker?.cancel(); ticker = nil }

    func answer(_ id: String) { engine.answer(choiceID: id) }

    func next() {
        engine.next()
        if engine.phase == .finished {
            if !finishedRecorded { finishedRecorded = true; model.finishSession() }
        } else {
            motion.startThinking(duration: QuizEngine.timeLimit)
        }
    }

    private func handle(_ q: Question, _ r: Resolution) {
        if case .correct = r {
            let wasLast = anchor >= WorldMotionController.sectionCount - 1
            anchor = min(anchor + 1, WorldMotionController.sectionCount - 1)
            // Already in the last section: surge to the very bottom of the art instead.
            motion.boost(to: wasLast ? motion.maxPosition : WorldMotionController.sectionTop(anchor))
            model.record(question: q, correct: true)
        } else {
            motion.fall()
            model.record(question: q, correct: false)
        }
    }
}

struct QuizView: View {
    let model: AppModel
    @Binding var path: [Route]
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: QuizSession?
    @State private var restartToken = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let session {
                    QuizContent(session: session, model: model, onRestart: restart, onHome: { path.removeAll() })
                        .id(ObjectIdentifier(session))
                        .onAppear { session.start(viewportHeight: geo.size.height) }
                        .onDisappear { session.stop() }
                } else {
                    Theme.night.ignoresSafeArea()
                }
            }
            .onAppear { if session == nil, model.canStartSession { session = QuizSession(model: model) } }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: scenePhase) { _, phase in session?.paused = phase != .active }
    }

    private func restart() {
        session?.stop()
        session = QuizSession(model: model)
    }
}

private struct QuizContent: View {
    let session: QuizSession
    let model: AppModel
    let onRestart: () -> Void
    let onHome: () -> Void

    var body: some View {
        let engine = session.engine
        ZStack {
            WorldBackgroundView(motion: session.motion)
            if engine.phase == .finished {
                ResultView(model: model, engine: engine, onRestart: onRestart, onHome: onHome)
            } else {
                quizBody(engine)
            }
        }
        .id(engine.phase == .finished)
    }

    private func quizBody(_ engine: QuizEngine) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text("第\(engine.index + 1)問 / \(engine.total)問")
                    .font(.subheadline.weight(.bold))
                Spacer()
                TimerLabel(engine: engine)
            }
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 3)

            VStack(alignment: .leading, spacing: 16) {
                Text(engine.current.question)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(engine.current.choices) { c in
                    ChoiceButton(choice: c, phase: engine.phase, correctID: engine.current.correctChoiceId) {
                        session.answer(c.id)
                    }
                }
            }
            .parchmentPanel(opacity: 0.8)

            Spacer(minLength: 0)
            feedback(engine)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func feedback(_ engine: QuizEngine) -> some View {
        switch engine.phase {
        case .answering:
            Label("考え中…", systemImage: "chevron.down.2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black, radius: 3)
                .padding(.bottom, 24)
        case .resolved(let r):
            VStack(spacing: 10) {
                switch r {
                case .correct:
                    Text("正解!  +\(engine.lastXPGain) XP").font(.title2.weight(.black)).foregroundStyle(Theme.good)
                case .wrong:
                    Text("残念…").font(.title2.weight(.black)).foregroundStyle(Theme.bad)
                case .timeout:
                    Text("時間切れ…").font(.title2.weight(.black)).foregroundStyle(Theme.bad)
                }
                if case .correct = r {} else {
                    Text("正解: \(engine.current.correctText)").font(.subheadline.weight(.bold))
                }
                if !engine.current.explanation.isEmpty {
                    Text(engine.current.explanation).font(.footnote)
                }
                Button(engine.isLast ? "結果を見る" : "次の問題へ") { session.next() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .foregroundStyle(Theme.ink)
            .parchmentPanel(opacity: 0.92)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case .finished:
            EmptyView()
        }
    }
}

/// Isolated so the 60fps timer only invalidates this label.
private struct TimerLabel: View {
    let engine: QuizEngine
    var body: some View {
        Label(String(format: "%.1f", engine.remaining), systemImage: "timer")
            .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(engine.remaining <= 5 ? Theme.bad : .white)
            .shadow(color: .black, radius: 3)
            .accessibilityLabel("残り \(Int(engine.remaining.rounded(.up))) 秒")
    }
}

private struct ChoiceButton: View {
    let choice: Choice
    let phase: QuizPhase
    let correctID: String
    let action: () -> Void

    private var state: (fill: Color, mark: String?) {
        guard case .resolved(let r) = phase else { return (.white.opacity(0.75), nil) }
        if choice.id == correctID { return (Theme.good.opacity(0.9), "checkmark") }
        if case .wrong(let chosen) = r, chosen == choice.id { return (Theme.bad.opacity(0.9), "xmark") }
        return (.white.opacity(0.4), nil)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(choice.id)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.ink, in: Circle())
                Text(choice.text).font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                if let m = state.mark { Image(systemName: m).fontWeight(.black) }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(state.fill, in: Capsule())
            .overlay(Capsule().stroke(Theme.parchmentDark, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(phase != .answering)
    }
}
