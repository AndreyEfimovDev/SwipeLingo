import Foundation
import SwiftData

// MARK: - BookReaderViewModel

@Observable
final class BookReaderViewModel {

    let book: Book

    var chapterIndex:    Int     = 0
    var scrollOffset:    Double  = 0      // 0.0 – 1.0
    var isDownloading:   Bool    = false
    var downloadFraction: Double = 0
    var isChapterReady:  Bool    = false

    // Word tap → dictionary lookup
    var tappedWord:      String? = nil
    var showDictionary:  Bool    = false

    // Chapter/bookmark sheet
    var showChapterList:  Bool = false
    var showBookmarks:    Bool = false
    // Drives bookmark icon animation: true for 0.6s after adding
    var bookmarkJustAdded: Bool = false

    private let downloader = BookDownloadService.shared
    private var saveTask: Task<Void, Never>? = nil

    init(book: Book, progress: BookProgress?) {
        self.book         = book
        self.chapterIndex = progress?.chapterIndex ?? 0
        self.scrollOffset = progress?.scrollOffset ?? 0
        self.isChapterReady = downloader.isChapterDownloaded(book: book, index: chapterIndex)
    }

    // MARK: - Chapter navigation

    var currentChapter: BookChapter? {
        book.chapters.first { $0.index == chapterIndex }
    }

    var hasPrevious: Bool { chapterIndex > 0 }
    var hasNext:     Bool { chapterIndex < book.totalChapters - 1 }

    func goToPrevious() {
        guard hasPrevious else { return }
        chapterIndex -= 1
        scrollOffset  = 0
        refreshChapterReady()
    }

    func goToNext() {
        guard hasNext else { return }
        chapterIndex += 1
        scrollOffset  = 0
        refreshChapterReady()
    }

    func goToChapter(_ index: Int) {
        chapterIndex = index
        scrollOffset = 0
        refreshChapterReady()
    }

    private func refreshChapterReady() {
        isChapterReady = downloader.isChapterDownloaded(book: book, index: chapterIndex)
    }

    // MARK: - Download

    func downloadCurrentChapterIfNeeded() async {
        guard !isChapterReady else { return }
        isDownloading = true
        defer { isDownloading = false }
        do {
            try await downloader.downloadChapter(book: book, index: chapterIndex)
            isChapterReady = true
        } catch {
            log("[Reader] Download failed: \(error)", level: .error)
        }
    }

    func downloadAllIfNeeded(context: ModelContext? = nil) async {
        guard !downloader.allChaptersDownloaded(book: book) else {
            clearNewFlag(context: context)
            return
        }
        isDownloading = true
        defer { isDownloading = false }
        do {
            try await downloader.downloadAllChapters(book: book) { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.downloadFraction = fraction
                }
            }
            clearNewFlag(context: context)
        } catch {
            log("[Reader] Bulk download failed: \(error)", level: .error)
        }
    }

    private func clearNewFlag(context: ModelContext?) {
        guard book.isNew, let context else { return }
        book.isNew = false
        context.saveWithErrorHandling()
    }

    // MARK: - Local chapter URL

    func chapterFileURL() -> URL? {
        guard isChapterReady else { return nil }
        return downloader.localChapterURL(book: book, index: chapterIndex)
    }

    // MARK: - Progress persistence

    func updateScrollOffset(_ offset: Double, context: ModelContext) {
        scrollOffset = offset
        scheduleSave(context: context)
    }

    private func scheduleSave(context: ModelContext) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            saveProgress(context: context)
        }
    }

    func saveProgress(context: ModelContext) {
        let bookId    = book.id
        let predicate = #Predicate<BookProgress> { $0.bookId == bookId }
        let existing  = (try? context.fetch(FetchDescriptor(predicate: predicate)))?.first

        if let progress = existing {
            progress.chapterIndex = chapterIndex
            progress.scrollOffset = scrollOffset
            progress.lastReadAt   = Date.now
        } else {
            let progress = BookProgress(
                bookId:       book.id,
                chapterIndex: chapterIndex,
                scrollOffset: scrollOffset
            )
            context.insert(progress)
        }
        context.saveWithErrorHandling()
    }

    // MARK: - Word tap

    func handleWordTap(_ word: String) {
        let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
        guard !cleaned.isEmpty else { return }
        tappedWord    = cleaned
        showDictionary = true
    }

    // MARK: - Bookmarks

    func addBookmark(context: ModelContext) {
        let title = currentChapter?.title ?? "Chapter \(chapterIndex + 1)"
        let bookmark = BookBookmark(
            bookId:       book.id,
            chapterIndex: chapterIndex,
            chapterTitle: title,
            scrollOffset: scrollOffset
        )
        context.insert(bookmark)
        context.saveWithErrorHandling()
        log("[Reader] Bookmark added: \(title)", level: .info)

        // Animate icon briefly
        bookmarkJustAdded = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            bookmarkJustAdded = false
        }
    }

    /// Delete a specific bookmark (called from the list via swipe).
    func deleteBookmark(_ bookmark: BookBookmark, context: ModelContext) {
        context.delete(bookmark)
        context.saveWithErrorHandling()
        log("[Reader] Bookmark deleted: \(bookmark.chapterTitle)", level: .info)
    }

    /// Remove all bookmarks on the current chapter (context menu → Remove Bookmark).
    func removeBookmark(from bookmarks: [BookBookmark], context: ModelContext) {
        bookmarks
            .filter { $0.chapterIndex == chapterIndex }
            .forEach { context.delete($0) }
        context.saveWithErrorHandling()
        log("[Reader] Bookmark removed for chapter \(chapterIndex)", level: .info)
    }

    /// True if the current chapter already has at least one bookmark.
    func hasBookmark(in bookmarks: [BookBookmark]) -> Bool {
        bookmarks.contains { $0.chapterIndex == chapterIndex }
    }

}
