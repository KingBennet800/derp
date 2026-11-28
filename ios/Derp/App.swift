import UIKit
import WebKit

/// Derp's things that outlive a window: your dork, library, passwords,
/// pairing, the ad blocker, downloads, and where Derp is running.
final class DerpApp {
    static let shared = DerpApp()

    let setup: Setup
    let folder: URL
    let library: Library
    let logins: Logins
    let dork: Dork
    let pages = Pages()
    let blocker = Blocker()
    let downloads = Downloads()
    private(set) lazy var bridge = Bridge(app: self)
    private(set) lazy var contentController = pages.contentController(bridge: bridge)
    private(set) lazy var pairing = Pairing(app: self, directory: folder)
    private var privateStore: WKWebsiteDataStore?
    private let windows = NSHashTable<BrowserViewController>.weakObjects()

    private init() {
        setup = Setup.current
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Derp")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        folder = support
        library = Library(directory: support)
        logins = Logins(library: library)
        dork = Dork(directory: support)
    }

    func start() {
        blocker.load { [weak self] list in
            guard let self, let list else { return }
            if self.blocker.on { self.contentController.add(list) }
        }
        pairing.start()
        if ProcessInfo.processInfo.arguments.contains("-derpFresh") { forgetEverything() }
    }

    /// For the UI tests: start as a brand-new Derp.
    private func forgetEverything() {
        for key in Prefs.store.dictionaryRepresentation().keys { Prefs.store.removeObject(forKey: key) }
        library.db.run("DELETE FROM bookmarks")
        library.db.run("DELETE FROM history")
    }

    // ── Windows and tabs ───────────────────────────────────────────────────

    func register(_ window: BrowserViewController) { windows.add(window) }
    var windowCount: Int { windows.allObjects.count }
    var browsers: [Browser] { windows.allObjects.map(\.browser) }
    func allTabs() -> [Tab] { browsers.flatMap(\.tabs) }

    func find(_ webView: WKWebView) -> (Browser, Tab)? {
        for browser in browsers { if let tab = browser.tab(for: webView) { return (browser, tab) } }
        return nil
    }

    /// The window you're using (or any).
    var front: BrowserViewController? {
        windows.allObjects.first { $0.view.window?.windowScene?.activationState == .foregroundActive } ?? windows.allObjects.first
    }

    /// A web view's setup: Derp's pages, its scripts, the ad blocker, and
    /// private tabs' own data, forgotten when the last one closes.
    func configuration(private isPrivate: Bool) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.setURLSchemeHandler(pages, forURLScheme: Pages.scheme)
        if isPrivate {
            if privateStore == nil { privateStore = .nonPersistent() }
            config.websiteDataStore = privateStore!
        }
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = [.audio]
        config.applicationNameForUserAgent = "Version/\(UIDevice.current.systemVersion.split(separator: ".").first ?? "17").0 Mobile/15E148 Safari/604.1"
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.isFraudulentWebsiteWarningEnabled = true
        return config
    }

    func forgetPrivate() { privateStore = nil }

    var memorySaver: Bool {
        get { Prefs.bool("memorySaver", true) }
        set { Prefs.set("memorySaver", newValue) }
    }

    /// derp:// links, and web addresses from other apps (or from LiveContainer,
    /// which hands Derp links shared to it).
    func open(_ url: URL, in window: BrowserViewController? = nil) {
        guard let window = window ?? front else { return }
        let text = url.absoluteString
        if text.hasPrefix(Pairing.link) { return window.confirmPair(text) }
        if Address.isWeb(text) { return window.openTab(url, private: false, background: false) }
        guard url.scheme == "derp" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func item(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch url.host {
        case "open":
            if let target = item("url").flatMap(URL.init(string:)), Address.isWeb(target.absoluteString) || target.absoluteString.hasPrefix(Pairing.link) {
                open(target, in: window)
            }
        case "search":
            window.browser.newTab(Address.toURL(item("q") ?? "", dark: window.dark))
        case "new-tab":
            window.browser.newTab(nil)
        case "private-tab":
            window.browser.newTab(nil, private: true)
        default:
            break
        }
    }
}

// ── The ad blocker ──────────────────────────────────────────────────────────

/// Derp's ad blocker. On iOS, WebKit can't run uBlock Origin (Derp for
/// Android's), so Derp blocks with WebKit's own content blocker, from the same
/// kind of filter lists (EasyList and EasyPrivacy, see ios/blocklist.py),
/// compiled once on this device.
final class Blocker {
    private(set) var list: WKContentRuleList?
    private var file: URL? { Bundle.main.url(forResource: "blocklist", withExtension: "json") }

    var on: Bool {
        get { Prefs.bool("adBlocker", true) }
        set { Prefs.set("adBlocker", newValue) }
    }

    /// The rules' name changes with each Derp, so a new Derp compiles its new rules.
    private var identifier: String { "derp-blocklist-" + WhatsNew.version + "-" + String((try? file?.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }

    func load(_ done: @escaping (WKContentRuleList?) -> Void) {
        guard let store = WKContentRuleListStore.default() else { return done(nil) }
        let id = identifier
        store.lookUpContentRuleList(forIdentifier: id) { [weak self] found, _ in
            if let found {
                self?.list = found
                return done(found)
            }
            guard let file = self?.file, let rules = try? String(contentsOf: file) else { return done(nil) }
            store.getAvailableContentRuleListIdentifiers { ids in
                for old in ids ?? [] where old.hasPrefix("derp-blocklist-") && old != id { store.removeContentRuleList(forIdentifier: old) { _ in } }
            }
            let started = Date()
            store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: rules) { compiled, error in
                if let error { NSLog("Derp: ad blocker rules didn't compile: %@", "\(error)") }
                NSLog("Derp: ad blocker rules compiled in %.1fs", Date().timeIntervalSince(started))
                self?.list = compiled
                done(compiled)
            }
        }
    }

    func set(_ on: Bool, in controller: WKUserContentController) {
        self.on = on
        guard let list else { return }
        if on { controller.add(list) } else { controller.remove(list) }
    }
}

// ── Launching ───────────────────────────────────────────────────────────────

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        DerpApp.shared.start()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default", sessionRole: session.role)
    }

    /// Windows you closed: their tabs go too.
    func application(_ application: UIApplication, didDiscardSceneSessions sessions: Set<UISceneSession>) {
        for session in sessions { Browser.forget(windowID: session.persistentIdentifier) }
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var controller: BrowserViewController?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        // A link this window opens with: from another app, LiveContainer, a quick action or a new window.
        var url = options.urlContexts.first?.url
            ?? options.userActivities.first(where: { $0.activityType == NSUserActivityTypeBrowsingWeb })?.webpageURL
        if url == nil, let activity = options.userActivities.first(where: { $0.activityType == BrowserViewController.newWindow }) {
            url = (activity.userInfo?["url"] as? String).flatMap(URL.init(string:))
        }
        let controller = BrowserViewController(windowID: session.persistentIdentifier)
        let window = UIWindow(windowScene: scene)
        // The UI tests' dark mode.
        if ProcessInfo.processInfo.arguments.contains("-derpDark") { window.overrideUserInterfaceStyle = .dark }
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        self.controller = controller
        if let url, url.scheme == "derp" || url.absoluteString.hasPrefix(Pairing.link) {
            controller.start(opening: nil)
            DispatchQueue.main.async { DerpApp.shared.open(url, in: controller) }
        } else {
            controller.start(opening: url)
        }
        if let shortcut = options.shortcutItem { DispatchQueue.main.async { self.perform(shortcut) } }
    }

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        for context in contexts { DerpApp.shared.open(context.url, in: controller) }
    }

    /// LiveContainer hands a running Derp web links this way (as a universal link).
    func scene(_ scene: UIScene, continue activity: NSUserActivity) {
        if let url = activity.webpageURL { DerpApp.shared.open(url, in: controller) }
    }

    func windowScene(_ scene: UIWindowScene, performActionFor item: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        perform(item)
        completionHandler(true)
    }

    /// Home Screen quick actions (an installed Derp has them; LiveContainer's apps don't).
    private func perform(_ item: UIApplicationShortcutItem) {
        guard let controller else { return }
        switch item.type {
        case "newTab": controller.browser.newTab(nil)
        case "privateTab": controller.browser.newTab(nil, private: true)
        case "search":
            controller.browser.newTab(nil)
            controller.focusAddress()
        default: break
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) { controller?.resumed() }
    func sceneWillResignActive(_ scene: UIScene) { controller?.paused() }
}
