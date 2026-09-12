import SwiftUI
import SwiftData
import Combine

// MARK: - ErrorManager

@MainActor
final class ErrorManager: ObservableObject {
    static let shared = ErrorManager()

    // Блокирующий алерт
    @Published var errorMessage: String?
    @Published var showAlert: Bool = false

    // Неблокирующий баннер
    @Published var bannerMessage: String?
    private var bannerTask: Task<Void, Never>?

    private init() {}

    func handle(_ error: Error? = nil, message: String) {
        errorMessage = error?.localizedDescription ?? message
        showAlert = true
        if let error {
            log("❌ \(message): \(error.localizedDescription)", level: .error)
        } else {
            log("❌ \(message)", level: .error)
        }
    }

    /// Показывает неблокирующий баннер, автоматически скрывается через 3 секунды.
    func showBanner(_ message: String) {
        bannerTask?.cancel()
        bannerMessage = message
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            bannerMessage = nil
        }
    }

    func clear() {
        errorMessage = nil
        showAlert = false
    }
}

// MARK: - SwiftData Errors

enum SwiftDataError {
    case saveFailed
    case fetchFailed
    case deleteFailed
    case initializationFailed

    var message: String {
        switch self {
        case .saveFailed:           return "Failed to save data. Changes may not be persisted."
        case .fetchFailed:          return "Failed to load data."
        case .deleteFailed:         return "Failed to delete data."
        case .initializationFailed: return "Failed to initialize database. Please reinstall the app."
        }
    }
}

// MARK: - Network Errors

enum AppNetworkError {
    case noConnection
    case timeout
    case serverError
    case notFound
    case decodingFailed

    var message: String {
        switch self {
        case .noConnection:   return "No internet connection. Check your network settings."
        case .timeout:        return "Request timed out. Please try again."
        case .serverError:    return "Server error. Please try again later."
        case .notFound:       return "Content not found."
        case .decodingFailed: return "Failed to process server response."
        }
    }
}

// MARK: - Import Errors

enum ImportError {
    case importFailed
    case invalidData

    var message: String {
        switch self {
        case .importFailed: return "Failed to import content."
        case .invalidData:  return "Invalid data format."
        }
    }
}

// MARK: - ModelContext Extensions

extension ModelContext {
    /// Сохраняет context, направляя любую ошибку через ErrorManager.
    func saveWithErrorHandling() {
        do {
            try save()
        } catch {
            ErrorManager.shared.handle(error, message: SwiftDataError.saveFailed.message)
        }
    }

    /// Загружает объекты, направляя любую ошибку через ErrorManager. При ошибке возвращает [].
    func fetchWithErrorHandling<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        do {
            return try fetch(descriptor)
        } catch {
            ErrorManager.shared.handle(error, message: SwiftDataError.fetchFailed.message)
            return []
        }
    }

    /// Считает объекты, направляя любую ошибку через ErrorManager. При ошибке возвращает 0.
    func fetchCountWithErrorHandling<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> Int {
        do {
            return try fetchCount(descriptor)
        } catch {
            ErrorManager.shared.handle(error, message: SwiftDataError.fetchFailed.message)
            return 0
        }
    }
}

// MARK: - View Extension

extension View {
    /// Подключает глобальный алерт ошибок, управляемый ErrorManager.shared.
    func errorAlert() -> some View {
        modifier(ErrorAlertModifier())
    }

    /// Подключает глобальный баннер ошибок, управляемый ErrorManager.shared.
    func errorBanner() -> some View {
        modifier(BannerModifier())
    }
}

// MARK: - ErrorAlertModifier

private struct ErrorAlertModifier: ViewModifier {
    @ObservedObject private var errorManager = ErrorManager.shared

    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: $errorManager.showAlert) {
                Button("OK") { errorManager.clear() }
            } message: {
                Text(errorManager.errorMessage ?? "An unknown error occurred.")
            }
    }
}

// MARK: - BannerModifier

private struct BannerModifier: ViewModifier {
    @ObservedObject private var errorManager = ErrorManager.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message = errorManager.bannerMessage {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.subheadline)
                    Text(message)
                        .font(.subheadline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.75), in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: errorManager.bannerMessage)
            }
        }
        .animation(.spring(duration: 0.3), value: errorManager.bannerMessage)
    }
}
