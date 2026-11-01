import XCTest
@testable import SwipeLingo

// MARK: - DictionaryServiceTests
//
// Порядок источников в DictionaryService.lookup:
//   • Merriam-Webster (MW) — основной; если ответил — Free Dictionary не запрашивается
//   • MW упал (сеть/таймаут/не-200) → откат на Free Dictionary
//   • MW ответил без транскрипции → транскрипция берётся из Free, остальное остаётся от MW
//   • оба упали → DictionaryError.networkError
// Регрессия: запросы шли через URLSession.shared с таймаутом 60 с — зависший MW держал экран
// словаря до минуты, прежде чем срабатывал откат. Теперь у сервиса своя сессия с коротким таймаутом.
// Сеть подменяется URLProtocol-заглушкой (хосты MW и Free различаются по host).

@MainActor
final class DictionaryServiceTests: XCTestCase {

    private let mwHost   = "www.dictionaryapi.com"
    private let freeHost = "api.dictionaryapi.dev"

    override func setUp() {
        super.setUp()
        DictionaryStubProtocol.reset()
    }

    // MARK: - Helpers

    private func makeService() -> DictionaryService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DictionaryStubProtocol.self]
        return DictionaryService(session: URLSession(configuration: config))
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

    // MARK: - Источники

    func testMWSuccessIsUsedAndFreeIsNotRequested() async throws {
        DictionaryStubProtocol.replies[mwHost] = .json(mwJSON(transcription: "ˈmī"))

        let entry = try await makeService().lookup(word: "my")

        XCTAssertEqual(entry.transcription, "ˈmī")
        XCTAssertTrue(entry.audioURL.contains("media.merriam-webster.com"))
        XCTAssertEqual(DictionaryStubProtocol.requestedHosts, [mwHost], "при успехе MW откат не нужен")
    }

    func testMWNetworkFailureFallsBackToFree() async throws {
        DictionaryStubProtocol.replies[mwHost]   = .failure(.timedOut)
        DictionaryStubProtocol.replies[freeHost] = .json(freeJSON)

        let entry = try await makeService().lookup(word: "my")

        XCTAssertEqual(entry.transcription, "/mi/")
        XCTAssertEqual(entry.meanings.first?.definitions.first?.text, "free definition")
        XCTAssertEqual(DictionaryStubProtocol.requestedHosts, [mwHost, freeHost])
    }

    func testMWNon200StatusFallsBackToFree() async throws {
        DictionaryStubProtocol.replies[mwHost]   = .status(500)
        DictionaryStubProtocol.replies[freeHost] = .json(freeJSON)

        let entry = try await makeService().lookup(word: "my")

        XCTAssertEqual(entry.transcription, "/mi/")
    }

    func testMWWithoutTranscriptionTakesItFromFreeButKeepsMWContent() async throws {
        DictionaryStubProtocol.replies[mwHost]   = .json(mwJSON(transcription: nil, definition: "mw definition"))
        DictionaryStubProtocol.replies[freeHost] = .json(freeJSON)

        let entry = try await makeService().lookup(word: "my")

        XCTAssertEqual(entry.transcription, "/mi/", "транскрипция — из Free")
        XCTAssertEqual(entry.meanings.first?.definitions.first?.text, "mw definition", "определения остаются от MW")
    }

    func testBothSourcesFailingThrowsNetworkError() async {
        DictionaryStubProtocol.replies[mwHost]   = .failure(.timedOut)
        DictionaryStubProtocol.replies[freeHost] = .failure(.notConnectedToInternet)

        do {
            _ = try await makeService().lookup(word: "my")
            XCTFail("ожидалась ошибка")
        } catch let error as DictionaryService.DictionaryError {
            guard case .networkError = error else {
                return XCTFail("ожидалась .networkError, получили \(error)")
            }
        } catch {
            XCTFail("неожиданный тип ошибки: \(error)")
        }
    }

    // MARK: - Таймаут

    func testDefaultSessionTimeoutIsShort() {
        let config = DictionaryService.defaultSession.configuration

        XCTAssertEqual(config.timeoutIntervalForRequest, DictionaryService.requestTimeout)
        XCTAssertLessThanOrEqual(config.timeoutIntervalForRequest, 10, "60 с (как у URLSession.shared) — слишком долго для отката")
    }
}

// MARK: - DictionaryLookupViewModelTests
//
// `load` не должен стирать показанный кэш (`showCached`) спиннером:
//   • есть кэш → во время запроса остаётся .loaded; свежие данные подменяют кэш
//   • есть кэш и запрос упал → кэш остаётся, ошибка не показывается
//   • кэша нет → .loading, затем .loaded / .error
// Регрессия: load первой строкой ставил phase = .loading — кэш пропадал сразу после показа, и даже для
// сохранённого слова приходилось ждать сеть (на устройстве ~3 с), а при сбое сети вместо кэша была ошибка.

@MainActor
final class DictionaryLookupViewModelTests: XCTestCase {

    private func entry(_ transcription: String) -> DictionaryEntry {
        DictionaryEntry(word: "she", transcription: transcription, audioURL: "", meanings: [])
    }

    private func makeViewModel(_ stub: StubLookup) -> DictionaryLookupViewModel {
        DictionaryLookupViewModel(audioService: AudioPlayerService(), service: stub)
    }

    /// Короткая метка фазы для сравнения (DictionaryEntry не Equatable).
    private func label(_ phase: DictionaryLookupViewModel.Phase) -> String {
        switch phase {
        case .loading:             return "loading"
        case .loaded(let entry):   return "loaded:\(entry.transcription)"
        case .error:               return "error"
        }
    }

    func testRefreshKeepsCachedEntryVisibleWhileLoading() async {
        let stub = StubLookup(result: .success(entry("fresh")))
        let vm = makeViewModel(stub)
        vm.showCached(entry("cached"))
        var phaseDuringLookup = ""
        stub.onLookup = { phaseDuringLookup = self.label(vm.phase) }

        await vm.load(word: "she")

        XCTAssertEqual(phaseDuringLookup, "loaded:cached", "кэш не должен заменяться спиннером на время запроса")
        XCTAssertEqual(label(vm.phase), "loaded:fresh", "свежие данные подменяют кэш")
        XCTAssertTrue(vm.didLoad)
    }

    func testFailedRefreshKeepsCachedEntry() async {
        let stub = StubLookup(result: .failure(URLError(.timedOut)))
        let vm = makeViewModel(stub)
        vm.showCached(entry("cached"))

        await vm.load(word: "she")

        XCTAssertEqual(label(vm.phase), "loaded:cached", "при сбое сети кэш остаётся, а не заменяется ошибкой")
        XCTAssertFalse(vm.didLoad, "didLoad запускает повторное кэширование — свежих данных не было")
    }

    func testLoadWithoutCacheShowsLoadingThenLoaded() async {
        let stub = StubLookup(result: .success(entry("fresh")))
        let vm = makeViewModel(stub)
        var phaseDuringLookup = ""
        stub.onLookup = { phaseDuringLookup = self.label(vm.phase) }

        await vm.load(word: "she")

        XCTAssertEqual(phaseDuringLookup, "loading")
        XCTAssertEqual(label(vm.phase), "loaded:fresh")
        XCTAssertTrue(vm.didLoad)
    }

    func testLoadFailureWithoutCacheShowsError() async {
        let stub = StubLookup(result: .failure(URLError(.notConnectedToInternet)))
        let vm = makeViewModel(stub)

        await vm.load(word: "she")

        XCTAssertEqual(label(vm.phase), "error")
        XCTAssertFalse(vm.didLoad)
    }
}

// MARK: - Подменный источник для ViewModel

@MainActor
private final class StubLookup: DictionaryLookingUp {
    let result: Result<DictionaryEntry, Error>
    /// Вызывается в момент запроса — чтобы тест мог посмотреть состояние ViewModel «посреди» загрузки.
    var onLookup: (@MainActor () -> Void)?

    init(result: Result<DictionaryEntry, Error>) {
        self.result = result
    }

    func lookup(word: String) async throws -> DictionaryEntry {
        onLookup?()
        return try result.get()
    }
}

// MARK: - URLProtocol-заглушка сети

/// Отвечает на запросы по host из `replies`; неизвестный host → ошибка соединения.
/// Состояние статическое (URLProtocol создаётся самой сессией) — тесты XCTest идут последовательно,
/// `reset()` вызывается в `setUp`.
private final class DictionaryStubProtocol: URLProtocol, @unchecked Sendable {

    enum Reply {
        case json(String)
        case status(Int)
        case failure(URLError.Code)
    }

    nonisolated(unsafe) static var replies: [String: Reply] = [:]
    nonisolated(unsafe) static var requestedHosts: [String] = []

    static func reset() {
        replies = [:]
        requestedHosts = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let host = url.host ?? ""
        Self.requestedHosts.append(host)

        switch Self.replies[host] ?? .failure(.cannotConnectToHost) {
        case .json(let body):
            respond(url: url, status: 200, body: Data(body.utf8))
        case .status(let code):
            respond(url: url, status: code, body: Data())
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}

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
