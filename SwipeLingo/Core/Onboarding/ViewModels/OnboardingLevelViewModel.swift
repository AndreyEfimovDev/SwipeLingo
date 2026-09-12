import SwiftData

// MARK: - OnboardingLevelViewModel
//
// Бизнес-логика шага выбора CEFR-уровня в онбординге: создание UserProfile
// при первом заходе на шаг и выбор уровня. @Query-результат (profiles) и
// modelContext остаются во View — передаются сюда параметром на каждый вызов,
// та же конвенция, что и в остальных ViewModel проекта.

@Observable
final class OnboardingLevelViewModel {

    /// Создаёт `UserProfile` с дефолтным уровнем, если у пользователя его ещё нет.
    /// Вызывать из `.onAppear` — на этом шаге онбординга профиль должен
    /// существовать до того, как пользователь сможет выбрать уровень.
    func ensureProfile(profiles: [UserProfile], context: ModelContext) {
        guard profiles.isEmpty else { return }
        context.insert(UserProfile())
    }

    /// Выставляет выбранный уровень профилю.
    func selectLevel(_ level: CEFRLevel, profile: UserProfile?) {
        profile?.cefrLevel = level
    }
}
