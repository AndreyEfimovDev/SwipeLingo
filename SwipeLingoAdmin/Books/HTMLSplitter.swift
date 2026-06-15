import Foundation

// MARK: - HTMLSplitter
//
// Splits a single HTML document into multiple sections at <h2> or <h3> headings.
// Used during EPUB export to turn one large chapter file into individual fable pages.
//
// Strategy:
//   - Count <h3> and <h2> occurrences; split at whichever is more granular (>1 occurrence)
//   - Each split section is wrapped in a complete <html>/<body> document (preserving <head>)
//   - Content before the first heading is kept only if it contains >80 non-tag characters
//   - Image src attributes are rewritten to absolute GitHub raw URLs

struct HTMLSplitter {

    struct Section {
        let title:       String
        let htmlContent: String
    }

    // MARK: - Split by headings

    static func split(html: String, fallbackTitle: String) -> [Section] {
        let h3 = countTag("h3", in: html)
        let h2 = countTag("h2", in: html)

        if h3 > 1 {
            let result = splitAt(tag: "h3", html: html)
            if result.count > 1 { return result }
        }
        if h2 > 1 {
            let result = splitAt(tag: "h2", html: html)
            if result.count > 1 { return result }
        }
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
