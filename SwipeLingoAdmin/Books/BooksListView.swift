import SwiftUI

// MARK: - BooksListView

struct BooksListView: View {

    @Environment(AdminStore.self) private var store

    @State private var showImportEPUB  = false
    @State private var showEditor:     FSBook? = nil
    @State private var confirmDelete:  FSBook? = nil
    @State private var deployTask:     Task<Void, Never>? = nil

    private var visibleBooks: [FSBook] {
        store.books.filter { $0.deployStatus != .deleted }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        Group {
            if visibleBooks.isEmpty {
                emptyState
            } else {
                booksList
            }
        }
        .navigationTitle("Books")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showImportEPUB) { ImportEPUBSheet() }
        .sheet(item: $showEditor)           { BookEditorSheet(book: $0) }
        .alert("Delete Book", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { confirmDelete = nil }
            Button("Delete from Firestore", role: .destructive) {
                if let book = confirmDelete {
                    deployTask = Task { await store.deleteBookForever(id: book.id) }
                }
                confirmDelete = nil
            }
        } message: {
            Text("This will delete the book document from Firestore. Storage files (cover + chapters) must be removed manually from Firebase Console.")
        }
        .onDisappear { deployTask?.cancel() }
    }

    // MARK: - Books list

    private var booksList: some View {
        Table(visibleBooks) {
            TableColumn("Title") { book in
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title).fontWeight(.medium)
                    Text(book.author).font(.caption).foregroundStyle(.secondary)
                }
            }
            .width(min: 180)

            TableColumn("CEFR") { book in
                Text(book.cefrLevel.displayCode)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(book.cefrLevel.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(book.cefrLevel.color)
            }
            .width(60)

            TableColumn("Access") { book in
                Text(book.accessTier.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(60)

            TableColumn("Chapters") { book in
                Text("\(book.totalChapters)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(70)

            TableColumn("Status") { book in
                deployStatusBadge(book.deployStatus)
            }
            .width(80)

            TableColumn("Updated") { book in
                Text(book.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(100)

            TableColumn("Actions") { book in
                HStack(spacing: 8) {
                    // Deploy / Re-deploy
                    Button {
                        deployTask = Task { await store.deployBook(id: book.id) }
                    } label: {
                        Image(systemName: book.deployStatus == .live ? "arrow.clockwise" : "arrow.up.circle")
                    }
                    .help(book.deployStatus == .live ? "Re-deploy to Firestore" : "Deploy to Firestore")
                    .disabled(store.isDeploying)

                    // Edit metadata
                    Button {
                        showEditor = book
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .help("Edit metadata")

                    // Delete
                    Button(role: .destructive) {
                        confirmDelete = book
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete from Firestore")
                }
                .buttonStyle(.borderless)
            }
            .width(90)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Books", systemImage: "book.closed")
        } description: {
            Text("Import an EPUB file to get started.")
        } actions: {
            Button("Import EPUB") { showImportEPUB = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if store.isDeploying {
                ProgressView().controlSize(.small)
            }
            if let error = store.deployError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(error)
            }
            Button {
                showImportEPUB = true
            } label: {
                Label("Import EPUB", systemImage: "arrow.down.doc")
            }
        }
    }

    // MARK: - Status badge

    @ViewBuilder
    private func deployStatusBadge(_ status: SetDeployStatus) -> some View {
        let (label, color): (String, Color) = switch status {
        case .new:     ("New",     .secondary)
        case .draft:   ("Draft",   .orange)
        case .ready:   ("Ready",   .blue)
        case .live:    ("Live",    .green)
        case .deleted: ("Deleted", .red)
        }
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
