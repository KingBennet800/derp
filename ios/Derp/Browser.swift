import UIKit
import WebKit

/// A tab: a web view (or, while Memory Saver has it asleep, what it'll wake up to).
final class Tab {
    let id = UUID()
    let isPrivate: Bool
    var webView: WKWebView?
    var url = ""
    var title = ""
    var progress: Double = 1
    var loading = false
    var canGoBack = false
    var canGoForward = false
    var desktop = UIDevice.current.userInterfaceIdiom == .pad

    /// Restored tabs load the first time you look at them.
    var pending: String?

    /// What Derp's script in the page (page.js) said: whether it reads well
    /// in Reader view, and its icon.
    var pageURL = ""
    var readable = false
    var icon: String?

    /// What Reader view shows (the page's address and HTML), once you open it.
    var reading: (url: String, html: String)?

    /// Memory Saver: when you last looked at this tab, and while it's asleep,
    /// the pages and history it wakes up to.
    var seen = Date()
    var sleeping: Any?
    var asleep: Bool { webView == nil && pending == nil && sleeping != nil }

    /// A derp:// page Derp itself is opening (web pages can't open them).
    var opening: URL?

    var observers: [NSKeyValueObservation] = []

    init(private isPrivate: Bool) {
        self.isPrivate = isPrivate
    }
}

/// What a window shows: the Browser tells it when tabs change.
protocol BrowserUI: AnyObject {
    func show(_ tab: Tab)
    func tabsChanged()
    func tabChanged(_ tab: Tab)
    func focusAddress()
    func blankTab()
    func loadingChanged(_ loading: Bool)
    func present(_ controller: UIViewController, from sourceView: UIView?)
    func toast(_ text: String)
    func confirmPair(_ link: String)
    func downloadStarted()
    func saveStickers(_ png: Data?, done: @escaping (Bool) -> Void)
    func scanPairingCode(done: @escaping () -> Void)
    func importFile(kind: String, done: @escaping ([String: Any]) -> Void)
    func unlock(done: @escaping (Bool) -> Void)
    func openTab(_ url: URL, private: Bool, background: Bool)
    func pageEnded()
    var dark: Bool { get }
}

/// One window's tabs. Derp for Android has one window; on an iPad an
/// installed Derp can have several, each with its own tabs.
final class Browser: NSObject {
    let app = DerpApp.shared
    let windowID: String
    private(set) var tabs: [Tab] = []
    private(set) var current: Tab?
    weak var ui: BrowserUI?
    private var started = false

    init(windowID: String) {
        self.windowID = windowID
    }

    // ── Starting ───────────────────────────────────────────────────────────

    /// Restores this window's tabs (or opens a new tab), opens [url] if
    /// asked to, and, until you've made your dork, opens the dork editor.
    func start(opening url: URL?) {
        guard !started else { return }
        started = true
        restore()
        if let url {
            newTab(url.absoluteString)
        } else if tabs.isEmpty {
            newTab(nil)
        }
        if !app.dork.made { openWelcome() }
        select(current ?? tabs.last!)
    }

    private func openWelcome() {
        let welcome = Pages.base + "dork.html?welcome=1"
        if let tab = current ?? tabs.last, tab.pending == "derp:newtab.html" || tab.url == Pages.base + "newtab.html" || (tab.url.isEmpty && tab.pending == nil) {
            tab.pending = nil
            load(tab, welcome)
        } else {
            newTab(welcome)
        }
    }

    // ── Tabs ───────────────────────────────────────────────────────────────

    @discardableResult
    func newTab(_ url: String?, private isPrivate: Bool = false, select: Bool = true, after parent: Tab? = nil, configuration: WKWebViewConfiguration? = nil) -> Tab {
        let tab = Tab(private: isPrivate)
        let index = parent.flatMap { p in tabs.firstIndex { $0 === p } }.map { $0 + 1 } ?? tabs.count
        tabs.insert(tab, at: index)
        if let configuration {
            attach(tab, configuration: configuration)
        } else if let url {
            load(tab, url)
        } else {
            home(tab)
        }
        if select { self.select(tab) }
        ui?.tabsChanged()
        save()
        if url == nil && configuration == nil && select { ui?.blankTab() }
        return tab
    }

    func select(_ tab: Tab) {
        if current !== tab { current?.seen = Date() }
        current = tab
        tab.seen = Date()
        wake(tab)
        if let saved = tab.pending {
            tab.pending = nil
            load(tab, resolve(saved))
        }
        ui?.show(tab)
        save()
    }

    func close(_ tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        tabs.remove(at: index)
        tab.observers = []
        tab.webView?.stopLoading()
        tab.webView?.removeFromSuperview()
        tab.webView = nil
        if current === tab {
            current = nil
            let next: Tab? = tabs.indices.contains(index) ? tabs[index] : tabs.last
            if let next { select(next) } else { newTab(nil) }
        }
        if tab.isPrivate && !app.allTabs().contains(where: { $0.isPrivate }) { app.forgetPrivate() }
        ui?.tabsChanged()
        save()
    }

    func load(_ tab: Tab, _ url: String) {
        tab.url = url
        guard let target = URL(string: url) else { return }
        if target.scheme == Pages.scheme { tab.opening = target }
        let webView = tab.webView ?? attach(tab)
        webView.load(URLRequest(url: target))
        ui?.tabChanged(tab)
    }

    func home(_ tab: Tab) { load(tab, Pages.base + "newtab.html") }

    func openPage(_ name: String) {
        guard let tab = current else { return }
        load(tab, Pages.base + name)
    }

    /// Screenshot with stickers: the picture (a PNG data: URL) waiting for
    /// stickers.html, and the tab it opens next to.
    var stickerShot: String?
    private weak var stickerFrom: Tab?

    func openStickers(_ shot: String, from tab: Tab) {
        stickerShot = shot
        stickerFrom = tab
        newTab(Pages.base + "stickers.html", private: tab.isPrivate, after: tab)
    }

    /// The sticker editor in [tab] is done: it closes, and you're back on the page.
    func closeStickers(_ tab: Tab?) {
        let from = stickerFrom
        stickerShot = nil
        stickerFrom = nil
        if let tab, tabs.contains(where: { $0 === tab }) { close(tab) }
        if let from, tabs.contains(where: { $0 === from }) { select(from) }
    }

    /// Pages worth remembering in history and bookmarks: websites, not Derp's own.
    func isWebPage(_ tab: Tab) -> Bool { Address.isWeb(tab.url) }
    func isDerpPage(_ tab: Tab) -> Bool { Pages.isPage(tab.url) }
    func isReader(_ tab: Tab) -> Bool { tab.url.hasPrefix(Pages.base + "reader.html") }

    /// Bookmarks the page, or removes its bookmark; true if it's bookmarked now.
    func toggleBookmark(_ tab: Tab) -> Bool {
        app.pairing.changed()
        if app.library.isBookmarked(tab.url) {
            app.library.unbookmark(tab.url)
            return false
        }
        app.library.bookmark(tab.url, title: tab.title.isEmpty ? display(tab) : tab.title)
        return true
    }

    func toggleDesktop(_ tab: Tab) {
        tab.desktop.toggle()
        tab.webView?.reload()
    }

    /// What the address bar shows: the site's name, what you searched for, or
    /// nothing on Derp's own pages.
    func display(_ tab: Tab) -> String {
        let url = tab.pending ?? tab.url
        if url.isEmpty || url.hasPrefix("derp:") { return isReader(tab) ? Address.host(tab.reading?.url ?? "") ?? "" : "" }
        if let terms = Engine.current.terms(url) { return terms }
        return Address.host(url) ?? url
    }

    /// The full address, or what you searched for, for editing.
    func address(_ tab: Tab) -> String {
        let url = tab.pending ?? tab.url
        if url.hasPrefix("derp:") { return "" }
        return Engine.current.terms(url) ?? url
    }

    // ── Restoring tabs ─────────────────────────────────────────────────────

    /// Your (non-private) tabs, saved so they come back next time. Derp's own
    /// pages are saved as derp:<page>.
    func save() {
        let kept = tabs.filter { !$0.isPrivate }
        let list = kept.map { saved(isReader($0) ? ($0.reading?.url ?? "") : ($0.pending ?? $0.url)) }
        let index = kept.firstIndex { $0 === current } ?? 0
        Prefs.set("tabs." + windowID, list)
        Prefs.set("current." + windowID, index)
        // A window iOS forgot comes back with the tabs last seen.
        Prefs.set("tabs.last", list)
        Prefs.set("current.last", index)
    }

    private func restore() {
        let fresh = Prefs.store.array(forKey: "tabs." + windowID) == nil
        let key = fresh && app.windowCount <= 1 ? "last" : windowID
        let list = Prefs.store.array(forKey: "tabs." + key) as? [String] ?? []
        for url in list {
            let tab = Tab(private: false)
            tab.pending = url.isEmpty ? "derp:newtab.html" : url
            tab.title = ""
            tabs.append(tab)
        }
        let index = Prefs.store.integer(forKey: "current." + key)
        current = tabs.indices.contains(index) ? tabs[index] : tabs.last
    }

    private func saved(_ url: String) -> String {
        if url.isEmpty { return "derp:newtab.html" }
        if Pages.isPage(url) { return "derp:" + (url.dropFirst(Pages.base.count).components(separatedBy: "?").first ?? "newtab.html") }
        return url
    }

    private func resolve(_ saved: String) -> String {
        saved.hasPrefix("derp:") && !saved.hasPrefix("derp://") ? Pages.base + saved.dropFirst(5) : saved
    }

    static func forget(windowID: String) {
        Prefs.set("tabs." + windowID, nil)
        Prefs.set("current." + windowID, nil)
    }

    // ── Web views ──────────────────────────────────────────────────────────

    @discardableResult
    private func attach(_ tab: Tab, configuration: WKWebViewConfiguration? = nil) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration ?? app.configuration(private: tab.isPrivate))
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.isFindInteractionEnabled = true
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        webView.backgroundColor = Palette.of(dark: ui?.dark ?? false, private: tab.isPrivate).content
        webView.isOpaque = false
        tab.webView = webView
        tab.observers = [
            webView.observe(\.estimatedProgress) { [weak self, weak tab] view, _ in
                guard let self, let tab else { return }
                tab.progress = view.estimatedProgress
                self.ui?.tabChanged(tab)
            },
            webView.observe(\.isLoading) { [weak self, weak tab] view, _ in
                guard let self, let tab else { return }
                tab.loading = view.isLoading
                if tab === self.current { self.ui?.loadingChanged(view.isLoading) }
                self.ui?.tabChanged(tab)
            },
            webView.observe(\.title) { [weak self, weak tab] view, _ in
                guard let self, let tab else { return }
                tab.title = view.title ?? ""
                if !tab.isPrivate && Address.isWeb(tab.url) { self.app.library.title(tab.url, title: tab.title) }
                self.ui?.tabChanged(tab)
            },
            webView.observe(\.url) { [weak self, weak tab] view, _ in
                guard let self, let tab, let url = view.url?.absoluteString else { return }
                tab.url = url
                self.ui?.tabChanged(tab)
                self.save()
            },
            webView.observe(\.canGoBack) { [weak self, weak tab] view, _ in
                guard let self, let tab else { return }
                tab.canGoBack = view.canGoBack
                self.ui?.tabChanged(tab)
            },
            webView.observe(\.canGoForward) { [weak self, weak tab] view, _ in
                guard let self, let tab else { return }
                tab.canGoForward = view.canGoForward
                self.ui?.tabChanged(tab)
            },
        ]
        return webView
    }

    func tab(for webView: WKWebView) -> Tab? { tabs.first { $0.webView === webView } }

    // ── Memory Saver ───────────────────────────────────────────────────────

    /// Memory Saver: tabs you haven't looked at for half an hour (or, when
    /// iOS is short of memory, all but the one you're on) fall asleep. Their
    /// page is let go, and comes back, history and all, when you look at it.
    /// Tabs playing something stay awake.
    func sleepIdleTabs(all: Bool = false) {
        guard app.memorySaver else { return }
        let idle = Date().addingTimeInterval(-30 * 60)
        for tab in tabs where tab !== current && tab.webView != nil && (all || tab.seen < idle) {
            tab.webView?.requestMediaPlaybackState { [weak self] state in
                guard state == .none || state == .paused else { return }
                self?.sleep(tab)
            }
        }
    }

    private func sleep(_ tab: Tab) {
        guard tab !== current, let webView = tab.webView else { return }
        tab.sleeping = webView.interactionState ?? tab.url
        tab.observers = []
        webView.removeFromSuperview()
        tab.webView = nil
        tab.readable = false
        NSLog("Derp: Memory Saver: a tab fell asleep")
        ui?.tabsChanged()
    }

    /// A sleeping tab you look at again wakes up where it was.
    private func wake(_ tab: Tab) {
        guard tab.webView == nil, let state = tab.sleeping else { return }
        tab.sleeping = nil
        let webView = attach(tab)
        if let url = state as? String {
            if let target = URL(string: url) { webView.load(URLRequest(url: target)) }
        } else {
            webView.interactionState = state
        }
        NSLog("Derp: Memory Saver: a tab woke up")
        ui?.tabsChanged()
    }

    // ── Reader view ────────────────────────────────────────────────────────

    func canRead(_ tab: Tab) -> Bool { tab.readable && tab.pageURL == tab.url && tab.webView != nil }

    /// Asks the page for itself (page.js); Reader view opens with it.
    func openReader(_ tab: Tab) {
        guard canRead(tab), let webView = tab.webView else { return }
        webView.evaluateJavaScript("derpReaderPage()", in: nil, in: Pages.world) { [weak self] result in
            guard let self, case .success(let value) = result, let page = value as? [String: Any],
                  let url = page["url"] as? String, let html = page["html"] as? String else { return }
            tab.reading = (url, html)
            self.load(tab, Pages.base + "reader.html")
        }
    }

    // ── Passwords ──────────────────────────────────────────────────────────

    /// You signed in somewhere: offer to save the password (or update it). Not
    /// in private tabs, and not if you turned it off on the Passwords page.
    func offerToSaveLogin(_ tab: Tab, origin: WKSecurityOrigin, body: [String: Any]) {
        let password = body["password"] as? String ?? ""
        let username = body["username"] as? String ?? ""
        guard !tab.isPrivate, app.logins.offerToSave, !password.isEmpty, ["http", "https"].contains(origin.protocol) else { return }
        let site = origin.origin
        guard let kind = app.logins.offer(origin: site, username: username, password: password) else { return }
        let alert = UIAlertController(title: kind == "update" ? "Update your password for \(origin.host)?" : "Save your password for \(origin.host)?",
                                      message: username.isEmpty ? nil : username, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Not now", style: .cancel))
        alert.addAction(UIAlertAction(title: kind == "update" ? "Update" : "Save", style: .default) { [weak self] _ in
            self?.app.logins.save(origin: site, formAction: body["action"] as? String, realm: nil, username: username, password: password)
            self?.app.pairing.changed()
            self?.ui?.toast(kind == "update" ? "Password updated" : "Password saved")
        })
        ui?.present(alert, from: nil)
    }

    /// You tapped a sign-in form: offer the logins saved for the site.
    func offerLogins(_ tab: Tab, frame: WKFrameInfo) {
        let logins = app.logins.forSite(frame.securityOrigin.host)
        guard !logins.isEmpty, let webView = tab.webView else { return }
        let sheet = UIAlertController(title: "Sign in as", message: frame.securityOrigin.host, preferredStyle: .actionSheet)
        for login in logins {
            sheet.addAction(UIAlertAction(title: login.username.isEmpty ? "(no username)" : login.username, style: .default) { [weak self] _ in
                guard let password = self?.app.logins.password(login.guid) else { return }
                self?.app.logins.used(login.guid)
                webView.callAsyncJavaScript("return derpFill(username, password)", arguments: ["username": login.username, "password": password],
                                            in: frame, in: Pages.world, completionHandler: nil)
            })
        }
        sheet.addAction(UIAlertAction(title: "Not now", style: .cancel))
        ui?.present(sheet, from: webView)
    }
}

// ── Each tab's web view ─────────────────────────────────────────────────────

extension Browser: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        guard let tab = self.tab(for: webView), let url = action.request.url else { return decisionHandler(.allow, preferences) }
        let main = action.targetFrame?.isMainFrame ?? true
        let text = url.absoluteString
        preferences.preferredContentMode = tab.desktop ? .desktop : .mobile

        // A pairing code's link (from your computer): pair, once you say so.
        if text.hasPrefix(Pairing.link) {
            ui?.confirmPair(text)
            return decisionHandler(.cancel, preferences)
        }
        if url.scheme == Pages.scheme {
            // Derp's pages open from Derp, or from each other; derp://open… is Derp's own link.
            if url.host != "pages" {
                app.open(url)
                return decisionHandler(.cancel, preferences)
            }
            // (sourceFrame can be missing, whatever its type says.)
            let source = action.value(forKey: "sourceFrame") as? WKFrameInfo
            let fromPage = source?.securityOrigin.protocol == Pages.scheme
            let fromDerp = tab.opening.map { $0.path == url.path } ?? false
            tab.opening = nil
            return decisionHandler(fromPage || fromDerp || !main ? .allow : .cancel, preferences)
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if !["http", "https", "about", "data", "blob", "file", "javascript"].contains(scheme) {
            // mailto:, tel:, maps and other apps' links go to those apps.
            if main { UIApplication.shared.open(url) { [weak self] opened in if !opened { self?.ui?.toast("No app here can open that link") } } }
            return decisionHandler(.cancel, preferences)
        }
        if action.shouldPerformDownload { return decisionHandler(.download, preferences) }
        if main && (scheme == "http" || scheme == "https") {
            if let duck = Address.doodleOnDuck(url, dark: ui?.dark ?? false) {
                decisionHandler(.cancel, preferences)
                return load(tab, duck)
            }
            if let clean = Address.stripped(url), action.request.httpMethod == "GET" {
                decisionHandler(.cancel, preferences)
                webView.load(URLRequest(url: clean))
                return
            }
            // Tells Google whether Derp is light or dark, the way Chrome does
            // (its Sec-CH-Prefers-Color-Scheme hint), so its pages come in Derp's theme.
            if url.host == "www.google.com", action.request.httpMethod == "GET",
               action.request.value(forHTTPHeaderField: "Sec-CH-Prefers-Color-Scheme") == nil {
                decisionHandler(.cancel, preferences)
                var request = action.request
                request.setValue(ui?.dark == true ? "dark" : "light", forHTTPHeaderField: "Sec-CH-Prefers-Color-Scheme")
                webView.load(request)
                return
            }
        }
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        if response.isForMainFrame && (!response.canShowMIMEType || disposition.lowercased().hasPrefix("attachment")) {
            return decisionHandler(.download)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        app.downloads.start(download, ui: ui)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        app.downloads.start(download, ui: ui)
    }

    /// History: the pages you go to, except in private tabs.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let tab = self.tab(for: webView), let url = webView.url?.absoluteString else { return }
        tab.url = url
        tab.readable = false
        if !tab.isPrivate && Address.isWeb(url) { app.library.visit(url) }
        ui?.tabChanged(tab)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let tab = self.tab(for: webView), tab === current { ui?.pageEnded() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let error = error as NSError
        // A link another app opens, a download, a stop: not worth telling.
        guard error.code != NSURLErrorCancelled, error.domain != "WebKitErrorDomain" || error.code != 102 else { return }
        if let tab = self.tab(for: webView), tab === current { ui?.toast(error.localizedDescription) }
    }

    /// A tab's page crashed (or iOS needed the memory): load it again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let tab = self.tab(for: webView) else { return }
        if tab === current { webView.reload() } else { sleep(tab) }
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        guard method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest else {
            return completionHandler(.performDefaultHandling, nil)
        }
        let alert = UIAlertController(title: "Sign in to \(challenge.protectionSpace.host)", message: challenge.protectionSpace.realm, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Username"; $0.textContentType = .username }
        alert.addTextField { $0.placeholder = "Password"; $0.isSecureTextEntry = true; $0.textContentType = .password }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(.cancelAuthenticationChallenge, nil) })
        alert.addAction(UIAlertAction(title: "Sign in", style: .default) { _ in
            let user = alert.textFields?[0].text ?? "", password = alert.textFields?[1].text ?? ""
            completionHandler(.useCredential, URLCredential(user: user, password: password, persistence: .forSession))
        })
        ui?.present(alert, from: nil)
    }

    /// Links that open a new window open a new tab.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let parent = self.tab(for: webView)
        let tab = newTab(nil, private: parent?.isPrivate ?? false, after: parent, configuration: configuration)
        return tab.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let tab = self.tab(for: webView) { close(tab) }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        ui?.present(alert, from: nil) ?? completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.protocol == Pages.scheme ? nil : frame.securityOrigin.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        ui?.present(alert, from: nil) ?? completionHandler(false)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
        ui?.present(alert, from: nil) ?? completionHandler(nil)
    }

    /// A site asks for the camera or microphone: you say whether it may.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let what: String
        switch type {
        case .camera: what = "your camera"
        case .microphone: what = "your microphone"
        default: what = "your camera and microphone"
        }
        let alert = UIAlertController(title: "Let \(origin.host) use \(what)?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Don’t allow", style: .cancel) { _ in decisionHandler(.deny) })
        alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in decisionHandler(.grant) })
        ui?.present(alert, from: nil) ?? decisionHandler(.deny)
    }

    /// Long-press on a link: open it in a new tab, a private tab, copy or share it.
    func webView(_ webView: WKWebView, contextMenuConfigurationForElement element: WKContextMenuElementInfo,
                 completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
        guard let link = element.linkURL, let tab = self.tab(for: webView) else { return completionHandler(nil) }
        let config = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            var actions = [
                UIAction(title: "Open in new tab", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in
                    self?.newTab(link.absoluteString, private: tab.isPrivate, select: false, after: tab)
                    self?.ui?.toast("Opened in a new tab")
                },
            ]
            if !tab.isPrivate {
                actions.append(UIAction(title: "Open in private tab", image: UIImage(systemName: "theatermasks")) { [weak self] _ in
                    self?.newTab(link.absoluteString, private: true, after: tab)
                })
            }
            actions.append(UIAction(title: "Copy link", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.url = link })
            actions.append(UIAction(title: "Share link", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                self?.ui?.present(UIActivityViewController(activityItems: [link], applicationActivities: nil), from: webView)
            })
            return UIMenu(title: link.absoluteString, children: actions)
        }
        completionHandler(config)
    }
}
