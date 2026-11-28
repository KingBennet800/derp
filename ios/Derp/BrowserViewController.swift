import UIKit
import WebKit

/// A Derp window. Wide windows (an iPad, or a big enough multitasking window)
/// look like desktop Derp: a tab strip with folder tabs, and the toolbar with
/// back, forward and reload under it. Narrow ones (an iPhone, Slide Over, a
/// small LiveContainer window) keep the toolbar at the bottom, with a tabs
/// button, like Derp for Android on a phone.
final class BrowserViewController: UIViewController, BrowserUI, UITextFieldDelegate {
    static let newWindow = "io.github.kingbennet800.derp.window"

    let app = DerpApp.shared
    let browser: Browser
    var palette = Palette.light

    // Views
    let strip = TabStrip()
    let toolbar = UIView()
    let buttons = UIStackView()
    let address = AddressField()
    let progress = ProgressLine()
    let page = UIView()
    lazy var back = iconButton("back", "Back") { [weak self] in self?.browser.current?.webView?.goBack() }
    lazy var forward = iconButton("forward", "Forward") { [weak self] in self?.browser.current?.webView?.goForward() }
    lazy var reload = iconButton("reload", "Reload") { [weak self] in self?.reloadOrStop() }
    lazy var tabsButton = TabsButton()
    lazy var avatar = AvatarButton()
    lazy var stripAvatar = AvatarButton()
    lazy var menuButton = iconButton("menu", "Menu") {}
    var tabsPanel: TabsPanel?
    private var layout: [NSLayoutConstraint] = []
    private var wide: Bool?
    private var awayAt: Date?
    private var sweep: Timer?
    private var started = false
    // Just for fun's state (Extras.swift).
    var duckBusy = false
    var snail: UIImageView?
    var loadingNow = false
    var slowPage: DispatchWorkItem?
    var sparkedAt: CFTimeInterval = 0

    var tablet: Bool { traitCollection.horizontalSizeClass == .regular }
    var dark: Bool { traitCollection.userInterfaceStyle == .dark }

    init(windowID: String) {
        browser = Browser(windowID: windowID)
        super.init(nibName: nil, bundle: nil)
        browser.ui = self
        app.register(self)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var preferredStatusBarStyle: UIStatusBarStyle { palette.dark ? .lightContent : .darkContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        page.clipsToBounds = true
        for view in [page, progress, toolbar, strip] {
            view.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(view)
        }
        address.delegate = self
        address.addTarget(self, action: #selector(typed), for: .editingChanged)
        address.accessibilityIdentifier = "address"
        buttons.axis = .horizontal
        buttons.alignment = .center
        buttons.spacing = 2
        buttons.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(buttons)
        for view in [back, forward, reload, address, tabsButton, avatar, menuButton] as [UIView] { buttons.addArrangedSubview(view) }
        NSLayoutConstraint.activate([
            buttons.leadingAnchor.constraint(equalTo: toolbar.safeAreaLayoutGuide.leadingAnchor, constant: 6),
            buttons.trailingAnchor.constraint(equalTo: toolbar.safeAreaLayoutGuide.trailingAnchor, constant: -4),
            buttons.topAnchor.constraint(equalTo: toolbar.topAnchor),
            buttons.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            address.heightAnchor.constraint(equalToConstant: 42),
        ])
        for button in [back, forward, reload, menuButton, tabsButton, avatar] as [UIView] {
            button.widthAnchor.constraint(equalToConstant: 42).isActive = true
            button.heightAnchor.constraint(equalToConstant: 42).isActive = true
        }
        menuButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in done(self?.menuItems() ?? []) }])
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.accessibilityIdentifier = "menu"
        tabsButton.addAction(UIAction { [weak self] _ in self?.toggleTabs() }, for: .touchUpInside)
        tabsButton.accessibilityIdentifier = "tabs"
        for button in [avatar, stripAvatar] {
            button.addAction(UIAction { [weak self] _ in
                self?.closeTabs()
                self?.browser.openPage("dork.html")
            }, for: .touchUpInside)
        }
        avatar.accessibilityIdentifier = "dork"
        strip.avatar = stripAvatar
        strip.onSelect = { [weak self] tab in self?.browser.select(tab) }
        strip.onClose = { [weak self] tab, from in
            self?.ghost(from: from)
            self?.browser.close(tab)
        }
        strip.onNew = { [weak self] in self?.browser.newTab(nil) }
        NotificationCenter.default.addObserver(self, selector: #selector(dorkChanged), name: Dork.changed, object: nil)
        relayout()
    }

    func start(opening url: URL?) {
        loadViewIfNeeded()
        browser.start(opening: url)
        render()
        // A fresh window (not one iOS rebuilt).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.maybeFlurry(1) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.showWhatsNew(WhatsNew.since(made: self.app.dork.made))
        }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.horizontalSizeClass != traitCollection.horizontalSizeClass { relayout() }
        if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle { render() }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        browser.sleepIdleTabs(all: true)
    }

    // ── Coming and going ───────────────────────────────────────────────────

    /// Every time Derp comes to the screen: look for a newer Derp (at most once
    /// an hour), sync your devices, and maybe your dork pet has news.
    func resumed() {
        Updater.check(self, manual: false)
        app.pairing.resumed()
        sweep?.invalidate()
        sweep = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in self?.browser.sleepIdleTabs() }
        let away = awayAt.map { Date().timeIntervalSince($0) } ?? 0
        awayAt = nil
        DispatchQueue.main.async { [weak self] in self?.petResume(away) }
        remindSignature()
    }

    func paused() {
        awayAt = Date()
        sweep?.invalidate()
        app.pairing.paused()
        browser.save()
    }

    // ── Layout ─────────────────────────────────────────────────────────────

    private func relayout() {
        guard wide != tablet else { return }
        wide = tablet
        NSLayoutConstraint.deactivate(layout)
        let safe = view.safeAreaLayoutGuide
        var c: [NSLayoutConstraint] = [
            page.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progress.heightAnchor.constraint(equalToConstant: 2),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            strip.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
        ]
        if tablet {
            c += [
                strip.topAnchor.constraint(equalTo: safe.topAnchor),
                strip.heightAnchor.constraint(equalToConstant: 44),
                toolbar.topAnchor.constraint(equalTo: strip.bottomAnchor),
                toolbar.heightAnchor.constraint(equalToConstant: 50),
                progress.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
                page.topAnchor.constraint(equalTo: progress.bottomAnchor),
                page.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ]
        } else {
            c += [
                strip.topAnchor.constraint(equalTo: safe.topAnchor),
                strip.heightAnchor.constraint(equalToConstant: 0),
                page.topAnchor.constraint(equalTo: safe.topAnchor),
                progress.topAnchor.constraint(equalTo: page.bottomAnchor),
                toolbar.topAnchor.constraint(equalTo: progress.bottomAnchor),
                toolbar.heightAnchor.constraint(equalToConstant: 54),
                toolbar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            ]
        }
        layout = c
        NSLayoutConstraint.activate(c)
        strip.isHidden = !tablet
        progress.lineAtTop = !tablet
        forward.isHidden = !tablet
        reload.isHidden = !tablet
        tabsButton.isHidden = tablet
        avatar.isHidden = tablet
        closeTabs()
        render()
    }

    /// A round icon button in desktop Derp's style.
    func iconButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(Icon.named(icon), for: .normal)
        button.accessibilityLabel = label
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    // ── Showing tabs ───────────────────────────────────────────────────────

    func show(_ tab: Tab) {
        if let webView = tab.webView, webView.superview !== page {
            page.subviews.forEach { $0.removeFromSuperview() }
            webView.translatesAutoresizingMaskIntoConstraints = false
            page.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.leadingAnchor.constraint(equalTo: page.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: page.trailingAnchor),
                webView.topAnchor.constraint(equalTo: page.topAnchor),
                webView.bottomAnchor.constraint(equalTo: page.bottomAnchor),
            ])
        }
        render()
    }

    func tabsChanged() { render() }

    func tabChanged(_ tab: Tab) {
        if tab === browser.current { render() } else { strip.fill(self) }
        tabsPanel?.fill(self)
    }

    func loadingChanged(_ loading: Bool) {
        snailCheck(loading)
        if !loading { maybeHiccup() }
    }

    func pageEnded() {}

    /// Everything in the toolbar, from the current tab.
    func render() {
        guard isViewLoaded else { return }
        let tab = browser.current
        palette = Palette.of(dark: dark, private: tab?.isPrivate ?? false)
        setNeedsStatusBarAppearanceUpdate()
        view.backgroundColor = tablet ? palette.frame : palette.toolbar
        page.backgroundColor = palette.content
        tab?.webView?.backgroundColor = palette.content
        toolbar.backgroundColor = palette.toolbar
        progress.colors(line: palette.contentLine, background: palette.toolbar)
        progress.rainbow = Gag.rainbow.on
        progress.busy = tab?.loading ?? false
        view.tintColor = palette.accent
        for button in [back, forward, reload, menuButton] { button.tintColor = palette.icon }
        back.isEnabled = tab?.canGoBack ?? false
        forward.isEnabled = tab?.canGoForward ?? false
        let loading = tab?.loading ?? false
        reload.setImage(Icon.named(loading ? "stop" : "reload"), for: .normal)
        reload.accessibilityLabel = loading ? "Stop" : "Reload"
        address.paint(palette, private: tab?.isPrivate ?? false)
        if !address.isFirstResponder { address.text = tab.map { browser.display($0) } ?? "" }
        tabsButton.paint(count: browser.tabs.count, palette: palette)
        paintAvatar()
        strip.fill(self)
        tabsPanel?.fill(self)
    }

    @objc private func dorkChanged() { paintAvatar() }

    private func paintAvatar() {
        let picture = app.dork.picture ?? Icon.art("logo")
        avatar.paint(picture, palette: palette)
        stripAvatar.paint(picture, palette: palette)
    }

    /// A tab's title; tabs Memory Saver has put to sleep snore, with Sleepy tabs on.
    func tabTitle(_ tab: Tab) -> String {
        var title = tab.title
        if title.isEmpty { title = browser.display(tab) }
        if title.isEmpty { title = browser.isReader(tab) ? "Reader view" : "New tab" }
        return tab.asleep && Gag.sleepy.on ? "💤 " + title : title
    }

    /// A tab's icon: Derp's logo on Derp's pages, the mask for private tabs, a globe for websites.
    func icon(_ tab: Tab) -> (UIImage?, UIColor?) {
        if tab.isPrivate { return (Icon.named("mask"), palette.dark ? Palette.privateTabs.accent : UIColor(hex: "#7C5CF5")) }
        if browser.display(tab).isEmpty { return (Icon.art("logo"), nil) }
        return (Icon.named("globe"), palette.dim)
    }

    // ── Address bar ────────────────────────────────────────────────────────

    func textFieldDidBeginEditing(_ field: UITextField) {
        if let tab = browser.current { field.text = browser.address(tab) }
        DispatchQueue.main.async { field.selectAll(nil) }
        address.paint(palette, private: browser.current?.isPrivate ?? false)
    }

    func textFieldDidEndEditing(_ field: UITextField) {
        if !duckBusy { field.text = browser.current.map { browser.display($0) } ?? "" }
        address.paint(palette, private: browser.current?.isPrivate ?? false)
    }

    func textFieldShouldReturn(_ field: UITextField) -> Bool {
        go(field.text ?? "")
        return false
    }

    private var lastLength = 0

    @objc private func typed() {
        let length = address.text?.count ?? 0
        // A character or two typed (not the whole address set at once).
        if (1...2).contains(length - lastLength) { sparks() }
        lastLength = length
    }

    private func go(_ text: String) {
        guard let tab = browser.current, !text.trimmingCharacters(in: .whitespaces).isEmpty, !duckBusy else { return }
        if Gag.duck.on && Int.random(in: 0..<10) == 0 { return duck(text) }
        address.resignFirstResponder()
        browser.load(tab, Address.toURL(text, dark: dark))
    }

    func focusAddress() {
        closeTabs()
        address.becomeFirstResponder()
    }

    private func reloadOrStop() {
        guard let webView = browser.current?.webView else { return }
        if webView.isLoading { webView.stopLoading() } else { webView.reload() }
    }

    // ── Tabs view (narrow windows) ─────────────────────────────────────────

    private func toggleTabs() {
        if tabsPanel == nil { openTabs() } else { closeTabs() }
    }

    func openTabs() {
        address.resignFirstResponder()
        let panel = TabsPanel()
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.topAnchor.constraint(equalTo: view.topAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        tabsPanel = panel
        panel.fill(self)
        panel.alpha = 0
        panel.transform = CGAffineTransform(translationX: 0, y: 24)
        UIView.animate(withDuration: 0.18) {
            panel.alpha = 1
            panel.transform = .identity
        }
    }

    func closeTabs() {
        guard let panel = tabsPanel else { return }
        tabsPanel = nil
        UIView.animate(withDuration: 0.14, animations: {
            panel.alpha = 0
            panel.transform = CGAffineTransform(translationX: 0, y: 24)
        }, completion: { _ in panel.removeFromSuperview() })
    }

    // ── Menu ───────────────────────────────────────────────────────────────

    private func action(_ title: String, _ image: String? = nil, subtitle: String? = nil, on: Bool? = nil, enabled: Bool = true, handler: @escaping () -> Void) -> UIAction {
        let action = UIAction(title: title, image: image.flatMap { Icon.named($0) ?? UIImage(systemName: $0) }) { _ in handler() }
        action.subtitle = subtitle
        if let on { action.state = on ? .on : .off }
        if !enabled { action.attributes = .disabled }
        return action
    }

    private func menuItems() -> [UIMenuElement] {
        guard let tab = browser.current else { return [] }
        let web = browser.isWebPage(tab)
        let marked = web && app.library.isBookmarked(tab.url)
        var quick: [UIMenuElement] = []
        if !tablet {
            quick.append(action("Forward", "forward", enabled: tab.canGoForward) { tab.webView?.goForward() })
            quick.append(action(tab.loading ? "Stop" : "Reload", tab.loading ? "stop" : "reload") { [weak self] in self?.reloadOrStop() })
        }
        quick.append(action(marked ? "Remove bookmark" : "Bookmark this page", marked ? "star-filled" : "star", enabled: web) { [weak self] in
            guard let self else { return }
            let now = self.browser.toggleBookmark(tab)
            self.toast(now ? "Bookmarked" : "Bookmark removed")
            if now { self.confetti() }
        })
        quick.append(action("Share", "share", enabled: web) { [weak self] in
            guard let url = URL(string: tab.url) else { return }
            self?.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), from: self?.menuButton)
        })
        quick.append(action("New tab", "plus") { [weak self] in self?.browser.newTab(nil) })

        var pageItems: [UIMenuElement] = [action("New private tab", "mask") { [weak self] in self?.browser.newTab(nil, private: true) }]
        if canOpenWindows {
            pageItems.append(action("New window", "macwindow.badge.plus") { [weak self] in self?.newWindow(nil) })
        }
        pageItems += [
            action("Find in page", "search", enabled: web || browser.isReader(tab)) { tab.webView?.findInteraction?.presentFindNavigator(showingReplace: false) },
            action("Reader view", "text.justify.left", enabled: browser.canRead(tab)) { [weak self] in self?.browser.openReader(tab) },
            action("Add to Home Screen", "plus.app", enabled: web) { [weak self] in self?.addToHome(tab) },
            action("Screenshot with stickers", "camera", enabled: web) { [weak self] in self?.screenshotStickers(tab) },
            action("Desktop site", "desktopcomputer", on: tab.desktop) { [weak self] in self?.browser.toggleDesktop(tab) },
            action("Your dork", "face.smiling") { [weak self] in self?.browser.openPage("dork.html") },
        ]
        let library: [UIMenuElement] = [
            action("Bookmarks", "book") { [weak self] in self?.browser.openPage("bookmarks.html") },
            action("History", "clock") { [weak self] in self?.browser.openPage("history.html") },
            action("Passwords", "key") { [weak self] in self?.browser.openPage("passwords.html") },
            action("Import data", "square.and.arrow.down") { [weak self] in self?.browser.openPage("import.html") },
            action("Your devices", "laptopcomputer.and.iphone", subtitle: app.pairing.paired ? "Paired" : nil) { [weak self] in self?.browser.openPage("devices.html") },
        ]
        let engines = UIMenu(title: "Search engine", subtitle: Engine.label, image: Icon.named("search"), children:
            DoodleResults.allCases.map { results in
                action("Doodle, with \(results.label)’s results", on: Engine.current == .doodle && DoodleResults.current == results) {
                    Engine.current = .doodle
                    DoodleResults.current = results
                }
            } + Engine.allCases.filter { $0 != .doodle }.map { engine in
                action(engine.label, on: Engine.current == engine) { Engine.current = engine }
            })
        let looks = UIMenu(title: "Look", subtitle: Look.current.label, image: UIImage(systemName: "paintpalette"), children: Look.allCases.map { look in
            action(look.label, on: Look.current == look) { [weak self] in
                Look.current = look
                self?.app.windowsRender()
            }
        })
        let funCount = Gag.allCases.filter(\.on).count
        let settings: [UIMenuElement] = [
            engines,
            looks,
            action("Ad blocker", "shield", on: app.blocker.on) { [weak self] in self?.toggleBlocker() },
            action("Memory Saver", "leaf", on: app.memorySaver) { [weak self] in self?.toggleMemorySaver() },
            action("Just for fun", "sparkles", subtitle: funCount == 0 ? "Off" : "\(funCount) on") { [weak self] in self?.justForFun() },
            action("Clear browsing data", "trash") { [weak self] in self?.confirmClear() },
        ]
        let about: [UIMenuElement] = [
            action(app.setup.inLiveContainer ? "Open links in Derp (LiveContainer)" : "Open links in Derp", "link") { [weak self] in self?.linksHelp() },
            action("Check for updates", "arrow.down.circle") { [weak self] in
                guard let self else { return }
                Updater.check(self, manual: true)
            },
            action("About Derp", "info.circle") { [weak self] in self?.about() },
        ]
        let row = UIMenu(options: .displayInline, children: quick)
        row.preferredElementSize = .small
        return [
            row,
            UIMenu(options: .displayInline, children: pageItems),
            UIMenu(options: .displayInline, children: library),
            UIMenu(options: .displayInline, children: settings),
            UIMenu(options: .displayInline, children: about),
        ]
    }

    /// More than one window: an installed Derp on an iPad (LiveContainer's
    /// apps share its one window, or one of its multitasking windows).
    var canOpenWindows: Bool {
        UIApplication.shared.supportsMultipleScenes && app.setup.ownsLinks && UIDevice.current.userInterfaceIdiom == .pad
    }

    func newWindow(_ url: URL?) {
        let activity = NSUserActivity(activityType: BrowserViewController.newWindow)
        if let url { activity.userInfo = ["url": url.absoluteString] }
        UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: nil) { [weak self] error in
            self?.toast("Couldn’t open a window (\(error.localizedDescription))")
        }
    }

    private func toggleBlocker() {
        let on = !app.blocker.on
        if on && app.blocker.list == nil {
            toast("The ad blocker is getting ready. Try again in a moment.")
            return
        }
        app.blocker.set(on, in: app.contentController)
        for tab in app.allTabs() { tab.webView?.reload() }
        toast(on ? "Ad blocker on" : "Ad blocker off")
    }

    private func toggleMemorySaver() {
        app.memorySaver.toggle()
        toast(app.memorySaver ? "Memory Saver on: tabs you haven’t looked at for half an hour fall asleep" : "Memory Saver off")
    }

    // ── BrowserUI ──────────────────────────────────────────────────────────

    func present(_ controller: UIViewController, from source: UIView?) {
        if let popover = controller.popoverPresentationController {
            let anchor = source ?? menuButton
            popover.sourceView = anchor
            popover.sourceRect = anchor.bounds
        }
        var top: UIViewController = self
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        top.present(controller, animated: true)
    }

    func openTab(_ url: URL, private isPrivate: Bool, background: Bool) {
        closeTabs()
        browser.newTab(url.absoluteString, private: isPrivate, select: !background)
    }

    func blankTab() {
        if Gag.peekaboo.on && Gag.motion && Int.random(in: 0..<6) == 0 { DispatchQueue.main.async { self.peek() } }
        DispatchQueue.main.async { self.maybeFlurry(5) }
    }

    func downloadStarted() {
        carryDownload()
        toast("Downloading…")
    }
}

extension DerpApp {
    /// A new Look shows in every window.
    func windowsRender() {
        for browser in browsers { (browser.ui as? BrowserViewController)?.render() }
    }
}
