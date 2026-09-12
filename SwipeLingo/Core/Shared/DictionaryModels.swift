import Foundation

// MARK: - Сырые Codable-структуры API
// Точно отражают JSON Free Dictionary API.
// https://api.dictionaryapi.dev/api/v2/entries/en/{word}

struct APIEntry: Codable {
    let word: String
    let phonetics: [APIPhonetic]
    let meanings: [APIMeaning]
}

struct APIPhonetic: Codable {
    let text: String?
    let audio: String?
}

struct APIMeaning: Codable {
    let partOfSpeech: String
    let definitions: [APIDefinitionItem]
    let synonyms: [String]
}

struct APIDefinitionItem: Codable {
    let definition: String
    let example: String?
}

// MARK: - Сырые модели Merriam-Webster Learner's Dictionary
// https://www.dictionaryapi.com/api/v3/references/learners/json/{word}?key={key}
//
// Ответ — это [Any]: реальные записи это объекты, а подсказки "did-you-mean" — строки.
// Перед декодированием фильтруем только объекты.
// Структура `def/sseq` — глубоко вложенные массивы со смешанными типами, парсится через
// JSONSerialization в DictionaryService, а не через Codable.

struct MWEntry: Decodable {
    let hwi: MWHeadwordInfo?
    /// Функциональная метка — часть речи, напр. "noun", "verb".
    let fl: String?
    /// Предформатированные краткие определения — из них уже убрана большая часть разметки.
    let shortdef: [String]

    enum CodingKeys: String, CodingKey { case hwi, fl, shortdef }
}

struct MWHeadwordInfo: Decodable {
    let prs: [MWPronunciation]?
}

struct MWPronunciation: Decodable {
    /// Транскрипция в нотации MW, напр. "ˈwərd".
    let mw: String?
    let sound: MWSound?
}

struct MWSound: Decodable {
    /// Базовое имя файла, используется для построения URL аудио.
    let audio: String?
}

// MARK: - Чистые структуры уровня приложения
// Используются DictionaryService и UI — отвязаны от деталей API.

struct DictionaryEntry {
    let word: String
    /// IPA-транскрипция, напр. "/həˈloʊ/", пустая строка, если недоступна.
    let transcription: String
    /// Строка HTTPS-URL аудио, пустая строка, если недоступна.
    let audioURL: String
    let meanings: [DictionaryMeaning]
}

struct DictionaryMeaning {
    let partOfSpeech: String
    let definitions: [DictionaryDefinition]
    /// Первые 5 синонимов из API.
    let synonyms: [String]
}

struct DictionaryDefinition {
    let text: String
    let example: String?
}

// MARK: - Mapping: raw API → clean app types

extension APIEntry {
    func toDictionaryEntry() -> DictionaryEntry {
        // Логируем сырые phonetics, чтобы можно было проверить, что реально вернул API
        log("'\(word)' — \(phonetics.count) phonetic(s):")
        for (i, p) in phonetics.enumerated() {
            log("[\(i)] text: \(p.text ?? "nil")  audio: \(p.audio ?? "nil")")
        }

        // Первый непустой текст транскрипции
        let transcription = phonetics
            .compactMap(\.text)
            .first(where: { !$0.isEmpty }) ?? ""

        // Первый непустой HTTPS-URL аудио (protocol-relative "//" нормализуется)
        let audioURL: String = phonetics
            .compactMap(\.audio)
            .compactMap { raw -> String? in
                guard !raw.isEmpty else { return nil }
                if raw.hasPrefix("//") { return "https:" + raw }
                return raw
            }
            .first(where: { $0.hasPrefix("https") }) ?? ""

        log("resolved → transcription: '\(transcription)'  audioURL: '\(audioURL)'")

        return DictionaryEntry(
            word: word,
            transcription: transcription,
            audioURL: audioURL,
            meanings: meanings.map { $0.toDictionaryMeaning() }
        )
    }
}

extension APIMeaning {
    func toDictionaryMeaning() -> DictionaryMeaning {
        DictionaryMeaning(
            partOfSpeech: partOfSpeech,
            definitions: definitions.map {
                DictionaryDefinition(text: $0.definition, example: $0.example)
            },
            synonyms: Array(synonyms.prefix(5))
        )
    }
}
