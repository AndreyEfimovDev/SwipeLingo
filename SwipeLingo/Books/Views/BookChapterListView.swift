import SwiftUI

// MARK: - BookChapterListView

struct BookChapterListView: View {

    let book:         Book
    let currentIndex: Int
    let onSelect:     (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(book.chapters) { chapter in
                            chapterRow(chapter)
                                .id(chapter.index)

                            if chapter.index != book.chapters.last?.index {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .myShadow()
                    .padding(16)
                }
                .background(Color(.systemBackground).ignoresSafeArea())
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo(currentIndex, anchor: .center)
                    }
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.myColors.myBlue)
                }
            }
        }
    }

    // MARK: - Chapter row

    private func chapterRow(_ chapter: BookChapter) -> some View {
        Button {
            onSelect(chapter.index)
        } label: {
            HStack(spacing: 12) {
                Text("\(chapter.index + 1)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
                    .frame(width: 28, alignment: .trailing)

                Text(chapter.title)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.myColors.myAccent)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if chapter.index == currentIndex {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.myColors.myBlue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            chapter.index == currentIndex
                ? Color.myColors.myBlue.opacity(0.06)
                : Color.clear
        )
    }
}
