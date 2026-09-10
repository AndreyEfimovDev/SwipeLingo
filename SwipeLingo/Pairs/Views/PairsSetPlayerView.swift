import SwiftUI
import SwiftData

// MARK: - PairsSetPlayerView
// Воспроизведение одного PairsSet.
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
//
// Вся стейт-машина (шаги показа, авто/ручной режим, тайминги TTS, SRS) живёт в
// PairsSetPlayerViewModel. Здесь остаётся разметка и то, что физически не может жить
// вне View: @AppStorage, ScrollViewReader/proxy.scrollTo, навигационный @State.

struct PairsSetPlayerView: View {

    @Environment(\.modelContext) private var context

    let set: PairsSet
    /// Если задан — вызывается когда воспроизведение сета завершено.
    /// В этом режиме SRS-кнопки и Replay не показываются (управление передаётся наружу).
    var onComplete: (() -> Void)? = nil
    /// Если true — воспроизведение стартует автоматически без экрана Start.
    /// Используется в PairsSessionView чтобы убрать лишний шаг между сетами.
    var autoStart: Bool = false
    /// Если задан — используется как начальный режим вместо @AppStorage.
    /// Позволяет PairsSessionView задать pile-level режим; пользователь может
    /// поменять его локально для replay, но Next Set всегда получает pile-level.
    var initialAnimationMode: AnimationMode? = nil

    @State private var viewModel: PairsSetPlayerViewModel

    init(set: PairsSet, onComplete: (() -> Void)? = nil, autoStart: Bool = false, initialAnimationMode: AnimationMode? = nil) {
        self.set = set
        self.onComplete = onComplete
        self.autoStart = autoStart
        self.initialAnimationMode = initialAnimationMode
        _viewModel = State(initialValue: PairsSetPlayerViewModel(set: set))
    }

    @AppStorage(Constants.StorageKey.pairsAnimationMode) private var defaultAnimationMode: AnimationMode = .manual
    @AppStorage(Constants.StorageKey.pairsAudioEnabled)  private var audioEnabled: Bool = true
    @AppStorage(Constants.StorageKey.ttsVoiceIdentifier) private var ttsVoiceIdentifier: String = ""
    @AppStorage(Constants.StorageKey.srsEnabled)         private var srsEnabled: Bool = true
    @AppStorage(Constants.StorageKey.userPlan)           private var userPlan: AccessTier = .free

    /// Навигационное состояние — по правилу проекта остаётся в View, не в ViewModel.
    @State private var showPlans = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            subtitleLine
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                        if !viewModel.hasStarted {
                            startScreen
                        } else {
                            // Pairs table — одна карточка, секции внутри
                            VStack(spacing: 0) {
                                ForEach(Array(viewModel.pairGroups.enumerated()), id: \.offset) { groupIdx, group in
                                    if let firstIdx = group.indices.first, viewModel.isPairVisible(at: firstIdx) {
                                        // Разделитель между группами (не перед первой)
                                        if groupIdx > 0 {
                                            Rectangle()
                                                .fill(Color.myColors.myAccent.opacity(0.08))
                                                .frame(height: 1)
                                                .frame(maxWidth: .infinity)
                                        }
                                        // Заголовок секции (тег + leftTitle/rightTitle)
                                        if !group.tag.isEmpty {
                                            groupSectionHeader(
                                                tag: group.tag,
                                                leftTitle: group.leftTitle,
                                                rightTitle: group.rightTitle
                                            )
                                        }
                                    }
                                    // Видимые пары секции
                                    ForEach(group.indices, id: \.self) { idx in
                                        if viewModel.isPairVisible(at: idx) {
                                            pairRow(pair: set.items[idx], index: idx)
                                        }
                                    }
                                }
                            }
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .myShadow()
                            .padding(.horizontal, 16)

                            // SRS buttons + replay — только в standalone режиме (без onComplete)
                            if viewModel.showCompletion && onComplete == nil {
                                if srsEnabled { srsRatingButtons.padding(.top, 24) }
                                replayButton
                                    .padding(.top, srsEnabled ? 8 : 24)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            // Hints — только во время воспроизведения
                            if !viewModel.isComplete {
                                if viewModel.showTapHint {
                                    tapHint.padding(.top, 20)
                                        .transition(.opacity)
                                } else if viewModel.isManualPaused {
                                    resumeHint.padding(.top, 20)
                                        .transition(.opacity)
                                } else if viewModel.animationMode == .automatic && viewModel.isPaused {
                                    resumeHint.padding(.top, 20)
                                }
                            }
                        }

                        Color.clear.frame(height: 80).id("bottom")
                    }
                    .padding(.top, 16)
                }
                .background(Color(.systemBackground).ignoresSafeArea())
                .contentShape(Rectangle())
                .onTapGesture { viewModel.handleTap() }
                .onChange(of: viewModel.revealedSteps) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                // Parallel mode: когда левый TTS закончил → озвучиваем правый
                .onChange(of: viewModel.audioService.isPlaying) { _, isNow in
                    viewModel.handleAudioPlaybackChange(isPlayingNow: isNow)
                }
                // Завершение сета: в session-режиме вызываем onComplete, иначе прокручиваем к SRS
                .onChange(of: viewModel.showCompletion) { _, show in
                    guard show else { return }
                    if let onComplete {
                        onComplete()
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        withAnimation(.easeOut(duration: 0.4)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                // Manual mode: последняя строка показана → ждём окончания аудио → показываем SRS
                .onChange(of: viewModel.isComplete) { _, _ in
                    viewModel.scheduleCompletionIfNeeded()
                }
            } // closes ScrollViewReader
        } // closes VStack
        // В session-режиме (onComplete != nil) заголовок и back button задаёт PairsSessionView
        .if(onComplete == nil) { $0
            .customBackButton("Pairs")
            .navigationTitle(set.title ?? "Pairs")
            .navigationBarTitleDisplayMode(.inline)
        }
        .toolbar { toolbarContent }
        .onAppear {
            viewModel.audioEnabled = audioEnabled
            viewModel.ttsVoiceIdentifier = ttsVoiceIdentifier
            viewModel.userPlan = userPlan
            viewModel.onAppear(
                initialAnimationMode: initialAnimationMode ?? defaultAnimationMode,
                autoStart: autoStart,
                context: context
            )
        }
        .onChange(of: ttsVoiceIdentifier) { _, newValue in viewModel.ttsVoiceIdentifier = newValue }
        .onChange(of: userPlan) { _, newValue in viewModel.userPlan = newValue }
        .onDisappear {
            viewModel.cancelAllTasks()
        }
        .sheet(isPresented: $showPlans) { PlansView() }
    } // closes body

    // MARK: - Start Screen

    private var startScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            Button { viewModel.startPlayback() } label: {
                VStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 72))
                    Text("Start")
                        .font(.title3.weight(.semibold))
                }
            }
            .foregroundStyle(Color.myColors.myBlue)
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: UIScreen.main.bounds.height * 0.6)
    }

    private var subtitleLine: some View {
        // Count + tier badge + mode switcher — закреплена над ScrollView
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .top, spacing: 2) {
                let count = set.items.count
                if count > 0 {
                    Text("\(count) pairs")
                        .font(.subheadline)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                }
                AccessTierBadge(tier: set.accessTier, isSmall: true)
                    .offset(y: -3)
            }
            Spacer()
            modeToggle
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    // MARK: - Group Section Header
    //
    // Заголовок секции внутри плеера: tag (uppercase) + leftTitle/rightTitle (если заданы).
    // Появляется вместе с первой парой группы.

    @ViewBuilder
    private func groupSectionHeader(tag: String, leftTitle: String?, rightTitle: String?) -> some View {
        VStack(spacing: 0) {
            Text(tag.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, (leftTitle != nil || rightTitle != nil) ? 4 : 8)

            if leftTitle != nil || rightTitle != nil {
                HStack(spacing: 0) {
                    if let left = leftTitle {
                        Text(left)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.myColors.myGreen)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer()
                    }
                    if let right = rightTitle {
                        Rectangle()
                            .fill(Color.myColors.myAccent.opacity(0.1))
                            .frame(width: 1, height: 12)
                        Text(right)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.myColors.myRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 12)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(Color.myColors.myAccent.opacity(0.04))
    }

    // MARK: - Mode Toggle (одна кнопка — показывает текущий режим, тап переключает)

    private var modeToggle: some View {
        let isAuto = viewModel.animationMode == .automatic
        let isPlaybackActive = viewModel.hasStarted && !viewModel.showCompletion
        return Button {
            defaultAnimationMode = viewModel.switchMode(to: isAuto ? .manual : .automatic)
        } label: {
            HStack(spacing: 4) {
                Text(isAuto ? "Auto" : "Manual")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.myColors.myAccent)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .opacity(isPlaybackActive ? 0.4 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isPlaybackActive)
        .animation(.easeInOut(duration: 0.15), value: viewModel.animationMode)
        .animation(.easeInOut(duration: 0.2), value: isPlaybackActive)
    }

    // MARK: - Pair Row
    //
    // Layout:
    //   left + right  → одна строка, две колонки (right всегда короткий)
    //   left only     → полная ширина, medium weight
    //   description   → новая строка, полная ширина
    //   sample        → новая строка, полная ширина, italic

    @ViewBuilder
    private func pairRow(pair: Pair, index: Int) -> some View {
        let thresh        = viewModel.thresholds[index]
        let revealedSteps = viewModel.revealedSteps
        let leftVisible   = thresh.leftStep.map   { revealedSteps >= $0 } ?? false
        let rightVisible  = thresh.rightStep.map  { revealedSteps >= $0 } ?? false
        let descVisible   = thresh.descStep.map   { revealedSteps >= $0 } ?? false
        let sampleVisible = thresh.sampleStep.map { revealedSteps >= $0 } ?? false
        let isLocked      = viewModel.isLocked(at: index)

        VStack(alignment: .leading, spacing: 0) {

            // Line 1: left [+ right]
            HStack(alignment: .top, spacing: 0) {
                if pair.right != nil {
                    // Two-column layout
                    cellText(pair.left, visible: leftVisible)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Rectangle()
                        .fill(Color.myColors.myAccent.opacity(0.1))
                        .frame(width: 1)
                        .padding(.vertical, 8)

                    if isLocked {
                        lockedCell(visible: rightVisible)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        cellText(pair.right, visible: rightVisible)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    // Full-width left
                    cellText(pair.left, visible: leftVisible, weight: .medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Line 2: description
            if pair.description != nil {
                if isLocked {
                    lockedCellSecondary(visible: descVisible)
                } else {
                    cellTextSecondary(pair.description, visible: descVisible, isItalic: false)
                }
            }

            // Line 3: sample
            if pair.sample != nil {
                if isLocked {
                    lockedCellSecondary(visible: sampleVisible)
                } else {
                    cellTextSecondary(pair.sample, visible: sampleVisible, isItalic: true)
                }
            }

            if index < set.items.count - 1 {
                Divider().padding(.leading, 12)
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.05), value: revealedSteps)
    }

    @ViewBuilder
    private func lockedCell(visible: Bool) -> some View {
        Button {
            viewModel.pauseForUpgrade()
            showPlans = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.3))
                Text("Upgrade to unlock")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myBlue.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 6)
    }

    @ViewBuilder
    private func lockedCellSecondary(visible: Bool) -> some View {
        Button {
            viewModel.pauseForUpgrade()
            showPlans = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.3))
                Text("Upgrade to unlock")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myBlue.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 6)
    }

    @ViewBuilder
    private func cellText(_ text: String?, visible: Bool, weight: Font.Weight = .regular) -> some View {
        if let text {
            Text(text)
                .font(.body.weight(weight))
                .foregroundStyle(Color.myColors.myAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : 6)
        } else {
            Color.clear.frame(height: 48)
        }
    }

    @ViewBuilder
    private func cellTextSecondary(_ text: String?, visible: Bool, isItalic: Bool) -> some View {
        if let text, !text.isEmpty {
            Text(text)
                .font(isItalic ? .subheadline.italic() : .subheadline)
                .foregroundStyle(isItalic
                    ? Color.myColors.myAccent.opacity(0.55)
                    : Color.myColors.myAccent.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : 6)
        }
    }

    // MARK: - SRS Section

    /// Кнопки оценки — показываются только когда SRS включён и оценка ещё не выставлена
    private var srsRatingButtons: some View {
        VStack(spacing: 12) {
            if viewModel.hasRated {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.myColors.myGreen)
                    .transition(.opacity)
            } else {
                Text("How well did you know this?")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))

                HStack(spacing: 10) {
                    srsButton("Forgot", color: Color.myColors.myRed)    { viewModel.rate(.again, context: context) }
                    srsButton("Hard",   color: Color.myColors.myOrange) { viewModel.rate(.hard,  context: context) }
                    srsButton("Easy",   color: Color.myColors.myGreen)  { viewModel.rate(.easy,  context: context) }
                }
            }
        }
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.2), value: viewModel.hasRated)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Кнопка Replay — всегда видна после завершения воспроизведения
    private var replayButton: some View {
        Button { viewModel.restartSet() } label: {
            VStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 64))
                Text("Replay")
                    .font(.title3.weight(.semibold))
            }
        }
        .foregroundStyle(Color.myColors.myBlue)
        .frame(maxWidth: .infinity, alignment: .center)
        .buttonStyle(.plain)
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
            Image(systemName: "hand.tap")
            Text("Tap to resume")
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
                viewModel.audioEnabled = audioEnabled
                if !audioEnabled {
                    viewModel.stopAudioForToggleOff()
                }
            } label: {
                Image(systemName: audioEnabled ? "speaker.wave.2" : "speaker.slash")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(audioEnabled ? Color.myColors.myBlue : Color.myColors.myAccent.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }
}
