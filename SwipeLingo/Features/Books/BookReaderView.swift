import SwiftUI
import SwiftData
import WebKit

// MARK: - IdentifiableString

private struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}

// MARK: - BookImageFullscreenView

private struct BookImageFullscreenView: View {

    let urlString: String
    @Environment(\.dismiss) private var dismiss

    @State private var scale:       CGFloat = 1.0
    @State private var lastScale:   CGFloat = 1.0
    @State private var offset:      CGSize  = .zero
    @State private var lastOffset:  CGSize  = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = max(1.0, lastScale * value)
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                        if scale < 1.0 {
                                            withAnimation(.spring()) {
                                                scale = 1.0
                                                offset = .zero
                                            }
                                            lastScale = 1.0
                                            lastOffset = .zero
                                        }
                                    }
                                    .simultaneously(with:
                                        DragGesture()
                                            .onChanged { value in
                                                guard scale > 1.0 else { return }
                                                offset = CGSize(
                                                    width:  lastOffset.width  + value.translation.width,
                                                    height: lastOffset.height + value.translation.height
                                                )
                                            }
                                            .onEnded { _ in
                                                lastOffset = offset
                                            }
                                    )
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.spring()) {
                                    if scale > 1.0 {
                                        scale = 1.0
                                        offset = .zero
                                        lastScale = 1.0
                                        lastOffset = .zero
                                    } else {
                                        scale = 2.5
                                        lastScale = 2.5
                                    }
                                }
                            }
                    case .failure:
                        VStack(spacing: 12) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.5))
                            Text("Failed to load image")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    default:
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(20)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - BookReaderView

struct BookReaderView: View {

    let book: Book

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme)  private var colorScheme

    @Query private var allProgress:  [BookProgress]
    @Query private var allBookmarks: [BookBookmark]

    @State private var viewModel: BookReaderViewModel
    @State private var downloadTask: Task<Void, Never>? = nil
    @State private var fullscreenImageURL: String? = nil

    @AppStorage("bookFontSize") private var fontSize: Int = 18

    private let fontSizeMin = 14
    private let fontSizeMax = 26
    private let fontSizeStep = 2

    init(book: Book) {
        self.book = book
        _viewModel = State(initialValue: BookReaderViewModel(book: book, progress: nil))
    }

    private var progress: BookProgress? {
        allProgress.first { $0.bookId == book.id }
    }

    private var bookmarks: [BookBookmark] {
        allBookmarks.filter { $0.bookId == book.id }
    }

    private var hasBookmarkHere: Bool {
        viewModel.hasBookmark(in: bookmarks)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isDownloading && !viewModel.isChapterReady {
                    downloadingView
                } else if viewModel.isChapterReady {
                    readerContent
                } else {
                    downloadPrompt
                }
            }
            .navigationTitle(viewModel.currentChapter?.title ?? book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $viewModel.showDictionary) {
                if let word = viewModel.tappedWord {
                    BookWordLookupView(word: word)
                        .onAppear {
                            AnalyticsService.wordLookedUp(word: word, source: .book)
                        }
                }
            }
            .sheet(isPresented: $viewModel.showChapterList) {
                BookChapterListView(
                    book: book,
                    currentIndex: viewModel.chapterIndex
                ) { index in
                    viewModel.goToChapter(index)
                    viewModel.showChapterList = false
                }
            }
            .sheet(isPresented: $viewModel.showBookmarks) {
                BookBookmarksView(
                    bookmarks:    bookmarks,
                    currentIndex: viewModel.chapterIndex,
                    onSelect: { bookmark in
                        viewModel.goToChapter(bookmark.chapterIndex)
                        viewModel.showBookmarks = false
                    },
                    onDelete: { bookmark in
                        viewModel.deleteBookmark(bookmark, context: context)
                    }
                )
            }
        }
        .fullScreenCover(item: Binding(
            get: { fullscreenImageURL.map { IdentifiableString(value: $0) } },
            set: { if $0 == nil { fullscreenImageURL = nil } }
        )) { item in
            BookImageFullscreenView(urlString: item.value)
        }
        .onAppear {
            if let p = progress, viewModel.chapterIndex == 0 && viewModel.scrollOffset == 0 {
                viewModel = BookReaderViewModel(book: book, progress: p)
            }
            downloadTask = Task { await viewModel.downloadCurrentChapterIfNeeded() }
            AnalyticsService.bookOpened(bookId: book.id, bookTitle: book.title)
        }
        .onDisappear {
            downloadTask?.cancel()
            viewModel.saveProgress(context: context)
        }
    }

    // MARK: - Reader content

    private var readerContent: some View {
        BookPagedReader(
            book:         book,
            chapterIndex: viewModel.chapterIndex,
            colorScheme:  colorScheme,
            fontSize:     fontSize,
            onWordTap: { word in
                viewModel.handleWordTap(word)
            },
            onImageTap: { src in
                fullscreenImageURL = src
            },
            onPageChange: { newIndex in
                // Called by UIPageViewController after user swipe completes
                viewModel.goToChapter(newIndex)
                viewModel.saveProgress(context: context)
                AnalyticsService.bookChapterRead(bookId: book.id, chapterIndex: newIndex, totalChapters: book.totalChapters)
                // Proactively download the next 2 chapters so swipe is always available
                downloadTask = Task {
                    for offset in 1...2 {
                        let idx = newIndex + offset
                        guard idx < book.totalChapters else { break }
                        try? await BookDownloadService.shared.downloadChapter(book: book, index: idx)
                    }
                }
            }
        )
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottom) {
            bottomControls
        }
    }

    // MARK: - Bottom controls (floating, independent capsules)

    private var bottomControls: some View {
        HStack(alignment: .center) {
            // ‹ Previous chapter
            navButton(systemImage: "chevron.left", enabled: viewModel.hasPrevious) {
                viewModel.goToPrevious()
                viewModel.saveProgress(context: context)
            }

            Spacer()

            // Center pill: A− / counter / A+
            HStack(spacing: 12) {
                fontSizeButton(label: "A−", enabled: fontSize > fontSizeMin) {
                    fontSize = max(fontSize - fontSizeStep, fontSizeMin)
                }
                Text("\(viewModel.chapterIndex + 1) / \(book.totalChapters)")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                    .frame(minWidth: 52)
                    .frame(height: 44)

                fontSizeButton(label: "A+", enabled: fontSize < fontSizeMax) {
                    fontSize = min(fontSize + fontSizeStep, fontSizeMax)
                }
            }
            .padding(.horizontal, 5)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            // › Next chapter
            navButton(systemImage: "chevron.right", enabled: viewModel.hasNext) {
                viewModel.goToNext()
                viewModel.saveProgress(context: context)
                downloadTask = Task {
                    let idx = viewModel.chapterIndex + 1
                    guard idx < book.totalChapters else { return }
                    try? await BookDownloadService.shared.downloadChapter(book: book, index: idx)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func navButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? Color.myColors.myBlue : Color.myColors.myBlue.opacity(0.25))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Capsule())
//                .background(
//                    Capsule()
//                        .strokeBorder(
//                            enabled ? Color.myColors.myBlue.opacity(0.5) : Color.myColors.myBlue.opacity(0.15),
//                            lineWidth: 1.5
//                        )
//                )
                .contentShape(Capsule())
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }

    private func fontSizeButton(label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(enabled ? Color.myColors.myAccent.opacity(0.8) : Color.myColors.myAccent.opacity(0.25))
                .frame(width: 48, height: 36)
                .background(
                    Capsule()
                        .strokeBorder(
                            enabled ? Color.myColors.myAccent.opacity(0.2) : Color.myColors.myAccent.opacity(0.08),
                            lineWidth: 1.2
                        )
                )
                .contentShape(Capsule())
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }

    // MARK: - Download states

    private var downloadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(Color.myColors.myBlue)
                .scaleEffect(1.5)
            Text("Loading chapter…")
                .foregroundStyle(Color.myColors.myAccent.opacity(0.7))
        }
    }

    private var downloadPrompt: some View {
        VStack(spacing: 24) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 56))
                .foregroundStyle(Color.myColors.myBlue)

            VStack(spacing: 8) {
                Text(book.title)
                    .font(.headline)
                    .foregroundStyle(Color.myColors.myAccent)
                Text("Download to start reading")
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.7))
            }

            Button {
                downloadTask = Task {
                    await viewModel.downloadAllIfNeeded()
                    if viewModel.isChapterReady { return }
                    await viewModel.downloadCurrentChapterIfNeeded()
                }
            } label: {
                Text("Download Book")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color.myColors.myBlue, in: Capsule())
            }
        }
        .padding(32)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                viewModel.saveProgress(context: context)
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Books")
                }
                .foregroundStyle(Color.myColors.myBlue)
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            // Tap → open list. Long press → Add / Remove / Show All
            Button {
                viewModel.showBookmarks = true
            } label: {
                Image(systemName: hasBookmarkHere ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(Color.myColors.myBlue)
                    .symbolEffect(.bounce, value: viewModel.bookmarkJustAdded)
            }
            .contextMenu {
                if hasBookmarkHere {
                    Button(role: .destructive) {
                        viewModel.removeBookmark(from: bookmarks, context: context)
                    } label: {
                        Label("Remove Bookmark", systemImage: "bookmark.slash")
                    }
                } else {
                    Button {
                        viewModel.addBookmark(context: context)
                    } label: {
                        Label("Add Bookmark", systemImage: "bookmark")
                    }
                }
                Divider()
                Button {
                    viewModel.showBookmarks = true
                } label: {
                    Label("Show All Bookmarks", systemImage: "bookmark.fill")
                }
            }

            Button {
                viewModel.showChapterList = true
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(Color.myColors.myBlue)
            }
        }
    }
}
