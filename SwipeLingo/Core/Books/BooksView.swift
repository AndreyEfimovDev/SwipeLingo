import SwiftUI
import SwiftData

// MARK: - BooksView

struct BooksView: View {

    @Environment(\.modelContext) private var context
    /// Передаётся из composition root через AppView — не через .environment().
    private let appViewModel: AppViewModel
    /// Форвардятся дальше в BookReaderView.
    private let appSyncStateService: AppSyncStateService
    private let appSettings: AppSettings
    private let userService: UserFBService
    private let authService: AuthFBService
    private let audioService: AudioPlayerService
    /// Единственный источник правды — UserFBService (см. UserFBService.swift).
    private var userPlan: AccessTier { userService.userPlan }

    init(appViewModel: AppViewModel, appSyncStateService: AppSyncStateService, appSettings: AppSettings, userService: UserFBService, authService: AuthFBService, audioService: AudioPlayerService, bookCatalog: BookCatalogSyncing) {
        self.appViewModel = appViewModel
        self.appSyncStateService = appSyncStateService
        self.appSettings = appSettings
        self.userService = userService
        self.authService = authService
        self.audioService = audioService
        _vm = State(initialValue: BooksViewModel(catalog: bookCatalog))
    }

    @Query private var books: [Book]
    @State private var vm: BooksViewModel
    @State private var syncTask: Task<Void, Never>?
    @State private var readerBook: Book? = nil
    @State private var bookToDelete: Book? = nil

    private let columns = [GridItem(.adaptive(minimum: 155, maximum: 190), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if vm.filteredBooks(books, userPlan: userPlan).isEmpty {
                        emptyState
                    } else {
                        booksGrid
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 16) {
                    SearchBar(text: $vm.searchText, prompt: "Search books")
                    levelFilterBar
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .background(Color.myColors.myBackground)
            }
            .background(Color.myColors.myBackground.ignoresSafeArea())
            .navigationTitle("Books")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .navigationDestination(item: $readerBook) { book in
                BookReaderView(book: book, appSyncStateService: appSyncStateService, appSettings: appSettings, authService: authService, audioService: audioService)
            }
        }
        // Дубли книг от гонки CloudKit — схлопываем при каждом входе в раздел, в любой сборке.
        .onAppear { vm.mergeDuplicateBooks(context: context) }
        #if !DEBUG
        // В релизе каталог тихо обновляется при входе в раздел; в DEBUG мок-книги грузятся только кнопкой.
        .task { syncTask = Task { await vm.syncBooks(context: context) } }
        #endif
        .onDisappear { syncTask?.cancel() }
    }

    // MARK: - Level filter

    private var levelFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    title: "All",
                    isSelected: vm.selectedLevel == nil
                ) { vm.selectedLevel = nil }

                ForEach(CEFRLevel.allCases, id: \.self) { level in
                    FilterChip(
                        title: level.displayCode,
                        isSelected: vm.selectedLevel == level,
                        color: level.color
                    ) { vm.selectedLevel = level }
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
            ForEach(vm.filteredBooks(books, userPlan: userPlan)) { book in
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
            Text(vm.isSyncing ? "Loading books…" : "No books available")
                .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Кнопка идёт перед меню-переключателем табов (MainScreenToolbar ниже), чтобы сохранить
        // порядок кнопок в trailing-группе. Источник каталога — vm (мок в DEBUG, Firestore в релизе).
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                syncTask = Task { await vm.syncBooks(context: context) }
            } label: {
                if vm.isSyncing {
                    ProgressView().tint(Color.myColors.myBlue)
                } else {
                    #if DEBUG
                    // Отладка: загрузить мок-книги (MockBookCatalog), без сети.
                    Image(systemName: "wrench.and.screwdriver")
                        .navBarIconStyle(color: Color.myColors.myRed.opacity(0.5))
                    #else
                    Image(systemName: "arrow.clockwise")
                        .navBarIconStyle()
                    #endif
                }
            }
            .disabled(vm.isSyncing)
        }
        MainScreenToolbar(appViewModel: appViewModel, currentMode: .books)
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
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottomTrailing) {
                        if book.isNew {
                            Text("NEW")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.myColors.buttonTextAccent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.myColors.myRed.opacity(0.8), in: Capsule())
                                .padding(8)
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.myColors.myAccent)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.leading)
                        .frame(height: 36, alignment: .topLeading)

                    Text(book.author)
                        .font(.caption)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                        .lineLimit(1)
                        .frame(height: 16, alignment: .topLeading)

                    HStack(spacing: 6) {
                        CEFRBadgeView(level: book.cefrLevel)
                            .font(.caption)
                        AccessTierBadge(tier: book.accessTier)
                    }
                    .frame(height: 22, alignment: .center)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
        }
        .buttonStyle(.plain)
        .background(Color.myColors.myBackground)
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
                .scaledToFit()
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
                        .fill(isSelected ? color.opacity(0.12) : Color.myColors.myBackground)
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
