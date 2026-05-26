import SwiftUI
import UIKit
import WebKit

// MARK: - BookPagedReader
//
// UIViewControllerRepresentable wrapping UIPageViewController with .pageCurl transition.
// Each chapter is a BookChapterVC containing its own WKWebView.
// Adjacent chapter VCs are created lazily and cached (±3 around current).
// Swipe navigation is handled natively by UIPageViewController.
// Programmatic navigation (buttons, TOC) goes through setViewControllers(_:direction:animated:).

struct BookPagedReader: UIViewControllerRepresentable {

    let book:         Book
    let chapterIndex: Int          // driven by BookReaderViewModel
    let colorScheme:  ColorScheme
    let onWordTap:    (String) -> Void
    let onPageChange: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(book: book) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageVC = UIPageViewController(
            transitionStyle:       .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue]
        )
        pageVC.dataSource = context.coordinator
        pageVC.delegate   = context.coordinator
        context.coordinator.configure(
            pageVC:       pageVC,
            onWordTap:    onWordTap,
            onPageChange: onPageChange
        )

        let initial = context.coordinator.chapterVC(at: chapterIndex)
        pageVC.setViewControllers([initial], direction: .forward, animated: false)
        context.coordinator.currentIndex = chapterIndex

        pageVC.view.backgroundColor = background(for: colorScheme)
        return pageVC
    }

    func updateUIViewController(_ pageVC: UIPageViewController, context: Context) {
        let coord = context.coordinator
        coord.onWordTap    = onWordTap
        coord.onPageChange = onPageChange
        pageVC.view.backgroundColor = background(for: colorScheme)

        let target = chapterIndex
        guard target != coord.currentIndex else { return }
        let dir: UIPageViewController.NavigationDirection = target > coord.currentIndex ? .forward : .reverse
        let vc = coord.chapterVC(at: target)
        coord.currentIndex = target
        pageVC.setViewControllers([vc], direction: dir, animated: true)
    }

    private func background(for scheme: ColorScheme) -> UIColor {
        scheme == .dark
            ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            : UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1) // warm paper
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

        let book: Book
        var currentIndex = 0
        var onWordTap:    (String) -> Void = { _ in }
        var onPageChange: (Int) -> Void    = { _ in }
        private weak var pageVC: UIPageViewController?
        private var cache: [Int: BookChapterVC] = [:]

        init(book: Book) { self.book = book }

        func configure(
            pageVC: UIPageViewController,
            onWordTap: @escaping (String) -> Void,
            onPageChange: @escaping (Int) -> Void
        ) {
            self.pageVC       = pageVC
            self.onWordTap    = onWordTap
            self.onPageChange = onPageChange
        }

        func chapterVC(at index: Int) -> BookChapterVC {
            if let cached = cache[index] { return cached }
            let vc = BookChapterVC(index: index, book: book, coordinator: self)
            cache[index] = vc
            pruneCache(around: index)
            return vc
        }

        private func pruneCache(around center: Int) {
            let keep = (center - 3)...(center + 3)
            for key in cache.keys where !keep.contains(key) { cache.removeValue(forKey: key) }
        }

        // MARK: UIPageViewControllerDataSource

        func pageViewController(
            _ pvc: UIPageViewController,
            viewControllerBefore vc: UIViewController
        ) -> UIViewController? {
            guard let c = vc as? BookChapterVC, c.index > 0,
                  BookDownloadService.shared.isChapterDownloaded(book: book, index: c.index - 1)
            else { return nil }
            return chapterVC(at: c.index - 1)
        }

        func pageViewController(
            _ pvc: UIPageViewController,
            viewControllerAfter vc: UIViewController
        ) -> UIViewController? {
            guard let c = vc as? BookChapterVC,
                  c.index < book.totalChapters - 1,
                  BookDownloadService.shared.isChapterDownloaded(book: book, index: c.index + 1)
            else { return nil }
            return chapterVC(at: c.index + 1)
        }

        // MARK: UIPageViewControllerDelegate

        func pageViewController(
            _ pvc: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed,
                  let current = pvc.viewControllers?.first as? BookChapterVC else { return }
            currentIndex = current.index
            DispatchQueue.main.async { self.onPageChange(current.index) }
        }
    }
}

// MARK: - BookChapterVC

final class BookChapterVC: UIViewController {

    let index: Int
    private let book: Book
    private weak var coordinator: BookPagedReader.Coordinator?
    private var webView: WKWebView?

    init(index: Int, book: Book, coordinator: BookPagedReader.Coordinator) {
        self.index       = index
        self.book        = book
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Page background matches the webview background so the curl
        // always shows a solid page — even before HTML finishes rendering.
        let dark = traitCollection.userInterfaceStyle == .dark
        let pageBg: UIColor = dark
            ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            : UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)
        view.backgroundColor = pageBg

        let config = WKWebViewConfiguration()
        let proxy  = WeakScriptHandler(self)
        config.userContentController.add(proxy, name: "wordTapped")
        config.userContentController.add(proxy, name: "pageReady")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.backgroundColor = pageBg
        wv.isOpaque = true
        wv.scrollView.showsVerticalScrollIndicator = false
        wv.navigationDelegate = self
        wv.alpha = 0  // hidden until CSS injected; view.backgroundColor fills the curl visually
        view.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: view.topAnchor),
            wv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        webView = wv

        let url = BookDownloadService.shared.localChapterURL(book: book, index: index)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        wv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}

// MARK: - WKNavigationDelegate

extension BookChapterVC: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        injectCSS(into: webView)
        injectJS(into: webView)
        // Fade-in is triggered by JS "pageReady" message (fires after all images loaded/failed).
        // Fallback: JS also posts pageReady after 3s timeout.
    }
}

// MARK: - WKScriptMessageHandler

extension BookChapterVC: WKScriptMessageHandler {
    func userContentController(
        _ ucc: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case "wordTapped":
            if let word = message.body as? String {
                let clean = word.trimmingCharacters(in: .punctuationCharacters)
                guard !clean.isEmpty else { return }
                DispatchQueue.main.async { self.coordinator?.onWordTap(clean) }
            }
        case "pageReady":
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.22) { self.webView?.alpha = 1 }
            }
        default: break
        }
    }
}

// MARK: - CSS + JS injection

private extension BookChapterVC {

    func injectCSS(into wv: WKWebView) {
        let dark = traitCollection.userInterfaceStyle == .dark
        let fg   = dark ? "#e8e0d6" : "#1a1a1a"
        let bg   = dark ? "#1c1c1e" : "#faf9f6"
        let css  = """
        * { box-sizing: border-box; }
        html { -webkit-text-size-adjust: 100%; }
        body {
            font-family: Georgia, 'Times New Roman', serif;
            font-size: 18px;
            line-height: 1.75;
            color: \(fg);
            background: \(bg);
            margin: 0 auto;
            padding: 24px 24px 80px;
            max-width: 720px;
        }
        img { max-width: 100%; height: auto; display: block; margin: 1em auto; }
        h1, h2, h3 {
            font-family: -apple-system, sans-serif;
            font-weight: 700;
            line-height: 1.3;
            margin-top: 1.6em;
        }
        p { margin: 0 0 1.2em; }
        .sl-word { cursor: pointer; border-radius: 3px; transition: background 0.1s; }
        .sl-word:active { background: rgba(0, 122, 255, 0.15); }
        """
        wv.evaluateJavaScript("""
        (function(){
            var s = document.createElement('style');
            s.textContent = `\(css)`;
            document.head.appendChild(s);
        })();
        """, completionHandler: nil)
    }

    func injectJS(into wv: WKWebView) {
        wv.evaluateJavaScript("""
        (function(){
            // Word tap
            function wrapWords(node) {
                if (node.nodeType === 3) {
                    var parts = node.textContent.split(/(\\s+)/);
                    var frag  = document.createDocumentFragment();
                    parts.forEach(function(part) {
                        if (/\\S/.test(part)) {
                            var span = document.createElement('span');
                            span.className = 'sl-word';
                            span.textContent = part;
                            span.onclick = function() {
                                var c = part.replace(/[^a-zA-Z'\\-]/g,'');
                                if (c) window.webkit.messageHandlers.wordTapped.postMessage(c);
                            };
                            frag.appendChild(span);
                        } else {
                            frag.appendChild(document.createTextNode(part));
                        }
                    });
                    node.parentNode.replaceChild(frag, node);
                } else if (node.nodeType===1 && !['SCRIPT','STYLE','A'].includes(node.tagName)) {
                    Array.from(node.childNodes).forEach(wrapWords);
                }
            }
            wrapWords(document.body);

            // Signal ready after all images are loaded or failed
            var imgs     = Array.from(document.querySelectorAll('img[src]'));
            var total    = imgs.length;
            var done     = 0;
            var signaled = false;

            function signal() {
                if (!signaled) { signaled = true; window.webkit.messageHandlers.pageReady.postMessage(null); }
            }
            function tick(img, failed) {
                if (failed || img.naturalWidth === 0) img.style.display = 'none';
                if (++done >= total) signal();
            }

            if (total === 0) { signal(); return; }

            imgs.forEach(function(img) {
                if (img.complete) { tick(img, false); }
                else {
                    img.addEventListener('load',  function(){ tick(img, false); }, {once:true});
                    img.addEventListener('error', function(){ tick(img, true);  }, {once:true});
                }
            });

            // Hard timeout in case some images never respond
            setTimeout(signal, 3000);
        })();
        """, completionHandler: nil)
    }
}

// MARK: - WeakScriptHandler (breaks retain cycle with WKUserContentController)

private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}
