import Foundation

// MARK: - DictionaryService
//
// Tries Merriam-Webster Learner's Dictionary first (better definitions + examples).
// Falls back to Free Dictionary API (dictionaryapi.dev) if MW fails.
// Safe to call from @MainActor context — URLSession.data suspends off-MainActor internally.

struct DictionaryService {

    private static let mwBaseURL      = "https://www.dictionaryapi.com/api/v3/references/learners/json/"
    private static let freeBaseURL    = "https://api.dictionaryapi.dev/api/v2/entries/en/"

    // MARK: - Errors

    enum DictionaryError: LocalizedError {
        case invalidWord
        case notFound
        case networkError(Error)
        case decodingError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidWord:          return "Invalid word"
            case .notFound:             return "Word not found in dictionary"
            case .networkError(let e):  return e.localizedDescription
            case .decodingError(let e): return "Data error: \(e.localizedDescription)"
            }
        }
    }

    // MARK: - Public API

    /// Looks up `word`: tries Merriam-Webster first, falls back to Free Dictionary.
    func lookup(word: String) async throws -> DictionaryEntry {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DictionaryError.invalidWord }

        if let entry = try? await fetchMW(word: trimmed) {
            log("MW lookup succeeded for '\(trimmed)'")
            // MW иногда не содержит транскрипцию — берём её из FreeDictionary
            if entry.transcription.isEmpty,
               let freeEntry = try? await fetchFreeDictionary(word: trimmed),
               !freeEntry.transcription.isEmpty {
                log("MW transcription empty — using FreeDictionary transcription for '\(trimmed)'")
                return DictionaryEntry(
                    word:          entry.word,
                    transcription: freeEntry.transcription,
                    audioURL:      entry.audioURL,
                    meanings:      entry.meanings
                )
            }
            return entry
        }
        log("MW lookup failed for '\(trimmed)' — falling back to FreeDictionary")
        return try await fetchFreeDictionary(word: trimmed)
    }

    // MARK: - Merriam-Webster

    private func fetchMW(word: String) async throws -> DictionaryEntry {
        guard
            let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: Self.mwBaseURL + encoded + "?key=" + Secrets.merriamWebsterKey)
        else { throw DictionaryError.invalidWord }

        let data: Data
        do {
            let (responseData, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw DictionaryError.notFound
            }
            data = responseData
        } catch let e as DictionaryError { throw e
        } catch { throw DictionaryError.networkError(error) }

        // MW response is [Any]: real entries are objects, suggestions are strings.
        // Filter to objects only, then decode.
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

        // Use the first entry that has at least one definition.
        guard let entry = entries.first(where: { !$0.shortdef.isEmpty }) else {
            throw DictionaryError.notFound
        }

        let transcription = entry.hwi?.prs?.first(where: { $0.mw != nil })?.mw ?? ""
        let audioURL      = entry.hwi?.prs?.compactMap(\.sound?.audio).first.map(mwAudioURL) ?? ""
        let partOfSpeech  = entry.fl ?? ""
        let example       = extractFirstExample(from: rawArray)

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
                               meanings: [meaning])
    }

    /// Constructs the MW audio CDN URL from a sound filename.
    /// Subdirectory rules: https://dictionaryapi.com/products/json#sec-2.prs
    private func mwAudioURL(_ audio: String) -> String {
        let subdir: String
        if audio.hasPrefix("bix")           { subdir = "bix" }
        else if audio.hasPrefix("gg")       { subdir = "gg" }
        else if audio.first?.isNumber == true { subdir = "number" }
        else                                { subdir = String(audio.prefix(1)) }
        return "https://media.merriam-webster.com/audio/prons/en/us/mp3/\(subdir)/\(audio).mp3"
    }

    /// Extracts the first verbal illustration (example sentence) from MW `def/sseq/dt/vis`.
    /// Uses JSONSerialization because `sseq` is a deeply-nested mixed-type array.
    private func extractFirstExample(from rawArray: [Any]) -> String? {
        for item in rawArray {
            guard let entry = item as? [String: Any],
                  let defs  = entry["def"] as? [[String: Any]] else { continue }
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
        }
        return nil
    }

    /// Strips MW inline markup, leaving clean readable text.
    /// e.g. "{it}word{/it}" → "word", "{bc}" → ": ", "{d_link|word|id}" → "word"
    private func stripMWMarkup(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "{bc}",    with: ": ")
        result = result.replacingOccurrences(of: "{ldquo}", with: "\u{201C}")
        result = result.replacingOccurrences(of: "{rdquo}", with: "\u{201D}")
        result = result.replacingOccurrences(of: "{amp}",   with: "&")

        // {tag|display|id} or {tag|display} → display text (first pipe-segment)
        let pipePattern = "\\{[a-z_]+\\|([^|{}]+)(?:\\|[^{}]*)?\\}"
        if let regex = try? NSRegularExpression(pattern: pipePattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range,
                                                    withTemplate: "$1")
        }

        // Remove remaining {tags}
        let tagPattern = "\\{[^{}]*\\}"
        if let regex = try? NSRegularExpression(pattern: tagPattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range,
                                                    withTemplate: "")
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Free Dictionary (fallback)

    private func fetchFreeDictionary(word: String) async throws -> DictionaryEntry {
        guard
            let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: Self.freeBaseURL + encoded)
        else { throw DictionaryError.invalidWord }

        let data: Data
        do {
            let (responseData, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                throw DictionaryError.notFound
            }
            data = responseData
        } catch let e as DictionaryError { throw e
        } catch { throw DictionaryError.networkError(error) }

        do {
            let entries = try JSONDecoder().decode([APIEntry].self, from: data)
            guard let first = entries.first else { throw DictionaryError.notFound }
            return first.toDictionaryEntry()
        } catch let e as DictionaryError { throw e
        } catch { throw DictionaryError.decodingError(error) }
    }
}
