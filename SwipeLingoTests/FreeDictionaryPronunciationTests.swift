import XCTest
@testable import SwipeLingo

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
