// MARK: - CardLengthValidator
//
// Общая логика валидации текстовых полей карточки (en, item).
// Карточки рассчитаны на слова и короткие фразы, а не предложения.
//
// Используется:
//   • AddEditCardView  (таргет SwipeLingo)
//   • ShareExtensionView (таргет SwipeLingoShare)
//
// Лимиты:
//   ≤ 50 символов  — OK
//   51–150 символов — warning (сохранить / добавить ещё можно)
//   > 150 символов  — tooLong (сохранение / добавление заблокировано)

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
