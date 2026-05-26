import SwiftUI

// MARK: - AdminRootView

struct AdminRootView: View {
    @State private var isSignedIn = false

    var body: some View {
        if isSignedIn {
            ContentView()
        } else {
            AdminAuthView { isSignedIn = true }
        }
    }
}
