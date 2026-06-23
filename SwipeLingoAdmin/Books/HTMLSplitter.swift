import Foundation

// MARK: - HTMLSplitter
//
// Splits a single HTML document into multiple sections.
// Used during EPUB export to turn one large chapter file into individual pages.
//
// Strategy:
//   1. Pick the heading level (h2/h3/h4) with the MOST occurrences → maximises granularity.
//      e.g. Aesop: h2=52 fables vs h3=3 big sections → h2 chosen, each fable = one page.
//   2. Fallback: split by paragraphs (paragraphsPerPage) — for plain chapters with no headings.
//   - Each split section is wrapped in a complete <html>/<body> document (preserving <head>)
//   - Content before the first heading is kept only if it contains >80 non-tag characters
//   - Image src attributes are rewritten to absolute GitHub raw URLs

struct HTMLSplitter {

    struct Section {
        let title:       String
        let htmlContent: String
    }

    // MARK: - Split by headings, then by paragraphs as fallback

    /// - Parameter paragraphsPerPage: max <p> tags per output page when no headings found (default 10)
    static func split(html: String, fallbackTitle: String, paragraphsPerPage: Int = 10) -> [Section] {
        // Pick the heading level with the most occurrences — maximises granularity.
        // e.g. Aesop chapter 3: h2=52 fables, h3=3 big sections → h2 wins.
        let counts = ["h2", "h3", "h4"].map { (tag: $0, count: countTag($0, in: html)) }
        if let best = counts.filter({ $0.count > 1 }).max(by: { $0.count < $1.count }) {
            let result = splitAt(tag: best.tag, html: html)
            if result.count > 1 { return result }
        }

        // Fallback: split by paragraph count
        let byParagraph = splitByParagraphs(html: html, fallbackTitle: fallbackTitle, perPage: paragraphsPerPage)
        if byParagraph.count > 1 { return byParagraph }

        return [Section(title: fallbackTitle, htmlContent: html)]
    }

    // MARK: - Rewrite image src to absolute URLs

    static func rewriteImageSrc(in html: String, imagesBaseURL: String) -> String {
        guard let re = try? NSRegularExpression(
            pattern: #"(<img\b[^>]*?\bsrc=")([^"]+)(")"#,
            options: .caseInsensitive
        ) else { return html }

        let ns      = html as NSString
        let result  = NSMutableString(string: html)
        let matches = re.matches(in: html, range: NSRange(location: 0, length: ns.length))

        for match in matches.reversed() {
            let srcRange = match.range(at: 2)
            let src      = ns.substring(with: srcRange)
            guard !src.hasPrefix("http"), !src.hasPrefix("data:") else { continue }
            let filename = (src as NSString).lastPathComponent
            result.replaceCharacters(in: srcRange, with: "\(imagesBaseURL)/\(filename)")
        }
        return result as String
    }

    // MARK: - Private

    private static func countTag(_ tag: String, in html: String) -> Int {
        guard let re = try? NSRegularExpression(
            pattern: "<\(tag)[\\s>]",
            options: .caseInsensitive
        ) else { return 0 }
        return re.numberOfMatches(in: html, range: NSRange(html.startIndex..., in: html))
    }

    private static func splitAt(tag: String, html: String) -> [Section] {
        let headContent = extractHead(html)
        let body        = extractBody(html) ?? html
        let nsBody      = body as NSString
        let length      = nsBody.length

        guard let splitRe = try? NSRegularExpression(
            pattern: "(?i)(?=<\(tag)[\\s>])"
        ) else { return [] }

        let splits = splitRe.matches(in: body, range: NSRange(location: 0, length: length))
        guard !splits.isEmpty else { return [] }

        var sections: [Section] = []

        // Content before the first heading
        let firstStart = splits[0].range.location
        if firstStart > 0 {
            let pre  = nsBody.substring(to: firstStart)
            let text = stripTags(pre).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count > 80 {
                sections.append(Section(
                    title:       "Introduction",
                    htmlContent: wrap(head: headContent, body: pre)
                ))
            }
        }

        for (i, match) in splits.enumerated() {
            let start = match.range.location
            let end   = (i + 1 < splits.count) ? splits[i + 1].range.location : length
            let chunk = nsBody.substring(with: NSRange(location: start, length: end - start))
            let title = headingText(tag: tag, in: chunk) ?? "Chapter \(i + 1)"
            sections.append(Section(
                title:       title,
                htmlContent: wrap(head: headContent, body: chunk)
            ))
        }

        return sections
    }

    // MARK: - Split by paragraph count (fallback for plain novel chapters)

    private static func splitByParagraphs(html: String, fallbackTitle: String, perPage: Int) -> [Section] {
        let headContent = extractHead(html)
        let body        = extractBody(html) ?? html
        let nsBody      = body as NSString

        // Count meaningful block elements: <p>, <li>, <a> (for ToC-style pages)
        // Use <p> as primary split points; if too few <p>, fall back to character-based split
        guard let re = try? NSRegularExpression(pattern: "(?i)(?=<p[\\s>])") else {
            return [Section(title: fallbackTitle, htmlContent: html)]
        }
        var matches = re.matches(in: body, range: NSRange(location: 0, length: nsBody.length))

        // If not enough <p> tags, try splitting by <li> or <a> (ToC pages)
        if matches.count <= perPage {
            if let liRe = try? NSRegularExpression(pattern: "(?i)(?=<li[\\s>])") {
                let liMatches = liRe.matches(in: body, range: NSRange(location: 0, length: nsBody.length))
                if liMatches.count > perPage { matches = liMatches }
            }
        }

        guard matches.count > perPage else {
            return [Section(title: fallbackTitle, htmlContent: html)]
        }

        var sections: [Section] = []
        // Content before first <p> (e.g. heading of the chapter)
        let firstP = matches[0].range.location
        let preamble = firstP > 0 ? nsBody.substring(to: firstP) : ""

        // Group paragraph start indices into chunks of `perPage`
        var pageStarts: [Int] = []
        for i in stride(from: 0, to: matches.count, by: perPage) {
            pageStarts.append(matches[i].range.location)
        }

        for (pageIdx, start) in pageStarts.enumerated() {
            let end: Int
            if pageIdx + 1 < pageStarts.count {
                end = pageStarts[pageIdx + 1]
            } else {
                end = nsBody.length
            }

            let paragraphChunk = nsBody.substring(with: NSRange(location: start, length: end - start))
            // Include preamble (chapter heading) only on first page
            let bodyChunk = pageIdx == 0 ? preamble + paragraphChunk : paragraphChunk
            let pageTitle = pageIdx == 0 ? fallbackTitle : "\(fallbackTitle) (\(pageIdx + 1))"

            sections.append(Section(
                title:       pageTitle,
                htmlContent: wrap(head: headContent, body: bodyChunk)
            ))
        }

        return sections
    }

    private static func headingText(tag: String, in html: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: "(?i)<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>"
        ), let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              m.numberOfRanges > 1 else { return nil }
        let inner = (html as NSString).substring(with: m.range(at: 1))
        let text  = stripTags(inner).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func extractHead(_ html: String) -> String {
        guard let s = html.range(of: "<head", options: .caseInsensitive),
              let e = html.range(of: "</head>", options: .caseInsensitive)
        else { return "" }
        return String(html[s.lowerBound..<e.upperBound])
    }

    private static func extractBody(_ html: String) -> String? {
        guard let s  = html.range(of: "<body", options: .caseInsensitive),
              let gt = html[s.lowerBound...].range(of: ">"),
              let e  = html.range(of: "</body>", options: .caseInsensitive)
        else { return nil }
        return String(html[gt.upperBound..<e.lowerBound])
    }

    private static func wrap(head: String, body: String) -> String {
        "<!DOCTYPE html>\n<html>\n\(head)\n<body>\n\(body)\n</body>\n</html>"
    }

    static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
