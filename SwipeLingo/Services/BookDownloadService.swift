import Foundation
import FirebaseStorage
import FirebaseCore

// MARK: - BookDownloadService
//
// Downloads and caches book chapters (HTML) and cover images from Firebase Storage.
//
// Cache layout on disk (Documents/books/):
//   {firestoreId}/cover.jpg
//   {firestoreId}/chapters/0.html
//   {firestoreId}/chapters/1.html
//   ...
//
// Public API:
//   downloadChapter(book:index:)          → caches single chapter
//   downloadAllChapters(book:progress:)   → bulk download with progress callback
//   downloadCover(book:)                  → caches cover image
//   localChapterURL(book:index:)          → file:// URL for WKWebView
//   localCoverURL(book:)                  → file:// URL for AsyncImage
//   isChapterDownloaded(book:index:)
//   allChaptersDownloaded(book:)

@Observable
final class BookDownloadService {

    static let shared = BookDownloadService()

    // bookId → 0.0-1.0
    var downloadProgress: [String: Double] = [:]

    private let fm = FileManager.default

    // MARK: - Directory helpers

    private func booksRoot() -> URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("books", isDirectory: true)
    }

    private func bookDir(_ book: Book) -> URL {
        booksRoot().appendingPathComponent(book.firestoreId, isDirectory: true)
    }

    private func chaptersDir(_ book: Book) -> URL {
        bookDir(book).appendingPathComponent("chapters", isDirectory: true)
    }

    // MARK: - Public URL helpers

    func localChapterURL(book: Book, index: Int) -> URL {
        chaptersDir(book).appendingPathComponent("\(index).html")
    }

    func localCoverURL(book: Book) -> URL {
        bookDir(book).appendingPathComponent("cover.jpg")
    }

    func isChapterDownloaded(book: Book, index: Int) -> Bool {
        fm.fileExists(atPath: localChapterURL(book: book, index: index).path)
    }

    func allChaptersDownloaded(book: Book) -> Bool {
        (0..<book.totalChapters).allSatisfy { isChapterDownloaded(book: book, index: $0) }
    }

    func isCoverDownloaded(book: Book) -> Bool {
        fm.fileExists(atPath: localCoverURL(book: book).path)
    }

    // MARK: - Download chapter

    func downloadChapter(book: Book, index: Int) async throws {
        let dest = localChapterURL(book: book, index: index)
        guard !fm.fileExists(atPath: dest.path) else { return }

        try createDirectories(for: book)
        let path = book.chapterStoragePath(at: index)
        let data = try await fetchFromStorage(path: path)
        try data.write(to: dest)
        log("[Books] Downloaded chapter \(index) of '\(book.title)'")
    }

    // MARK: - Download all chapters

    func downloadAllChapters(
        book: Book,
        progress: ((Double) -> Void)? = nil
    ) async throws {
        try createDirectories(for: book)
        let total = book.totalChapters
        for index in 0..<total {
            try await downloadChapter(book: book, index: index)
            let fraction = Double(index + 1) / Double(total)
            downloadProgress[book.firestoreId] = fraction
            progress?(fraction)
        }
        downloadProgress.removeValue(forKey: book.firestoreId)
        log("[Books] All chapters downloaded for '\(book.title)'", level: .info)
    }

    // MARK: - Download cover

    @discardableResult
    func downloadCover(book: Book) async throws -> URL {
        let dest = localCoverURL(book: book)
        guard !fm.fileExists(atPath: dest.path) else { return dest }

        try createDirectories(for: book)
        let data = try await fetchFromStorage(path: book.coverStoragePath)
        try data.write(to: dest)
        return dest
    }

    // MARK: - Fetch (HTTP or Firebase Storage)

    private func fetchFromStorage(path: String) async throws -> Data {
        // Debug stub: if path is a full HTTP URL, download directly
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            guard let url = URL(string: path) else {
                throw BookDownloadError.invalidPath(path)
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw BookDownloadError.httpError(http.statusCode, url.absoluteString)
            }
            return data
        }
        // Firebase Storage path
        guard FirebaseApp.app() != nil else {
            throw BookDownloadError.firebaseNotConfigured
        }
        let ref = Storage.storage().reference(withPath: path)
        // 10 MB max per chapter
        return try await ref.data(maxSize: 10 * 1024 * 1024)
    }

    // MARK: - Cache management

    func clearCache(firestoreId: String) {
        let dir = booksRoot().appendingPathComponent(firestoreId, isDirectory: true)
        try? fm.removeItem(at: dir)
        log("[Books] Cleared cache for \(firestoreId)", level: .info)
    }

    // MARK: - Helpers

    private func createDirectories(for book: Book) throws {
        let chDir = chaptersDir(book)
        if !fm.fileExists(atPath: chDir.path) {
            try fm.createDirectory(at: chDir, withIntermediateDirectories: true)
        }
    }
}

// MARK: - BookDownloadError

enum BookDownloadError: LocalizedError {
    case firebaseNotConfigured
    case chapterNotFound(Int)
    case invalidPath(String)
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .firebaseNotConfigured:       return "Firebase is not configured."
        case .chapterNotFound(let i):      return "Chapter \(i) not found in storage."
        case .invalidPath(let p):          return "Invalid storage path: \(p)"
        case .httpError(let code, let url): return "HTTP \(code) downloading \(url)"
        }
    }
}
