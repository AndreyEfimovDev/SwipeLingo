import SwiftUI

// MARK: - BookBookmarksView
//
// Sheet showing all bookmarks for the current book.
// Tap a row → navigate to that chapter.
// Swipe to delete or use Edit mode.

struct BookBookmarksView: View {

    let bookmarks:    [BookBookmark]
    let currentIndex: Int
    let onSelect:     (BookBookmark) -> Void
    let onDelete:     (BookBookmark) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if bookmarks.isEmpty {
                    emptyState
                } else {
                    bookmarkList
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.myColors.myBlue)
                }
            }
        }
    }

    // MARK: - List

    private var bookmarkList: some View {
        List {
            ForEach(bookmarks.sorted { $0.createdAt > $1.createdAt }) { bookmark in
                bookmarkRow(bookmark)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    // MARK: - Row

    private func bookmarkRow(_ bookmark: BookBookmark) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "bookmark.fill")
                .font(.system(size: 15))
                .foregroundStyle(
                    bookmark.chapterIndex == currentIndex
                        ? Color.myColors.myBlue
                        : Color.myColors.myAccent.opacity(0.35)
                )
                .frame(width: 24)

            // Text
            VStack(alignment: .leading, spacing: 3) {
                Text(bookmark.chapterTitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.myColors.myAccent)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(positionLabel(for: bookmark.scrollOffset))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.5))

                    Text("·")
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.3))

                    Text(bookmark.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.5))
                }
            }

            Spacer()

            // Current indicator
            if bookmark.chapterIndex == currentIndex {
                Image(systemName: "eye.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.myColors.myBlue.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            bookmark.chapterIndex == currentIndex
                ? Color.myColors.myBlue.opacity(0.06)
                : Color(.systemBackground)
        )
        // Tap → navigate
        .onTapGesture { onSelect(bookmark) }
        // Swipe to delete — works because parent is List
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete(bookmark)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 48))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.2))
            Text("No bookmarks yet")
                .font(.headline)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.5))
            Text("Tap the bookmark icon while reading\nto save your position.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Helpers

    private func positionLabel(for offset: Double) -> String {
        switch offset {
        case ..<0.04: return "Top"
        case 0.96...: return "End"
        default:      return "\(Int(offset * 100))% through"
        }
    }
}
