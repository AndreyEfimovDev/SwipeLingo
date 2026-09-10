import UIKit
import GoogleSignIn

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Required for CloudKit push notifications (real-time sync delivery).
        // Without this CloudKit falls back to polling instead of push.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}
