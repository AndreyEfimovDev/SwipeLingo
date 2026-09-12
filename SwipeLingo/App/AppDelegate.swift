import UIKit
import GoogleSignIn

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Требуется для push-уведомлений CloudKit (доставка обновлений в реальном времени).
        // Без этого CloudKit переключается на механизм опроса вместо push-уведомлений.        application.registerForRemoteNotifications()
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}
