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
//
// Used by ImportEPUBSheet during the upload+deploy phase.

struct BookStorageService {

    // MARK: - Upload book

    struct UploadResult {
        var coverStoragePath: String
        var totalChapters:    Int
        var chapters:         [FSBookChapter]
    }

    /// Uploads cover + all HTML chapters. Reports progress via `onProgress(0.0 – 1.0)`.
    func uploadBook(
        bookId:      String,
        coverData:   Data?,
        chapters:    [EPUBParser.ParsedChapter],
        onProgress:  @escaping (Double) -> Void
    ) async throws -> UploadResult {
        let storage   = Storage.storage()
        let total     = chapters.count + (coverData != nil ? 1 : 0)
        var completed = 0

        // Cover (non-fatal: continue without cover if upload fails or data is absent)
        var coverStoragePath = ""
        if let data = coverData {
            let path = "books/\(bookId)/cover.jpg"
            let ref  = storage.reference(withPath: path)
            let meta = StorageMetadata()
            meta.contentType = "image/jpeg"
            do {
                try await ref.putDataAsync(data, metadata: meta)
                coverStoragePath = path
            } catch {
                log("[Storage] Cover upload failed (non-fatal): \(error)", level: .warning)
            }
            completed += 1
            onProgress(Double(completed) / Double(total))
        }

        // Chapters
        var fsChapters: [FSBookChapter] = []
        for chapter in chapters {
            let path = "books/\(bookId)/chapters/\(chapter.index).html"
            let ref  = storage.reference(withPath: path)
            let meta = StorageMetadata()
            meta.contentType = "text/html; charset=utf-8"
            guard let data = chapter.htmlContent.data(using: .utf8) else { continue }
            try await ref.putDataAsync(data, metadata: meta)
            fsChapters.append(FSBookChapter(index: chapter.index, title: chapter.title))
            completed += 1
            onProgress(Double(completed) / Double(total))
        }

        return UploadResult(
            coverStoragePath: coverStoragePath,
            totalChapters:    fsChapters.count,
            chapters:         fsChapters
        )
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

    func deleteBookFiles(bookId: String, totalChapters: Int) async {
        let storage = Storage.storage()
        // Cover
        try? await storage.reference(withPath: "books/\(bookId)/cover.jpg").delete()
        // Chapters
        for i in 0..<totalChapters {
            try? await storage.reference(withPath: "books/\(bookId)/chapters/\(i).html").delete()
        }
        log("[Storage] Deleted \(totalChapters) chapters for book \(bookId)", level: .info)
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
