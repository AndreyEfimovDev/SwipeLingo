import Foundation

// MARK: - BookCatalogVisibility
//
// Кому показывать книгу каталога. Флаг `isPublished` живёт только в Firestore (/books/{id}) и меняется из Admin:
//   • true  — книга загружается у всех;
//   • иначе — черновик: загружается только у тестировщиков (Secrets.bookTesterUIDs, вне git) с плашкой TESTING —
//     чтобы проверить форматирование книги в Release-сборке до того, как открыть её пользователям.
// Отсутствие поля = черновик (строгое правило).

enum BookCatalogVisibility {

    /// Что сделать с книгой из снимка Firestore.
    enum Decision: Equatable {
        /// Добавить или обновить локальную книгу; `isTesting` — показывать плашку TESTING.
        case show(isTesting: Bool)
        /// Не загружать.
        case skip
    }

    /// Решение по одной книге каталога.
    /// - Parameters:
    ///   - isPublished: значение поля `isPublished` из Firestore; `nil` — поля нет.
    ///   - isTester: текущий пользователь — тестировщик книг.
    static func decide(isPublished: Bool?, isTester: Bool) -> Decision {
        if isPublished == true { return .show(isTesting: false) }
        return isTester ? .show(isTesting: true) : .skip
    }

    /// Какие локальные книги удалить после синка с сервера: тех, что нет в каталоге (удалены в Admin), и
    /// снятых с публикации для этого пользователя. Документ, который не удалось разобрать, в каталоге есть —
    /// его книга остаётся (сбой формата не должен стирать прогресс чтения).
    /// - Parameters:
    ///   - localIds: `firestoreId` локальных книг.
    ///   - catalogIds: id всех документов каталога в ответе сервера.
    ///   - skippedIds: id книг каталога с решением `.skip`.
    /// - Returns: `firestoreId` книг, которые нужно удалить.
    static func firestoreIdsToRemove(localIds: [String], catalogIds: Set<String>, skippedIds: Set<String>) -> Set<String> {
        Set(localIds.filter { !catalogIds.contains($0) || skippedIds.contains($0) })
    }

    /// Является ли пользователь с данным Firebase UID тестировщиком книг.
    static func isTester(uid: String?, testerUIDs: Set<String> = Secrets.bookTesterUIDs) -> Bool {
        guard let uid, !uid.isEmpty else { return false }
        return testerUIDs.contains(uid)
    }
}
