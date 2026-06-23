import SwiftUI
import UniformTypeIdentifiers

// MARK: - ImportEPUBSheet
//
// 3-шаговый мастер импорта EPUB:
//   Step 1 — Pick file    → пользователь выбирает .epub через NSOpenPanel
//   Step 2 — Preview      → парсинг, редактирование метаданных, список глав
//   Step 3 — Uploading    → загрузка в Firebase Storage + деплой в Firestore

struct ImportEPUBSheet: View {

    @Environment(AdminStore.self) private var store
    @Environment(\.dismiss)       private var dismiss

    // MARK: - State

    private enum Step {
        case pick
        case preview(EPUBParser.ParsedBook, URL)
        case uploading(progress: Double)
        case done(FSBook)
        case failed(String)
    }

    @State private var step: Step = .pick

    // Metadata (editable in preview step)
    @State private var title:            String     = ""
    @State private var author:           String     = ""
    @State private var description:      String     = ""
    @State private var cefrLevel:        CEFRLevel  = .a1
    @State private var accessTier:       AccessTier = .free
    @State private var paragraphsPerPage: Int        = 10

    @State private var uploadTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .pick:                      pickView
                case .preview(let book, let url): previewView(book: book, epubURL: url)
                case .uploading(let progress):   uploadingView(progress: progress)
                case .done(let book):            doneView(book: book)
                case .failed(let msg):           failedView(message: msg)
                }
            }
            .navigationTitle("Import EPUB")
            .toolbar { toolbarContent }
        }
        .frame(minWidth: 560, minHeight: 520)
        .onDisappear { uploadTask?.cancel() }
    }

    // MARK: - Step 1: Pick

    private var pickView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue.opacity(0.7))

            VStack(spacing: 8) {
                Text("Select an EPUB file")
                    .font(.title2.weight(.semibold))
                Text("The EPUB will be parsed on this Mac.\nChapters and cover are uploaded to Firebase Storage.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button("Choose EPUB…") { openFilePicker() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Spacer()
        }
        .padding(32)
    }

    // MARK: - Step 2: Preview

    private func previewView(book: EPUBParser.ParsedBook, epubURL: URL) -> some View {
        HSplitView {
            // Left: metadata form
            Form {
                Section("Metadata") {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("Classification") {
                    Picker("CEFR Level", selection: $cefrLevel) {
                        ForEach(CEFRLevel.allCases, id: \.self) { level in
                            Text(level.displayCode + " — " + level.displayName).tag(level)
                        }
                    }
                    Picker("Access", selection: $accessTier) {
                        ForEach(AccessTier.allCases, id: \.self) { tier in
                            Text(tier.displayName).tag(tier)
                        }
                    }
                }
                Section {
                    Picker("Paragraphs per page", selection: $paragraphsPerPage) {
                        Text("5 — short pages").tag(5)
                        Text("8 — medium pages").tag(8)
                        Text("10 — standard (default)").tag(10)
                        Text("15 — long pages").tag(15)
                    }
                    .help("Used when the chapter has no headings (e.g. novels like Call of the Wild). Splits long chapters by paragraph count.")
                } header: {
                    Text("Page splitting")
                } footer: {
                    Text("Only applies when no h2/h3 headings are found in a chapter.")
                }
                Section {
                    LabeledContent("Cover", value: book.coverImageData != nil ? "Found" : "Not found")
                    LabeledContent("Chapters", value: "\(book.chapters.count)")
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 260)

            // Right: chapters preview
            List(book.chapters) { chapter in
                HStack {
                    Text("\(chapter.index + 1)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                    Text(chapter.title)
                }
            }
            .frame(minWidth: 220)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Back") { step = .pick }
                Spacer()
                Button("Export to Disk…") { exportToDisk(book: book) }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Upload & Deploy") {
                    uploadTask = Task { await upload(book: book, epubURL: epubURL) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            .background(.bar)
        }
    }

    // MARK: - Step 3: Uploading

    private func uploadingView(progress: Double) -> some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 320)

            Text(progress < 1 ? "Uploading… \(Int(progress * 100))%" : "Deploying to Firestore…")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(32)
    }

    // MARK: - Done

    private func doneView(book: FSBook) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("\"\(book.title)\" published!")
                .font(.title2.weight(.semibold))
            Text("\(book.totalChapters) chapters · \(book.cefrLevel.displayCode) · \(book.accessTier.displayName)")
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(32)
    }

    // MARK: - Failed

    private func failedView(message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
            Text("Import failed")
                .font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 12) {
                Button("Try again") { step = .pick }
                Button("Dismiss")   { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding(32)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
    }

    // MARK: - File picker

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "epub") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories    = false
        panel.message = "Select an EPUB file to import"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        parseEPUB(at: url)
    }

    private func parseEPUB(at url: URL) {
        Task {
            do {
                let parsed = try await EPUBParser().parse(epubURL: url)
                title  = parsed.title
                author = parsed.author
                step   = .preview(parsed, url)
            } catch {
                step = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Upload + Deploy

    private func upload(book: EPUBParser.ParsedBook, epubURL: URL) async {
        let bookId = FirestoreID.make(name: title)
        let now    = Date.now

        step = .uploading(progress: 0)

        do {
            let result = try await BookStorageService().uploadBook(
                bookId:    bookId,
                coverData: book.coverImageData,
                chapters:  book.chapters
            ) { progress in
                Task { @MainActor in
                    step = .uploading(progress: progress * 0.9)
                }
            }

            guard !Task.isCancelled else { return }

            step = .uploading(progress: 0.95)

            let fsBook = FSBook(
                id:               bookId,
                title:            title.trimmingCharacters(in: .whitespaces),
                author:           author.trimmingCharacters(in: .whitespaces),
                description:      description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description,
                cefrLevel:        cefrLevel,
                accessTier:       accessTier,
                coverStoragePath: result.coverStoragePath,
                totalChapters:    result.totalChapters,
                chapters:         result.chapters,
                deployStatus:     .new,
                updatedAt:        now,
                createdAt:        now
            )

            try await FirestoreService().deployBook(fsBook)

            guard !Task.isCancelled else { return }

            var live = fsBook
            live.deployStatus = .live
            store.add(live)

            step = .done(live)

        } catch {
            log("[ImportEPUB] Upload failed: \(error)", level: .error)
            step = .failed(error.localizedDescription)
        }
    }

    // MARK: - Export to Disk

    private func exportToDisk(book: EPUBParser.ParsedBook) {
        let panel = NSOpenPanel()
        panel.canChooseFiles       = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt               = "Export Here"
        panel.message              = "Choose a folder to export the parsed book"
        guard panel.runModal() == .OK, let dest = panel.url else { return }

        _ = dest.startAccessingSecurityScopedResource()
        defer { dest.stopAccessingSecurityScopedResource() }

        let bookId       = title.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(24).description
        let baseRaw      = "https://raw.githubusercontent.com/AndreyEfimovDev/Support/main/Books/\(bookId)"
        let imagesBase   = "\(baseRaw)/images"

        let bookDir = dest.appendingPathComponent(bookId, isDirectory: true)
        let chapDir = bookDir.appendingPathComponent("chapters", isDirectory: true)
        let imgDir  = bookDir.appendingPathComponent("images",   isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: chapDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: imgDir,  withIntermediateDirectories: true)

            // Save all images from the EPUB manifest
            for (filename, data) in book.images {
                try data.write(to: imgDir.appendingPathComponent(filename))
            }

            // Split each parsed chapter by headings, rewrite image src to GitHub URLs
            var allChapters: [[String: Any]] = []
            var chapterIndex = 0

            for parsedChapter in book.chapters {
                // Rewrite relative image src → absolute GitHub raw URLs
                let updatedHTML = HTMLSplitter.rewriteImageSrc(
                    in: parsedChapter.htmlContent,
                    imagesBaseURL: imagesBase
                )
                // Split large chapter by h3/h2 headings (one fable = one file)
                let sections = HTMLSplitter.split(html: updatedHTML, fallbackTitle: parsedChapter.title, paragraphsPerPage: paragraphsPerPage)

                for section in sections {
                    let file = chapDir.appendingPathComponent("\(chapterIndex).html")
                    try section.htmlContent.write(to: file, atomically: true, encoding: .utf8)
                    allChapters.append(["index": chapterIndex, "title": section.title])
                    chapterIndex += 1
                }
            }

            // Cover image
            if let coverData = book.coverImageData {
                try coverData.write(to: bookDir.appendingPathComponent("cover.jpg"))
            }

            // metadata.json
            let meta: [String: Any] = [
                "firestoreId":    bookId,
                "title":          title.trimmingCharacters(in: .whitespaces),
                "author":         author.trimmingCharacters(in: .whitespaces),
                "description":    description.trimmingCharacters(in: .whitespaces),
                "cefrLevel":      cefrLevel.rawValue,
                "accessTier":     accessTier.rawValue,
                "coverURL":       "\(baseRaw)/cover.jpg",
                "chapterBaseURL": "\(baseRaw)/chapters",
                "totalChapters":  allChapters.count,
                "chapters":       allChapters
            ]
            let metaData = try JSONSerialization.data(withJSONObject: meta, options: .prettyPrinted)
            try metaData.write(to: bookDir.appendingPathComponent("metadata.json"))

            NSWorkspace.shared.open(dest)
            log("[Export] \(chapterIndex) chapters, \(book.images.count) images → \(bookDir.path)", level: .info)

        } catch {
            log("[Export] Failed: \(error)", level: .error)
        }
    }
}
