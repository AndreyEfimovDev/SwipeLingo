import Foundation
import SwiftData

// MARK: - BookProgress

@Model class BookProgress {

    var id:           UUID
    var bookId:       UUID
    var chapterIndex: Int
    var scrollOffset: Double   // 0.0 – 1.0
    var lastReadAt:   Date

    init(bookId: UUID, chapterIndex: Int = 0, scrollOffset: Double = 0) {
        self.id           = UUID()
        self.bookId       = bookId
        self.chapterIndex = chapterIndex
        self.scrollOffset = scrollOffset
        self.lastReadAt   = Date.now
    }
}
