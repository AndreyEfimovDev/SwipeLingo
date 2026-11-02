//
//  DictionaryLookupViewModel.swift
//  SwipeLingo
//
//  Создано Andrey Efimov 10.09.2026.
//

import SwiftUI
import SwiftData
import Translation

// MARK: - DictionaryLookupViewModel

@Observable
final class DictionaryLookupViewModel {

    // MARK: Phase

    enum Phase {
        case loading
        case loaded(DictionaryEntry)
        case error(String)
    }

    // MARK: State

    private(set) var phase: Phase = .loading

    /// Показывает закэшированную запись сразу (вызывается из .task View до сетевого запроса).
    func showCached(_ entry: DictionaryEntry) {
        phase = .loaded(entry)
        cachedEntryIsFromMW = DictionaryService.isMerriamWebsterAudioURL(entry.audioURL)
    }

    /// Кэш карточки точно получен от Merriam-Webster (источник в карточке не хранится — судим по аудио).
    /// Только такой кэш защищён от записи Free: кэш, записанный из Free, свежий Free может заменить.
    private var cachedEntryIsFromMW = false
    /// Общий на всё приложение экземпляр, передаётся из composition root — см.
    /// комментарий в AppDependencies.swift (позволяет stop() гасить звук с ДРУГОГО экрана).
    let audioService: AudioPlayerService

    /// Сколько `load` выполняется сейчас. Счётчик, а не Bool: при перезапуске (повторное «Try Again»)
    /// отменённая загрузка завершается позже новой, и её `defer` не должен гасить признак новой.
    private var activeLoads = 0

    /// Идёт поиск (хотя бы один из источников ещё не ответил).
    var isRefreshing: Bool { activeLoads > 0 }

    /// Сколько раз на экране сменилась запись свежими данными. Триггер кэширования во View:
    /// записей за один поиск может быть две (Free, затем MW), поэтому одноразового Bool мало.
    private(set) var updateCount = 0

    /// Запись, которую View должен сохранить в кэш карточки; `nil` — кэшировать нечего (политика кэша ниже).
    private(set) var entryToCache: DictionaryEntry?

    /// Подпись у спиннера, пока на экране ещё не лучшая запись: что именно догружается.
    /// `nil` — спиннер не нужен (поиск окончен или уже показана запись Merriam-Webster).
    var refreshStatusText: String? {
        guard isRefreshing, case .loaded(let entry) = phase else { return nil }
        switch entry.source {
        case .merriamWebster?: return nil
        case .freeDictionary?: return "Looking for fuller definitions and examples…"
        case nil:              return "Loading full definitions…"
        }
    }

    // MARK: Service

    private let service: DictionaryLookingUp

    // MARK: Init

    /// - Parameter cachedEntry: кэш карточки — экран стартует сразу с ним, без кадра полноэкранного спиннера
    ///   (если показывать кэш из `.task`, первый кадр успевает отрисоваться в `.loading`).
    init(audioService: AudioPlayerService, service: DictionaryLookingUp = DictionaryService(), cachedEntry: DictionaryEntry? = nil) {
        self.audioService = audioService
        self.service = service
        if let cachedEntry {
            showCached(cachedEntry)
        }
    }

    // MARK: Actions

    /// Загружает свежую запись; результаты Free и MW приходят по мере готовности (Free → MW).
    ///
    /// Правила:
    /// - Уже показанная запись (кэш `showCached` или результат прошлой загрузки) НЕ сбрасывается в
    ///   спиннер: раньше `phase = .loading` стирал кэш сразу после показа, и даже для сохранённого
    ///   слова приходилось ждать сеть.
    /// - Показанную запись MW (свежую или кэш, точно полученный от MW) заменяет на экране только MW;
    ///   кэш неизвестного происхождения может заменить и Free (см. `apply`).
    /// - Если свежего не пришло (сбой, пустой поток), остаётся показанное; ошибка — только на пустом экране.
    /// - В кэш карточки (`entryToCache`) идёт то, что показано: MW — всегда, Free — когда он заменил
    ///   пустой экран, незащищённый кэш или другой Free.
    func load(word: String) async {
        if case .loaded = phase {
            // показанное оставляем
        } else {
            phase = .loading
        }
        entryToCache = nil   // не отдавать View запись прошлой загрузки

        activeLoads += 1
        defer { activeLoads -= 1 }

        var failureMessage: String?
        do {
            for try await entry in service.lookupUpdates(word: word) {
                if Task.isCancelled { break }
                apply(entry)
            }
        } catch {
            if !DictionaryService.isCancellation(error) {
                log("dictionary lookup failed: \(error.localizedDescription)", level: .warning)
            }
            failureMessage = error.localizedDescription
        }

        // Экран так и остался пустым (ни одной записи, кэша не было) — показываем ошибку, а не вечный
        // спиннер. При отмене (экран закрыт) ничего не пишем.
        if case .loading = phase, !Task.isCancelled {
            phase = .error(failureMessage ?? DictionaryService.DictionaryError.notFound.localizedDescription)
        }
    }

    /// Применяет очередную запись по правилам приоритета источников.
    private func apply(_ entry: DictionaryEntry) {
        var shownEntry: DictionaryEntry?
        if case .loaded(let shown) = phase { shownEntry = shown }

        if let shown = shownEntry {
            // Free (резервный источник: определения хуже, порядок значений другой) не вытесняет
            // показанную запись MW — свежую или кэш, точно полученный от MW, — иначе при недоступном MW
            // хорошая запись заменялась бы худшей. Кэш неизвестного происхождения (записанный из Free
            // или без аудио) не защищён: иначе однострочный кэш Free держался бы против полного свежего
            // Free, пока MW недоступен. Кэш без определений (`meanings` пуст) защищать тоже нечего.
            let shownIsFromMW: Bool
            switch shown.source {
            case .merriamWebster?: shownIsFromMW = true
            case .freeDictionary?: shownIsFromMW = false
            case nil:              shownIsFromMW = cachedEntryIsFromMW
            }
            let shownIsProtected = shownIsFromMW && !shown.meanings.isEmpty
            if shownIsProtected, entry.source != .merriamWebster {
                log("dictionary: fallback entry ignored, better entry is shown")
                return
            }
        }

        let merged = Self.fillingEmptyFields(of: entry, from: shownEntry)
        phase = .loaded(merged)
        entryToCache = merged
        updateCount += 1
        // На экране больше не кэш — его вердикт о происхождении к новой записи не относится.
        cachedEntryIsFromMW = false
    }

    /// Запись иногда приходит без транскрипции/аудио — не затираем ими уже имеющиеся непустые значения
    /// (из кэша), иначе пользователь теряет данные, которые у него были.
    ///
    /// Аудио наследуется только от записи того же происхождения: по хосту аудио кэш карточки судят, от MW
    /// ли он (`isMerriamWebsterAudioURL`). Если Free унаследует аудио MW, его определения при следующем
    /// открытии сойдут за MW и будут защищены от свежего Free; если MW унаследует аудио Free — наоборот.
    private static func fillingEmptyFields(of entry: DictionaryEntry, from previous: DictionaryEntry?) -> DictionaryEntry {
        guard let previous else { return entry }
        let entryIsMW         = entry.source == .merriamWebster
        let previousAudioIsMW = DictionaryService.isMerriamWebsterAudioURL(previous.audioURL)
        let canInheritAudio   = entry.audioURL.isEmpty && previousAudioIsMW == entryIsMW
        return DictionaryEntry(
            word:          entry.word,
            transcription: entry.transcription.isEmpty ? previous.transcription : entry.transcription,
            audioURL:      canInheritAudio ? previous.audioURL : entry.audioURL,
            meanings:      entry.meanings,
            source:        entry.source
        )
    }

    func toggleAudio(urlString: String) {
        if audioService.isPlaying {
            audioService.stop()
        } else {
            audioService.play(urlString: urlString)
        }
    }

    // MARK: - Card mutation
    //
    // Context и card передаются явно — тот же паттерн, что в SRSService / PileBuilderViewModel.
    // do-catch вместо try?, чтобы ошибки были видны в консоли.

    /// Ключи примеров, уже добавленных в этой сессии — управляет индикатором ✓ в UI.
    var addedItems: Set<String> = []

    func addDefinition(
        _ definition: DictionaryDefinition,
        to card: Card,
        context: ModelContext,
        translatedExample: String? = nil
    ) {
        var samplesEN   = card.userSampleEN
        var samplesItem = card.userSampleItem
        var changed = false

        let allEN = card.allSampleEN

        if let example = definition.example, !allEN.contains(example) {
            samplesEN.append(example)
            samplesItem.append(translatedExample ?? "")
            changed = true
            log("[+] example: \"\(example.prefix(60))\"")
            if let t = translatedExample { log("    translation: \"\(t.prefix(60))\"") }
        }

        guard changed else {
            log("[+] already present — skipped")
            return
        }

        card.userSampleEN   = samplesEN
        card.userSampleItem = samplesItem
        save(context: context)
        if let example = definition.example { addedItems.insert(example) }
    }

    func addSynonym(_ synonym: String, to card: Card, context: ModelContext) {
        var syns = card.synonyms
        guard !syns.contains(synonym) else {
            log("[+] '\(synonym)' already present — skipped")
            return
        }
        syns.append(synonym)
        card.synonyms = syns
        save(context: context)
        log("[+] synonym: '\(synonym)'")
    }

    private func save(context: ModelContext) {
        context.saveWithErrorHandling()
    }
}


