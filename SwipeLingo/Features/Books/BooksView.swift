import SwiftUI
import SwiftData

// MARK: - BooksView

struct BooksView: View {

    @Environment(\.modelContext) private var context
    @Environment(AppViewModel.self) private var appViewModel
    @AppStorage(Constants.StorageKey.userPlan) private var userPlan: AccessTier = .free

    @Query private var books: [Book]
    @State private var viewModel     = BooksViewModel()
    @State private var syncTask:     Task<Void, Never>?
    @State private var readerBook:   Book? = nil
    @State private var debugImportTask: Task<Void, Never>?
    @State private var bookToDelete: Book? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    levelFilterBar
                    if viewModel.filteredBooks(books, userPlan: userPlan).isEmpty {
                        emptyState
                    } else {
                        booksGrid
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Books")
            .searchable(text: $viewModel.searchText, prompt: "Search books")
            .toolbar { toolbarContent }
            .fullScreenCover(item: $readerBook) { book in
                BookReaderView(book: book)
            }
        }
        .task {
            syncTask = Task { await viewModel.syncBooks(context: context) }
        }
        .onDisappear { syncTask?.cancel() }
    }

    // MARK: - Level filter

    private var levelFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    title: "All",
                    isSelected: viewModel.selectedLevel == nil
                ) { viewModel.selectedLevel = nil }

                ForEach(CEFRLevel.allCases, id: \.self) { level in
                    FilterChip(
                        title: level.displayCode,
                        isSelected: viewModel.selectedLevel == level,
                        color: level.color
                    ) { viewModel.selectedLevel = level }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 44)
        .clipped()
    }

    // MARK: - Books grid

    private var booksGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(viewModel.filteredBooks(books, userPlan: userPlan)) { book in
                BookCard(book: book, userPlan: userPlan) {
                    readerBook = book
                }
                .contextMenu {
                    Button(role: .destructive) {
                        bookToDelete = book
                    } label: {
                        Label("Delete book", systemImage: "trash")
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete \"\(bookToDelete?.title ?? "")\"?",
            isPresented: Binding(get: { bookToDelete != nil }, set: { if !$0 { bookToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let book = bookToDelete {
                    BookDownloadService.shared.clearCache(firestoreId: book.firestoreId)
                    context.delete(book)
                    try? context.save()
                }
                bookToDelete = nil
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.3))
            Text(viewModel.isSyncing ? "Loading books…" : "No books available")
                .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { appViewModel.activeSheet = .settings } label: {
                Image(systemName: "gear")
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            // Sync
            if viewModel.isSyncing {
                ProgressView().tint(Color.myColors.myBlue)
            } else {
                Button {
                    syncTask = Task { await viewModel.syncBooks(context: context) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                }
            }

            // Debug import
            Button {
                debugImportTask = Task { await importDebugBook() }
            } label: {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.5))
            }

            // Mode switcher — matches FlashCardsView / PairsView style
            Menu {
                Button { appViewModel.studyMode = .cards } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.stack").frame(width: 20)
                        Text("Switch to Cards")
                    }
                }
                Button { appViewModel.studyMode = .pairs } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles").frame(width: 20)
                        Text("Switch to Pairs")
                    }
                }
                Divider()
                Button { appViewModel.activeSheet = .statistics } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chart.line.uptrend.xyaxis").frame(width: 20)
                        Text("Statistics")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }

    // MARK: - Debug import

    private func importDebugBook() async {
        let metaURL = URL(string: "https://raw.githubusercontent.com/AndreyEfimovDev/Support/main/Books/metadata.json")!
        do {
            let (data, _) = try await URLSession.shared.data(from: metaURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            let firestoreId    = json["firestoreId"]    as? String ?? UUID().uuidString
            let title          = json["title"]          as? String ?? "Untitled"
            let author         = json["author"]         as? String ?? "Unknown"
            let desc           = json["description"]    as? String
            let cefrRaw        = json["cefrLevel"]      as? String ?? "a1"
            let accessRaw      = json["accessTier"]     as? String ?? "free"
            let coverURL       = json["coverURL"]       as? String ?? ""
            let chapterBaseURL = json["chapterBaseURL"] as? String ?? ""
            let totalChapters  = json["totalChapters"]  as? Int    ?? 0
            let chaptersRaw    = json["chapters"]       as? [[String: Any]] ?? []
            let chapters       = chaptersRaw.compactMap { d -> BookChapter? in
                guard let idx = d["index"] as? Int, let t = d["title"] as? String else { return nil }
                return BookChapter(index: idx, title: t)
            }

            let existing = try context.fetch(FetchDescriptor<Book>())
            existing.filter { $0.firestoreId == firestoreId }.forEach {
                BookDownloadService.shared.clearCache(firestoreId: $0.firestoreId)
                context.delete($0)
            }

            let book = Book(
                firestoreId:      firestoreId,
                title:            title,
                author:           author,
                description:      desc?.isEmpty == false ? desc : nil,
                cefrLevel:        CEFRLevel(rawValue: cefrRaw)   ?? .a1,
                accessTier:       AccessTier(rawValue: accessRaw) ?? .free,
                coverStoragePath: coverURL,
                chapterBaseURL:   chapterBaseURL,
                totalChapters:    totalChapters,
                chapters:         chapters,
                createdAt:        .now,
                updatedAt:        .now
            )
            context.insert(book)
            try context.save()
            log("[BookDebug] Imported '\(title)' (\(totalChapters) chapters)", level: .info)
        } catch {
            log("[BookDebug] Import failed: \(error)", level: .error)
        }
    }
}

// MARK: - BookCard

private struct BookCard: View {

    let book:     Book
    let userPlan: AccessTier
    let onTap:    () -> Void

    @State private var coverImage: Image? = nil
    @State private var loadTask:   Task<Void, Never>? = nil

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                coverView
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.myColors.myAccent)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(book.author)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        CEFRBadgeView(level: book.cefrLevel)
                        if book.accessTier != .free {
                            AccessTierBadge(tier: book.accessTier)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            }
        }
        .buttonStyle(.plain)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .myShadow()
        .task {
            loadTask = Task { await loadCover() }
        }
        .onDisappear { loadTask?.cancel() }
    }

    @ViewBuilder
    private var coverView: some View {
        if let image = coverImage {
            image
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                book.cefrLevel.color.opacity(0.15)
                VStack(spacing: 8) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(book.cefrLevel.color.opacity(0.6))
                    Text(book.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .lineLimit(3)
                }
            }
        }
    }

    private func loadCover() async {
        let service = BookDownloadService.shared
        if service.isCoverDownloaded(book: book) {
            loadCoverFromDisk()
            return
        }
        guard !Task.isCancelled else { return }
        _ = try? await service.downloadCover(book: book)
        guard !Task.isCancelled else { return }
        loadCoverFromDisk()
    }

    @MainActor
    private func loadCoverFromDisk() {
        let url = BookDownloadService.shared.localCoverURL(book: book)
        guard let uiImage = UIImage(contentsOfFile: url.path) else { return }
        coverImage = Image(uiImage: uiImage)
    }
}

// MARK: - FilterChip

private struct FilterChip: View {
    let title:      String
    let isSelected: Bool
    var color:      Color = Color.myColors.myBlue
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? color : Color.myColors.myAccent.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? color.opacity(0.12) : Color(.systemBackground))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? color.opacity(0.5) : Color.myColors.myAccent.opacity(0.15),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
