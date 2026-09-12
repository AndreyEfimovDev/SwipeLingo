import UIKit

// MARK: - KeyboardManager
//
// Определяет программную клавиатуру или физическую (iPad Magic Keyboard).
// Физические клавиатуры сообщают высоту < 100pt — там кнопка скрытия не нужна.
// Использовать как @State внутри View: @State private var keyboard = KeyboardManager()

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
        Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: UIResponder.keyboardWillShowNotification) {
                guard let self else { return }
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { continue }
                // Magic Keyboard (физическая) сообщает высоту < 100pt → кнопка скрытия не нужна
                let isSoftwareKeyboard = frame.height >= 100
                isKeyboardVisible    = true
                shouldShowHideButton = isSoftwareKeyboard
                log("keyboard height: \(frame.height) → showButton: \(isSoftwareKeyboard)")
            }
        }
    }

    private func observeHide() {
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillHideNotification) {
                guard let self else { return }
                isKeyboardVisible    = false
                shouldShowHideButton = false
            }
        }
    }
}
