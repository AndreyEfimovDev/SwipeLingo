import Foundation
import SwiftData

// MARK: - PairsViewModel
// Логика экрана каталога Pairs сетов.
// TODO: загрузка метаданных сетов из Firestore, фильтрация по AccessTier.

@Observable
final class PairsViewModel {
    var sets: [PairsSet] = []
    var isLoading = false

    func loadSets(context: ModelContext) {
        // TODO: реализовать загрузку из SwiftData + синхронизацию с Firestore
        let descriptor = FetchDescriptor<PairsSet>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        sets = (try? context.fetch(descriptor)) ?? []
    }
}
