import SwiftUI

// MARK: - DatabaseErrorView
//
// Отображается вместо основного содержимого приложения, если инициализация
// SwiftData ModelContainer не удаётся даже после сброса хранилища (см. Startup
// в SwipeLingoApp.swift) — без какой-либо зависимости от SwiftData.

struct DatabaseErrorView: View {
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
