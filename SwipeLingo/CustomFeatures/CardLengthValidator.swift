// MARK: - CardLengthValidator
//
// Shared validation logic for card text fields (en, item).
// Cards are designed for words and short phrases, not sentences.
//
// Used by:
//   • AddEditCardView  (SwipeLingo target)
//   • ShareExtensionView (SwipeLingoShare target)
//
// Limits:
//   ≤ 50 chars  — OK
//   51–150 chars — warning (can still save / add)
//   > 150 chars  — tooLong (save / add blocked)

import Foundation

enum CardLengthState: Equatable {
    case ok
    case warning
    case tooLong
}

enum CardLengthValidator {
    static let warningLength = 50
    static let maxLength     = 150

    static func state(for text: String) -> CardLengthState {
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        if count > maxLength     { return .tooLong }
        if count > warningLength { return .warning }
        return .ok
    }
}
