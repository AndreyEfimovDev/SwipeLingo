import SwiftUI

@main
struct SwipeLingoAdminApp: App {

    @State private var store = AdminStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        .defaultSize(width: 1200, height: 750)
    }
}
