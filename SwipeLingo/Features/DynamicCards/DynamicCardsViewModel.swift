import Foundation
import SwiftData

// MARK: - DynamicCardsViewModel
// Логика экрана каталога Pairs сетов.
// TODO: загрузка метаданных сетов из Firestore, фильтрация по AccessTier.

@Observable
final class DynamicCardsViewModel {
    var sets: [DynamicSet] = []
    var isLoading = false

    func loadSets(context: ModelContext) {
        // TODO: реализовать загрузку из SwiftData + синхронизацию с Firestore
        let descriptor = FetchDescriptor<DynamicSet>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        sets = (try? context.fetch(descriptor)) ?? []
    }
}
