import SwiftData

// MARK: - OnboardingLevelViewModel
//
// Бизнес-логика шага выбора CEFR-уровня в онбординге: создание UserProfile
// при первом заходе на шаг и выбор уровня. @Query-результат (profiles) и
// modelContext остаются во View — передаются сюда параметром на каждый вызов,
// та же конвенция, что и в остальных ViewModel проекта.

@Observable
final class OnboardingLevelViewModel {

    /// Резолвит/создаёт `UserProfile` для текущего аккаунта, если его ещё нет.
    /// Вызывать из `.onAppear` — на этом шаге онбординга профиль должен
    /// существовать до того, как пользователь сможет выбрать уровень.
    ///
    /// Делегирует в `UserProfileDedupeService.resolveOrCreateProfile` —
    /// единственное место в приложении, которое создаёт `UserProfile` (общий
    /// источник правды с `UserSessionSyncService`/`ProfileView`, не своя копия
    /// проверки). Раньше здесь была наивная `profiles.isEmpty` без учёта
    /// `firebaseUID` — на общем iCloud с чужим уже синкнутым профилем это могло
    /// подхватить ЧУЖОЙ профиль вместо создания своего (см. `firebaseUID` ниже).
    func ensureProfile(firebaseUID: String, context: ModelContext) {
        UserProfileDedupeService().resolveOrCreateProfile(firebaseUID: firebaseUID, context: context)
    }

    /// Выставляет выбранный уровень профилю.
    func selectLevel(_ level: CEFRLevel, profile: UserProfile?) {
        profile?.cefrLevel = level
        profile?.touch()
    }
}
