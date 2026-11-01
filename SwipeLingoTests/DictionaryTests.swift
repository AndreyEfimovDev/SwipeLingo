import XCTest
@testable import SwipeLingo

// MARK: - DictionaryServiceTests
//
// DictionaryService.lookupUpdates запускает Merriam-Webster (MW) и Free Dictionary ПАРАЛЛЕЛЬНО и отдаёт
// результаты по мере прихода (Free → MW):
//   • MW приоритетнее: пришёл после Free — заменяет его; пришёл раньше — поздний Free ничего не меняет
//   • MW с транскрипцией — финал: медленный Free не ждём (поток завершается сразу)
//   • один источник упал — поток отдаёт результат второго, без ошибки
//   • MW без транскрипции — транскрипция берётся из Free (при любом порядке прихода), остальное от MW
//   • оба упали — ошибка Free (она приоритетна), пустое слово — invalidWord
//   • отмена потребителя отменяет оба запроса, а `lookup` в этом случае бросает CancellationError
// `lookup(word:)` (один итог — автозаполнение, Admin) — последовательно MW → Free: Free запрашивается только
// при сбое MW или пустой транскрипции (иначе пакетный импорт в Admin слал бы запрос к Free на каждое слово)
// Регрессия: запросы шли последовательно (MW → Free) через URLSession.shared с таймаутом 60 с —
// при недоступном MW пользователь ждал таймаут, хотя Free отвечает за доли секунды.
// Сеть подменяется URLProtocol-заглушкой (хосты MW и Free различаются по host, ответ можно задержать).

@MainActor
final class DictionaryServiceTests: XCTestCase {

    private let mwHost   = "www.dictionaryapi.com"
    private let freeHost = "api.dictionaryapi.dev"

    override func setUp() {
        super.setUp()
        StubState.shared.reset()
    }

    // MARK: - Helpers

    private func makeService() -> DictionaryService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DictionaryStubProtocol.self]
        return DictionaryService(session: URLSession(configuration: config))
    }

    private func collect(_ service: DictionaryService, word: String = "my") async throws -> [DictionaryEntry] {
        var updates: [DictionaryEntry] = []
        for try await entry in service.lookupUpdates(word: word) {
            updates.append(entry)
        }
        return updates
    }

    private func setReplies(mw: StubReply, free: StubReply) {
        StubState.shared.set(mw, forHost: mwHost)
        StubState.shared.set(free, forHost: freeHost)
    }

    /// Ответ MW: одна запись; `transcription == nil` — запись без блока произношения.
    private func mwJSON(transcription: String?, definition: String = "belonging to me") -> String {
        let hwi = transcription.map { #"{"prs":[{"mw":"\#($0)","sound":{"audio":"my000001"}}]}"# } ?? "{}"
        return #"[{"hwi":\#(hwi),"fl":"adjective","shortdef":["\#(definition)"]}]"#
    }

    private let freeJSON = """
    [{"word":"my","phonetics":[{"text":"/mi/","audio":"https://example.com/my.mp3"}],
      "meanings":[{"partOfSpeech":"adjective","definitions":[{"definition":"free definition"}],"synonyms":[]}]}]
    """

    // MARK: - Порядок и приоритет

    func testFreeComesFirstThenMWReplacesIt() async throws {
        setReplies(mw: .json(mwJSON(transcription: "ˈmī"), delay: 0.3), free: .json(freeJSON))

        let updates = try await collect(makeService())

        XCTAssertEqual(updates.map(\.source), [.freeDictionary, .merriamWebster])
        XCTAssertEqual(updates.map(\.transcription), ["/mi/", "ˈmī"])
    }

    func testLateFreeDoesNotChangeEntryWhenMWAlreadyArrived() async throws {
        setReplies(mw: .json(mwJSON(transcription: "ˈmī")), free: .json(freeJSON, delay: 0.3))

        let updates = try await collect(makeService())

        XCTAssertEqual(updates.map(\.source), [.merriamWebster], "Free после MW с транскрипцией ничего не меняет")
    }

    func testMWWithTranscriptionDoesNotWaitForSlowFree() async throws {
        setReplies(mw: .json(mwJSON(transcription: "ˈmī")), free: .json(freeJSON, delay: 5))
        let started = ContinuousClock.now

        let updates = try await collect(makeService())

        XCTAssertEqual(updates.map(\.source), [.merriamWebster])
        XCTAssertLessThan(started.duration(to: .now), .seconds(2), "завершённый MW не должен ждать зависший Free")
    }

    func testLookupReturnsBestEntry() async throws {
        setReplies(mw: .json(mwJSON(transcription: "ˈmī"), delay: 0.2), free: .json(freeJSON))

        let entry = try await makeService().lookup(word: "my")

        XCTAssertEqual(entry.source, .merriamWebster)
        XCTAssertTrue(entry.audioURL.contains("media.merriam-webster.com"))
    }

    // MARK: - lookup: последовательно MW → Free

    func testLookupDoesNotRequestFreeWhenMWIsComplete() async throws {
        setReplies(mw: .json(mwJSON(transcription: "ˈmī")), free: .json(freeJSON))

        let entry = try await makeService().lookup(word: "my")

        XCTAssertEqual(entry.source, .merriamWebster)
        XCTAssertEqual(StubState.shared.requestedHosts, [mwHost], "MW ответил полностью — Free не нужен")
    }

    func testLookupTakesTranscriptionFromFreeWhenMWHasNone() async throws {
        setReplies(mw: .json(mwJSON(transcription: nil, definition: "mw definition")), free: .json(freeJSON))

        let entry = try await makeService().lookup(word: "my")

        XCTAssertEqual(entry.source, .merriamWebster)
        XCTAssertEqual(entry.transcription, "/mi/")
        XCTAssertEqual(entry.meanings.first?.definitions.first?.text, "mw definition")
        XCTAssertEqual(StubState.shared.requestedHosts, [mwHost, freeHost])
    }

    func testLookupFallsBackToFreeWhenMWFails() async throws {
        setReplies(mw: .failure(.timedOut), free: .json(freeJSON))

        let entry = try await makeService().lookup(word: "my")

        XCTAssertEqual(entry.source, .freeDictionary)
        XCTAssertEqual(StubState.shared.requestedHosts, [mwHost, freeHost], "сначала MW, потом Free")
    }

    func testLookupThrowsFreeErrorWhenBothFail() async {
        setReplies(mw: .failure(.timedOut), free: .status(404))

        do {
            _ = try await makeService().lookup(word: "my")
            XCTFail("ожидалась ошибка")
        } catch let error as DictionaryService.DictionaryError {
            guard case .notFound = error else {
                return XCTFail("ожидалась .notFound (ошибка Free), получили \(error)")
            }
        } catch {
            XCTFail("неожиданный тип ошибки: \(error)")
        }
    }

    func testBothSourcesAreRequestedInParallel() async throws {
        // Ответы задержаны на 1 с. Параллельно — второй запрос стартует сразу за первым; последовательно —
        // только после ответа на первый (через ~1 с). Сравниваем моменты СТАРТА запросов, а не общее время:
        // общее время зависит от загрузки машины (в прогоне с хост-приложением оно уже давало ложный провал).
        setReplies(mw: .json(mwJSON(transcription: "ˈmī"), delay: 1), free: .json(freeJSON, delay: 1))

        _ = try await collect(makeService())

        let starts = StubState.shared.requestStarts
        XCTAssertEqual(Set(starts.map(\.host)), [mwHost, freeHost])
        guard starts.count == 2 else { return XCTFail("ожидалось два запроса, было \(starts.count)") }
        let gap = abs(starts[1].at.timeIntervalSince(starts[0].at))
        XCTAssertLessThan(gap, 0.5, "второй запрос стартовал через \(gap) с — запросы идут не параллельно")
    }

    // MARK: - Сбой одного из источников

    func testMWNetworkFailureYieldsFreeOnly() async throws {
        setReplies(mw: .failure(.timedOut), free: .json(freeJSON))

        let updates = try await collect(makeService())

        XCTAssertEqual(updates.map(\.source), [.freeDictionary])
        XCTAssertEqual(updates.first?.meanings.first?.definitions.first?.text, "free definition")
    }

    func testMWNon200StatusYieldsFreeOnly() async throws {
        setReplies(mw: .status(500), free: .json(freeJSON))

        let updates = try await collect(makeService())

        XCTAssertEqual(updates.map(\.source), [.freeDictionary])
    }

    func testFreeFailureYieldsMWOnly() async throws {
        setReplies(mw: .json(mwJSON(transcription: "ˈmī")), free: .failure(.notConnectedToInternet))

        let updates = try await collect(makeService())

        XCTAssertEqual(updates.map(\.source), [.merriamWebster])
    }

    func testMWWithoutTranscriptionAndFailedFreeFinishesWithoutError() async throws {
        setReplies(mw: .json(mwJSON(transcription: nil)), free: .failure(.notConnectedToInternet))

        let updates = try await collect(makeService())   // не должно бросить: одна запись уже отдана

        XCTAssertEqual(updates.map(\.source), [.merriamWebster])
        XCTAssertEqual(updates.first?.transcription, "")
    }

    func testBothSourcesFailingThrowsNetworkError() async {
        setReplies(mw: .failure(.timedOut), free: .failure(.notConnectedToInternet))

        do {
            _ = try await collect(makeService())
            XCTFail("ожидалась ошибка")
        } catch let error as DictionaryService.DictionaryError {
            guard case .networkError = error else {
                return XCTFail("ожидалась .networkError, получили \(error)")
            }
        } catch {
            XCTFail("неожиданный тип ошибки: \(error)")
        }
    }

    func testFreeErrorIsPreferredWhenBothFail() async {
        // MW — сетевая ошибка, Free — «слово не найдено»: пользователю нужна ошибка Free, а не таймаут MW.
        setReplies(mw: .failure(.timedOut), free: .status(404))

        do {
            _ = try await collect(makeService())
            XCTFail("ожидалась ошибка")
        } catch let error as DictionaryService.DictionaryError {
            guard case .notFound = error else {
                return XCTFail("ожидалась .notFound (ошибка Free), получили \(error)")
            }
        } catch {
            XCTFail("неожиданный тип ошибки: \(error)")
        }
    }

    func testEmptyWordThrowsInvalidWord() async {
        do {
            _ = try await collect(makeService(), word: "   ")
            XCTFail("ожидалась ошибка")
        } catch let error as DictionaryService.DictionaryError {
            guard case .invalidWord = error else {
                return XCTFail("ожидалась .invalidWord, получили \(error)")
            }
        } catch {
            XCTFail("неожиданный тип ошибки: \(error)")
        }
        XCTAssertTrue(StubState.shared.requestedHosts.isEmpty, "для пустого слова запросы не отправляются")
    }

    // MARK: - Транскрипция из Free

    func testMWWithoutTranscriptionIsPatchedFromFreeWhenFreeComesFirst() async throws {
        setReplies(mw: .json(mwJSON(transcription: nil, definition: "mw definition"), delay: 0.3), free: .json(freeJSON))

        let updates = try await collect(makeService())

        XCTAssertEqual(updates.map(\.source), [.freeDictionary, .merriamWebster])
        XCTAssertEqual(updates.last?.transcription, "/mi/", "транскрипция — из Free")
        XCTAssertEqual(updates.last?.meanings.first?.definitions.first?.text, "mw definition", "определения — от MW")
    }

    func testMWWithoutTranscriptionIsPatchedFromFreeWhenMWComesFirst() async throws {
        setReplies(mw: .json(mwJSON(transcription: nil, definition: "mw definition")), free: .json(freeJSON, delay: 0.3))

        let updates = try await collect(makeService())

        XCTAssertEqual(updates.map(\.source), [.merriamWebster, .merriamWebster])
        XCTAssertEqual(updates.map(\.transcription), ["", "/mi/"], "поздний Free дополняет транскрипцию уже показанной записи MW")
    }

    // MARK: - Отмена и таймаут

    func testCancellationCancelsBothRequests() async {
        setReplies(mw: .json(mwJSON(transcription: "ˈmī"), delay: 5), free: .json(freeJSON, delay: 5))
        let service = makeService()
        let task = Task { _ = try? await self.collect(service) }

        try? await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        await task.value

        // Ответы заготовлены на 5 с — до остановки обоих запросов они дойти не могли, значит их отменили.
        await waitUntil(timeout: 1) { StubState.shared.stoppedCount == 2 }
    }

    func testLookupThrowsCancellationErrorWhenCallerIsCancelled() async {
        setReplies(mw: .json(mwJSON(transcription: "ˈmī"), delay: 5), free: .json(freeJSON, delay: 5))
        let service = makeService()
        let task = Task { () -> Error? in
            do {
                _ = try await service.lookup(word: "my")
                return nil
            } catch {
                return error
            }
        }

        try? await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        let error = await task.value

        XCTAssertTrue(error is CancellationError, "при отмене ожидалась CancellationError, получили \(String(describing: error))")
    }

    func testMerriamWebsterAudioURLIsRecognisedByHost() {
        XCTAssertTrue(DictionaryService.isMerriamWebsterAudioURL("https://media.merriam-webster.com/audio/prons/en/us/mp3/m/my000001.mp3"))
        XCTAssertFalse(DictionaryService.isMerriamWebsterAudioURL("https://api.dictionaryapi.dev/media/pronunciations/en/my-us.mp3"))
        XCTAssertFalse(DictionaryService.isMerriamWebsterAudioURL(""))
        XCTAssertFalse(DictionaryService.isMerriamWebsterAudioURL("https://example.com/media.merriam-webster.com/my.mp3"),
                       "проверяется хост, а не подстрока")
    }

    func testLookupTurnsCancelledRequestErrorIntoCancellationError() async {
        // Поток успел завершиться ошибкой отменённого запроса, а вызывающий уже отменён — для него это
        // отмена, а не сетевая ошибка.
        let lookup = CancelledRequestLookup()
        let task = Task { () -> Error? in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await lookup.lookup(word: "my")
                return nil
            } catch {
                return error
            }
        }

        let error = await task.value

        XCTAssertTrue(error is CancellationError, "ожидалась CancellationError, получили \(String(describing: error))")
    }

    func testIsCancellationRecognisesWrappedCancelledRequest() {
        XCTAssertTrue(DictionaryService.isCancellation(CancellationError()))
        XCTAssertTrue(DictionaryService.isCancellation(URLError(.cancelled)))
        XCTAssertTrue(DictionaryService.isCancellation(DictionaryService.DictionaryError.networkError(URLError(.cancelled))))
        XCTAssertFalse(DictionaryService.isCancellation(DictionaryService.DictionaryError.networkError(URLError(.timedOut))))
        XCTAssertFalse(DictionaryService.isCancellation(DictionaryService.DictionaryError.notFound))
    }

    func testDefaultSessionTimeoutIsShort() {
        let config = DictionaryService.defaultSession.configuration

        XCTAssertEqual(config.timeoutIntervalForRequest, DictionaryService.requestTimeout)
        XCTAssertLessThanOrEqual(config.timeoutIntervalForRequest, 10, "60 с (как у URLSession.shared) — слишком долго")
    }
}

// MARK: - FreeDictionaryPronunciationTests
//
// `APIEntry.toDictionaryEntry()` берёт транскрипцию и аудио из ОДНОГО варианта произношения:
//   • среди вариантов с текстом и аудио — американский ударный (по имени файла: `-us`, без `unstressed`)
//   • такого нет — первый вариант с текстом и аудио
//   • полных вариантов нет — первый текст и первое аудио по отдельности
//   • `//…` дополняется до https, не-https аудио отбрасывается
// Регрессия: поля выбирались независимо — у «you» транскрипция /jʉː/ (вариант без аудио) показывалась
// вместе с аудио /jə/ из другого варианта.

@MainActor
final class FreeDictionaryPronunciationTests: XCTestCase {

    private let base = "https://api.dictionaryapi.dev/media/pronunciations/en/"

    private func entry(_ word: String, _ phonetics: [(String?, String?)]) -> DictionaryEntry {
        APIEntry(
            word: word,
            phonetics: phonetics.map { APIPhonetic(text: $0.0, audio: $0.1) },
            meanings: []
        ).toDictionaryEntry()
    }

    func testPicksAmericanStressedVariantForYou() {
        // Реальный ответ Free для «you» (2026-11-01)
        let result = entry("you", [
            ("/jʉː/", ""),
            ("/jə/", base + "you-au-us-unstressed.mp3"),
            ("/juː/", base + "you-uk-stressed.mp3"),
            ("/ju/", ""),
            ("/ju/", base + "you-us-stressed.mp3"),
            ("/jə/", base + "you-au-us-unstressed.mp3"),
        ])

        XCTAssertEqual(result.transcription, "/ju/")
        XCTAssertEqual(result.audioURL, base + "you-us-stressed.mp3")
    }

    func testFallsBackToFirstCompleteVariantWithoutAmericanAudio() {
        let result = entry("colour", [
            ("/ˈkʌlə/", ""),
            ("/ˈkʌlə(ɹ)/", base + "colour-uk.mp3"),
            ("/ˈkʌləɹ/", base + "colour-au.mp3"),
        ])

        XCTAssertEqual(result.transcription, "/ˈkʌlə(ɹ)/")
        XCTAssertEqual(result.audioURL, base + "colour-uk.mp3")
    }

    func testWordUsIsNotTakenForRegionTag() {
        // Префикс со словом отрезается: «us-uk» — британское аудио слова «us», а не американское
        let result = entry("us", [
            ("/ʌs/", base + "us-uk.mp3"),
            ("/əs/", base + "us-us.mp3"),
        ])

        XCTAssertEqual(result.transcription, "/əs/")
        XCTAssertEqual(result.audioURL, base + "us-us.mp3")
    }

    func testWithoutCompleteVariantFieldsArePickedSeparately() {
        let result = entry("word", [
            (nil, base + "word-us.mp3"),
            ("/wɜːd/", nil),
        ])

        XCTAssertEqual(result.transcription, "/wɜːd/")
        XCTAssertEqual(result.audioURL, base + "word-us.mp3")
    }

    func testAudioURLIsNormalisedToHTTPS() {
        let relative = entry("cat", [("/kæt/", "//ssl.gstatic.com/dictionary/cat.mp3")])
        XCTAssertEqual(relative.audioURL, "https://ssl.gstatic.com/dictionary/cat.mp3")

        let insecure = entry("cat", [("/kæt/", "http://example.com/cat.mp3")])
        XCTAssertEqual(insecure.audioURL, "", "не-https аудио не берём")
        XCTAssertEqual(insecure.transcription, "/kæt/")
    }
}

// MARK: - Подменный источник с отменённым запросом

/// Поток, сразу завершённый ошибкой отменённого запроса (как у сервиса, когда запрос отменили).
@MainActor
private final class CancelledRequestLookup: DictionaryLookingUp {
    func lookupUpdates(word: String) -> AsyncThrowingStream<DictionaryEntry, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: DictionaryService.DictionaryError.networkError(URLError(.cancelled)))
        }
    }
}

// MARK: - URLProtocol-заглушка сети

private enum StubReply {
    case json(String, delay: TimeInterval = 0)
    case status(Int, delay: TimeInterval = 0)
    case failure(URLError.Code, delay: TimeInterval = 0)

    var delay: TimeInterval {
        switch self {
        case .json(_, let delay), .status(_, let delay), .failure(_, let delay): return delay
        }
    }
}

/// Состояние заглушки общее для сессии и теста; обращения идут с разных потоков — под замком.
private final class StubState: @unchecked Sendable {
    static let shared = StubState()

    private let lock = NSLock()
    private var replies: [String: StubReply] = [:]
    private var starts: [(host: String, at: Date)] = []
    private var stopped = 0

    func reset() {
        lock.lock(); defer { lock.unlock() }
        replies = [:]
        starts = []
        stopped = 0
    }

    func set(_ reply: StubReply, forHost host: String) {
        lock.lock(); defer { lock.unlock() }
        replies[host] = reply
    }

    /// Записывает обращение к host и возвращает заготовленный ответ (неизвестный host → ошибка соединения).
    func take(host: String) -> StubReply {
        lock.lock(); defer { lock.unlock() }
        starts.append((host: host, at: Date()))
        return replies[host] ?? .failure(.cannotConnectToHost)
    }

    func noteStopped() {
        lock.lock(); defer { lock.unlock() }
        stopped += 1
    }

    var requestedHosts: [String] {
        lock.lock(); defer { lock.unlock() }
        return starts.map(\.host)
    }

    /// Хост и момент старта каждого запроса — для проверки параллельности.
    var requestStarts: [(host: String, at: Date)] {
        lock.lock(); defer { lock.unlock() }
        return starts
    }

    /// Сколько запросов остановлено (отменены или завершены) — для проверки отмены.
    var stoppedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }
}

private final class DictionaryStubProtocol: URLProtocol, @unchecked Sendable {

    private let lock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let reply = StubState.shared.take(host: url.host ?? "")
        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [self] in
            guard !isStopped else { return }
            switch reply {
            case .json(let body, _):
                respond(url: url, status: 200, body: Data(body.utf8))
            case .status(let code, _):
                respond(url: url, status: code, body: Data())
            case .failure(let code, _):
                client?.urlProtocol(self, didFailWithError: URLError(code))
            }
        }
    }

    override func stopLoading() {
        lock.lock()
        stopped = true
        lock.unlock()
        StubState.shared.noteStopped()
    }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    private func respond(url: URL, status: Int, body: Data) {
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
