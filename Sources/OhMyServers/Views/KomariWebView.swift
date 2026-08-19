import AppKit
import SwiftUI
import WebKit

/// Shared, preloaded Komari web view. The WKWebView is created once and reused
/// across popover opens, so the menu shows live cards instantly instead of
/// reloading the whole Komari SPA (JS bundle + WebSocket handshake) every time.
@MainActor
final class KomariWebStore: ObservableObject {
    static let shared = KomariWebStore()

    @Published private(set) var contentHeight: CGFloat = 300

    static var defaultURL: URL? {
        URL(string: UserDefaults.standard.string(forKey: "komariBaseURL") ?? "https://komari.fourj.ccwu.cc")
    }

    private var webView: WKWebView?
    private var loadedURL: URL?

    /// Warm the web view at app launch so the first popover open is instant.
    func preload() {
        guard let url = Self.defaultURL else { return }
        _ = webView(for: url)
    }

    func webView(for url: URL) -> WKWebView {
        if let webView, loadedURL == url { return webView }

        let config = WKWebViewConfiguration()

        // The site reads localStorage "appearance" before first paint; force dark to match the menubar.
        let darkModeJS = #"try { localStorage.setItem('appearance', '"dark"'); } catch (e) {}"#
        config.userContentController.addUserScript(
            WKUserScript(source: darkModeJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        let cssJSON = (try? String(decoding: JSONEncoder().encode(Self.stripChromeCSS), as: UTF8.self)) ?? #""""#
        let injectJS = """
        var s = document.createElement('style');
        s.textContent = \(cssJSON);
        document.head.appendChild(s);
        \(Self.sizeObserverJS)
        """
        config.userContentController.addUserScript(
            WKUserScript(source: injectJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )

        let coordinator = Coordinator { [weak self] height in
            self?.contentHeight = height
        }
        config.userContentController.add(coordinator, name: "komariSize")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: url))

        self.webView = webView
        loadedURL = url
        return webView
    }

    private static let stripChromeCSS = """
    /* Live frontend (komari 1.4.x): floating control pill + footer */
    .floating-controls, .site-footer { display: none !important; }
    /* Neutralize shell layout: content padding, max width, forced viewport height */
    .flex-1.px-3 { padding: 0 !important; }
    .max-w-\\[1720px\\] { max-width: none !important; }
    .min-h-screen { min-height: 0 !important; }
    html, body { background: transparent !important; margin: 0 !important; }
    /* Two cards side by side */
    div[style*="grid-template-columns"] {
        grid-template-columns: repeat(2, minmax(0, 1fr)) !important;
        gap: 12px !important;
    }
    ::-webkit-scrollbar { display: none; }
    """

    /// Posts document.body.scrollHeight on every layout change.
    private static let sizeObserverJS = """
    function komariPostSize() {
        window.webkit.messageHandlers.komariSize.postMessage(document.body.scrollHeight);
    }
    new ResizeObserver(komariPostSize).observe(document.body);
    komariPostSize();
    setTimeout(komariPostSize, 500);
    setTimeout(komariPostSize, 1500);
    """

    /// Retained by the WKUserContentController for the web view's lifetime.
    private final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onHeight: (CGFloat) -> Void

        init(onHeight: @escaping (CGFloat) -> Void) {
            self.onHeight = onHeight
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "komariSize" else { return }
            let raw = (message.body as? Double) ?? (message.body as? Int).map(Double.init)
            guard let height = raw, height > 100, height < 1200 else { return }
            DispatchQueue.main.async {
                self.onHeight(CGFloat(height))
            }
        }

        // target=_blank links open in the default browser.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}

/// Embeds the shared Komari web view (see KomariWebStore).
struct KomariWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        KomariWebStore.shared.webView(for: url)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
