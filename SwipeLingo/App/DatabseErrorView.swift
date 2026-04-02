import SwiftUI

/// Shown when the SwiftData ModelContainer fails to initialize even after a store reset.
/// Displayed instead of the main app content — no SwiftData dependency.
struct DatabseErrorView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("Database Error")
                .font(.title.bold())

            Text("The app could not initialize its database.\nPlease reinstall the app.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
