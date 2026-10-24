import SwiftUI
import AVFAudio

/// Wires the pure QuizEngine to a frame ticker, the world motion and persistence.
@MainActor
@Observable
final class QuizSession {
    let engine: QuizEngine
    let motion = WorldMotionController()
    private let model: AppModel
    let stage: Stage
    private var ticker: Task<Void, Never>?
    private var finishedRecorded = false
    private var countdownStarted = false
    private let sound = SoundPlayer.shared
    private var lastTick: ContinuousClock.Instant?
    private let now: () -> ContinuousClock.Instant   // injectable for tests
    private let carryOverDepth: Double?
    /// Pausing (Background, or the player's pause button) drops the clock reference, so the suspended
    /// interval is never counted. `paused` is the system's switch (scene phase); `userPaused` is the button.
    var paused = false { didSet { pauseChanged() } }
    var userPaused = false { didSet { pauseChanged() } }
    var isPaused: Bool { paused || userPaused }
    /// Length of the "3, 2, 1, 0" voice; it starts that long before the deadline.
    @ObservationIgnored private var cachedLead: Double?
    private var countdownLead: Double {
        if let c = cachedLead { return c }
        let d = SoundPlayer.shared.duration(of: .countdown)
        cachedLead = d > 0 ? d : 3.4
        return cachedLead!
    }

    private func pauseChanged() {
        lastTick = nil
        guard isPaused else { return }
        sound.stopAll()
        countdownStarted = false      // on resume, restart it from the right spot for the time left
        MusicPlayer.shared.cancelDuck()
    }

    /// `carryOverDepth`: where the previous run's world currently is, so a quick retry rises back to the
    /// surface from there instead of warping.
    init(model: AppModel, stage: Stage? = nil, carryOverDepth: Double? = nil,
         now: @escaping () -> ContinuousClock.Instant = { ContinuousClock().now }) {
        let stage = stage ?? model.currentStage
        self.model = model
        self.stage = stage
        self.now = now
        self.carryOverDepth = carryOverDepth
        self.engine = QuizEngine(questions: model.makeSession(stage: stage),
                                 xpPerCorrect: model.xpPerCorrect(for: stage))
        precondition(!engine.questions.isEmpty, "session must have questions")
        engine.onResolved = { [weak self] q, r in self?.handle(q, r) }
        motion.configure(stage: stage, questionCount: engine.total)
    }

    /// Sets up geometry, position and clocks without starting the frame ticker (tests drive `advance()`).
    func configure(viewportHeight: Double, width: Double) {
        motion.setViewport(viewportHeight, width: width)
        if let carry = carryOverDepth {
            motion.jump(to: carry)
            motion.settle(to: 0)                 // every run starts on the surface, at the top of 001
        } else {
            motion.jump(to: 0)
        }
        motion.startThinking(duration: QuizEngine.timeLimit)
        lastTick = now()
    }

    func start(viewportHeight: Double, width: Double) {
        guard ticker == nil else { return }
        configure(viewportHeight: viewportHeight, width: width)
        MusicPlayer.shared.request(stage.config.music.randomElement() ?? .earth)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                self?.advance()
            }
        }
    }

    func stop() { ticker?.cancel(); ticker = nil; lastTick = nil; sound.stopAll() }

    /// Single time source: the frame ticker and answer handling both advance the engine to "now" first,
    /// so an answer arriving after the deadline is a timeout regardless of task ordering.
    func advance() {
        guard !isPaused else { return }
        let current = now()
        defer { lastTick = current }
        guard let last = lastTick else { return }
        let d = current - last
        let dt = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        engine.tick(dt)
        motion.step(dt)
        // "3, 2, 1, 0" voice: ends as the time runs out. After a pause it resumes from the matching offset.
        if engine.phase == .answering, !countdownStarted, engine.remaining <= countdownLead {
            countdownStarted = true
            if let p = sound.play(.countdown) {
                p.currentTime = max(0, countdownLead - engine.remaining)
                MusicPlayer.shared.duck(to: 0.35, for: engine.remaining + 0.2)
            }
        }
    }

    func answer(_ id: String) { advance(); engine.answer(choiceID: id) }

    var currentDepth: Double { motion.depth }

    func next() {
        advance()   // settle elapsed time against the finished question, so the new one starts from a fresh clock
        sound.stopAll()   // nothing from the previous question may leak into the next one
        engine.next()
        countdownStarted = false
        if engine.phase == .finished {
            if !finishedRecorded { finishedRecorded = true; model.finishSession(); duck(for: [sound.play(.finishVoice)]) }
        } else {
            motion.startThinking(duration: QuizEngine.timeLimit)
        }
    }

    /// Lowers the music only for sounds that actually started, for as long as the longest of them lasts.
    private func duck(for players: [AVAudioPlayer?]) {
        let lengths = players.compactMap { $0?.duration }
        guard let longest = lengths.max() else { return }
        MusicPlayer.shared.duck(for: longest + 0.3)
    }

    private func handle(_ q: Question, _ r: Resolution) {
        switch r {
        case .correct:
            model.record(question: q, correct: true, xp: engine.xpPerCorrectAnswer)
            Haptics.correct()
            sound.stop(.countdown)
            let voice = sound.play(.correctVoice)
            let chime = sound.play(.correctChime)   // correct = voice + chime only (dig_*/break_*.mp3 stay bundled, unused)
            // Hold the music down for as long as the longer of the two sounds, plus a short tail.
            // Nothing audible (sound effects off) means nothing to duck for.
            duck(for: [voice, chime])
            // Each correct answer dives to the top of the next image; the last one reaches the very bottom.
            motion.boost(to: motion.restingDepth(afterCorrect: engine.correctCount))
        case .wrong:
            model.record(question: q, correct: false)
            Haptics.wrong()
            sound.stop(.countdown)
            duck(for: [sound.play(.wrong)])
            motion.fall(distance: WorldMotionController.wrongFall)
        case .timeout:
            model.record(question: q, correct: false)
            Haptics.timeout()
            sound.stop(.countdown)
            duck(for: [sound.play(.timeoutVoice)])
            motion.fall(distance: WorldMotionController.timeoutFall)
        }
    }
}

struct QuizView: View {
    let model: AppModel
    let stage: Stage
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
            .onAppear { if session == nil, model.canStartSession { session = QuizSession(model: model, stage: stage) } }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: scenePhase) { _, phase in session?.paused = phase != .active }
    }

    private func restart() {
        let carry = session?.currentDepth
        session?.stop()
        session = QuizSession(model: model, stage: stage, carryOverDepth: carry)
    }
}

private struct QuizContent: View {
    let session: QuizSession
    let model: AppModel
    let onRestart: () -> Void
    let onHome: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var progressSize: CGFloat = 24
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Decorative motion: off with the in-app switch or the system "Reduce Motion".
    private var effects: Bool { AppSettings.shared.effectsEnabled && !reduceMotion }

    var body: some View {
        let engine = session.engine
        ZStack {
            WorldBackgroundView(motion: session.motion)
            if effects {
                AmbientEffects(motion: session.motion)
                LowTimeVignette(engine: engine)
            }
            if engine.phase == .finished {
                ResultView(model: model, engine: engine, onRestart: onRestart, onHome: onHome)
            } else {
                // The burst is an overlay: it is drawn on top but never takes part in layout, so its
                // 520pt sparkle can no longer widen the screen (it did, on every correct answer).
                quizBody(engine)
                    .overlay {
                        if effects, case .resolved(let r) = engine.phase {
                            AnswerBurst(resolution: r, xp: engine.lastXPGain).id(engine.index)
                        }
                    }
                    .overlay(alignment: .top) {
                        // Streak shout-out: from the second correct answer in a row. Overlay only, no layout.
                        if effects, case .resolved(.correct) = engine.phase, engine.combo >= 2 {
                            ComboBurst(combo: engine.combo).id(engine.index).padding(.top, 20)
                        }
                    }
                if session.userPaused {
                    PauseOverlay(onResume: { session.userPaused = false }, onHome: onHome)
                }
            }
        }
        .id(engine.phase == .finished)
        .onChange(of: reduceMotion, initial: true) { _, on in session.motion.reduceMotion = on }
    }

    private func quizBody(_ engine: QuizEngine) -> some View {
        GeometryReader { geo in
            // The content width is pinned to the screen: a long single line must wrap, never widen the layout.
            let contentWidth = max(geo.size.width - 36, 100)
            VStack(spacing: 14) {
                // One row normally; at large text sizes progress and timer stack so the time never wraps.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        progressLabel(engine)
                        Spacer(minLength: 0)
                        TimerLabel(engine: engine)
                        pauseButton
                    }
                    VStack(spacing: 6) {
                        HStack(spacing: 12) {
                            progressLabel(engine)
                            Spacer(minLength: 0)
                            pauseButton
                        }
                        HStack { Spacer(minLength: 0); TimerLabel(engine: engine) }
                    }
                    // Largest text sizes: the short "10 / 20" always fits next to the pause button.
                    VStack(spacing: 6) {
                        HStack(spacing: 12) {
                            progressLabel(engine, short: true)
                            Spacer(minLength: 0)
                            pauseButton
                        }
                        HStack { Spacer(minLength: 0); TimerLabel(engine: engine) }
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 3)
                .frame(width: contentWidth)

                // The panel is centred when it is short and scrolls when it is not (small screens, big text),
                // so every word of the question and both choices can always be reached.
                GeometryReader { area in
                    ScrollView {
                        questionPanel(engine)
                            .frame(width: contentWidth)
                            .frame(maxWidth: .infinity, minHeight: area.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.visible)
                    .id(engine.index)        // a new question always starts scrolled to its top
                }
                // Fixed-height feedback area: the question panel stays put when an answer is revealed.
                feedback(engine)
                    .frame(width: contentWidth, height: geo.size.height * (typeSize.isAccessibilitySize ? 0.3 : 0.42) > 300 ? 300 : geo.size.height * (typeSize.isAccessibilitySize ? 0.3 : 0.42), alignment: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    private func progressLabel(_ engine: QuizEngine, short: Bool = false) -> some View {
        let full = "第\(engine.index + 1)問 / \(engine.total)問"
        return Text(short ? "\(engine.index + 1) / \(engine.total)" : full)
            .font(.mplus(fixed: progressSize, .heavy))
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(full)          // VoiceOver and tests always get the full wording
            .accessibilityIdentifier("progress")
    }

    private var pauseButton: some View {
        Button { session.userPaused = true } label: {
            Image(systemName: "pause.fill")
                .font(.headline)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.4), in: Circle())
        }
        .accessibilityLabel("一時停止")
        .accessibilityIdentifier("pause")
    }

    private func questionPanel(_ engine: QuizEngine) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(engine.current.question)
                .font(.mplus(.title3, .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(engine.current.choices) { c in
                ChoiceButton(choice: c, phase: engine.phase, correctID: engine.current.correctChoiceId) {
                    session.answer(c.id)
                }
            }
        }
        .parchmentPanel(opacity: 0.8)
    }

    @ViewBuilder
    private func feedback(_ engine: QuizEngine) -> some View {
        switch engine.phase {
        case .answering:
            Label("考え中…", systemImage: "chevron.down.2")
                .font(.mplus(.subheadline, .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black, radius: 3)
                .padding(.bottom, 24)
        case .resolved(let r):
            VStack(spacing: 10) {
                // Text scrolls if it is long; the button below is always reachable.
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        switch r {
                        case .correct:
                            // The streak is spelled out here too, so it is readable with effects off.
                            Text("正解!  +\(engine.lastXPGain) XP" + (engine.combo >= 2 ? "   \(engine.combo)連続!" : ""))
                                .font(.mplus(.title2, .black)).foregroundStyle(Theme.goodDark)
                        case .wrong:
                            Text("残念…").font(.mplus(.title2, .black)).foregroundStyle(Theme.badDark)
                        case .timeout:
                            Text("時間切れ…").font(.mplus(.title2, .black)).foregroundStyle(Theme.badDark)
                        }
                        if case .correct = r {} else {
                            Text("正解: \(engine.current.correctText)").font(.mplus(.subheadline, .bold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !engine.current.explanation.isEmpty {
                            Text(engine.current.explanation)
                                .font(.mplus(.body))
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.visible)
                Button(engine.isLast ? "結果を見る" : "次の問題へ") { session.next() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .foregroundStyle(Theme.ink)
            .parchmentPanel(opacity: 0.96)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case .finished:
            EmptyView()
        }
    }
}

/// Pause menu. It hides the question, so pausing is not a way to get extra thinking time.
private struct PauseOverlay: View {
    let onResume: () -> Void
    let onHome: () -> Void
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("一時停止").font(.mplus(.title, .black)).foregroundStyle(.white)
                VStack(spacing: 4) {
                    Toggle("BGM", isOn: $settings.bgmEnabled)
                    Toggle("効果音・ボイス", isOn: $settings.sfxEnabled)
                }
                .tint(Theme.ember)
                .foregroundStyle(Theme.ink)
                .parchmentPanel(opacity: 0.95)
                Button("再開", action: onResume).buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("resume")
                Button("ホームへもどる", action: onHome).buttonStyle(PrimaryButtonStyle(tint: Theme.parchment))
                Text("ここまでの回答とXPは保存されています。この回のつづきはありません。")
                    .font(.mplus(.footnote)).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 460)
        }
    }
}

/// Isolated so the 60fps timer only invalidates this label.
private struct TimerLabel: View {
    let engine: QuizEngine
    var body: some View {
        Label(String(format: "%.1f", engine.remaining), systemImage: "timer")
            .font(.mplus(.title3, .heavy).monospacedDigit())
            .foregroundStyle(engine.remaining <= 5 ? Theme.bad : .white)
            .shadow(color: .black, radius: 3)
            .lineLimit(1)
            .fixedSize()
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

    @ScaledMetric(relativeTo: .body) private var badge: CGFloat = 30

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(choice.id)
                    .font(.mplus(.callout, .black))
                    .foregroundStyle(.white)
                    .frame(width: badge, height: badge)
                    .background(Theme.ink, in: Circle())
                // Full text, any length: wraps instead of truncating, and the row grows with it.
                Text(choice.text)
                    .font(.mplus(.title3, .bold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let m = state.mark { Image(systemName: m).fontWeight(.black) }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(state.fill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.parchmentDark, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(phase != .answering)
    }
}

/// "N COMBO!" shout for consecutive correct answers. Bigger and hotter as the streak grows.
private struct ComboBurst: View {
    let combo: Int
    @State private var scale = 0.3
    @State private var opacity = 1.0

    /// 0: 2 in a row, 1: 3-4, 2: 5-9, 3: 10+
    private var tier: Int { combo >= 10 ? 3 : combo >= 5 ? 2 : combo >= 3 ? 1 : 0 }
    private var colors: [Color] {
        switch tier {
        case 3: return [Color(red: 1, green: 0.4, blue: 0.8), Color(red: 0.6, green: 0.35, blue: 1)]
        case 2: return [Color(red: 1, green: 0.25, blue: 0.2), Color(red: 1, green: 0.65, blue: 0.1)]
        case 1: return [Color(red: 1, green: 0.6, blue: 0.1), Color(red: 1, green: 0.9, blue: 0.3)]
        default: return [Color(red: 1, green: 0.9, blue: 0.35), .white]
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if tier >= 2 { Image(systemName: "flame.fill").font(.system(size: 40, weight: .black)) }
            Text("\(combo)").font(.mplus(fixed: CGFloat(52 + 4 * min(combo, 10)), .black))
            Text("COMBO" + String(repeating: "!", count: min(tier + 1, 3)))
                .font(.mplus(fixed: 30, .black))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
        .shadow(color: .black.opacity(0.8), radius: 0, x: 0, y: 3)
        .shadow(color: colors[0].opacity(0.8), radius: 14)
        .padding(.horizontal, 20)
        .rotationEffect(.degrees(-5))
        .scaleEffect(scale)
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.42)) { scale = 1 }
            withAnimation(.easeIn(duration: 0.4).delay(1.1)) { opacity = 0 }
        }
    }
}

/// Big ○ with a floating "+XP" on a correct answer; a quieter × otherwise.
private struct AnswerBurst: View {
    let resolution: Resolution
    let xp: Int
    @State private var scale = 0.3
    @State private var opacity = 1.0
    @State private var xpOffset = 0.0

    private var correct: Bool { if case .correct = resolution { return true } else { return false } }

    var body: some View {
        ZStack {
            if correct { SparkleBurst() }
            Text(correct ? "○" : "×")
                .font(.mplus(fixed: 220, .black))
                .foregroundStyle(correct ? Theme.good : Theme.bad)
                .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
                .scaleEffect(scale)
                .opacity(correct ? opacity : opacity * 0.8)
            if correct && xp > 0 {
                Text("+\(xp) XP")
                    .font(.mplus(fixed: 44, .black))
                    .foregroundStyle(Theme.ember)
                    .shadow(color: .black, radius: 4, y: 2)
                    .offset(y: 120 + xpOffset)
                    .opacity(opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { scale = 1.0 }
            withAnimation(.easeOut(duration: 1.4)) { xpOffset = -110 }
            withAnimation(.easeIn(duration: 0.5).delay(0.9)) { opacity = 0 }
        }
    }
}
