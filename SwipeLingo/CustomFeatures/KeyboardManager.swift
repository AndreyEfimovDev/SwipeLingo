import UIKit

// MARK: - KeyboardManager
//
// Detects software vs physical keyboard (iPad Magic Keyboard).
// Physical keyboards report height < 100 pt — no need for a dismiss button there.
// Use as @State inside a View: @State private var keyboard = KeyboardManager()

@Observable
@MainActor
final class KeyboardManager {

    var shouldShowHideButton = false
    var isKeyboardVisible    = false

    init() {
        observeShow()
        observeHide()
    }

    private func observeShow() {
        Task {
            for await note in NotificationCenter.default.notifications(named: UIResponder.keyboardWillShowNotification) {
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { continue }
                // Magic Keyboard (physical) reports height < 100 pt → no dismiss button needed
                let isSoftwareKeyboard = frame.height >= 100
                isKeyboardVisible    = true
                shouldShowHideButton = isSoftwareKeyboard
                log("keyboard height: \(frame.height) → showButton: \(isSoftwareKeyboard)")
            }
        }
    }

    private func observeHide() {
        Task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillHideNotification) {
                isKeyboardVisible    = false
                shouldShowHideButton = false
            }
        }
    }
}
