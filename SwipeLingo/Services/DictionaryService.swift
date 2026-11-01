import Foundation

// MARK: - DictionaryService
//
// Запрашивает Merriam-Webster Learner's Dictionary (лучше определения + примеры) и Free Dictionary API
// (dictionaryapi.dev) ПАРАЛЛЕЛЬНО и отдаёт результаты по мере прихода: Free обычно приходит за доли секунды,
// MW — медленнее или не приходит вовсе (с устройства бывают таймауты), поэтому ждать MW перед показом
// первого результата незачем. MW приоритетнее: если он пришёл, он заменяет Free.
// Для вызывающих, которым нужен один итог (автозаполнение, Admin), — `lookup(word:)`: последовательно MW → Free,
// без лишнего запроса к Free, когда MW ответил полностью.
// Безопасно вызывать из контекста @MainActor — URLSession.data внутри приостанавливается вне MainActor.

/// Поиск слова в словаре. Протокол нужен, чтобы ViewModel можно было проверить на подменном
/// источнике (без сети); боевая реализация — `DictionaryService`.
protocol DictionaryLookingUp {
    /// Результаты поиска по мере прихода (каждый следующий лучше предыдущего: Free → MW).
    /// Поток завершается без ошибки, если пришёл хотя бы один результат; с ошибкой — только если не пришёл ни один.
    /// Отмена потребителя отменяет оба сетевых запроса.
    func lookupUpdates(word: String) -> AsyncThrowingStream<DictionaryEntry, Error>

    /// Один итоговый результат — для вызывающих, которым не нужен промежуточный показ (автозаполнение, Admin).
    /// При отмене вызывающего бросает `CancellationError`.
    func lookup(word: String) async throws -> DictionaryEntry
}

extension DictionaryLookingUp {
    /// Реализация по умолчанию — через поток: дожидается его окончания и возвращает лучший (последний) результат.
    /// `DictionaryService` переопределяет её последовательной схемой (см. там).
    func lookup(word: String) async throws -> DictionaryEntry {
        var best: DictionaryEntry?
        do {
            for try await entry in lookupUpdates(word: word) {
                best = entry
            }
        } catch {
            // При отмене вызывающего поток мог успеть завершиться ошибкой отменённого запроса
            // (URLError.cancelled) — для вызывающего это отмена, а не сетевая ошибка.
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
        try Task.checkCancellation()
        guard let best else { throw DictionaryService.DictionaryError.notFound }
        return best
    }
}

struct DictionaryService: DictionaryLookingUp {

    private static let mwBaseURL      = "https://www.dictionaryapi.com/api/v3/references/learners/json/"
    private static let freeBaseURL    = "https://api.dictionaryapi.dev/api/v2/entries/en/"

    /// Таймаут одного запроса, секунды. У `URLSession.shared` он 60 с — зависший Merriam-Webster
    /// держал бы экран словаря до минуты, прежде чем сработал откат на Free Dictionary.
    /// Значение подобрано на глаз (на устройстве MW отвечал ~3 с); при необходимости подправить.
    static let requestTimeout: TimeInterval = 8

    /// Сессия для словарных запросов с коротким таймаутом. Одна на всё приложение: каждый
    /// `DictionaryService()` переиспользует её, а не плодит новые сессии.
    static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = requestTimeout
        config.timeoutIntervalForResource = requestTimeout * 2
        return URLSession(configuration: config)
    }()

    private let session: URLSession

    /// - Parameter session: сессия для запросов; в тестах подменяется на сессию с `URLProtocol`-заглушкой.
    init(session: URLSession = DictionaryService.defaultSession) {
        self.session = session
    }

    // MARK: - Errors

    enum DictionaryError: LocalizedError {
        case invalidWord
        case notFound
        case networkError(Error)
        case decodingError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidWord:
                return "Invalid word"
            case .notFound:
                return "Word not found in dictionary"
            case .networkError(let error):
                return error.localizedDescription
            case .decodingError(let error):
                return "Data error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Public API

    /// Один итог: сначала MW; Free — только если MW не ответил или пришёл без транскрипции (тогда она берётся
    /// из Free). Параллельный режим здесь почти ничего не даёт — итог всё равно ждёт MW, а при его недоступности
    /// обе схемы упираются в таймаут, — зато Free не получает запрос на каждое слово (пакетный импорт в Admin).
    func lookup(word: String) async throws -> DictionaryEntry {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DictionaryError.invalidWord }

        let mwEntry: DictionaryEntry
        do {
            mwEntry = try await fetchMW(word: trimmed)
        } catch {
            try Task.checkCancellation()
            if !Self.isCancellation(error) {
                log("MW lookup failed for '\(trimmed)': \(error.localizedDescription)", level: .warning)
            }
            do {
                return try await fetchFreeDictionary(word: trimmed)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw error
            }
        }

        guard mwEntry.transcription.isEmpty else { return mwEntry }
        let freeEntry = try? await fetchFreeDictionary(word: trimmed)
        try Task.checkCancellation()
        return Self.bestEntry(mw: mwEntry, free: freeEntry) ?? mwEntry
    }

    /// Запускает MW и Free одновременно и отдаёт лучший из пришедших результатов по мере прихода.
    func lookupUpdates(word: String) -> AsyncThrowingStream<DictionaryEntry, Error> {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        return AsyncThrowingStream { continuation in
            guard !trimmed.isEmpty else {
                continuation.finish(throwing: DictionaryError.invalidWord)
                return
            }
            let task = Task { await runLookup(word: trimmed, continuation: continuation) }
            // Потребитель ушёл (закрыли экран) — отменяем оба запроса, а не ждём их таймаута.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Итог одного из двух параллельных запросов.
    private enum Outcome {
        case mw(Result<DictionaryEntry, Error>)
        case free(Result<DictionaryEntry, Error>)
    }

    private func runLookup(word: String, continuation: AsyncThrowingStream<DictionaryEntry, Error>.Continuation) async {
        var mwEntry: DictionaryEntry?
        var freeEntry: DictionaryEntry?
        var mwError: Error?
        var freeError: Error?
        var lastYielded: DictionaryEntry?

        await withTaskGroup(of: Outcome.self) { group in
            group.addTask { .mw(await Self.capture { try await self.fetchMW(word: word) }) }
            group.addTask { .free(await Self.capture { try await self.fetchFreeDictionary(word: word) }) }

            for await outcome in group {
                switch outcome {
                case .mw(.success(let entry)):    mwEntry = entry
                case .free(.success(let entry)):  freeEntry = entry
                case .mw(.failure(let error)):
                    mwError = error
                    // Только описание: в самом `error` лежит URL с ключом MW. Отмена (экран закрыт,
                    // MW уже не нужен) — не сбой.
                    if !Self.isCancellation(error) {
                        log("MW lookup failed for '\(word)': \(error.localizedDescription)", level: .warning)
                    }
                case .free(.failure(let error)):  freeError = error
                }

                // Отдаём результат, только если он отличается от уже отданного: Free, пришедший
                // после MW с транскрипцией, ничего не меняет. Сравнение по источнику и транскрипции
                // достаточно, пока `bestEntry` дополняет у MW только транскрипцию; если начнёт
                // подмешивать ещё поля из Free — расширить условие, иначе обновления будут глотаться.
                guard let best = Self.bestEntry(mw: mwEntry, free: freeEntry),
                      best.source != lastYielded?.source || best.transcription != lastYielded?.transcription
                else { continue }
                lastYielded = best
                continuation.yield(best)

                // MW с транскрипцией — лучшее, что можно получить: поздний Free ничего не изменит,
                // так что не ждём его (зависший Free держал бы поток и `isRefreshing` до таймаута).
                if best.source == .merriamWebster, !best.transcription.isEmpty {
                    group.cancelAll()
                }
            }
        }

        if lastYielded != nil {
            continuation.finish()
            return
        }
        // Ни один источник не дал результата. Ошибку Free предпочитаем: она совпадает с прежним поведением (откат на Free).
        let failure = freeError ?? mwError ?? DictionaryError.notFound
        if !Self.isCancellation(failure) {
            log("dictionary lookup failed for '\(word)': \(failure.localizedDescription)", level: .warning)
        }
        continuation.finish(throwing: failure)
    }

    /// Ошибка — следствие отмены (закрыли экран, или запрос отменён, потому что уже пришёл MW),
    /// а не сбой источника: в логах такие не показываем.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if case .networkError(let underlying)? = error as? DictionaryError {
            return isCancellation(underlying)
        }
        return (error as? URLError)?.code == .cancelled
    }

    private static func capture(_ work: () async throws -> DictionaryEntry) async -> Result<DictionaryEntry, Error> {
        do {
            return .success(try await work())
        } catch {
            return .failure(error)
        }
    }

    /// Лучший из доступных результатов: MW приоритетнее Free. MW иногда приходит без транскрипции —
    /// тогда она берётся из Free (определения и аудио остаются от MW).
    static func bestEntry(mw: DictionaryEntry?, free: DictionaryEntry?) -> DictionaryEntry? {
        guard let mw else { return free }
        guard mw.transcription.isEmpty, let free, !free.transcription.isEmpty else { return mw }
        return DictionaryEntry(
            word:          mw.word,
            transcription: free.transcription,
            audioURL:      mw.audioURL,
            meanings:      mw.meanings,
            source:        .merriamWebster
        )
    }

    // MARK: - Merriam-Webster

    private func fetchMW(word: String) async throws -> DictionaryEntry {
        guard
            let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: Self.mwBaseURL + encoded + "?key=" + Secrets.merriamWebsterKey)
        else { throw DictionaryError.invalidWord }

        let data: Data
        do {
            let (responseData, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw DictionaryError.notFound
            }
            data = responseData
        } catch let e as DictionaryError { throw e
        } catch { throw DictionaryError.networkError(error) }

        // Ответ MW — это [Any]: реальные записи это объекты, а предложения-подсказки — строки.
        // Фильтруем только объекты, затем декодируем.
        guard
            let rawArray  = try? JSONSerialization.jsonObject(with: data) as? [Any],
            let objects   = rawArray.compactMap({ $0 as? [String: Any] }) as [[String: Any]]?,
            !objects.isEmpty
        else { throw DictionaryError.notFound }

        let filteredData = try JSONSerialization.data(withJSONObject: objects)
        let entries: [MWEntry]
        do {
            entries = try JSONDecoder().decode([MWEntry].self, from: filteredData)
        } catch {
            throw DictionaryError.decodingError(error)
        }

        // Статья выбирается по совпадению с запросом, а не первая попавшаяся: на фразу MW Learner's
        // отдаёт статью главного слова («look up» → «look») или вовсе другого («run out of» → «patience»).
        // Порядок: заголовок → run-on фраза внутри статьи → форма слова из `stems`. Фраза идёт раньше
        // `stems`, потому что в `stems` у «look» есть и «look after» — по ним нашлось бы значение «look».
        let query = Self.normalizedMWTerm(word)
        let withDefinitions = entries.indices.filter { !entries[$0].shortdef.isEmpty }

        if let index = withDefinitions.first(where: { entries[$0].hwi?.hw.map(Self.normalizedMWTerm) == query }) {
            return makeMWEntry(word: word, entry: entries[index], raw: objects[index])
        }
        if let phrase = mwPhraseMeaning(query, in: objects) {
            log("MW '\(word)' → run-on phrase, defs: \(phrase.definitions.count)")
            return DictionaryEntry(word: word, transcription: "", audioURL: "",
                                   meanings: [phrase], source: .merriamWebster)
        }
        if let index = withDefinitions.first(where: {
            entries[$0].meta?.stems?.contains { Self.normalizedMWTerm($0) == query } == true
        }) {
            return makeMWEntry(word: word, entry: entries[index], raw: objects[index])
        }
        log("MW '\(word)' → no entry for this headword")
        throw DictionaryError.notFound
    }

    /// Приводит заголовок, фразу или запрос MW к виду для сравнения: без слогоделителей `*`,
    /// в нижнем регистре, с одиночными пробелами.
    private static func normalizedMWTerm(_ term: String) -> String {
        term.replacingOccurrences(of: "*", with: "")
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Собирает запись словаря из статьи MW: краткие определения, произношение и первый пример статьи.
    ///
    /// - Parameters:
    ///   - word: Запрос пользователя — попадает в запись как есть.
    ///   - entry: Декодированная статья.
    ///   - raw: Та же статья как словарь — для примеров из `def`, которые не декодируются через Codable.
    private func makeMWEntry(word: String, entry: MWEntry, raw: [String: Any]) -> DictionaryEntry {
        let transcription = entry.hwi?.prs?.first(where: { $0.mw != nil })?.mw ?? ""
        let audioURL      = entry.hwi?.prs?.compactMap(\.sound?.audio).first.map(mwAudioURL) ?? ""
        let partOfSpeech  = entry.fl ?? ""
        let example       = extractFirstExample(from: raw)

        let definitions = entry.shortdef.enumerated().map { i, text in
            DictionaryDefinition(text: text, example: i == 0 ? example : nil)
        }
        let meaning = DictionaryMeaning(partOfSpeech: partOfSpeech,
                                        definitions: definitions,
                                        synonyms: [])

        log("MW '\(word)' → fl: \(partOfSpeech), defs: \(entry.shortdef.count), audio: \(audioURL)")
        return DictionaryEntry(word: word,
                               transcription: transcription,
                               audioURL: audioURL,
                               meanings: [meaning],
                               source: .merriamWebster)
    }

    /// Строит URL MW audio CDN по имени звукового файла.
    /// Правила поддиректорий: https://dictionaryapi.com/products/json#sec-2.prs
    private func mwAudioURL(_ audio: String) -> String {
        let subdir: String
        if audio.hasPrefix("bix")           { subdir = "bix" }
        else if audio.hasPrefix("gg")       { subdir = "gg" }
        else if audio.first?.isNumber == true { subdir = "number" }
        else                                { subdir = String(audio.prefix(1)) }
        return "https://\(Self.mwAudioHost)/audio/prons/en/us/mp3/\(subdir)/\(audio).mp3"
    }

    private static let mwAudioHost = "media.merriam-webster.com"

    /// Аудио с CDN Merriam-Webster — признак, что запись (в т.ч. сохранённая в кэше карточки, где источник
    /// не хранится) получена от MW. Пустая строка или другой хост — источник не доказан.
    static func isMerriamWebsterAudioURL(_ urlString: String) -> Bool {
        URL(string: urlString)?.host == mwAudioHost
    }

    /// Извлекает первый пример-иллюстрацию (example sentence) из `def/sseq/dt/vis` одной статьи MW.
    /// Использует JSONSerialization, потому что `sseq` — глубоко вложенный массив со смешанными типами.
    private func extractFirstExample(from entry: [String: Any]) -> String? {
        guard let defs = entry["def"] as? [[String: Any]] else { return nil }
        for def in defs {
            guard let sseq = def["sseq"] as? [[[Any]]] else { continue }
            for senseSeq in sseq {
                for senseItem in senseSeq {
                    guard senseItem.count >= 2,
                          (senseItem[0] as? String) == "sense",
                          let content = senseItem[1] as? [String: Any],
                          let dt      = content["dt"] as? [[Any]] else { continue }
                    for dtItem in dt {
                        guard dtItem.count >= 2,
                              (dtItem[0] as? String) == "vis",
                              let visItems = dtItem[1] as? [[String: Any]],
                              let text     = visItems.first?["t"] as? String else { continue }
                        return stripMWMarkup(text)
                    }
                }
            }
        }
        return nil
    }

    /// Ищет устойчивое выражение среди run-on фраз (`dros`) статей ответа.
    ///
    /// Отдельной статьи на фразу («look up», «by the way») у MW Learner's нет — её значение лежит
    /// внутри статьи главного слова. Совпадение — точное, после `normalizedMWTerm`.
    ///
    /// - Returns: Значение фразы с определениями и примерами смыслов или `nil`, если фразы нет
    ///   или у неё не нашлось ни одного определения.
    private func mwPhraseMeaning(_ query: String, in objects: [[String: Any]]) -> DictionaryMeaning? {
        for object in objects {
            guard let dros = object["dros"] as? [[String: Any]] else { continue }
            for dro in dros {
                guard let drp  = dro["drp"] as? String, Self.normalizedMWTerm(drp) == query,
                      let defs = dro["def"] as? [[String: Any]] else { continue }
                let definitions = mwSenseDefinitions(in: defs)
                guard !definitions.isEmpty else { continue }
                return DictionaryMeaning(partOfSpeech: dro["gram"] as? String ?? "phrase",
                                         definitions: definitions,
                                         synonyms: [])
            }
        }
        return nil
    }

    /// Определения смыслов из `def/sseq`: текст смысла и его первый пример.
    ///
    /// У части фраз текста в `dt` нет — значение дано пояснением об употреблении (`uns`,
    /// у «by the way»); тогда текст и пример берутся из него.
    private func mwSenseDefinitions(in defs: [[String: Any]]) -> [DictionaryDefinition] {
        var definitions: [DictionaryDefinition] = []
        for def in defs {
            guard let sseq = def["sseq"] as? [[[Any]]] else { continue }
            for senseSeq in sseq {
                for senseItem in senseSeq {
                    guard senseItem.count >= 2,
                          (senseItem[0] as? String) == "sense",
                          let content = senseItem[1] as? [String: Any],
                          let dt      = content["dt"] as? [[Any]] else { continue }
                    // Пояснение `uns` — массив вложенных dt: ["uns", [[["text", …], ["vis", …]]]]
                    let usageNotes = dt
                        .filter { $0.count >= 2 && ($0[0] as? String) == "uns" }
                        .compactMap { $0[1] as? [[[Any]]] }
                        .flatMap { $0.joined() }
                    let items = dt + usageNotes

                    guard let rawText = items.first(where: { ($0.first as? String) == "text" && $0.count >= 2 })?[1] as? String
                    else { continue }
                    // "{bc}" в начале смысла превращается в ": " — у определения он лишний
                    var text = stripMWMarkup(rawText)
                    while text.hasPrefix(":") { text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces) }
                    guard !text.isEmpty else { continue }

                    let example = items
                        .first(where: { ($0.first as? String) == "vis" && $0.count >= 2 })
                        .flatMap { ($0[1] as? [[String: Any]])?.first?["t"] as? String }
                        .map(stripMWMarkup)
                    definitions.append(DictionaryDefinition(text: text, example: example))
                }
            }
        }
        return definitions
    }

    /// Убирает инлайн-разметку MW, оставляя чистый читаемый текст.
    /// напр. "{it}word{/it}" → "word", "{bc}" → ": ", "{d_link|word|id}" → "word"
    private func stripMWMarkup(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "{bc}",    with: ": ")
        result = result.replacingOccurrences(of: "{ldquo}", with: "\u{201C}")
        result = result.replacingOccurrences(of: "{rdquo}", with: "\u{201D}")
        result = result.replacingOccurrences(of: "{amp}",   with: "&")

        // {tag|display|id} или {tag|display} → отображаемый текст (первый сегмент до |)
        let pipePattern = "\\{[a-z_]+\\|([^|{}]+)(?:\\|[^{}]*)?\\}"
        if let regex = try? NSRegularExpression(pattern: pipePattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range,
                                                    withTemplate: "$1")
        }

        // Убираем оставшиеся {tags}
        let tagPattern = "\\{[^{}]*\\}"
        if let regex = try? NSRegularExpression(pattern: tagPattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range,
                                                    withTemplate: "")
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Free Dictionary (резервный вариант)

    private func fetchFreeDictionary(word: String) async throws -> DictionaryEntry {
        guard
            let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: Self.freeBaseURL + encoded)
        else { throw DictionaryError.invalidWord }

        let data: Data
        do {
            let (responseData, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                throw DictionaryError.notFound
            }
            data = responseData
        } catch let e as DictionaryError { throw e
        } catch { throw DictionaryError.networkError(error) }

        do {
            let entries = try JSONDecoder().decode([APIEntry].self, from: data)
            guard let first = entries.first else { throw DictionaryError.notFound }
            var entry = first.toDictionaryEntry()
            entry.source = .freeDictionary
            return entry
        } catch let e as DictionaryError { throw e
        } catch { throw DictionaryError.decodingError(error) }
    }
}
