import SwiftUI
import SwiftData

// MARK: - PairsSetPlayerViewModel
//
// Стейт-машина воспроизведения одного PairsSet: пошаговый показ пар (revealedSteps),
// авто/ручной режим, озвучка (TTS) с таймингами и SRS-оценка. Перенесена из
// PairsSetPlayerView как есть — механический перенос без изменения таймингов/логики,
// чтобы не сломать чувствительные к таймингу сценарии (пары left/right в parallel-режиме,
// ожидание конца TTS перед следующим шагом).
//
// Настройки из @AppStorage (audioEnabled/ttsVoiceIdentifier/userPlan) не хранятся как
// @AppStorage внутри VM (property wrapper недоступен вне View) — View зеркалирует их сюда
// через onAppear + .onChange, чтобы асинхронные циклы (startAutoPlay и т.п.) видели
// актуальное значение на каждой итерации, а не protokol снятое один раз при старте.

@Observable
final class PairsSetPlayerViewModel {

    // MARK: Данные сета

    let set: PairsSet

    // MARK: Зеркала @AppStorage (синхронизируются View'ю)

    var audioEnabled: Bool = true
    var ttsVoiceIdentifier: String = ""
    var userPlan: AccessTier = .free

    // MARK: Состояние воспроизведения

    var animationMode: AnimationMode = .manual
    var hasStarted: Bool = false
    var isPaused: Bool = false          // пауза в auto режиме
    var isManualPaused: Bool = false    // пауза TTS в manual режиме (тап во время воспроизведения)
    var showCompletion: Bool = false    // true только после окончания аудио последней строки
    var showTapHint: Bool = false       // true после окончания TTS текущего шага в manual
    var revealedSteps: Int = 0
    private(set) var thresholds: [(leftStep: Int?, rightStep: Int?, descStep: Int?, sampleStep: Int?)] = []
    private(set) var totalSteps: Int = 0

    var showPlans: Bool = false
    var hasRated: Bool = false   // SRS оценка уже выставлена в standalone-режиме

    // MARK: Tasks

    private var autoPlayTask:   Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private var tapHintTask:    Task<Void, Never>?
    private var audioTask:      Task<Void, Never>?

    // MARK: Audio

    let audioService = AudioPlayerService()
    /// Текст для озвучки правой стороны — ставится при parallel, озвучивается после окончания левого TTS.
    private(set) var pendingRightSpeech: String? = nil
    /// true в промежутке между окончанием левого TTS и стартом правого (speechGap),
    /// чтобы waitForAudio/waitForAudioThenPause не думали что аудио уже закончилось.
    private(set) var isRightSpeechPending: Bool = false

    // MARK: Константы таймингов

    private let autoPlayDelay: Double  = 2.5  // fallback-задержка когда аудио выключено
    private let readPause: Double      = 0.8  // пауза после появления строки перед озвучкой
    private let speechGap: Double      = 0.6  // пауза между left и right TTS в parallel режиме
    private let postAudioDelay: Double = 1.4  // пауза после окончания TTS перед следующей строкой
    private var previewPairCount: Int { Constants.paywallPreviewLimit }

    // MARK: Computed

    var isComplete: Bool { revealedSteps >= totalSteps && totalSteps > 0 }
    var isPaywalled: Bool { !userPlan.canAccess(set.accessTier) }

    // MARK: Init

    init(set: PairsSet) {
        self.set = set
    }

    // MARK: - Жизненный цикл экрана

    /// Вызывается из `.onAppear`: считает пороги показа, выставляет начальный режим,
    /// стартует воспроизведение если `autoStart`, и снимает флаг `isNew` с сета.
    func onAppear(initialAnimationMode: AnimationMode, autoStart: Bool, context: ModelContext) {
        let computed = computeThresholds()
        thresholds = computed
        totalSteps = computed.reduce(0) { result, t in
            [result, t.leftStep ?? 0, t.rightStep ?? 0, t.descStep ?? 0, t.sampleStep ?? 0].max() ?? result
        }
        animationMode = initialAnimationMode
        if autoStart { startPlayback() }
        if set.isNew {
            set.isNew = false
            context.saveWithErrorHandling()
        }
    }

    /// Пользователь выключил звук через тулбар — останавливаем всё, что сейчас озвучивается.
    func stopAudioForToggleOff() {
        audioTask?.cancel()
        pendingRightSpeech = nil
        isRightSpeechPending = false
        audioService.stop()
    }

    /// Реакция на изменение `audioService.isPlaying` (parallel-режим): когда левый TTS
    /// закончился — после паузы `speechGap` озвучиваем правый.
    func handleAudioPlaybackChange(isPlayingNow: Bool) {
        guard !isPlayingNow, let text = pendingRightSpeech else { return }
        pendingRightSpeech = nil
        isRightSpeechPending = true   // gap начался — не даём waitForAudio выйти раньше времени
        guard audioEnabled else {
            isRightSpeechPending = false
            return
        }
        audioTask = Task {
            try? await Task.sleep(for: .seconds(speechGap))
            guard !Task.isCancelled, audioEnabled else {
                isRightSpeechPending = false
                return
            }
            isRightSpeechPending = false   // сбрасываем перед стартом речи
            audioService.speak(text: text, voiceIdentifier: ttsVoiceIdentifier)
        }
    }

    // MARK: - Pair Groups
    //
    // Группирует элементы сета по tag — для секционного отображения.
    // Последовательные пары с одинаковым tag образуют группу.

    var pairGroups: [(tag: String, leftTitle: String?, rightTitle: String?, indices: [Int])] {
        var result: [(tag: String, leftTitle: String?, rightTitle: String?, indices: [Int])] = []
        var i = 0
        while i < set.items.count {
            let tag = set.items[i].tag
            let groupStart = i
            var indices: [Int] = []
            while i < set.items.count && set.items[i].tag == tag {
                indices.append(i)
                i += 1
            }
            result.append((
                tag:        tag,
                leftTitle:  set.items[groupStart].leftTitle,
                rightTitle: set.items[groupStart].rightTitle,
                indices:    indices
            ))
        }
        return result
    }

    // MARK: - SRS

    func rate(_ rating: SRSRating, context: ModelContext) {
        SRSService().evaluate(set: set, rating: rating)
        context.saveWithErrorHandling()
        withAnimation { hasRated = true }
    }

    // MARK: - Interaction

    func handleTap() {
        guard hasStarted, !isComplete else { return }
        switch animationMode {
        case .automatic:
            isPaused ? resumeAutoPlay() : pauseAutoPlay()
        case .manual:
            if showTapHint {
                // TTS завершён — переходим к следующей строке
                tapHintTask?.cancel()
                withAnimation { showTapHint = false }
                withAnimation(.spring(duration: 0.4, bounce: 0.05)) { advance() }
            } else if isManualPaused {
                // Возобновляем: переигрываем текущий шаг с начала
                withAnimation { isManualPaused = false }
                speakCurrentStep()
                scheduleManualHint()
            } else {
                // TTS играет — ставим на паузу
                tapHintTask?.cancel()
                audioTask?.cancel()
                pendingRightSpeech = nil
                isRightSpeechPending = false
                audioService.stop()
                withAnimation { isManualPaused = true }
            }
        }
    }

    func startPlayback() {
        hasStarted = true
        withAnimation(.spring(duration: 0.4, bounce: 0.05)) { advance() }
        if animationMode == .automatic {
            startAutoPlay(skipFirst: true)
        }
    }

    /// Переключает режим анимации. Возвращает новое значение — вызывающая сторона (View)
    /// сама пишет его в `@AppStorage`, т.к. VM не может хранить @AppStorage напрямую.
    @discardableResult
    func switchMode(to mode: AnimationMode) -> AnimationMode {
        guard mode != animationMode else { return animationMode }
        // Если переключаемся из auto — отменяем автопроигрывание
        if animationMode == .automatic {
            autoPlayTask?.cancel()
        }
        isPaused = false
        animationMode = mode
        // Если переключились в auto во время воспроизведения — запускаем
        if mode == .automatic, hasStarted, !isComplete {
            startAutoPlay(skipFirst: true)
        }
        return mode
    }

    func pauseAutoPlay() {
        isPaused = true
        autoPlayTask?.cancel()
        audioTask?.cancel()
        pendingRightSpeech = nil
        isRightSpeechPending = false
        audioService.stop()
        log("⏸ Auto play paused at step \(revealedSteps)")
    }

    func resumeAutoPlay() {
        isPaused = false
        startAutoPlay(skipFirst: true)
        log("▶ Auto play resumed from step \(revealedSteps)")
    }

    // MARK: - Advance

    func advance() {
        guard revealedSteps < totalSteps else { return }
        revealedSteps += 1
        speakCurrentStep()
        // Manual mode: запускаем ожидание TTS → показываем подсказку.
        // Раньше это делалось в View'вском .onChange(of: revealedSteps) — перенесено сюда,
        // т.к. это прямое следствие продвижения шага, а не отдельный UI-эффект.
        if animationMode == .manual && !isComplete {
            scheduleManualHint()
        }
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
                withAnimation { self.showCompletion = true }
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

        // Ждём окончания всего аудио: левая сторона + правая (pendingRightSpeech / isRightSpeechPending)
        while audioService.isPlaying || pendingRightSpeech != nil || isRightSpeechPending {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
        }

        // Пауза после окончания речи — пользователь успевает прочитать и осмыслить
        try? await Task.sleep(for: .seconds(postAudioDelay))
    }

    /// Ждёт окончания TTS без финальной паузы — для показа tapHint в manual mode.
    private func waitForAudio() async {
        guard !Task.isCancelled else { return }
        guard audioEnabled else { return }

        try? await Task.sleep(for: .seconds(readPause + 0.3))
        guard !Task.isCancelled else { return }

        var attempts = 0
        while !audioService.isPlaying && attempts < 15 {
            try? await Task.sleep(for: .milliseconds(100))
            attempts += 1
            guard !Task.isCancelled else { return }
        }

        while audioService.isPlaying || pendingRightSpeech != nil || isRightSpeechPending {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
        }

        // Короткая пауза перед появлением подсказки
        try? await Task.sleep(for: .seconds(0.3))
    }

    /// Запускает таск, который показывает tapHint после окончания TTS (только manual mode).
    private func scheduleManualHint() {
        tapHintTask?.cancel()
        showTapHint = false
        tapHintTask = Task {
            await waitForAudio()
            guard !Task.isCancelled, !isComplete else { return }
            withAnimation { showTapHint = true }
        }
    }

    /// Ставит воспроизведение на паузу перед переходом на экран Plans.
    /// После возврата пользователь видит resumeHint и может продолжить.
    func pauseForUpgrade() {
        guard hasStarted, !isComplete else { return }
        switch animationMode {
        case .automatic:
            guard !isPaused else { return }
            pauseAutoPlay()
        case .manual:
            guard !isManualPaused, !showTapHint else { return }
            tapHintTask?.cancel()
            audioTask?.cancel()
            pendingRightSpeech = nil
            isRightSpeechPending = false
            audioService.stop()
            withAnimation { showTapHint = false; isManualPaused = true }
        }
    }

    /// Ждёт завершения последней строки в manual-режиме, затем показывает SRS-блок.
    /// Раньше запускалось из View'вского `.onChange(of: isComplete)`.
    func scheduleCompletionIfNeeded() {
        guard isComplete, animationMode == .manual else { return }
        completionTask?.cancel()
        completionTask = Task {
            await waitForAudioThenPause()
            guard !Task.isCancelled else { return }
            withAnimation { self.showCompletion = true }
        }
    }

    func cancelAllTasks() {
        autoPlayTask?.cancel()
        completionTask?.cancel()
        tapHintTask?.cancel()
        audioTask?.cancel()
        pendingRightSpeech = nil
        isRightSpeechPending = false
        audioService.stop()
        isPaused = false
        isManualPaused = false
        showTapHint = false
    }

    func restartSet() {
        autoPlayTask?.cancel()
        completionTask?.cancel()
        tapHintTask?.cancel()
        audioTask?.cancel()
        pendingRightSpeech = nil
        isRightSpeechPending = false
        audioService.stop()
        isPaused = false
        isManualPaused = false
        showCompletion = false
        showTapHint = false
        hasRated = false
        // hasStarted остаётся true — стартовый экран показывается только один раз
        withAnimation(.spring(duration: 0.3)) { revealedSteps = 0 }
        // Запускаем воспроизведение сразу без стартового экрана
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            withAnimation(.spring(duration: 0.4, bounce: 0.05)) { self.advance() }
            if self.animationMode == .automatic {
                self.startAutoPlay(skipFirst: true)
            }
        }
        log("↩ Set restarted")
    }

    // MARK: - Audio / TTS

    /// Определяет текст(ы) для текущего шага и запускает TTS с паузой readPause.
    ///
    /// Матрица шагов:
    ///   parallel + right != nil:  leftStep == rightStep → primary=left, secondary=right (очередь)
    ///   sequential left:          leftStep  → primary=left
    ///   sequential right:         rightStep → primary=right
    ///   descStep:                 primary=description
    ///   sampleStep:                primary=sample
    ///
    /// secondary (правый в parallel) ставится в pendingRightSpeech и озвучивается
    /// через handleAudioPlaybackChange после окончания левого TTS.
    private func speakCurrentStep() {
        audioTask?.cancel()
        pendingRightSpeech = nil
        isRightSpeechPending = false
        guard audioEnabled else { return }

        var primaryText:   String? = nil
        var secondaryText: String? = nil   // только для parallel left+right

        for (index, thresh) in thresholds.enumerated() {
            guard index < set.items.count else { continue }
            let pair = set.items[index]
            let isLocked = isPaywalled && index >= previewPairCount

            if thresh.leftStep == revealedSteps {
                // Left-шаг (sequential) ИЛИ общий left+right шаг (parallel)
                primaryText = pair.left
                // Parallel: leftStep == rightStep → ставим right в очередь как secondary
                if thresh.rightStep == revealedSteps, !isLocked {
                    secondaryText = pair.right
                }
            } else if thresh.rightStep == revealedSteps, !isLocked {
                // Sequential: right на своём отдельном шаге
                primaryText = pair.right
            } else if thresh.descStep == revealedSteps, !isLocked {
                primaryText = pair.description
            } else if thresh.sampleStep == revealedSteps, !isLocked {
                primaryText = pair.sample
            }
        }

        let voiceId = ttsVoiceIdentifier

        audioTask = Task { [weak self] in
            guard let self else { return }
            // Пауза: даём пользователю увидеть текст глазами
            try? await Task.sleep(for: .seconds(self.readPause))
            guard !Task.isCancelled, self.audioEnabled else { return }

            if let text = primaryText, !text.isEmpty {
                // speak() внутри вызывает stop() → isPlaying = false → handleAudioPlaybackChange срабатывает.
                // pendingRightSpeech ставим ПОСЛЕ speak(), иначе onChange подхватит его
                // раньше времени (до начала воспроизведения левого слова).
                self.audioService.speak(text: text, voiceIdentifier: voiceId)
                if let right = secondaryText, !right.isEmpty {
                    self.pendingRightSpeech = right
                }
            }
        }
    }

    // MARK: - Helpers

    func isPairVisible(at index: Int) -> Bool {
        guard index < thresholds.count else { return false }
        let t = thresholds[index]
        return (t.leftStep.map   { revealedSteps >= $0 } ?? false)
            || (t.rightStep.map  { revealedSteps >= $0 } ?? false)
            || (t.descStep.map   { revealedSteps >= $0 } ?? false)
            || (t.sampleStep.map { revealedSteps >= $0 } ?? false)
    }

    func isLocked(at index: Int) -> Bool {
        isPaywalled && index >= previewPairCount
    }

    private func computeThresholds() -> [(leftStep: Int?, rightStep: Int?, descStep: Int?, sampleStep: Int?)] {
        var result: [(leftStep: Int?, rightStep: Int?, descStep: Int?, sampleStep: Int?)] = []
        var step = 0

        for pair in set.items {
            var leftStep:   Int? = nil
            var rightStep:  Int? = nil
            var descStep:   Int? = nil
            var sampleStep: Int? = nil

            if pair.right != nil && pair.displayMode == .parallel {
                // Parallel: left + right появляются вместе на одном шаге
                step += 1
                if pair.left  != nil { leftStep  = step }
                rightStep = step
                if pair.description != nil { step += 1; descStep   = step }
                if pair.sample      != nil { step += 1; sampleStep = step }
            } else {
                // Sequential (или нет right): каждое поле — отдельный шаг
                if pair.left        != nil { step += 1; leftStep   = step }
                if pair.right       != nil { step += 1; rightStep  = step }
                if pair.description != nil { step += 1; descStep   = step }
                if pair.sample      != nil { step += 1; sampleStep = step }
            }

            result.append((leftStep, rightStep, descStep, sampleStep))
        }
        return result
    }
}
