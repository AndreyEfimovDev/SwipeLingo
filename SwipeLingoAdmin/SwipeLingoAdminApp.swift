import SwiftUI
import FirebaseCore

@main
struct SwipeLingoAdminApp: App {

    @State private var store = AdminStore()

    init() {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            log("[Firebase] App configured", level: .info)
        } else {
            log("[Firebase] GoogleService-Info.plist not found — Firebase disabled", level: .warning)
        }
    }

    var body: some Scene {
        WindowGroup {
            AdminRootView()
                .environment(store)
        }
        .defaultSize(width: 1200, height: 750)
    }
}
