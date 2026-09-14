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
    /// после подтверждённого входа. Резолвит/создаёт профиль через
    /// `UserProfileDedupeService.resolveOrCreateProfile` — единственное место в
    /// приложении, которое создаёт `UserProfile` (см. её комментарий про
    /// синхронность/атомарность; та же функция вызывается из
    /// `OnboardingLevelViewModel`/`ProfileView` — общий источник правды, не
    /// три независимые копии одной и той же проверки). Проставляет имя из
    /// Firebase; затем синхронизирует профиль и подписку с Firestore.
    @discardableResult
    func syncAfterVerifiedSession(
        user: FirebaseAuth.User,
        container: ModelContainer,
        nativeLanguage: NativeLanguage,
        userService: UserFBService
    ) async -> UserSessionSyncResult {
        let ctx = container.mainContext
        let dedupeService = UserProfileDedupeService()
        let hasForeignProfileData = dedupeService.hasForeignProfiles(
            firebaseUID: user.uid, allProfiles: ctx.fetchWithErrorHandling(FetchDescriptor<UserProfile>())
        )
        let profile = dedupeService.resolveOrCreateProfile(firebaseUID: user.uid, context: ctx)

        // Синхронизируем имя из Firebase.
        if user.isAnonymous {
            if profile.name.isEmpty { profile.name = "Anonymous" }
        } else if let n = user.displayName, !n.isEmpty {
            profile.name = n
        } else if let email = user.email, !email.isEmpty {
            profile.name = String(email.prefix(while: { $0 != "@" }))
        }
        profile.touch()   // одним вызовом на все мутации name выше
        ctx.saveWithErrorHandling()

        let cefrRaw = profile.cefrLevel.rawValue
        let isReturningUser = await userService.createOrUpdateUser(user, nativeLanguage: nativeLanguage.rawValue, cefrLevel: cefrRaw)
        await userService.syncSubscription(for: user.uid)
        return UserSessionSyncResult(isReturningUser: isReturningUser, hasForeignProfileData: hasForeignProfileData)
    }
}
