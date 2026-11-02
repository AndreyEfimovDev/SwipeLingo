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

    /// Единственное место в приложении, которое создаёт `UserProfile` "по
    /// требованию" — единый источник правды на вопрос "есть ли профиль для этого
    /// аккаунта", вместо того чтобы каждый вызывающий (`OnboardingLevelViewModel`,
    /// `UserSessionSyncService`, `ProfileView`) независимо решал это по своему
    /// снапшоту. Синхронная функция (НЕ `async`) — в неё физически нельзя вставить
    /// `await`, компилятор не даст; вызов на MainActor поэтому гарантированно
    /// атомарен от fetch до insert. Какой бы из вызывающих ни сработал первым,
    /// следующий увидит уже созданный профиль через свой собственный `fetch` (сама
    /// функция всегда фетчит заново, не принимает снапшот снаружи — так фетч,
    /// проверка и создание остаются одним неразрывным участком, а не "вызывающий
    /// сам фетчит где-то до, потом передаёт сюда возможно устаревший список").
    ///
    /// Если "мой" профиль нашёлся, но ещё не привязан (`firebaseUID` пуст) —
    /// привязывает его. Только вызывать из мест, которые действительно должны
    /// иметь право создать профиль (`.onAppear`, после verified-сессии) — не из
    /// вычисляемых свойств, читаемых многократно/пассивно.
    @discardableResult
    func resolveOrCreateProfile(firebaseUID: String, context: ModelContext) -> UserProfile {
        let allProfiles = context.fetchWithErrorHandling(FetchDescriptor<UserProfile>())
        if let existing = resolveProfile(firebaseUID: firebaseUID, allProfiles: allProfiles, context: context) {
            if existing.firebaseUID.isEmpty { existing.firebaseUID = firebaseUID }
            return existing
        }
        let fresh = UserProfile()
        fresh.firebaseUID = firebaseUID
        context.insert(fresh)
        return fresh
    }
}
