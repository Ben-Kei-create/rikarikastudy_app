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
    private var lastTick: ContinuousClock.Instant?
    private let now: () -> ContinuousClock.Instant   // injectable for tests
    private let carryOverPosition: Double?
    /// Pausing (Background) drops the clock reference, so the suspended interval is never counted.
    var paused = false { didSet { lastTick = nil } }

    /// Permanent resting depth from XP/Lv; animations only deviate from it temporarily.
    private var permanent: Double { motion.permanentPosition(fraction: model.levelFraction) }

    /// `carryOverPosition`: where the previous session's world currently is, so a quick retry
    /// converges from there instead of warping.
    init(model: AppModel, carryOverPosition: Double? = nil,
         now: @escaping () -> ContinuousClock.Instant = { ContinuousClock().now }) {
        self.model = model
        self.now = now
        self.carryOverPosition = carryOverPosition
        self.engine = QuizEngine(questions: model.makeSession())
        precondition(!engine.questions.isEmpty, "session must have questions")
        engine.onResolved = { [weak self] q, r in self?.handle(q, r) }
        motion.restProvider = { [weak self] in self?.permanent ?? 0 }
    }

    /// Sets up geometry, position and clocks without starting the frame ticker (tests drive `advance()`).
    func configure(viewportHeight: Double, width: Double) {
        motion.setViewport(viewportHeight, width: width)
        if let carry = carryOverPosition {
            motion.jump(to: carry)
            motion.settle(to: permanent)
        } else {
            motion.jump(to: permanent)
        }
        motion.startThinking(duration: QuizEngine.timeLimit)
        lastTick = now()
    }

    func start(viewportHeight: Double, width: Double) {
        guard ticker == nil else { return }
        configure(viewportHeight: viewportHeight, width: width)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                self?.advance()
            }
        }
    }

    func stop() { ticker?.cancel(); ticker = nil; lastTick = nil }

    /// Single time source: the frame ticker and answer handling both advance the engine to "now" first,
    /// so an answer arriving after the deadline is a timeout regardless of task ordering.
    func advance() {
        guard !paused else { return }
        let current = now()
        defer { lastTick = current }
        guard let last = lastTick else { return }
        let d = current - last
        let dt = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        engine.tick(dt)
        motion.step(dt)
    }

    func answer(_ id: String) { advance(); engine.answer(choiceID: id) }

    var currentPosition: Double { motion.position }

    func next() {
        advance()   // settle elapsed time against the finished question, so the new one starts from a fresh clock
        engine.next()
        motion.settle(to: permanent)   // converge back to the permanent depth, never warp
        if engine.phase == .finished {
            if !finishedRecorded { finishedRecorded = true; model.finishSession() }
        } else {
            motion.startThinking(duration: QuizEngine.timeLimit)
        }
    }

    private func handle(_ q: Question, _ r: Resolution) {
        switch r {
        case .correct:
            model.record(question: q, correct: true)       // XP first, so `permanent` is the new depth
            motion.boost(to: permanent)
        case .wrong:
            model.record(question: q, correct: false)
            motion.fall(distance: 380)
        case .timeout:
            model.record(question: q, correct: false)
            motion.fall(distance: 440)
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
                        .onAppear { session.start(viewportHeight: geo.size.height, width: geo.size.width) }
                        .onDisappear { session.stop() }
                        .id(ObjectIdentifier(session))   // outermost: a new session recreates the view and re-runs onAppear
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
        let carry = session?.currentPosition
        session?.stop()
        session = QuizSession(model: model, carryOverPosition: carry)
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
            .frame(maxHeight: .infinity)   // centred in the space between header and feedback area

            // Fixed-height feedback area: the question panel stays put when an answer is revealed.
            feedback(engine)
                .frame(height: 300, alignment: .bottom)
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
