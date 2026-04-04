import SwiftUI

// MARK: - DynamicSetPlayerView
// Воспроизведение одного DynamicSet.
//
// DisplayMode (.sequential / .parallel) — из модели сета, задаётся автором контента.
// AnimationMode (.manual / .automatic) — пользовательская настройка:
//   • manual:    тап в любом месте → следующий элемент
//   • automatic: авто-показ с задержкой; тап → пауза / возобновление
//
// Жизненный цикл:
//   1. Стартовый экран (hasStarted = false):
//      заголовок + подзаголовок + хедеры колонок + кнопка Start + переключатель режима
//   2. Воспроизведение (hasStarted = true):
//      элементы появляются по шагам; переключатель режима над таблицей
//   3. Завершение (isComplete = true):
//      SRS-оценка всего сета + кнопка Replay
//
// Озвучка (TTS):
//   После появления каждого шага — пауза 0.5с — озвучка.
//   sequential: озвучивается один текст (left или right).
//   parallel:   left → пауза 0.4с (после окончания left TTS) → right.
//   Кнопка включения/отключения в тулбаре.

struct DynamicSetPlayerView: View {

    let set: DynamicSet

    @AppStorage("dynamicAnimationMode")     private var defaultAnimationMode: AnimationMode = .manual
    @AppStorage("dynamicCardsAudioEnabled") private var audioEnabled: Bool = true
    @AppStorage("ttsVoiceIdentifier")       private var ttsVoiceIdentifier: String = ""

    @State private var animationMode:  AnimationMode = .manual
    @State private var hasStarted:     Bool = false
    @State private var isPaused:       Bool = false
    @State private var showCompletion: Bool = false   // true только после окончания аудио последней строки
    @State private var revealedSteps:  Int = 0
    @State private var thresholds: [(leftStep: Int?, rightStep: Int?)] = []
    @State private var totalSteps: Int = 0
    @State private var autoPlayTask:   Task<Void, Never>?
    @State private var completionTask: Task<Void, Never>?

    // Audio
    @State private var audioService = AudioPlayerService()
    @State private var audioTask: Task<Void, Never>?
    /// Текст для озвучки правой стороны — ставится при parallel, озвучивается после окончания левого TTS
    @State private var pendingRightSpeech: String? = nil

    private let autoPlayDelay: Double = 2.5  // fallback-задержка когда аудио выключено
    private let readPause: Double = 0.8     // пауза после появления строки перед озвучкой
    private let speechGap: Double = 0.6    // пауза между left и right TTS в parallel режиме
    private let postAudioDelay: Double = 1.4 // пауза после окончания TTS перед следующей строкой

    // MARK: - Computed

    private var isComplete: Bool { revealedSteps >= totalSteps && totalSteps > 0 }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Subtitle
                    if let subtitle = set.subtitle {
                        Text(subtitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.myColors.myAccent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.myColors.myAccent.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }

                    if !hasStarted {
                        startScreen
                    } else {
                        // Column headers — только во время воспроизведения
                        if set.leftTitle != nil || set.rightTitle != nil {
                            columnHeaders
                                .padding(.bottom, 6)
                        }

                        // Pairs table
                        VStack(spacing: 0) {
                            ForEach(Array(set.items.enumerated()), id: \.offset) { index, pair in
                                if isPairVisible(at: index) {
                                    pairRow(pair: pair, index: index)
                                }
                            }
                        }
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .myShadow()
                        .padding(.horizontal, 16)

                        // SRS buttons + replay + mode toggle — после окончания аудио последней строки
                        if showCompletion {
                            srsSection
                                .padding(.top, 24)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Hints — только во время воспроизведения
                        if !isComplete {
                            if animationMode == .manual {
                                tapHint.padding(.top, 20)
                            } else if isPaused {
                                resumeHint.padding(.top, 20)
                            }
                        }
                    }

                    Color.clear.frame(height: 32).id("bottom")
                }
                .padding(.top, 16)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .contentShape(Rectangle())
            .onTapGesture {
                handleTap()
            }
            .onChange(of: revealedSteps) {
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                speakCurrentStep()
            }
            // Parallel mode: когда левый TTS закончил → озвучиваем правый
            .onChange(of: audioService.isPlaying) { _, isNow in
                guard !isNow, let text = pendingRightSpeech else { return }
                pendingRightSpeech = nil
                guard audioEnabled else { return }
                audioTask = Task {
                    try? await Task.sleep(for: .seconds(speechGap))
                    guard !Task.isCancelled, audioEnabled else { return }
                    audioService.speak(text: text, voiceIdentifier: ttsVoiceIdentifier)
                }
            }
            // Manual mode: последняя строка показана → ждём окончания аудио → показываем SRS
            .onChange(of: isComplete) { _, complete in
                guard complete, animationMode == .manual else { return }
                completionTask?.cancel()
                completionTask = Task {
                    await waitForAudioThenPause()
                    guard !Task.isCancelled else { return }
                    withAnimation { showCompletion = true }
                }
            }
        }
        .navigationTitle(set.title ?? "English+")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear {
            let computed = computeThresholds()
            thresholds = computed
            totalSteps = computed.reduce(0) { max($0, max($1.leftStep ?? 0, $1.rightStep ?? 0)) }
            animationMode = defaultAnimationMode
        }
        .onDisappear {
            autoPlayTask?.cancel()
            completionTask?.cancel()
            audioTask?.cancel()
            pendingRightSpeech = nil
            audioService.stop()
        }
    }

    // MARK: - Start Screen

    private var startScreen: some View {
        VStack(spacing: 40) {
            Spacer()

            Button { startPlayback() } label: {
                VStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 72))
                    Text("Start")
                        .font(.title3.weight(.semibold))
                }
            }
            .foregroundStyle(Color.myColors.myBlue)
            .buttonStyle(.plain)

            modeToggle

            Spacer()
        }
        .frame(maxWidth: .infinity)
        // minHeight: даём Spacer-ам пространство для центрирования содержимого по вертикали.
        // Вычитаем приблизительную высоту nav bar + subtitle + tab bar + отступы.
        .frame(minHeight: UIScreen.main.bounds.height * 0.6)
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        HStack(spacing: 8) {
            modePill(.automatic, label: "Auto")
            modePill(.manual,    label: "Manual")
        }
        .padding(.horizontal, 48)
    }

    private func modePill(_ mode: AnimationMode, label: String) -> some View {
        let isActive = animationMode == mode
        return Button { switchMode(to: mode) } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isActive ? Color.myColors.myBlue : Color.myColors.myAccent.opacity(0.5))
                .frame(maxWidth: 200)
                .padding(.vertical, 12)
                .background(Color.clear, in: .capsule)
                .overlay(Capsule().strokeBorder(
                    isActive ? Color.myColors.myBlue : Color.myColors.myAccent.opacity(0.5),
                    lineWidth: isActive ? 2 : 0.5))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: animationMode)
    }

    // MARK: - Column Headers

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Group {
                if let title = set.leftTitle {
                    Text(title).frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(Color.myColors.myGreen)
                } else { Spacer() }
            }

            Rectangle()
                .fill(Color.myColors.myAccent.opacity(0.1))
                .frame(width: 1, height: 16)

            Group {
                if let title = set.rightTitle {
                    Text(title).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12)
                        .foregroundStyle(Color.myColors.myRed)
                } else { Spacer() }
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 28)
    }

    // MARK: - Pair Row

    @ViewBuilder
    private func pairRow(pair: DynamicPair, index: Int) -> some View {
        let thresh = thresholds[index]
        let leftVisible  = thresh.leftStep.map  { revealedSteps >= $0 } ?? false
        let rightVisible = thresh.rightStep.map { revealedSteps >= $0 } ?? false

        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                cellText(pair.left?.text, visible: leftVisible)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.myColors.myAccent.opacity(0.1))
                    .frame(width: 1)
                    .padding(.vertical, 8)

                cellText(pair.right?.text, visible: rightVisible)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animation(.spring(duration: 0.4, bounce: 0.05), value: revealedSteps)

            if index < set.items.count - 1 {
                Divider().padding(.leading, 12)
            }
        }
    }

    @ViewBuilder
    private func cellText(_ text: String?, visible: Bool) -> some View {
        if let text {
            Text(text)
                .font(.body)
                .foregroundStyle(Color.myColors.myAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : 6)
        } else {
            Color.clear.frame(height: 48)
        }
    }

    // MARK: - SRS Section

    private var srsSection: some View {
        VStack(spacing: 12) {
            Text("How well did you know this?")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))

            HStack(spacing: 10) {
                srsButton("Forgot", color: Color.myColors.myRed)    { }
                srsButton("Hard",   color: Color.myColors.myOrange)  { }
                srsButton("Easy",   color: Color.myColors.myGreen)   { }
            }
            // TODO: SRS-логика для DynamicSet (оценка всего сета целиком)
            // Требует SRS-полей в DynamicSet: dueDate, interval, easeFactor, repetitions

            // Replay button
            Button { restartSet() } label: {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.myColors.myBlue)
                    Text("Replay")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.myColors.myBlue)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            // Mode toggle — под Replay
            modeToggle
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
    }

    private func srsButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(color.opacity(0.12))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hints

    private var tapHint: some View {
        HStack {
            Spacer()
            Text("Tap anywhere for next")
            Image(systemName: "hand.tap")
            Spacer()
        }
        .font(.headline)
        .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
    }

    private var resumeHint: some View {
        HStack {
            Spacer()
            Image(systemName: "pause.circle")
            Text("Paused — tap to resume")
            Spacer()
        }
        .font(.headline)
        .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                audioEnabled.toggle()
                if !audioEnabled {
                    audioTask?.cancel()
                    pendingRightSpeech = nil
                    audioService.stop()
                }
            } label: {
                Image(systemName: audioEnabled ? "speaker.wave.2" : "speaker.slash")
                    .foregroundStyle(audioEnabled ? Color.myColors.myBlue : Color.myColors.myAccent.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }

    // MARK: - Interaction

    private func handleTap() {
        guard hasStarted, !isComplete else { return }
        switch animationMode {
        case .automatic:
            isPaused ? resumeAutoPlay() : pauseAutoPlay()
        case .manual:
            withAnimation(.spring(duration: 0.4, bounce: 0.05)) { advance() }
        }
    }

    private func startPlayback() {
        hasStarted = true
        withAnimation(.spring(duration: 0.4, bounce: 0.05)) { advance() }
        if animationMode == .automatic {
            startAutoPlay(skipFirst: true)
        }
    }

    private func switchMode(to mode: AnimationMode) {
        guard mode != animationMode else { return }
        // Если переключаемся из auto — отменяем автопроигрывание
        if animationMode == .automatic {
            autoPlayTask?.cancel()
        }
        isPaused = false
        animationMode = mode
        defaultAnimationMode = mode   // запоминаем выбор
        // Если переключились в auto во время воспроизведения — запускаем
        if mode == .automatic, hasStarted, !isComplete {
            startAutoPlay(skipFirst: true)
        }
    }

    private func pauseAutoPlay() {
        isPaused = true
        autoPlayTask?.cancel()
        audioTask?.cancel()
        pendingRightSpeech = nil
        audioService.stop()
        log("⏸ Auto play paused at step \(revealedSteps)")
    }

    private func resumeAutoPlay() {
        isPaused = false
        startAutoPlay(skipFirst: true)
        log("▶ Auto play resumed from step \(revealedSteps)")
    }

    // MARK: - Advance

    private func advance() {
        guard revealedSteps < totalSteps else { return }
        revealedSteps += 1
        // Озвучка вызывается через .onChange(of: revealedSteps)
    }

    // MARK: - Auto Play

    private func startAutoPlay(skipFirst: Bool) {
        autoPlayTask?.cancel()
        autoPlayTask = Task {
            // skipFirst: первый элемент уже показан (вызван advance() в startPlayback/restartSet),
            // поэтому сначала ждём окончания его аудио, потом идём дальше.
            if skipFirst {
                await waitForAudioThenPause()
            }
            while !Task.isCancelled && !isComplete {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(duration: 0.4, bounce: 0.05)) { advance() }
                // waitForAudioThenPause вызывается и после последней строки:
                // цикл выходит только после возврата из этого вызова,
                // т.е. SRS появится строго после окончания аудио последней строки.
                await waitForAudioThenPause()
            }
            // Auto-режим: цикл завершился штатно (не по отмене) → показываем SRS
            if !Task.isCancelled {
                withAnimation { showCompletion = true }
            }
        }
    }

    /// Ждёт окончания TTS (левый + правый в parallel), затем делает паузу перед следующей строкой.
    /// Если аудио выключено — фиксированная задержка autoPlayDelay.
    private func waitForAudioThenPause() async {
        guard !Task.isCancelled else { return }

        guard audioEnabled else {
            try? await Task.sleep(for: .seconds(autoPlayDelay))
            return
        }

        // Даём время readPause + запас, чтобы speakCurrentStep() успел запустить TTS
        try? await Task.sleep(for: .seconds(readPause + 0.3))
        guard !Task.isCancelled else { return }

        // Ждём, пока TTS начнёт воспроизводить (на случай если инициализация заняла время)
        var attempts = 0
        while !audioService.isPlaying && attempts < 15 {
            try? await Task.sleep(for: .milliseconds(100))
            attempts += 1
            guard !Task.isCancelled else { return }
        }

        // Ждём окончания всего аудио: левая сторона + правая (pendingRightSpeech)
        while audioService.isPlaying || pendingRightSpeech != nil {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
        }

        // Пауза после окончания речи — пользователь успевает прочитать и осмыслить
        try? await Task.sleep(for: .seconds(postAudioDelay))
    }

    private func restartSet() {
        autoPlayTask?.cancel()
        completionTask?.cancel()
        audioTask?.cancel()
        pendingRightSpeech = nil
        audioService.stop()
        isPaused = false
        showCompletion = false
        // hasStarted остаётся true — стартовый экран показывается только один раз
        withAnimation(.spring(duration: 0.3)) { revealedSteps = 0 }
        // Запускаем воспроизведение сразу без стартового экрана
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(duration: 0.4, bounce: 0.05)) { advance() }
            if animationMode == .automatic {
                startAutoPlay(skipFirst: true)
            }
        }
        log("↩ Set restarted")
    }

    // MARK: - Audio / TTS

    /// Определяет текст(ы) для текущего шага и запускает TTS с паузой readPause.
    /// sequential: один текст (left или right).
    /// parallel:   left → (ждём окончания TTS через .onChange(isPlaying)) → right.
    private func speakCurrentStep() {
        audioTask?.cancel()
        pendingRightSpeech = nil
        guard audioEnabled else { return }

        var leftText:  String? = nil
        var rightText: String? = nil

        for (index, thresh) in thresholds.enumerated() {
            guard index < set.items.count else { continue }
            let pair = set.items[index]

            switch set.displayMode {
            case .sequential:
                if thresh.leftStep  == revealedSteps { leftText  = pair.left?.text  }
                if thresh.rightStep == revealedSteps { rightText = pair.right?.text }
            case .parallel:
                if thresh.leftStep == revealedSteps || thresh.rightStep == revealedSteps {
                    leftText  = pair.left?.text
                    rightText = pair.right?.text
                }
            }
        }

        let voiceId = ttsVoiceIdentifier

        audioTask = Task {
            // Пауза: даём пользователю увидеть текст глазами
            try? await Task.sleep(for: .seconds(readPause))
            guard !Task.isCancelled, audioEnabled else { return }

            if let text = leftText, !text.isEmpty {
                // speak() внутри вызывает stop() → isPlaying = false → onChange срабатывает.
                // pendingRightSpeech ставим ПОСЛЕ speak(), иначе onChange подхватит его
                // раньше времени (до начала воспроизведения левого слова).
                audioService.speak(text: text, voiceIdentifier: voiceId)
                if let right = rightText, !right.isEmpty {
                    pendingRightSpeech = right
                }
            } else if let text = rightText, !text.isEmpty {
                // sequential: только правый элемент в этом шаге
                audioService.speak(text: text, voiceIdentifier: voiceId)
            }
        }
    }

    // MARK: - Helpers

    private func isPairVisible(at index: Int) -> Bool {
        guard index < thresholds.count else { return false }
        let t = thresholds[index]
        return (t.leftStep.map  { revealedSteps >= $0 } ?? false)
            || (t.rightStep.map { revealedSteps >= $0 } ?? false)
    }

    private func computeThresholds() -> [(leftStep: Int?, rightStep: Int?)] {
        var result: [(leftStep: Int?, rightStep: Int?)] = []
        var step = 0

        for pair in set.items {
            switch set.displayMode {
            case .sequential:
                var leftStep:  Int? = nil
                var rightStep: Int? = nil
                if pair.left  != nil { step += 1; leftStep  = step }
                if pair.right != nil { step += 1; rightStep = step }
                result.append((leftStep, rightStep))
            case .parallel:
                step += 1
                result.append((
                    pair.left  != nil ? step : nil,
                    pair.right != nil ? step : nil
                ))
            }
        }
        return result
    }
}
