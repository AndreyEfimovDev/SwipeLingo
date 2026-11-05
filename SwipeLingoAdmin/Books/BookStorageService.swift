import Foundation
import FirebaseStorage
import AppKit

// MARK: - BookStorageService
//
// Uploads book assets to Firebase Storage (Admin Tool only).
//
// Storage layout:
//   books/{bookId}/cover.jpg
//   books/{bookId}/chapters/0.html
//   books/{bookId}/chapters/1.html
//   ...
//   books/{bookId}/images/{файл}   ← главы ссылаются как "../images/{файл}"
//
// Used by ImportEPUBSheet during the upload+deploy phase.

struct BookStorageService {

    // MARK: - Upload book

    struct UploadResult {
        var coverStoragePath: String
        var totalChapters:    Int
        var chapters:         [FSBookChapter]
    }

    /// Загружает обложку, картинки и страницы книги (уже поделённые `HTMLSplitter.pages`).
    /// Прогресс — через `onProgress(0.0 – 1.0)`. Ошибка обложки или картинки не фатальна
    /// (книга читается и без них), ошибка страницы прерывает загрузку.
    func uploadBook(
        bookId:      String,
        coverData:   Data?,
        pages:       [HTMLSplitter.Section],
        images:      [String: Data],
        onProgress:  @escaping (Double) -> Void
    ) async throws -> UploadResult {
        let storage   = Storage.storage()
        let total     = pages.count + images.count + (coverData != nil ? 1 : 0)
        var completed = 0
        func step() {
            completed += 1
            onProgress(Double(completed) / Double(max(total, 1)))
        }

        // Обложка
        var coverStoragePath = ""
        if let data = coverData {
            let path = "books/\(bookId)/cover.jpg"
            let meta = StorageMetadata()
            meta.contentType = "image/jpeg"
            do {
                try await storage.reference(withPath: path).putDataAsync(data, metadata: meta)
                coverStoragePath = path
            } catch {
                log("[Storage] Cover upload failed (non-fatal): \(error.localizedDescription)", level: .warning)
            }
            step()
        }

        // Картинки — до страниц, чтобы к моменту деплоя книги все ссылки уже вели на файлы
        for (filename, data) in images.sorted(by: { $0.key < $1.key }) {
            let meta = StorageMetadata()
            meta.contentType = Self.imageContentType(for: filename)
            do {
                try await storage.reference(withPath: "books/\(bookId)/images/\(filename)").putDataAsync(data, metadata: meta)
            } catch {
                log("[Storage] Image '\(filename)' upload failed (non-fatal): \(error.localizedDescription)", level: .warning)
            }
            step()
        }

        // Страницы (главы) — индекс = позиция в оглавлении
        var fsChapters: [FSBookChapter] = []
        for page in pages {
            guard let data = page.htmlContent.data(using: .utf8) else { continue }
            let meta = StorageMetadata()
            meta.contentType = "text/html; charset=utf-8"
            try await storage.reference(withPath: "books/\(bookId)/chapters/\(fsChapters.count).html").putDataAsync(data, metadata: meta)
            fsChapters.append(FSBookChapter(index: fsChapters.count, title: page.title))
            step()
        }

        return UploadResult(
            coverStoragePath: coverStoragePath,
            totalChapters:    fsChapters.count,
            chapters:         fsChapters
        )
    }

    /// MIME-тип картинки по расширению файла (для корректной отдачи из Storage).
    static func imageContentType(for filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "png":         "image/png"
        case "gif":         "image/gif"
        case "svg":         "image/svg+xml"
        case "webp":        "image/webp"
        default:            "application/octet-stream"
        }
    }

    // MARK: - Upload cover only (for metadata update)

    func uploadCover(_ data: Data, bookId: String) async throws -> String {
        let path = "books/\(bookId)/cover.jpg"
        let ref  = Storage.storage().reference(withPath: path)
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        try await ref.putDataAsync(data, metadata: meta)
        return path
    }

    // MARK: - Delete all book files

    /// Удаляет все файлы книги в Storage: обложку, главы и картинки (папки перечисляются через listAll —
    /// число глав и имена картинок знать заранее не нужно). Ошибки отдельных файлов только логируются.
    func deleteBookFiles(bookId: String) async {
        let root = Storage.storage().reference(withPath: "books/\(bookId)")
        var deleted = 0
        try? await root.child("cover.jpg").delete()
        for folder in ["chapters", "images"] {
            do {
                let items = try await root.child(folder).listAll().items
                for item in items {
                    try? await item.delete()
                    deleted += 1
                }
            } catch {
                log("[Storage] List '\(folder)' failed for \(bookId): \(error.localizedDescription)", level: .warning)
            }
        }
        log("[Storage] Deleted \(deleted) file(s) for book \(bookId)", level: .info)
    }
}

// MARK: - StorageReference async helpers
// Firebase Storage SDK for macOS doesn't expose async methods natively — bridge via callback.

extension StorageReference {

    func putDataAsync(_ data: Data, metadata: StorageMetadata?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.putData(data, metadata: metadata) { _, error in
                if let error { continuation.resume(throwing: error) }
                else         { continuation.resume() }
            }
        }
    }

    func delete() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.delete { error in
                if let error { continuation.resume(throwing: error) }
                else         { continuation.resume() }
            }
        }
    }
}
