import AppKit
import WebKit
import SwiftUI

@MainActor final class BrowserSession: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    let provider: Provider
    let webView: WKWebView
    private var window: NSWindow?
    private var popups: [ObjectIdentifier: NSWindow] = [:]
    private var statusLabels: [ObjectIdentifier: NSTextField] = [:]
    var isSigningIn: Bool { window?.isVisible == true || popups.values.contains { $0.isVisible } }

    private func makeWindow(for view: WKWebView, title: String) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 740),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.delegate = self
        let status = NSTextField(labelWithString: "Loading sign-in page…")
        status.lineBreakMode = .byTruncatingMiddle
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let reload = NSButton(title: "Reload", target: self, action: #selector(reloadPage(_:)))
        let dashboard = NSButton(title: "Return to usage", target: self, action: #selector(returnToUsage))
        let bar = NSStackView(views: [status, reload, dashboard])
        bar.orientation = .horizontal
        bar.spacing = 12
        let content = NSView()
        for child in [bar, view] { child.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(child) }
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            bar.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            view.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 8),
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        statusLabels[ObjectIdentifier(view)] = status
        w.contentView = content
        w.center()
        return w
    }
    @objc private func reloadPage(_ sender: NSButton) {
        if let popup = popups.first(where: { $0.value === sender.window }),
           let view = popup.value.contentView?.subviews.compactMap({ $0 as? WKWebView }).first {
            view.reload()
        } else if webView.url?.scheme == "https" { webView.reload() }
        else { webView.load(URLRequest(url: provider.website)) }
    }
    @objc private func returnToUsage() {
        for popup in Array(popups.values) { popup.close() }
        webView.load(URLRequest(url: provider.website))
        window?.makeKeyAndOrderFront(nil)
    }
    init(provider: Provider) {
        self.provider = provider
        let config = WKWebViewConfiguration()
        let identifier = provider == .chatgpt ? "D11CC34A-A372-4D0A-9327-68AB45A0D9B3" : provider == .claude ? "D11CC34A-A372-4D0A-9327-68AB45A0D9B1" : "D11CC34A-A372-4D0A-9327-68AB45A0D9B2"
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: identifier)!)
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }
    func show() {
        if window == nil {
            window = makeWindow(for: webView, title: "Sign in to \(provider.name) — close this window, then Check connection")
        }
        if webView.url == nil || webView.url?.scheme == "about" { webView.load(URLRequest(url: provider.website)) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func clear() async {
        webView.stopLoading()
        window?.close()
        for popup in Array(popups.values) { popup.close() }
        await webView.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        webView.loadHTMLString("", baseURL: nil)
    }
    func json(path: String) async throws -> Data {
        guard !isSigningIn else { throw UsageError.unavailable("Finish signing in and close the sign-in windows before checking the connection.") }
        if webView.url?.host != provider.website.host {
            webView.load(URLRequest(url: provider.website))
            for _ in 0..<80 {
                try await Task.sleep(nanoseconds: 250_000_000)
                if !webView.isLoading && webView.url?.host == provider.website.host { break }
            }
        }
        guard webView.url?.host == provider.website.host, webView.url?.scheme == "https" else { throw UsageError.unauthorized }
        let script = """
        const abort = new AbortController();
        const timer = setTimeout(() => abort.abort(), 20000);
        try {
          const headers = {Accept:'application/json'};
          if (chatgpt) {
            // Keep the session token inside the isolated web view; never persist or return it.
            const session = await fetch('/api/auth/session', {credentials:'include', cache:'no-store', redirect:'error', signal:abort.signal});
            if (!session.ok) return JSON.stringify({status:session.status, body:''});
            const auth = await session.json();
            if (!auth.accessToken) return JSON.stringify({status:401, body:''});
            headers.Authorization = 'Bearer ' + auth.accessToken;
          }
          const r = await fetch(path, {credentials:'include', cache:'no-store', redirect:'error', signal:abort.signal, headers});
          return JSON.stringify({status:r.status, body:await r.text()});
        } finally { clearTimeout(timer); }
        """
        let result = try await webView.callAsyncJavaScript(script, arguments: ["path": path, "chatgpt": provider == .chatgpt], in: nil, contentWorld: .defaultClient)
        guard let text = result as? String, let data = text.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? Int, let body = json["body"] as? String else { throw UsageError.malformed }
        return try Self.checked(status: status, body: Data(body.utf8))
    }
    static func checked(status: Int, body: Data) throws -> Data {
        switch status {
        case 200: return body
        case 401, 403: throw UsageError.unauthorized
        case 429: throw UsageError.rateLimited
        default: throw UsageError.unavailable("The dashboard returned HTTP \(status). Try opening the provider and signing in again.")
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        // Preserve window.opener and WebKit's supplied configuration for OAuth callbacks.
        // Loading the popup request in the parent destroys the original login context.
        let child = WKWebView(frame: .zero, configuration: configuration)
        child.navigationDelegate = self
        child.uiDelegate = self
        let popup = makeWindow(for: child, title: "Continue signing in to \(provider.name)")
        popups[ObjectIdentifier(child)] = popup
        popup.makeKeyAndOrderFront(nil)
        return child
    }
    func webViewDidClose(_ webView: WKWebView) {
        popups[ObjectIdentifier(webView)]?.close()
    }
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow,
              let entry = popups.first(where: { $0.value === closing }) else { return }
        popups.removeValue(forKey: entry.key)
        statusLabels.removeValue(forKey: entry.key)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        statusLabels[ObjectIdentifier(webView)]?.stringValue = webView.url?.host ?? "Sign-in window · use Return to usage if this page is blank"
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showNavigationError(error, in: webView)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showNavigationError(error, in: webView)
    }
    private func showNavigationError(_ error: Error, in view: WKWebView) {
        let code = (error as NSError).code
        guard code != NSURLErrorCancelled else { return }
        // Do not display callback URLs or OAuth parameters from the underlying error.
        statusLabels[ObjectIdentifier(view)]?.stringValue = "Page failed to load (\(code)). Reload or return to usage to retry."
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        statusLabels[ObjectIdentifier(webView)]?.stringValue = "The sign-in page stopped. Click Reload to try again."
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme
        decisionHandler(scheme == "https" || scheme == "about" ? .allow : .cancel)
    }
}
