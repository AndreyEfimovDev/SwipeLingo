import Foundation
import SwiftData

// MARK: - BookProgress

@Model class BookProgress {

    var id:           UUID   = UUID()
    var bookId:       UUID   = UUID()
    var chapterIndex: Int    = 0
    var scrollOffset: Double = 0.0   // 0.0 – 1.0
    var lastReadAt:   Date   = Date()

    init(bookId: UUID, chapterIndex: Int = 0, scrollOffset: Double = 0) {
        self.id           = UUID()
        self.bookId       = bookId
        self.chapterIndex = chapterIndex
        self.scrollOffset = scrollOffset
        self.lastReadAt   = Date.now
    }
}
