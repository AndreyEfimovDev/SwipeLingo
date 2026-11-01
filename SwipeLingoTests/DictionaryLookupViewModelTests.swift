import XCTest
@testable import SwipeLingo

// MARK: - DictionaryLookupViewModelTests
//
// Результаты приходят по мере готовности (Free, затем MW); правила экрана:
//   • показанная запись не сбрасывается в спиннер; показанную запись MW (свежую или кэш, точно от MW —
//     по аудио с CDN Merriam-Webster) заменяет только MW; кэш от Free / без аудио / без определений
//     может заменить и Free
//   • пустой экран → .loading до первой записи, затем Free, затем MW заменяет его
//   • нет свежих записей / ошибка при показанной записи → она остаётся, ошибки нет; на пустом экране — .error
//   • в кэш карточки (`entryToCache`): MW всегда; Free только на пустом экране; пустые транскрипция/аудио
//     у MW не затирают имеющиеся
//   • подпись спиннера (`refreshStatusText`) зависит от того, что сейчас на экране
//   • перезапуск и отмена `load` не ломают состояние
// Регрессии: `load` первой строкой ставил .loading и стирал показанный кэш; при недоступном MW кэш с
// определением MW заменялся записью Free (другое значение слова); однострочный кэш, записанный из Free,
// держался против полного свежего Free, пока MW недоступен (так было с «She» на устройстве).

@MainActor
final class DictionaryLookupViewModelTests: XCTestCase {

    private let mwAudio   = "https://media.merriam-webster.com/audio/prons/en/us/mp3/s/she00001.mp3"
    private let freeAudio = "https://api.dictionaryapi.dev/media/pronunciations/en/she-uk.mp3"

    private func entry(
        _ transcription: String,
        _ source: DictionarySource?,
        withMeanings: Bool = true,
        audioURL: String = ""
    ) -> DictionaryEntry {
        let meanings = withMeanings
            ? [DictionaryMeaning(partOfSpeech: "", definitions: [DictionaryDefinition(text: "definition", example: nil)], synonyms: [])]
            : []
        return DictionaryEntry(word: "she", transcription: transcription, audioURL: audioURL, meanings: meanings, source: source)
    }

    private func makeViewModel(_ stub: StubLookup) -> DictionaryLookupViewModel {
        DictionaryLookupViewModel(audioService: AudioPlayerService(), service: stub)
    }

    /// Короткая метка фазы (DictionaryEntry не Equatable): "loaded:<транскрипция>".
    private func label(_ phase: DictionaryLookupViewModel.Phase) -> String {
        switch phase {
        case .loading:           return "loading"
        case .loaded(let entry): return "loaded:\(entry.transcription)"
        case .error:             return "error"
        }
    }

    // MARK: - Старт

    func testViewModelCreatedWithCacheStartsWithCacheShown() {
        let vm = DictionaryLookupViewModel(
            audioService: AudioPlayerService(),
            service: StubLookup(),
            cachedEntry: entry("cached", nil, audioURL: mwAudio)
        )

        XCTAssertEqual(label(vm.phase), "loaded:cached", "без кадра полноэкранного спиннера до .task")
    }

    func testViewModelCreatedWithMWCacheProtectsItFromFree() async {
        let stub = StubLookup()
        let vm = DictionaryLookupViewModel(
            audioService: AudioPlayerService(),
            service: stub,
            cachedEntry: entry("cached", nil, audioURL: mwAudio)
        )
        let task = Task { await vm.load(word: "she") }
        await waitUntil { vm.isRefreshing }

        stub.send(entry("free", .freeDictionary, audioURL: freeAudio))
        stub.finish()
        await task.value

        XCTAssertEqual(label(vm.phase), "loaded:cached", "кэш, переданный в init, защищён так же, как через showCached")
    }

    // MARK: - Пустой экран

    func testNoCacheShowsFreeFirstThenMWReplacesIt() async {
        let stub = StubLookup()
        let vm = makeViewModel(stub)
        let task = Task { await vm.load(word: "she") }
        await waitUntil { vm.isRefreshing }
        XCTAssertEqual(label(vm.phase), "loading", "пока нечего показывать — спиннер на весь экран")

        stub.send(entry("free", .freeDictionary))
        await waitUntil { vm.updateCount == 1 }
        XCTAssertEqual(label(vm.phase), "loaded:free")
        XCTAssertEqual(vm.entryToCache?.transcription, "free", "кэша не было — Free сохраняется")
        XCTAssertEqual(vm.refreshStatusText, "Looking for fuller definitions and examples…")

        stub.send(entry("mw", .merriamWebster))
        await waitUntil { vm.updateCount == 2 }
        XCTAssertEqual(label(vm.phase), "loaded:mw")
        XCTAssertEqual(vm.entryToCache?.transcription, "mw")
        XCTAssertNil(vm.refreshStatusText, "показан MW — догружать нечего")

        stub.finish()
        await task.value
        XCTAssertFalse(vm.isRefreshing)
    }

    func testNoCacheAndLookupErrorShowsError() async {
        let stub = StubLookup()
        let vm = makeViewModel(stub)
        let task = Task { await vm.load(word: "she") }
        await waitUntil { vm.isRefreshing }

        stub.fail(URLError(.notConnectedToInternet))
        await task.value

        XCTAssertEqual(label(vm.phase), "error")
        XCTAssertEqual(vm.updateCount, 0)
        XCTAssertFalse(vm.isRefreshing)
    }

    func testNoCacheAndStreamFinishingEmptyShowsErrorNotEndlessSpinner() async {
        let stub = StubLookup()
        let vm = makeViewModel(stub)
        let task = Task { await vm.load(word: "she") }
        await waitUntil { vm.isRefreshing }

        stub.finish()   // ни записей, ни ошибки
        await task.value

        XCTAssertEqual(label(vm.phase), "error")
        XCTAssertFalse(vm.isRefreshing)
    }

    func testPatchedMWEntryUpdatesScreenAndCacheAgain() async {
        let stub = StubLookup()
        let vm = makeViewModel(stub)
        let task = Task { await vm.load(word: "she") }
        await waitUntil { vm.isRefreshing }

        stub.send(entry("", .merriamWebster))          // MW без транскрипции
        stub.send(entry("patched", .merriamWebster))   // тот же MW, дополненный транскрипцией из Free
        await waitUntil { vm.updateCount == 2 }
        stub.finish()
        await task.value

        XCTAssertEqual(label(vm.phase), "loaded:patched")
        XCTAssertEqual(vm.entryToCache?.transcription, "patched", "в кэш уходит последняя версия записи")
    }

    // MARK: - Кэш показан

    func testCacheFromMWIsReplacedOnlyByMW() async {
        let stub = StubLookup()
        let vm = makeViewModel(stub)
        vm.showCached(entry("cached", nil, audioURL: mwAudio))
        let task = Task { await vm.load(word: "she") }
        await waitUntil { vm.isRefreshing }
        XCTAssertEqual(label(vm.phase), "loaded:cached", "кэш не заменяется спиннером")
        XCTAssertEqual(vm.refreshStatusText, "Loading full definitions…")

        stub.send(entry("free", .freeDictionary))
        stub.send(entry("mw", .merriamWebster))
        await waitUntil { vm.updateCount == 1 && self.label(vm.phase) == "loaded:mw" }
        stub.finish()
        await task.value

        // Если бы Free заменил кэш, счётчик был бы 2, а в кэш карточки уходила бы промежуточная запись.
        XCTAssertEqual(vm.updateCount, 1, "Free не вытесняет кэш от MW")
        XCTAssertEqual(vm.entryToCache?.transcription, "mw")
    }

    func testCachedEntryWithoutDefinitionsMayBeReplacedByFree() async {
        let stub = StubLookup()
        let vm = makeViewModel(stub)
        vm.showCached(entry("cached", nil, withMeanings: false, audioURL: mwAudio))
        let task = Task { await vm.load(word: "she") }
        await waitUntil { vm.isRefreshing }

        stub.send(entry("free", .freeDictionary))
        await waitUntil { vm.updateCount == 1 }
        stub.finish()
        await task.value

        XCTAssertEqual(label(vm.phase), "loaded:free", "защищать в кэше без определений нечего")
        XCTAssertNotEqual(vm.entryToCache?.audioURL, mwAudio,
                          "Free не наследует аудио MW — иначе при следующем открытии его определения сойдут за MW")
    }

    func testCacheFromFreeIsReplacedByFreshFree() async {
        let stub = StubLookup()
        let vm = makeViewModel(stub)
        vm.showCached(entry("cached", nil, audioURL: freeAudio))
        let task = Task { await vm.load(word: "she") }
        await waitUntil { vm.isRefreshing }

        stub.send(entry("free", .freeDictionary, audioURL: freeAudio))
        await waitUntil { vm.updateCount == 1 }
        stub.finish()
        await task.value

        XCTAssertEqual(label(vm.phase), "loaded:free", "кэш от Free не держится против полного свежего Free")
        XCTAssertEqual(vm.entryToCache?.transcription, "free")
    }

    func testCacheWithoutAudioIsReplacedByFreshFree() async {
        let stub = StubLookup()
        let vm = makeViewModel(stub)
        vm.showCached(entry("cached", nil))   // аудио нет — происхождение не доказано
        let task = Task { await vm.load(word: "she") }
        await waitUntil { vm.isRefreshing }

        stub.send(entry("free", .freeDictionary))
        await waitUntil { vm.updateCount == 1 }
        stub.finish()
        await task.value

        XCTAssertEqual(label(vm.phase), "loaded:free")
    }

    func testCachedEntrySurvivesWhenNothingFreshArrives() async {
        let stub = StubLookup()
        let vm = makeViewModel(stub)
        vm.showCached(entry("cached", nil))
        let task = Task { await vm.load(word: "she") }
        await waitUntil { vm.isRefreshing }

        stub.finish()
        await task.value

        XCTAssertEqual(label(vm.phase), "loaded:cached")
        XCTAssertNil(vm.entryToCache)
        XCTAssertFalse(vm.isRefreshing)
        XCTAssertNil(vm.refreshStatusText)
    }

    func testCachedEntrySurvivesLookupFailure() async {
        let stub = StubLookup()
        let vm = makeViewModel(stub)
        vm.showCached(entry("cached", nil))
        let task = Task { await vm.load(word: "she") }
        await waitUntil { vm.isRefreshing }

        stub.fail(URLError(.timedOut))
        await task.value

        XCTAssertEqual(label(vm.phase), "loaded:cached", "при сбое остаётся кэш, а не ошибка")
        XCTAssertEqual(vm.updateCount, 0)
    }

    func testMWWithEmptyTranscriptionDoesNotWipeCachedTranscription() async {
        let stub = StubLookup()
        let vm = makeViewModel(stub)
        vm.showCached(entry("cached", nil))
        let task = Task { await vm.load(word: "she") }
        await waitUntil { vm.isRefreshing }

        stub.send(entry("", .merriamWebster))
        await waitUntil { vm.updateCount == 1 }
        stub.finish()
        await task.value

        XCTAssertEqual(label(vm.phase), "loaded:cached", "транскрипция из кэша сохраняется")
        XCTAssertEqual(vm.entryToCache?.transcription, "cached", "и в кэш карточки пустое значение не пишется")
        XCTAssertEqual(vm.entryToCache?.source, .merriamWebster)
    }

    func testProtectedMWCacheSurvivesWhenOnlyFreeArrives() async {
        let stub = StubLookup()
        let vm = makeViewModel(stub)
        vm.showCached(entry("cached", nil, audioURL: mwAudio))
        let task = Task { await vm.load(word: "she") }
        await waitUntil { vm.isRefreshing }

        stub.send(entry("free", .freeDictionary, audioURL: freeAudio))   // MW недоступен — пришёл только Free
        stub.finish()
        await task.value

        XCTAssertEqual(label(vm.phase), "loaded:cached")
        XCTAssertNil(vm.entryToCache, "кэш от MW не перезаписывается записью Free")
        XCTAssertEqual(vm.updateCount, 0)
    }

    func testMWWithoutAudioKeepsMWAudioFromCache() async {
        let stub = StubLookup()
        let vm = makeViewModel(stub)
        vm.showCached(entry("cached", nil, audioURL: mwAudio))
        let task = Task { await vm.load(word: "she") }
        await waitUntil { vm.isRefreshing }

        stub.send(entry("mw", .merriamWebster))   // без аудио
        await waitUntil { vm.updateCount == 1 }
        stub.finish()
        await task.value

        XCTAssertEqual(vm.entryToCache?.audioURL, mwAudio)
    }

    func testMWWithoutAudioDoesNotInheritFreeAudio() async {
        let stub = StubLookup()
        let vm = makeViewModel(stub)
        vm.showCached(entry("cached", nil, audioURL: freeAudio))
        let task = Task { await vm.load(word: "she") }
        await waitUntil { vm.isRefreshing }

        stub.send(entry("mw", .merriamWebster))   // без аудио
        await waitUntil { vm.updateCount == 1 }
        stub.finish()
        await task.value

        XCTAssertEqual(vm.entryToCache?.audioURL, "", "аудио Free у записи MW исказило бы её происхождение")
    }

    // MARK: - Перезапуск и отмена

    func testCancelledOlderLoadDoesNotClearRefreshingOfNewerOne() async {
        let stub = StubLookup()
        let vm = makeViewModel(stub)
        let older = Task { await vm.load(word: "she") }
        await waitUntil { stub.callCount == 1 }
        let newer = Task { await vm.load(word: "she") }
        await waitUntil { stub.callCount == 2 }

        older.cancel()
        await older.value
        XCTAssertTrue(vm.isRefreshing, "отменённая старая загрузка не гасит признак новой")

        stub.finishAll()
        await newer.value
        XCTAssertFalse(vm.isRefreshing)
    }

    func testSecondLoadKeepsMWAndResetsEntryToCache() async {
        let stub = StubLookup()
        let vm = makeViewModel(stub)

        let first = Task { await vm.load(word: "she") }
        await waitUntil { vm.isRefreshing }
        stub.send(entry("mw", .merriamWebster))
        await waitUntil { vm.updateCount == 1 }
        stub.finish()
        await first.value
        XCTAssertNotNil(vm.entryToCache)

        let second = Task { await vm.load(word: "she") }
        await waitUntil { vm.isRefreshing }
        XCTAssertNil(vm.entryToCache, "запись прошлой загрузки не должна уйти во View повторно")
        XCTAssertEqual(label(vm.phase), "loaded:mw", "показанное не сбрасывается в спиннер")
        stub.send(entry("free", .freeDictionary))
        stub.finish()
        await second.value

        XCTAssertEqual(label(vm.phase), "loaded:mw", "Free не вытесняет показанный MW")
        XCTAssertEqual(vm.updateCount, 1)
    }

    func testCancelledLoadStopsRefreshingAndWritesNothing() async {
        let stub = StubLookup()
        let vm = makeViewModel(stub)
        let task = Task { await vm.load(word: "she") }
        await waitUntil { vm.isRefreshing }

        task.cancel()
        await task.value

        XCTAssertFalse(vm.isRefreshing)
        XCTAssertEqual(label(vm.phase), "loading", "при отмене (экран закрыт) ошибку не показываем")
        XCTAssertEqual(vm.updateCount, 0)
    }
}

// MARK: - Подменный источник для ViewModel

/// Управляется вручную: тест сам решает, когда и какая запись «приходит».
@MainActor
private final class StubLookup: DictionaryLookingUp {
    /// По потоку на каждый вызов `lookupUpdates`; `send`/`finish`/`fail` действуют на последний.
    private var continuations: [AsyncThrowingStream<DictionaryEntry, Error>.Continuation] = []

    var callCount: Int { continuations.count }

    func lookupUpdates(word: String) -> AsyncThrowingStream<DictionaryEntry, Error> {
        AsyncThrowingStream { continuation in
            self.continuations.append(continuation)
        }
    }

    func send(_ entry: DictionaryEntry)  { continuations.last?.yield(entry) }
    func finish()                        { continuations.last?.finish() }
    func fail(_ error: Error)            { continuations.last?.finish(throwing: error) }
    func finishAll()                     { continuations.forEach { $0.finish() } }
}
