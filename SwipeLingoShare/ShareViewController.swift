import UIKit
import SwiftUI

// MARK: - ShareViewController
// Entry point for the SwipeLingoShare extension.
// Extracts selected plain text, presents ShareExtensionView,
// and saves the word to the shared App Group UserDefaults queue.

class ShareViewController: UIViewController {

    private let appGroupID = "group.PELSH.SwipeLingo"
    private let pendingKey = "pendingInboxWords"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        extractText()
    }

    // MARK: - Text extraction

    private func extractText() {
        guard
            let item     = extensionContext?.inputItems.first as? NSExtensionItem,
            let provider = item.attachments?.first,
            provider.hasItemConformingToTypeIdentifier("public.plain-text")
        else { cancel(); return }

        provider.loadItem(forTypeIdentifier: "public.plain-text") { [weak self] item, _ in
            DispatchQueue.main.async {
                let word = (item as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !word.isEmpty else { self?.cancel(); return }
                self?.presentShareView(word: word)
            }
        }
    }

    // MARK: - Present SwiftUI view

    private func presentShareView(word: String) {
        let shareView = ShareExtensionView(word: word) { [weak self] in
            self?.saveToInbox(word: word)
        } onCancel: { [weak self] in
            self?.cancel()
        }

        let hosting = UIHostingController(rootView: shareView)
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hosting)
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
    }

    // MARK: - Actions

    /// Appends `word` to the shared pending queue and closes the extension.
    private func saveToInbox(word: String) {
        let defaults = UserDefaults(suiteName: appGroupID)
        var pending  = defaults?.stringArray(forKey: pendingKey) ?? []
        pending.append(word)
        defaults?.set(pending, forKey: pendingKey)
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(
            withError: NSError(domain: "SwipeLingoShare", code: 0)
        )
    }
}
