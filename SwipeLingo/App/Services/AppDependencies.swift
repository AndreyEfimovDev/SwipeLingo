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
    let authFBService: AuthFBService
    let userFBService: UserFBService
    /// Нужен только SettingsView.
    let appSyncStateService: AppSyncStateService
    /// Не читается напрямую нигде — держит подписку на NSPersistentStoreRemoteChange
    /// живой весь процесс (см. CollectionDedupeObserver). Поле существует
    /// только ради времени жизни объекта, как и сам обозреватель.
    let collectionDedupeObserver: CollectionDedupeObserver
    /// Активный таб, sheets — нужен всему дереву Cards/Pairs/Books.
    let appViewModel: AppViewModel
    /// Общие пользовательские настройки (тема и т.п.) — консолидированы, чтобы не
    /// повторять `@AppStorage(...)` в каждом View, читающем то же самое значение.
    let appSettings: AppSettings
    /// Единственный на всё приложение экземпляр — так `stop()` перед `play()`/`speak()`
    /// (см. AudioPlayerService) останавливает и звук, запущенный на ДРУГОМ экране, а не
    /// только на своём. При отдельных экземплярах на TinderCardsView/DictionaryLookupView/
    /// PairsSetPlayerView/VoiceSettingsView возможно наложение двух звуков одновременно
    /// (напр. Dictionary lookup поверх TinderCardsView).
    let audioService: AudioPlayerService
}
