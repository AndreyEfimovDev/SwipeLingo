import Foundation

// MARK: - AppDependencies
//
// Единая точка сборки зависимостей приложения (composition root). Собирается
// один раз в SwipeLingoApp и передаётся вниз явными init-параметрами View —
// без .environment()/.environmentObject() для сервисов. Промежуточные View,
// которые сами ничего отсюда не читают (например AppView для полей, которые
// нужны только глубже), либо форвардят весь бандл, либо распаковывают в
// отдельные let-параметры конкретных потребителей — см. AppView.swift.
struct AppDependencies {
    let authService: FireBaseAuthService
    let userService: UserService
    /// Нужен только SettingsView.
    let appSyncStateService: AppSyncStateService
    /// Активный таб, sheets — нужен всему дереву Cards/Pairs/Books.
    let appViewModel: AppViewModel
}
