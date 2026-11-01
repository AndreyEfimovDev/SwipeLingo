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

/// Откуда взята запись словаря. Нужен, чтобы запись из резервного источника не вытесняла более качественную.
enum DictionarySource {
    case merriamWebster
    case freeDictionary
}

struct DictionaryEntry {
    let word: String
    /// IPA-транскрипция, напр. "/həˈloʊ/", пустая строка, если недоступна.
    let transcription: String
    /// Строка HTTPS-URL аудио, пустая строка, если недоступна.
    let audioURL: String
    let meanings: [DictionaryMeaning]
    /// Источник свежей записи; `nil` у записи, собранной из кэша карточки.
    var source: DictionarySource? = nil
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

        let (transcription, audioURL) = resolvePronunciation()

        log("resolved → transcription: '\(transcription)'  audioURL: '\(audioURL)'")

        return DictionaryEntry(
            word: word,
            transcription: transcription,
            audioURL: audioURL,
            meanings: meanings.map { $0.toDictionaryMeaning() }
        )
    }

    /// Выбирает транскрипцию и аудио из одного варианта произношения.
    ///
    /// Free отдаёт несколько вариантов (US/UK/AU, ударный/безударный), и у части из них нет
    /// аудио или текста. Если брать первое непустое поле каждого вида по отдельности, транскрипция
    /// и звук оказываются от разных произношений (у «you» было /jʉː/ при аудио /jə/).
    ///
    /// Порядок выбора:
    /// 1. вариант с текстом и аудио, где аудио американское ударное (`isPreferredAudio`);
    /// 2. первый вариант с текстом и аудио;
    /// 3. полных вариантов нет — первый непустой текст и первое аудио по отдельности.
    ///
    /// - Returns: Транскрипция и HTTPS-URL аудио; пустая строка, если поле недоступно.
    private func resolvePronunciation() -> (transcription: String, audioURL: String) {
        let variants = phonetics.map { (text: $0.text ?? "", audio: Self.normalizedAudioURL($0.audio)) }
        let complete = variants.filter { !$0.text.isEmpty && !$0.audio.isEmpty }

        if let best = complete.first(where: { isPreferredAudio($0.audio) }) ?? complete.first {
            return (best.text, best.audio)
        }
        return (
            variants.first(where: { !$0.text.isEmpty })?.text ?? "",
            variants.first(where: { !$0.audio.isEmpty })?.audio ?? ""
        )
    }

    /// Приводит сырой URL аудио к HTTPS: protocol-relative `//…` дополняется схемой.
    ///
    /// - Returns: HTTPS-URL или пустая строка, если аудио нет или схема не HTTPS.
    private static func normalizedAudioURL(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        let url = raw.hasPrefix("//") ? "https:" + raw : raw
        return url.hasPrefix("https") ? url : ""
    }

    /// Американское ударное произношение — по имени файла Free (`you-us-stressed.mp3`, `reliable-us.mp3`).
    ///
    /// Формат имён у Free не документирован, поэтому правило мягкое: оно только выбирает среди
    /// полных вариантов, а при несовпадении остаётся первый полный. Префикс со словом отрезается,
    /// чтобы слово вроде «us» не принималось за метку региона.
    private func isPreferredAudio(_ audioURL: String) -> Bool {
        guard let url = URL(string: audioURL) else { return false }
        var name = url.deletingPathExtension().lastPathComponent.lowercased()
        let wordPrefix = word.lowercased() + "-"
        if name.hasPrefix(wordPrefix) { name.removeFirst(wordPrefix.count) }
        let tags = name.split(separator: "-")
        return tags.contains("us") && !tags.contains("unstressed")
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
