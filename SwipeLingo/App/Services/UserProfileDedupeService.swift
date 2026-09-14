import Foundation
import SwiftData

// MARK: - UserProfileDedupeService
//
// Слияние дублей UserProfile — та же гонка CloudKit-синхронизации, что решена для
// AppSyncState (см. AppSyncStateManager.claim(firebaseUID:)), только у UserProfile
// уже есть естественный ключ аккаунта — firebaseUID, так что отдельная id-схема/claim
// не нужны, дедупликация работает прямо по этому полю.
//
// Профили с ЧУЖИМ непустым firebaseUID (общий iCloud, но другой реальный
// Firebase-аккаунт на этом устройстве — напр. семейный Apple ID) НЕ трогаются —
// иначе можно было бы смешать имя/уровень одного реального человека с другим.
// "Моими" (кандидатами на merge) считаются только профили с совпадающим firebaseUID
// либо ещё непривязанные (firebaseUID пустой — только что созданы, UID ещё не
// проставлен, см. UserSessionSyncService).

struct UserProfileDedupeService {

    /// Возвращает единственный профиль текущего аккаунта, сливая дубли при
    /// необходимости. Среди "своих" профилей побеждает самый недавно изменённый
    /// (`updatedAt`) — та же логика, что в `AppSyncStateManager.mergeDuplicates`
    /// (primary = самый свежий), остальные удаляются. Профили с чужим `firebaseUID`
    /// не трогаются и в результат не попадают — если среди "своих" ничего не
    /// нашлось, возвращает `nil` (вызывающая сторона создаёт новый профиль).
    func resolveProfile(firebaseUID: String, allProfiles: [UserProfile], context: ModelContext) -> UserProfile? {
        let mine = allProfiles.filter { $0.firebaseUID.isEmpty || $0.firebaseUID == firebaseUID }
        guard mine.count > 1 else { return mine.first }

        log("Found \(mine.count) UserProfile records for account — merging duplicates", level: .warning)
        let sorted = mine.sorted { $0.updatedAt > $1.updatedAt }
        let primary = sorted[0]
        for duplicate in sorted.dropFirst() {
            context.delete(duplicate)
        }
        context.saveWithErrorHandling()
        log("Merged \(mine.count) UserProfile duplicates → 1", level: .info)
        return primary
    }

    /// Есть ли среди `allProfiles` записи, принадлежащие ДРУГОМУ аккаунту (непустой
    /// `firebaseUID`, отличный от текущего)? Используется для предупреждения
    /// пользователя — см. `ForeignAccountWarningService`.
    func hasForeignProfiles(firebaseUID: String, allProfiles: [UserProfile]) -> Bool {
        allProfiles.contains { !$0.firebaseUID.isEmpty && $0.firebaseUID != firebaseUID }
    }
}
