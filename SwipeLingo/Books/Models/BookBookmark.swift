import Foundation
import SwiftData

// MARK: - BookBookmark

@Model class BookBookmark {

    var id:           UUID   = UUID()
    var bookId:       UUID   = UUID()
    var chapterIndex: Int    = 0
    var chapterTitle: String = ""
    var scrollOffset: Double = 0.0   // 0.0 – 1.0
    var selectedText: String?
    var createdAt:    Date   = Date()

    init(
        bookId:       UUID,
        chapterIndex: Int,
        chapterTitle: String,
        scrollOffset: Double,
        selectedText: String? = nil
    ) {
        self.id           = UUID()
        self.bookId       = bookId
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.scrollOffset = scrollOffset
        self.selectedText = selectedText
        self.createdAt    = Date.now
    }
}
