import Foundation
import SwiftData

// MARK: - BookCatalogSyncing
//
// Источник каталога книг: заполняет SwiftData книгами (метаданные + оглавление).
// Реализации: BookFBService (Firestore, релиз) и MockBookCatalog (мок-книги без сети, только DEBUG).
// Какая используется — решает composition root (AppDependencies.bookCatalog).
// @MainActor явно: протокол не наследует изоляцию по умолчанию, а все реализации и вызывающие
// работают с mainContext на MainActor — без этого ModelContext (не Sendable) «пересекал» бы
// границу изоляции (в тестовом таргете на Swift 6 это ошибка компиляции).

@MainActor
protocol BookCatalogSyncing {
    /// Загружает книги каталога в `context` (upsert по `firestoreId`, локальные книги не удаляются).
    /// - Parameter forceFullSync: игнорировать дату последнего синка и загрузить каталог целиком.
    func syncBooks(into context: ModelContext, forceFullSync: Bool) async
}
