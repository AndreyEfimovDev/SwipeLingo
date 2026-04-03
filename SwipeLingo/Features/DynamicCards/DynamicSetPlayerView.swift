import SwiftUI

// MARK: - DynamicSetPlayerView
// Воспроизведение одного DynamicSet.
//
// DisplayMode (.sequential / .parallel) — из модели сета, задаётся автором контента.
// AnimationMode (.manual / .automatic) — пользовательская настройка:
//   • manual:    тап в любом месте → следующий элемент
//   • automatic: авто-показ с задержкой, кнопка play/pause в тулбаре
//
// Порядок показа:
//   sequential: left[0] → right[0] → left[1] → right[1] → ...
//   parallel:   left[0]+right[0] → left[1]+right[1] → ...
//
// Озвучка (TTS):
//   После появления каждого шага — пауза 0.5с — озвучка.
//   sequential: озвучивается один текст (left или right).
//   parallel:   озвучивается left → пауза 0.4с (после окончания left TTS) → озвучивается right.
//   Кнопка включения/отключения в тулбаре.
//
// После показа всех элементов → SRS-оценка всего сета (TODO: SRS-поля в DynamicSet).

struct DynamicSetPlayerView: View {

    let set: DynamicSet

    @AppStorage("dynamicAnimationMode")     private var defaultAnimationMode: AnimationMode = .manual
    @AppStorage("dynamicCardsAudioEnabled") private var audioEnabled: Bool = true
    @AppStorage("ttsVoiceIdentifier")       private var ttsVoiceIdentifier: String = ""

    @State private var animationMode: AnimationMode = .manual
    @State private var revealedSteps: Int = 0
    @State private var thresholds: [(leftStep: Int?, rightStep: Int?)] = []
    @State private var totalSteps: Int = 0
    @State private var autoPlayTask: Task<Void, Never>?

    // Audio
    @State private var audioService = AudioPlayerService()
    @State private var audioTask: Task<Void, Never>?
    /// Текст для озвучки правой стороны — ставится при parallel, озвучивается после окончания левого TTS
    @State private var pendingRightSpeech: String? = nil

    private let autoPlayDelay: Double = 2.5
    private let readPause: Double = 0.5     // пауза после появления строки перед озвучкой
    private let speechGap: Double = 0.4    // пауза между left и right TTS в parallel режиме

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
                            .font(.subheadline)
                            .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }

                    // Column headers
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

                    // SRS buttons — после показа всех элементов
                    if isComplete {
                        srsSection
                            .padding(.top, 24)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Manual mode hint
                    if !isComplete && animationMode == .manual && revealedSteps > 0 {
                        tapHint.padding(.top, 20)
                    }

                    Color.clear.frame(height: 32).id("bottom")
                }
                .padding(.top, 16)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .onTapGesture {
                guard animationMode == .manual, !isComplete else { return }
                withAnimation(.spring(duration: 0.4, bounce: 0.05)) { advance() }
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
        }
        .navigationTitle(set.title ?? "English+")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear {
            let computed = computeThresholds()
            thresholds = computed
            totalSteps = computed.reduce(0) { max($0, max($1.leftStep ?? 0, $1.rightStep ?? 0)) }
            animationMode = defaultAnimationMode
            withAnimation(.spring(duration: 0.4, bounce: 0.05)) { advance() }
            if animationMode == .automatic { startAutoPlay(skipFirst: true) }
        }
        .onDisappear {
            autoPlayTask?.cancel()
            audioTask?.cancel()
            pendingRightSpeech = nil
            audioService.stop()
        }
    }

    // MARK: - Column Headers

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Group {
                if let title = set.leftTitle {
                    Text(title).frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(Color.myColors.myBlue)
                } else { Spacer() }
            }

            Rectangle()
                .fill(Color.myColors.myAccent.opacity(0.1))
                .frame(width: 1, height: 16)

            Group {
                if let title = set.rightTitle {
                    Text(title).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12)
                        .foregroundStyle(Color.myColors.myPurple)
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

    // MARK: - Tap Hint

    private var tapHint: some View {
        HStack {
            Spacer()
            Text("Tap anywhere to continue")
                .font(.caption)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
            Image(systemName: "hand.tap")
                .font(.caption)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
            Spacer()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            // Кнопка включения/отключения озвучки
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

            // Кнопка play/pause (animationMode)
            Button { toggleAnimationMode() } label: {
                Image(systemName: animationMode == .automatic ? "pause.circle" : "play.circle")
                    .foregroundStyle(Color.myColors.myBlue)
            }
        }
    }

    // MARK: - Advance

    private func advance() {
        guard revealedSteps < totalSteps else { return }
        revealedSteps += 1
        // Озвучка вызывается через .onChange(of: revealedSteps)
    }

    // MARK: - Auto Play

    private func toggleAnimationMode() {
        if animationMode == .manual {
            // Если сет завершён — перезапустить с начала
            if isComplete { restartSet() }
            animationMode = .automatic
            startAutoPlay(skipFirst: false)
        } else {
            animationMode = .manual
            autoPlayTask?.cancel()
        }
    }

    private func restartSet() {
        autoPlayTask?.cancel()
        audioTask?.cancel()
        pendingRightSpeech = nil
        audioService.stop()
        withAnimation(.spring(duration: 0.3)) { revealedSteps = 0 }
    }

    private func startAutoPlay(skipFirst: Bool) {
        autoPlayTask?.cancel()
        autoPlayTask = Task {
            if skipFirst {
                try? await Task.sleep(for: .seconds(autoPlayDelay))
            }
            while !Task.isCancelled && !isComplete {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(duration: 0.4, bounce: 0.05)) { advance() }
                try? await Task.sleep(for: .seconds(autoPlayDelay))
            }
            // Воспроизведение завершилось (не отменено) — возвращаем кнопку в play
            if !Task.isCancelled {
                animationMode = .manual
            }
        }
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
                // Если есть правый текст (parallel) — ставим в очередь, он сыграет после left
                if let right = rightText, !right.isEmpty {
                    pendingRightSpeech = right
                }
                audioService.speak(text: text, voiceIdentifier: voiceId)
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
