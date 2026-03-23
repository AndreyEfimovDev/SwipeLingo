import Foundation

// MARK: - DictionaryService
//
// Stateless value-type service (mirrors SRSService / PileService pattern).
// Fetches from Free Dictionary API and maps to app-layer DictionaryEntry.
// Safe to call from @MainActor context — URLSession.data suspends off-MainActor
// internally, so no blocking of the main thread.

struct DictionaryService {

    private static let baseURL = "https://api.dictionaryapi.dev/api/v2/entries/en/"

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

    /// Looks up `word` in the Free Dictionary API.
    /// Returns the first matching `DictionaryEntry` or throws `DictionaryError`.
    func lookup(word: String) async throws -> DictionaryEntry {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DictionaryError.invalidWord }

        guard
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: Self.baseURL + encoded)
        else { throw DictionaryError.invalidWord }

        let data: Data
        do {
            let (responseData, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                throw DictionaryError.notFound
            }
            data = responseData
        } catch let e as DictionaryError {
            throw e
        } catch {
            throw DictionaryError.networkError(error)
        }

        do {
            let entries = try JSONDecoder().decode([APIEntry].self, from: data)
            guard let first = entries.first else { throw DictionaryError.notFound }
            return first.toDictionaryEntry()
        } catch let e as DictionaryError {
            throw e
        } catch {
            throw DictionaryError.decodingError(error)
        }
    }
}
