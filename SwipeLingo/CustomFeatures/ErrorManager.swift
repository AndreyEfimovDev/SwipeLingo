import SwiftUI
import SwiftData

// MARK: - ErrorManager

@MainActor
final class ErrorManager: ObservableObject {
    static let shared = ErrorManager()

    @Published var errorMessage: String?
    @Published var showAlert: Bool = false

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
    /// Saves the context, routing any error through ErrorManager.
    func saveWithErrorHandling() {
        do {
            try save()
        } catch {
            ErrorManager.shared.handle(error, message: SwiftDataError.saveFailed.message)
        }
    }

    /// Fetches objects, routing any error through ErrorManager. Returns [] on failure.
    func fetchWithErrorHandling<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        do {
            return try fetch(descriptor)
        } catch {
            ErrorManager.shared.handle(error, message: SwiftDataError.fetchFailed.message)
            return []
        }
    }

    /// Counts objects, routing any error through ErrorManager. Returns 0 on failure.
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
    /// Attaches a global error alert driven by ErrorManager.shared.
    func errorAlert() -> some View {
        modifier(ErrorAlertModifier())
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
