import Foundation
import SwiftData

@Model
final class UserProfile {
    var name:         String = ""
    var cefrLevelRaw: String = CEFRLevel.a1.rawValue
    var firebaseUID:  String = ""

    /// Момент последнего изменения любого из полей выше — используется для выбора
    /// "победителя" при слиянии дублей (см. `UserProfileDedupeService`), если гонка
    /// CloudKit-синхронизации создаст больше одной записи для одного аккаунта.
    /// Обновляется явным вызовом `touch()` после мутации — НЕ через `didSet` на
    /// самих полях: SwiftData `@Model` переписывает доступ к свойствам через
    /// persistent backing store, и `didSet` на таких свойствах не гарантированно
    /// срабатывает (подтверждено тестами `UserProfileTests` — молча не срабатывал
    /// вовсе). Места вызова `touch()`: `OnboardingLevelViewModel.selectLevel`,
    /// `UserSessionSyncService.syncAfterVerifiedSession`, `ProfileView`.
    var updatedAt: Date = Date.now

    var cefrLevel: CEFRLevel {
        get { CEFRLevel(rawValue: cefrLevelRaw) ?? .a1 }
        set { cefrLevelRaw = newValue.rawValue }
    }

    /// Отображаемое имя: "Anonymous" если name пустое
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Anonymous" : trimmed
    }

    init(name: String = "", level: CEFRLevel = .a1) {
        self.name         = name
        self.cefrLevelRaw = level.rawValue
    }

    /// Обновляет `updatedAt` на "сейчас" — вызывать явно после любой мутации
    /// `name`/`cefrLevel(Raw)`/`firebaseUID`.
    func touch() {
        updatedAt = Date.now
    }
}
