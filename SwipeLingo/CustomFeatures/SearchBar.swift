import SwiftUI

// MARK: - Card search helper

extension Array where Element == Card {
    /// Filters by English word or translation; returns all cards when query is empty.
    func filtered(by query: String) -> [Card] {
        guard !query.isEmpty else { return self }
        return filter {
            $0.en.localizedCaseInsensitiveContains(query) ||
            $0.item.localizedCaseInsensitiveContains(query)
        }
    }
}

// MARK: - SearchEmptyState
// Shown when a search query returns zero results.

struct SearchEmptyState: View {
    let query: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 42))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
            Text("No results for \"\(query)\"")
                .font(.title3.bold())
                .foregroundStyle(Color.myColors.myAccent)
            Text("Try a different search term")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
        }
    }
}

// MARK: - SearchBar
// Universal search bar used across LibraryViews.
// Usage:
//   SearchBar(text: $searchText)
//   SearchBar(text: $searchText, prompt: "Search cards")

struct SearchBar: View {

    @Binding var text: String
    var prompt: String = "Search"

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.myColors.myAccent.opacity(text.isEmpty ? 0.35 : 0.8))

            TextField(prompt, text: $text)
                .focused($isFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)

            if isFocused {
                Button {
                    text = ""
                    isFocused = false
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.myColors.myRed.opacity(0.5))
                }
                .buttonStyle(.borderless)
            }
        }
        .font(.subheadline)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color.myColors.myAccent.opacity(isFocused ? 0 : 0.07), in: Capsule())
        .overlay{
            Capsule()
                .strokeBorder(isFocused ? Color.myColors.myBlue : .clear, lineWidth: 1)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isFocused)

    }
}
