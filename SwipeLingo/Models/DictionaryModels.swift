import Foundation

// MARK: - Raw API Codable structs
// Mirror the Free Dictionary API JSON exactly.
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

// MARK: - App-layer clean structs
// Used by DictionaryService and the UI — decoupled from API details.

struct DictionaryEntry {
    let word: String
    /// IPA transcription, e.g. "/həˈloʊ/", empty string if unavailable.
    let transcription: String
    /// HTTPS audio URL string, empty string if unavailable.
    let audioURL: String
    let meanings: [DictionaryMeaning]
}

struct DictionaryMeaning {
    let partOfSpeech: String
    let definitions: [DictionaryDefinition]
    /// First 5 synonyms from the API.
    let synonyms: [String]
}

struct DictionaryDefinition {
    let text: String
    let example: String?
}

// MARK: - Mapping: raw API → clean app types

extension APIEntry {
    func toDictionaryEntry() -> DictionaryEntry {
        // Log raw phonetics so we can verify what the API returns
        print("[DictionaryAPI] '\(word)' — \(phonetics.count) phonetic(s):")
        for (i, p) in phonetics.enumerated() {
            print("  [\(i)] text: \(p.text ?? "nil")  audio: \(p.audio ?? "nil")")
        }

        // First non-empty transcription text
        let transcription = phonetics
            .compactMap(\.text)
            .first(where: { !$0.isEmpty }) ?? ""

        // First non-empty HTTPS audio URL (protocol-relative "//" is normalised)
        let audioURL: String = phonetics
            .compactMap(\.audio)
            .compactMap { raw -> String? in
                guard !raw.isEmpty else { return nil }
                if raw.hasPrefix("//") { return "https:" + raw }
                return raw
            }
            .first(where: { $0.hasPrefix("https") }) ?? ""

        print("[DictionaryAPI] resolved → transcription: '\(transcription)'  audioURL: '\(audioURL)'")

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
