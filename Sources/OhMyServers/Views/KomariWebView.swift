import AppKit
import OhMyServersCore
import SwiftUI
import WebKit

/// Shared, preloaded Komari web views, one per site. WKWebViews are created once
/// and reused across popover opens, so the menu shows live cards instantly instead
/// of reloading each Komari SPA (JS bundle + WebSocket handshake) every time.
@MainActor
final class KomariWebStore: ObservableObject {
    static let shared = KomariWebStore()

    @Published private(set) var contentHeights: [UUID: CGFloat] = [:]

    private var webViews: [UUID: WKWebView] = [:]
    private var loadedURLs: [UUID: URL] = [:]

    /// Warm web views at app launch so the first popover open is instant.
    /// Also evicts views for sites that were removed or disabled.
    func preload(sites: [KomariSite]) {
        let validIDs = Set(sites.compactMap { $0.url != nil ? $0.id : nil })
        for id in webViews.keys where !validIDs.contains(id) {
            remove(siteID: id)
        }
        for site in sites {
            guard let url = site.url else { continue }
            _ = webView(siteID: site.id, url: url)
        }
    }

    func remove(siteID: UUID) {
        webViews[siteID]?.stopLoading()
        webViews.removeValue(forKey: siteID)
        loadedURLs.removeValue(forKey: siteID)
        contentHeights.removeValue(forKey: siteID)
    }

    func webView(siteID: UUID, url: URL) -> WKWebView {
        if let existing = webViews[siteID], loadedURLs[siteID] == url { return existing }

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
            self?.contentHeights[siteID] = height
        }
        config.userContentController.add(coordinator, name: "komariSize")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: url))

        webViews[siteID]?.stopLoading()
        webViews[siteID] = webView
        loadedURLs[siteID] = url
        return webView
    }

    func contentHeight(siteID: UUID) -> CGFloat {
        contentHeights[siteID] ?? 300
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

/// Embeds one site's shared Komari web view (see KomariWebStore).
struct KomariWebView: NSViewRepresentable {
    let siteID: UUID
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        KomariWebStore.shared.webView(siteID: siteID, url: url)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
