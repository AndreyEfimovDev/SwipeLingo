import Foundation
import SwiftData
import FirebaseAuth

// MARK: - UserSessionSyncService
//
// Синхронизация после подтверждённого входа (isSessionVerified): локальный
// UserProfile (SwiftData) + удалённый документ пользователя в Firestore.
// Вынесен из SwipeLingoApp — это бизнес-логика синхронизации, а не забота
// точки входа. appSyncStateService (флаг онбординга) сюда не передаётся —
// сервис только сообщает "returning user?", решение о флаге остаётся у
// вызывающей стороны (composition root), чтобы сервис не держал ссылку на
// чужое @State.

/// Результат `syncAfterVerifiedSession` — помимо статуса "возвращающийся
/// пользователь", несёт флаг обнаружения чужих локальных данных (см.
/// `hasForeignProfileData`), чтобы вызывающая сторона могла решить, нужно ли
/// предупреждение (см. `ForeignAccountWarningService`), не делая для этого
/// повторный fetch `UserProfile`.
struct UserSessionSyncResult {
    /// `true`, если это "возвращающийся" пользователь — в документе Firestore
    /// уже был сохранён `cefrLevel` (второе устройство). Вызывающая сторона
    /// использует это, чтобы пропустить онбординг.
    let isReturningUser: Bool
    /// `true`, если среди локальных `UserProfile` найдены записи ДРУГОГО
    /// аккаунта (общий iCloud, но другой Firebase-аккаунт на этом устройстве).
    let hasForeignProfileData: Bool
}

struct UserSessionSyncService {

    /// Синхронизирует локальный `UserProfile` и удалённый документ пользователя
    /// после подтверждённого входа. Создаёт профиль, если его ещё нет; сбрасывает
    /// его, если UID сменился (другой пользователь вошёл на этом устройстве);
    /// проставляет UID и имя из Firebase; затем синхронизирует профиль и подписку
    /// с Firestore.
    @discardableResult
    func syncAfterVerifiedSession(
        user: FirebaseAuth.User,
        container: ModelContainer,
        nativeLanguage: NativeLanguage,
        userService: UserFBService
    ) async -> UserSessionSyncResult {
        let ctx = container.mainContext
        let allProfiles = ctx.fetchWithErrorHandling(FetchDescriptor<UserProfile>())
        let dedupeService = UserProfileDedupeService()
        // Фильтрует "мои" профили (свой firebaseUID/непривязанные) и мержит дубли
        // среди них — профили ДРУГИХ аккаунтов на этом же iCloud не трогает.
        var profile = dedupeService.resolveProfile(
            firebaseUID: user.uid, allProfiles: allProfiles, context: ctx
        )
        let hasForeignProfileData = dedupeService.hasForeignProfiles(
            firebaseUID: user.uid, allProfiles: allProfiles
        )

        if profile == nil {
            let p = UserProfile()
            ctx.insert(p)
            profile = p
        }

        // Несовпадение UID теоретически не должно происходить — resolveProfile уже
        // гарантирует пустой/совпадающий firebaseUID. Оставлено как защитный барьер
        // на случай будущего изменения контракта resolveProfile.
        if let p = profile, !p.firebaseUID.isEmpty, p.firebaseUID != user.uid {
            log("Firebase UID changed — resetting UserProfile", level: .info)
            p.name = ""
            p.cefrLevel = .a1
        }

        // Проставляем UID и синхронизируем имя из Firebase.
        profile?.firebaseUID = user.uid
        if user.isAnonymous {
            if profile?.name.isEmpty == true { profile?.name = "Anonymous" }
        } else if let n = user.displayName, !n.isEmpty {
            profile?.name = n
        } else if let email = user.email, !email.isEmpty {
            profile?.name = String(email.prefix(while: { $0 != "@" }))
        }
        profile?.touch()   // одним вызовом на все мутации name/firebaseUID выше
        ctx.saveWithErrorHandling()

        let cefrRaw = profile?.cefrLevel.rawValue ?? ""
        let isReturningUser = await userService.createOrUpdateUser(user, nativeLanguage: nativeLanguage.rawValue, cefrLevel: cefrRaw)
        await userService.syncSubscription(for: user.uid)
        return UserSessionSyncResult(isReturningUser: isReturningUser, hasForeignProfileData: hasForeignProfileData)
    }
}
