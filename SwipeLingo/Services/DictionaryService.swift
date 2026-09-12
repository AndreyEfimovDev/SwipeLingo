import Foundation

// MARK: - DictionaryService
//
// Сначала пробует Merriam-Webster Learner's Dictionary (лучше определения + примеры).
// Если MW не сработал — откатывается на Free Dictionary API (dictionaryapi.dev).
// Безопасно вызывать из контекста @MainActor — URLSession.data внутри приостанавливается вне MainActor.

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

        // Берём первую запись, у которой есть хотя бы одно определение.
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

    /// Строит URL MW audio CDN по имени звукового файла.
    /// Правила поддиректорий: https://dictionaryapi.com/products/json#sec-2.prs
    private func mwAudioURL(_ audio: String) -> String {
        let subdir: String
        if audio.hasPrefix("bix")           { subdir = "bix" }
        else if audio.hasPrefix("gg")       { subdir = "gg" }
        else if audio.first?.isNumber == true { subdir = "number" }
        else                                { subdir = String(audio.prefix(1)) }
        return "https://media.merriam-webster.com/audio/prons/en/us/mp3/\(subdir)/\(audio).mp3"
    }

    /// Извлекает первый пример-иллюстрацию (example sentence) из MW `def/sseq/dt/vis`.
    /// Использует JSONSerialization, потому что `sseq` — глубоко вложенный массив со смешанными типами.
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
