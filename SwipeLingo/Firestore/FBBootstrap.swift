import Foundation
import FirebaseCore
import FirebaseCrashlytics
import FirebaseAnalytics
import GoogleSignIn

// MARK: - FirebaseBootstrap
//
// Идемпотентная конфигурация Firebase SDK + сопутствующих сервисов (Google
// Sign-In, Crashlytics). Вынесен из SwipeLingoApp — это bootstrap стороннего
// SDK, а не composition-root/routing забота точки входа.

enum FBBootstrap {

    /// Конфигурирует Firebase, если ещё не сконфигурирован — безопасно вызывать
    /// повторно (напр. из previews/тестов), повторно не переконфигурирует.
    /// Если GoogleService-Info.plist отсутствует в бандле — Firebase просто
    /// остаётся не сконфигурированным, а не крашит приложение (сборка без
    /// секретов работает).
    static func configure() {
        if FirebaseApp.app() == nil {
            if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
                FirebaseApp.configure()
                if let clientID = FirebaseApp.app()?.options.clientID {
                    GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
                }
                // В DEBUG крашлитика и аналитика отключены — тестовые креши и события из симулятора/отладки
                // не должны засорять прод-дашборды (проект Firebase один на обе сборки).
                #if DEBUG
                Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
                Analytics.setAnalyticsCollectionEnabled(false)
                #else
                Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
                Analytics.setAnalyticsCollectionEnabled(true)
                #endif
                log("App configured", level: .info)
            } else {
                log("GoogleService-Info.plist not found — Firebase disabled", level: .warning)
            }
        }
    }
}
