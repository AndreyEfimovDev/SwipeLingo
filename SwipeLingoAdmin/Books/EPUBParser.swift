import Foundation

// MARK: - EPUBParser
//
// Extracts book metadata and HTML chapters from an EPUB file on macOS.
//
// Pipeline:
//   1. unzip epub → temp directory
//   2. META-INF/container.xml → OPF file path
//   3. OPF (content.opf)      → title, author, manifest, spine, cover
//   4. toc.ncx or nav.xhtml   → chapter titles (fallback: "Chapter N")
//   5. Read spine items as HTML strings
//   6. Return ParsedBook

struct EPUBParser {

    // MARK: - Output types

    struct ParsedBook {
        var title:          String
        var author:         String
        var coverImageData: Data?
        var chapters:       [ParsedChapter]
        // filename → Data for all images in the manifest (jpg, png, gif, svg, webp)
        var images:         [String: Data]
    }

    struct ParsedChapter: Identifiable {
        var id:          Int { index }
        var index:       Int
        var title:       String
        var htmlContent: String
    }

    // MARK: - Entry point

    func parse(epubURL: URL) async throws -> ParsedBook {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("epub_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await unzip(source: epubURL, destination: tempDir)
        return try buildBook(from: tempDir)
    }

    // MARK: - Build book

    private func buildBook(from dir: URL) throws -> ParsedBook {
        let opfURL = try findOPF(in: dir)
        let opfDir = opfURL.deletingLastPathComponent()
        let opf    = try parseOPF(at: opfURL)

        let titles = parseTOC(opfDir: opfDir, manifestItems: opf.manifest)

        var chapters: [ParsedChapter] = []
        for (index, idref) in opf.spine.enumerated() {
            guard let item = opf.manifest[idref] else { continue }
            let itemURL = opfDir.appendingPathComponent(item.href)
            let html    = (try? String(contentsOf: itemURL, encoding: .utf8)) ?? ""
            // Skip pages with too little text (cover pages, image-only pages, nav pages)
            let plainText = html
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard plainText.count > 150 else { continue }
            let title = titles[idref] ?? titles[item.href] ?? "Chapter \(index + 1)"
            chapters.append(ParsedChapter(index: chapters.count, title: title, htmlContent: html))
        }

        var coverData: Data? = nil
        if let coverHref = opf.coverHref {
            let coverURL = opfDir.appendingPathComponent(coverHref)
            coverData = try? Data(contentsOf: coverURL)
        }

        // Collect all image files from the manifest
        var images: [String: Data] = [:]
        for item in opf.manifest.values where item.mediaType.hasPrefix("image/") {
            let imgURL  = opfDir.appendingPathComponent(item.href)
            let filename = imgURL.lastPathComponent
            if let data = try? Data(contentsOf: imgURL) {
                images[filename] = data
            }
        }

        return ParsedBook(
            title:          opf.title.isEmpty ? "Untitled" : opf.title,
            author:         opf.author.isEmpty ? "Unknown" : opf.author,
            coverImageData: coverData,
            chapters:       chapters,
            images:         images
        )
    }

    // MARK: - Unzip

    private func unzip(source: URL, destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments     = ["-o", "-q", source.path, "-d", destination.path]
            process.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: EPUBParserError.unzipFailed(Int(p.terminationStatus)))
                }
            }
            do    { try process.run() }
            catch { continuation.resume(throwing: error) }
        }
    }

    // MARK: - OPF location (META-INF/container.xml)

    private func findOPF(in dir: URL) throws -> URL {
        let containerURL = dir.appendingPathComponent("META-INF/container.xml")
        guard FileManager.default.fileExists(atPath: containerURL.path) else {
            throw EPUBParserError.missingContainerXML
        }
        let data    = try Data(contentsOf: containerURL)
        let handler = ContainerXMLHandler()
        let parser  = XMLParser(data: data)
        parser.delegate = handler
        parser.parse()
        guard let rootfilePath = handler.rootfilePath else {
            throw EPUBParserError.missingRootfile
        }
        return dir.appendingPathComponent(rootfilePath)
    }

    // MARK: - OPF parsing

    fileprivate struct OPFResult {
        var title:     String
        var author:    String
        var coverHref: String?
        var manifest:  [String: ManifestItem]  // id → item
        var spine:     [String]                // ordered idrefs
    }

    fileprivate struct ManifestItem {
        var id:        String
        var href:      String
        var mediaType: String
    }

    fileprivate func parseOPF(at url: URL) throws -> OPFResult {
        let data    = try Data(contentsOf: url)
        let handler = OPFHandler()
        let parser  = XMLParser(data: data)
        parser.delegate = handler
        parser.parse()

        // Resolve cover href from cover-image item or meta name="cover"
        var coverHref: String? = nil
        if let coverId = handler.coverId, let item = handler.manifest[coverId] {
            coverHref = item.href
        } else {
            coverHref = handler.manifest.values
                .first { $0.mediaType.hasPrefix("image/") && $0.href.localizedCaseInsensitiveContains("cover") }
                .map { $0.href }
        }

        return OPFResult(
            title:     handler.title,
            author:    handler.author,
            coverHref: coverHref,
            manifest:  handler.manifest,
            spine:     handler.spine
        )
    }

    // MARK: - TOC parsing (NCX or nav.xhtml)

    fileprivate func parseTOC(opfDir: URL, manifestItems: [String: ManifestItem]) -> [String: String] {
        // Try NCX first
        if let ncxItem = manifestItems.values.first(where: { $0.mediaType == "application/x-dtbncx+xml" }) {
            let ncxURL = opfDir.appendingPathComponent(ncxItem.href)
            if let titles = parseNCX(at: ncxURL) { return titles }
        }
        // Try nav document (EPUB3)
        if let navItem = manifestItems.values.first(where: { $0.href.hasSuffix("nav.xhtml") || $0.href.hasSuffix("toc.xhtml") }) {
            let navURL = opfDir.appendingPathComponent(navItem.href)
            if let titles = parseNavXHTML(at: navURL) { return titles }
        }
        return [:]
    }

    // Returns [idref/href → title]
    private func parseNCX(at url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let handler = NCXHandler()
        let parser  = XMLParser(data: data)
        parser.delegate = handler
        parser.parse()
        return handler.titles.isEmpty ? nil : handler.titles
    }

    private func parseNavXHTML(at url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let handler = NavXHTMLHandler()
        let parser  = XMLParser(data: data)
        parser.delegate = handler
        parser.parse()
        return handler.titles.isEmpty ? nil : handler.titles
    }
}

// MARK: - XML Handlers

private final class ContainerXMLHandler: NSObject, XMLParserDelegate {
    var rootfilePath: String?
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attr: [String: String]) {
        if element == "rootfile", rootfilePath == nil {
            rootfilePath = attr["full-path"]
        }
    }
}

private final class OPFHandler: NSObject, XMLParserDelegate {
    var title    = ""
    var author   = ""
    var coverId: String?
    var manifest: [String: EPUBParser.ManifestItem] = [:]
    var spine:    [String] = []

    private var currentElement = ""
    private var inMetadata     = false

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes attr: [String: String]) {
        currentElement = element
        switch element {
        case "metadata", "opf:metadata": inMetadata = true
        case "item":
            if let id = attr["id"], let href = attr["href"], let mediaType = attr["media-type"] {
                manifest[id] = EPUBParser.ManifestItem(id: id, href: href, mediaType: mediaType)
                if attr["properties"]?.contains("cover-image") == true { coverId = id }
            }
        case "itemref":
            if let idref = attr["idref"] { spine.append(idref) }
        case "meta":
            if attr["name"] == "cover", let content = attr["content"] { coverId = content }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        if element == "metadata" || element == "opf:metadata" { inMetadata = false }
        currentElement = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, inMetadata else { return }
        switch currentElement {
        case "dc:title":   if title.isEmpty  { title  = s }
        case "dc:creator": if author.isEmpty { author = s }
        default: break
        }
    }
}

private final class NCXHandler: NSObject, XMLParserDelegate {
    // href → title
    var titles: [String: String] = [:]
    private var currentLabel     = ""
    private var currentSrc       = ""
    private var inNavLabel       = false
    private var currentText      = ""

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes attr: [String: String]) {
        switch element {
        case "navPoint":
            currentLabel = ""
            currentSrc   = ""
        case "navLabel":
            inNavLabel = true
            currentText = ""
        case "content":
            if let src = attr["src"] {
                // Strip fragment (#anchor)
                currentSrc = String(src.split(separator: "#").first ?? Substring(src))
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        switch element {
        case "navLabel":
            inNavLabel   = false
            currentLabel = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        case "navPoint":
            if !currentLabel.isEmpty, !currentSrc.isEmpty {
                titles[currentSrc] = currentLabel
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inNavLabel { currentText += string }
    }
}

private final class NavXHTMLHandler: NSObject, XMLParserDelegate {
    var titles: [String: String] = [:]
    private var inNavToc   = false
    private var inA        = false
    private var currentHref = ""
    private var currentText = ""

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes attr: [String: String]) {
        if element == "nav", attr["epub:type"] == "toc" { inNavToc = true }
        if inNavToc, element == "a", let href = attr["href"] {
            inA         = true
            currentHref = String(href.split(separator: "#").first ?? Substring(href))
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        if element == "nav" { inNavToc = false }
        if element == "a", inA {
            inA = false
            let title = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, !currentHref.isEmpty {
                titles[currentHref] = title
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inA { currentText += string }
    }
}

// MARK: - EPUBParserError

enum EPUBParserError: LocalizedError {
    case unzipFailed(Int)
    case missingContainerXML
    case missingRootfile
    case emptySpine

    var errorDescription: String? {
        switch self {
        case .unzipFailed(let code):  return "unzip exited with code \(code)"
        case .missingContainerXML:    return "META-INF/container.xml not found"
        case .missingRootfile:        return "No rootfile found in container.xml"
        case .emptySpine:             return "EPUB spine is empty — no chapters found"
        }
    }
}
