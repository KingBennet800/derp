import AVFoundation
import LocalAuthentication
import Photos
import QuickLook
import SafariServices
import UIKit
import UniformTypeIdentifiers
import WebKit

// ── Messages and dialogs ────────────────────────────────────────────────────

extension BrowserViewController {
    private var toastRoom: CGFloat { tablet ? view.safeAreaInsets.bottom : view.bounds.height - toolbar.frame.minY - 2 }

    func toast(_ text: String) {
        Toast.show(text, in: view, above: toastRoom, palette: palette)
    }

    func alert(_ title: String, _ message: String?, actions: [UIAlertAction] = [UIAlertAction(title: "OK", style: .default)]) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        actions.forEach(alert.addAction)
        present(alert, from: nil)
    }

    /// A pairing code's link: pair with the computer that showed it, once you say so.
    func confirmPair(_ link: String) {
        guard Pairing.parse(link) != nil else {
            return toast("That pairing code didn’t work. Make a new one on your computer.")
        }
        let here = UIDevice.current.userInterfaceIdiom == .pad ? "this iPad" : "this iPhone"
        let already = app.pairing.paired ? "\n\nDerp on \(here) is paired already; it’ll leave that pair for this one." : ""
        alert("Pair with your computer?", "Your bookmarks, passwords and open tabs will be shared between Derp here and on your computer, end-to-end encrypted. Derp’s relay passes them along without being able to read them.\(already)", actions: [
            UIAlertAction(title: "Cancel", style: .cancel),
            UIAlertAction(title: "Pair", style: .default) { [weak self] _ in
                self?.app.pairing.join(link) { message in
                    self?.toast(message)
                    self?.browser.openPage("devices.html")
                }
            },
        ])
    }

    /// How links from other apps get to Derp, where it's running.
    func linksHelp() {
        let setup = app.setup
        var actions = [UIAlertAction(title: "OK", style: .cancel)]
        if setup.inLiveContainer, let link = setup.launchLink() {
            actions.append(UIAlertAction(title: "Add Derp to Home Screen", style: .default) { [weak self] _ in
                self?.installClip(label: setup.profile.map { "Derp · \($0)" } ?? "Derp", link: link, icon: UIImage(named: "AppIcon") ?? Icon.art("logo") ?? UIImage(),
                                  note: "Opens Derp in LiveContainer" + (setup.profile.map { ", in the “\($0)” container" } ?? "") + ".")
            })
            actions.append(UIAlertAction(title: "Copy Derp’s launch link", style: .default) { _ in UIPasteboard.general.url = link })
        } else {
            actions.append(UIAlertAction(title: "Copy an example link", style: .default) { _ in
                UIPasteboard.general.string = "derp://open?url=https://example.com"
            })
        }
        alert("Open links in Derp", setup.linksHelp, actions: actions)
    }

    func about() {
        let engine = "WebKit, iOS’s engine (Apple lets apps on iPhone and iPad use only it)."
        let message = """
        A fast, fluid browser with a goofy streak.

        Engine: \(engine)
        Ad blocker: \(app.blocker.on ? "on" : "off"), with EasyList and EasyPrivacy. Tracking parameters are stripped from links. No telemetry.

        \(app.setup.summary)\(app.setup.inLiveContainer ? " Apps running in LiveContainer can see each other’s files, so keep apps you don’t trust out of it." : "")

        Derp is open source and isn’t affiliated with Mozilla or Apple.
        """
        alert("Derp \(WhatsNew.version)", message, actions: [
            UIAlertAction(title: "Close", style: .cancel),
            UIAlertAction(title: "What’s new", style: .default) { [weak self] _ in self?.showWhatsNew(WhatsNew.current()) },
            UIAlertAction(title: "Website", style: .default) { [weak self] _ in self?.browser.newTab("https://kingbennet800.github.io/derp/") },
        ])
    }

    func offerUpdate(_ version: String) {
        let setup = app.setup
        var actions = [UIAlertAction(title: "Later", style: .cancel) { _ in
            Prefs.set("updateLater", version)
            Prefs.set("updateLaterAt", Date().timeIntervalSince1970)
        }]
        if let store = setup.store, setup.kind == .installed {
            actions.append(UIAlertAction(title: "Open \(store)", style: .default) { _ in
                UIApplication.shared.open(URL(string: store == "SideStore" ? "sidestore://" : "altstore://")!)
            })
        }
        actions.append(UIAlertAction(title: "Copy source link", style: .default) { _ in UIPasteboard.general.string = Updater.source })
        actions.append(UIAlertAction(title: "Download Derp.ipa", style: .default) { [weak self] _ in self?.browser.newTab(Updater.ipa) })
        alert("Derp \(version) is out", setup.updateHelp + " Your tabs, bookmarks, passwords and your dork stay.", actions: actions)
    }

    /// Sideloaded apps stop opening when their signature runs out: a nudge a
    /// couple of days before (SideStore and LiveContainer refresh it).
    func remindSignature() {
        guard let until = app.setup.signedUntil else { return }
        let left = until.timeIntervalSinceNow
        let day = Pet.dayString(Date())
        guard left > 0, left < 2 * 86_400, Prefs.store.string(forKey: "signatureNudged") != day else { return }
        Prefs.set("signatureNudged", day)
        let who = app.setup.inLiveContainer ? "LiveContainer" : "Derp"
        let how = app.setup.inLiveContainer ? "Refresh LiveContainer in SideStore (or LiveContainer’s built-in SideStore)." : "Refresh it in \(app.setup.store ?? "SideStore")."
        toast("\(who)’s signature runs out \(Setup.day(until)). \(how)")
    }

    func confirmClear() {
        alert("Clear browsing data?", "This deletes your history, cookies, site data and the cache, so you’ll be signed out of websites. Your tabs, bookmarks, passwords and your dork stay.", actions: [
            UIAlertAction(title: "Cancel", style: .cancel),
            UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
                WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
                self?.app.library.clearHistory()
                self?.toast("Browsing data cleared")
            },
        ])
    }

    func justForFun() {
        let sheet = JustForFunController { [weak self] in self?.render() }
        sheet.modalPresentationStyle = .formSheet
        if let sheetController = sheet.sheetPresentationController { sheetController.detents = [.medium(), .large()] }
        present(sheet, from: nil)
    }

    /// What's new: the new things in [releases] (newest first), each with where to find it, under your dork.
    func showWhatsNew(_ releases: [WhatsNew.Release]) {
        guard !releases.isEmpty, presentedViewController == nil else { return }
        let sheet = WhatsNewController(releases: releases, dork: app.dork.picture, palette: palette)
        sheet.modalPresentationStyle = .formSheet
        present(sheet, from: nil)
    }

    // ── Dork pet ───────────────────────────────────────────────────────────

    /// Back on the screen: today's a day together (maybe with an outfit to
    /// show), and after a while away your dork has napped: it wakes up.
    func petResume(_ away: TimeInterval) {
        guard Gag.pet.on else { return }
        if away >= 5 * 60 && Gag.motion { wakeUp() }
        if let unlock = Pet.count() { announce(unlock) }
    }

    private func wakeUp() {
        guard let sleepy = app.dork.sleepy else { return }
        for button in [avatar, stripAvatar] { button.face.image = sleepy }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            let picture = self.app.dork.picture
            for button in [self.avatar, self.stripAvatar] {
                button.face.image = picture
                UIView.animate(withDuration: 0.16, animations: { button.face.transform = CGAffineTransform(translationX: 0, y: -6) }) { _ in
                    UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.35, initialSpringVelocity: 1, options: []) { button.face.transform = .identity }
                }
            }
        }
    }

    /// "Bloop unlocked a crown!", with Try it on (the dork editor, wearing it).
    private func announce(_ unlock: Pet.Unlock) {
        alert("\(app.dork.name) unlocked \(unlock.what)!", "\(unlock.days) days together", actions: [
            UIAlertAction(title: "Later", style: .cancel),
            UIAlertAction(title: "Try it on", style: .default) { [weak self] _ in self?.browser.openPage("dork.html?wear=\(unlock.part).\(unlock.value)") },
        ])
    }

    // ── Pages asking for things ────────────────────────────────────────────

    func downloaded(_ url: URL) {
        toast("Saved \(url.lastPathComponent) to Downloads. \(app.setup.downloadsHelp)")
        let preview = QLPreviewController()
        let source = Preview(url)
        preview.dataSource = source
        objc_setAssociatedObject(preview, &previewKey, source, .OBJC_ASSOCIATION_RETAIN)
        if QLPreviewController.canPreview(url as NSURL) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.present(preview, from: nil) }
        }
    }

    /// Add to Home Screen: a Web Clip that opens the page in Derp (see HomeScreen).
    func addToHome(_ tab: Tab) {
        guard let url = URL(string: tab.url), let link = app.setup.launchLink(opening: url) else { return }
        let name = tab.title.isEmpty ? browser.display(tab) : tab.title
        let iconURL = tab.icon.flatMap(URL.init(string:)).flatMap { tab.pageURL == tab.url ? $0 : nil }
        let finish: (UIImage?) -> Void = { [weak self] picture in
            let icon = HomeScreen.icon(picture: picture, name: name, address: tab.url)
            self?.installClip(label: name, link: link, icon: icon, note: "Opens \(Address.host(tab.url) ?? "the page") in Derp" + (self?.app.setup.inLiveContainer == true ? ", in LiveContainer." : "."))
        }
        guard let iconURL else { return finish(nil) }
        URLSession.shared.dataTask(with: URLRequest(url: iconURL, timeoutInterval: 5)) { data, _, _ in
            let picture = data.flatMap { $0.count < 512 * 1024 ? UIImage(data: $0) : nil }
            DispatchQueue.main.async { finish(picture) }
        }.resume()
    }

    func installClip(label: String, link: URL, icon: UIImage, note: String) {
        guard let profile = HomeScreen.profile(label: label, link: link, icon: icon, note: note),
              let url = URL(string: "data:application/x-apple-aspen-config;base64," + profile.base64EncodedString()) else { return }
        alert("Add to Home Screen", "Derp makes a small profile that puts “\(label)” on your Home Screen. Tap Allow, then open Settings › Profile Downloaded and tap Install.", actions: [
            UIAlertAction(title: "Cancel", style: .cancel),
            UIAlertAction(title: "Continue", style: .default) { [weak self] _ in self?.present(SFSafariViewController(url: url), from: nil) },
        ])
    }

    /// A picture of the page, into the sticker editor (desktop Derp's) in a new tab.
    func screenshotStickers(_ tab: Tab) {
        guard let webView = tab.webView else { return }
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let self, let image else { return self?.toast("The screenshot didn’t work") ?? () }
            // At most 2000px along its long side, to keep it quick to pass along.
            let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
            let scale = min(1, 2000 / max(pixels.width, pixels.height))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let size = CGSize(width: pixels.width * scale, height: pixels.height * scale)
            let png = UIGraphicsImageRenderer(size: size, format: format).pngData { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            self.browser.openStickers("data:image/png;base64," + png.base64EncodedString(), from: tab)
        }
    }

    /// Saves the sticker editor's picture to Photos.
    func saveStickers(_ png: Data?, done: @escaping (Bool) -> Void) {
        guard let png else { return done(false) }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                return DispatchQueue.main.async {
                    self.toast("Let Derp add photos in Settings to save pictures")
                    done(false)
                }
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: nil)
            }) { saved, _ in
                DispatchQueue.main.async {
                    self.toast(saved ? "Saved to Photos" : "The picture didn’t save")
                    done(saved)
                }
            }
        }
    }

    /// Scan the pairing code Derp on your computer shows.
    func scanPairingCode(done: @escaping () -> Void) {
        let scanner = ScannerController { [weak self] code in
            done()
            guard let code else { return }
            if code.hasPrefix(Pairing.link) { self?.confirmPair(code) } else { self?.toast("That isn’t a pairing code from Derp") }
        }
        scanner.modalPresentationStyle = .formSheet
        present(scanner, from: nil)
    }

    /// Import data: pick a bookmarks (.html) or passwords (.csv) file another
    /// browser exported, and add what's in it.
    func importFile(kind: String, done: @escaping ([String: Any]) -> Void) {
        let passwords = kind == "passwords"
        let types: [UTType] = passwords ? [.commaSeparatedText, .plainText, .data] : [.html, .plainText, .data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        let delegate = PickerDelegate { [weak self] url in
            guard let self, let url else { return done(["ok": true, "cancelled": true]) }
            guard let data = try? Data(contentsOf: url), data.count < 50 * 1024 * 1024 else {
                // In LiveContainer, the file picker can need its fix.
                let hint = self.app.setup.inLiveContainer ? " If it keeps happening, turn on Fix File Picker in Derp’s settings in LiveContainer." : ""
                return done(["ok": false, "error": "Derp couldn’t read that file." + hint])
            }
            let text = String(decoding: data, as: UTF8.self)
            if passwords {
                let logins = Imports.logins(text)
                let (added, updated) = self.app.logins.importLogins(logins)
                done(["ok": true, "found": logins.count, "added": added, "updated": updated])
            } else {
                let marks = Imports.bookmarks(text)
                done(["ok": true, "found": marks.count, "added": self.app.library.importBookmarks(marks)])
            }
        }
        picker.delegate = delegate
        objc_setAssociatedObject(picker, &pickerKey, delegate, .OBJC_ASSOCIATION_RETAIN)
        present(picker, from: nil)
    }

    /// Face ID (or your passcode) before showing or copying a saved password,
    /// good for two minutes. Without a passcode there's nothing to ask.
    func unlock(done: @escaping (Bool) -> Void) {
        if Date().timeIntervalSince1970 < unlockedUntil { return done(true) }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return done(true) }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "To see your saved passwords") { ok, _ in
            DispatchQueue.main.async {
                if ok { unlockedUntil = Date().timeIntervalSince1970 + 120 }
                done(ok)
            }
        }
    }
}

private var previewKey = 0
private var pickerKey = 0
private var unlockedUntil: TimeInterval = 0

private final class PickerDelegate: NSObject, UIDocumentPickerDelegate {
    let done: (URL?) -> Void
    init(_ done: @escaping (URL?) -> Void) { self.done = done }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { done(urls.first) }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { done(nil) }
}

// ── Just for fun ────────────────────────────────────────────────────────────

extension BrowserViewController {
    /// Duck mode: 1 in 10 times you press Go, a duck waddles along the address
    /// bar and eats what you typed instead. Desktop Derp has the same duck.
    func duck(_ text: String) {
        duckBusy = true
        let size: CGFloat = 26
        let duck = UIImageView(image: Icon.art("duck"))
        let quack = PaddedLabel()
        quack.text = "Quack!"
        quack.font = .medium(13)
        quack.textColor = UIColor(hex: "#3A2A00")
        quack.backgroundColor = UIColor(hex: "#FFD43B")
        quack.layer.cornerRadius = 8
        quack.clipsToBounds = true
        quack.alpha = 0
        let field = address.convert(address.bounds, to: view)
        let textStart = field.minX + 38
        let font = address.font ?? .systemFont(ofSize: 16)
        func at(_ kept: Int) -> CGFloat {
            min(field.maxX - size - 10, textStart + (String(text.prefix(kept)) as NSString).size(withAttributes: [.font: font]).width)
        }
        duck.frame = CGRect(x: at(text.count), y: field.midY - size / 2 - 2, width: size, height: size)
        view.addSubview(duck)
        view.addSubview(quack)
        let placeholder = address.placeholder
        address.placeholder = nil
        let walk = min(2.4, 0.9 + Double(text.count) * 0.045)
        let start = CACurrentMediaTime()
        let link = DisplayLink { [weak self] link in
            guard let self else { return link.stop() }
            let t = min(1, (CACurrentMediaTime() - start) / walk)
            let kept = Int((Double(text.count) * (1 - t)).rounded())
            self.address.text = String(text.prefix(kept))
            duck.frame.origin.x = at(kept)
            duck.transform = CGAffineTransform(rotationAngle: CGFloat(9 * sin(t * walk / 0.22 * .pi) * .pi / 180))
            guard t >= 1 else { return }
            link.stop()
            self.address.text = ""
            duck.transform = .identity
            quack.sizeToFit()
            quack.frame = CGRect(x: duck.frame.maxX + 4, y: duck.frame.midY - (quack.bounds.height + 4) / 2, width: quack.bounds.width + 16, height: quack.bounds.height + 4)
            UIView.animate(withDuration: 0.16) { quack.alpha = 1 }
            UIView.animate(withDuration: 0.15, animations: { duck.frame.origin.y -= 5 }) { _ in UIView.animate(withDuration: 0.15) { duck.frame.origin.y += 5 } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                duck.removeFromSuperview()
                quack.removeFromSuperview()
                self.address.placeholder = placeholder
                self.duckBusy = false
            }
        }
        link.start()
    }

    /// Snail mode: a page loading for 3 seconds gets a snail on the loading bar.
    func snailCheck(_ loading: Bool) {
        guard loading != loadingNow else { return }
        loadingNow = loading
        slowPage?.cancel()
        if loading {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.loadingNow, self.snail == nil, Gag.snail.on else { return }
                self.snailCrawl()
            }
            slowPage = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        } else {
            snailAway()
        }
    }

    private func snailCrawl() {
        let size: CGFloat = 24
        let snail = UIImageView(image: Icon.art("snail"))
        let line = progress.convert(progress.bounds, to: view)
        // Its body (the bottom fifth of the drawing is empty) rests on the line.
        let y = (tablet ? line.maxY : line.minY) - size * 26 / 32
        snail.frame = CGRect(x: view.safeAreaInsets.left + 6, y: y, width: size, height: size)
        view.addSubview(snail)
        self.snail = snail
        UIView.animate(withDuration: 45, delay: 0, options: [.curveLinear]) {
            snail.frame.origin.x = self.view.bounds.width - self.view.safeAreaInsets.right - size - 6
        }
    }

    /// The page is there: off the snail zooms.
    private func snailAway() {
        guard let snail else { return }
        self.snail = nil
        let now = snail.layer.presentation()?.frame ?? snail.frame
        snail.layer.removeAllAnimations()
        snail.frame = now
        UIView.animate(withDuration: 0.45, delay: 0, options: [.curveEaseIn], animations: {
            snail.frame.origin.x = self.view.bounds.width + 30
            snail.alpha = 0
        }) { _ in snail.removeFromSuperview() }
    }

    /// Hiccups: now and then (1 in 12) a page that's done loading gets the hiccups.
    func maybeHiccup() {
        guard let tab = browser.current, Gag.hiccups.on, Gag.motion, browser.isWebPage(tab), Int.random(in: 0..<12) == 0 else { return }
        let hop: CGFloat = 14
        let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
        bounce.values = [0, -hop, 0, -hop * 0.45, 0]
        bounce.duration = 0.65
        page.layer.add(bounce, forKey: "hiccup")
        let hic = PaddedLabel()
        hic.text = "hic!"
        hic.font = .medium(15)
        hic.textColor = UIColor(hex: "#3A2A00")
        hic.backgroundColor = UIColor(hex: "#FFD43B")
        hic.layer.cornerRadius = 12
        hic.clipsToBounds = true
        hic.sizeToFit()
        let origin = page.convert(CGPoint(x: 16, y: 14), to: view)
        hic.frame = CGRect(x: origin.x, y: origin.y, width: hic.bounds.width + 20, height: hic.bounds.height + 6)
        hic.alpha = 0
        view.addSubview(hic)
        UIView.animate(withDuration: 0.15, animations: { hic.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.45, delay: 0.7, options: [], animations: {
                hic.frame.origin.y -= 18
                hic.alpha = 0
            }) { _ in hic.removeFromSuperview() }
        }
    }

    /// Seasons: 1 in [chance] times, the season drifts down over the page.
    func maybeFlurry(_ chance: Int) {
        guard Gag.seasons.on, Gag.motion, Int.random(in: 0..<chance) == 0 else { return }
        let art = Seasons.art()
        guard !art.isEmpty else { return }
        let flurry = Flurry(art: art, depth: 260)
        flurry.frame = page.convert(page.bounds, to: view)
        view.addSubview(flurry)
    }

    /// Peekaboo: your dork peeks up over the bottom of the page.
    func peek() {
        guard let face = app.dork.picture else { return }
        let size: CGFloat = 96, height: CGFloat = 150
        let pageFrame = page.convert(page.bounds, to: view)
        let stage = UIView(frame: CGRect(x: pageFrame.minX + 12, y: pageFrame.maxY - height, width: 150, height: height))
        stage.clipsToBounds = true
        stage.isUserInteractionEnabled = false
        let bubble = PaddedLabel()
        bubble.text = "Peekaboo!"
        bubble.font = .medium(14)
        bubble.textColor = palette.onAccent
        bubble.backgroundColor = palette.accent
        bubble.layer.cornerRadius = 10
        bubble.clipsToBounds = true
        bubble.sizeToFit()
        let group = UIView(frame: CGRect(x: 0, y: 0, width: 150, height: height))
        bubble.frame = CGRect(x: (150 - bubble.bounds.width - 20) / 2, y: 0, width: bubble.bounds.width + 20, height: bubble.bounds.height + 6)
        let dork = UIImageView(image: face)
        dork.frame = CGRect(x: (150 - size) / 2, y: bubble.frame.maxY + 6, width: size, height: size)
        dork.layer.cornerRadius = size / 2
        dork.clipsToBounds = true
        group.addSubview(bubble)
        group.addSubview(dork)
        stage.addSubview(group)
        view.addSubview(stage)
        group.transform = CGAffineTransform(translationX: 0, y: height)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5, options: [], animations: {
            group.transform = CGAffineTransform(translationX: 0, y: height * 0.3)
        }) { _ in
            let wiggle = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            wiggle.values = [0, -12, 10, -12, 10, 0].map { $0 * Double.pi / 180 }
            wiggle.duration = 1
            dork.layer.add(wiggle, forKey: "wiggle")
            UIView.animate(withDuration: 0.38, delay: 1.4, options: [.curveEaseIn], animations: {
                group.transform = CGAffineTransform(translationX: 0, y: height)
            }) { _ in stage.removeFromSuperview() }
        }
    }

    /// Party mode: confetti from the menu button when you bookmark a page.
    func confetti() {
        guard Gag.party.on, Gag.motion else { return }
        let at = menuButton.convert(CGPoint(x: menuButton.bounds.midX, y: menuButton.bounds.midY), to: view)
        view.addSubview(Burst(frame: view.bounds, at: at, style: .confetti))
    }

    /// Power typing: a few sparks from the caret as you type (at most every 40ms).
    func sparks() {
        let now = CACurrentMediaTime()
        guard !duckBusy, now - sparkedAt > 0.04, Gag.power.on, Gag.motion, let caret = address.selectedTextRange?.end else { return }
        sparkedAt = now
        let rect = address.caretRect(for: caret)
        let at = address.convert(CGPoint(x: rect.midX, y: rect.midY), to: view)
        view.addSubview(Burst(frame: view.bounds, at: at, style: .sparks))
    }

    /// Tab ghosts: a closed tab floats up from its close button as a little ghost.
    func ghost(from source: UIView) {
        guard Gag.ghosts.on, Gag.motion, source.window != nil else { return }
        let size: CGFloat = 36
        let center = source.convert(CGPoint(x: source.bounds.midX, y: source.bounds.midY), to: view)
        let ghost = UIImageView(image: Icon.art("ghost"))
        ghost.frame = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        ghost.alpha = 0
        ghost.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        view.addSubview(ghost)
        UIView.animate(withDuration: 0.18, animations: {
            ghost.alpha = 1
            ghost.transform = .identity
        }) { _ in
            let sway = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            sway.values = [0, -10, 10, -8, 0].map { $0 * Double.pi / 180 }
            sway.duration = 1.3
            ghost.layer.add(sway, forKey: "sway")
            UIView.animate(withDuration: 1.3, animations: {
                ghost.frame.origin.y -= 90
                ghost.alpha = 0
            }) { _ in ghost.removeFromSuperview() }
        }
    }

    /// Download duck: a duck carries the download along the toolbar, drops it
    /// off at the end, and goes.
    func carryDownload() {
        guard Gag.downloadDuck.on, Gag.motion else { return }
        let size: CGFloat = 30
        let carrier = UIView(frame: CGRect(x: 0, y: 0, width: size + 12, height: size))
        // The duck walks left; this one walks right, its parcel in its beak.
        let bird = UIImageView(image: Icon.art("duck"))
        bird.frame = CGRect(x: 0, y: 0, width: size, height: size)
        bird.transform = CGAffineTransform(scaleX: -1, y: 1)
        let parcel = UIImageView(image: Icon.art("parcel"))
        parcel.frame = CGRect(x: size - 6, y: size - 18 - 11, width: 18, height: 18)
        carrier.addSubview(bird)
        carrier.addSubview(parcel)
        let bar = toolbar.convert(toolbar.bounds, to: view)
        // On the toolbar's edge by the page: its top on narrow windows, its bottom on wide ones.
        carrier.frame.origin = CGPoint(x: 12, y: tablet ? bar.maxY - size + 4 : bar.minY - size + 6)
        view.addSubview(carrier)
        let waddle = CABasicAnimation(keyPath: "transform.rotation.z")
        waddle.fromValue = -8 * Double.pi / 180
        waddle.toValue = 8 * Double.pi / 180
        waddle.duration = 0.3
        waddle.autoreverses = true
        waddle.repeatCount = .infinity
        bird.layer.add(waddle, forKey: "waddle")
        UIView.animate(withDuration: 2.2, delay: 0, options: [.curveEaseInOut], animations: {
            carrier.frame.origin.x = self.view.bounds.width - 64
        }) { _ in
            UIView.animate(withDuration: 0.38) {
                parcel.transform = CGAffineTransform(translationX: 22, y: 0).scaledBy(x: 0.3, y: 0.3)
                parcel.alpha = 0
            }
            UIView.animate(withDuration: 0.6, delay: 0.38, options: [], animations: {
                carrier.alpha = 0
                carrier.frame.origin.y += 8
            }) { _ in carrier.removeFromSuperview() }
        }
    }
}

/// A label with a little room around its text.
final class PaddedLabel: UILabel {
    override func drawText(in rect: CGRect) { super.drawText(in: rect.insetBy(dx: 2, dy: 0)) }
    override var textAlignment: NSTextAlignment { get { .center } set {} }
}

/// A CADisplayLink calling a closure.
final class DisplayLink: NSObject {
    private var link: CADisplayLink?
    private let tick: (DisplayLink) -> Void
    init(_ tick: @escaping (DisplayLink) -> Void) { self.tick = tick }
    func start() {
        link = CADisplayLink(target: self, selector: #selector(step))
        link?.add(to: .main, forMode: .common)
    }
    func stop() {
        link?.invalidate()
        link = nil
    }
    @objc private func step() { tick(self) }
}

/// A burst of little bits in Derp's colors, up and out, that gravity pulls
/// away; it removes itself. Party mode's confetti and Power typing's sparks
/// (the same as Derp for Android's Burst).
final class Burst: UIView {
    struct Style {
        let count: Int
        let speed: ClosedRange<Double>
        let life: Double
        let gravity: Double
        let w: CGFloat
        let h: CGFloat
        static let confetti = Style(count: 70, speed: 350...1000, life: 1.8, gravity: 1500, w: 8, h: 5)
        static let sparks = Style(count: 8, speed: 80...240, life: 0.45, gravity: 400, w: 4, h: 4)
    }

    private struct Bit { var x: Double; var y: Double; var vx: Double; var vy: Double; var angle: Double; let spin: Double; let color: UIColor }
    private var bits: [Bit]
    private let style: Style
    private var age = 0.0
    private var last = CACurrentMediaTime()
    private var link: DisplayLink?

    init(frame: CGRect, at point: CGPoint, style: Style) {
        self.style = style
        let colors = ["#C6F57E", "#2FD6BE", "#2F6FEB", "#FFD43B", "#FF6B9A", "#B8A4FF"].map { UIColor(hex: $0) }
        bits = (0..<style.count).map { i in
            // Up and out, then gravity takes over.
            let angle = Double.random(in: (Double.pi * 1.05)...(Double.pi * 1.95))
            let speed = Double.random(in: style.speed)
            return Bit(x: point.x, y: point.y, vx: cos(angle) * speed, vy: sin(angle) * speed, angle: Double.random(in: 0..<360), spin: Double.random(in: -450...450), color: colors[i % colors.count])
        }
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isOpaque = false
        link = DisplayLink { [weak self] link in
            guard let self else { return link.stop() }
            self.setNeedsDisplay()
        }
        link?.start()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - last)
        last = now
        age += dt
        let fade = max(0, min(1, 1 - (age - style.life * 0.6) / (style.life * 0.4)))
        guard let context = UIGraphicsGetCurrentContext() else { return }
        for i in bits.indices {
            bits[i].vy += style.gravity * dt
            bits[i].vx *= 1 - 0.8 * dt
            bits[i].x += bits[i].vx * dt
            bits[i].y += bits[i].vy * dt
            bits[i].angle += bits[i].spin * dt
            let bit = bits[i]
            context.saveGState()
            context.translateBy(x: bit.x, y: bit.y)
            context.rotate(by: bit.angle * .pi / 180)
            bit.color.withAlphaComponent(fade).setFill()
            context.fill(CGRect(x: -style.w / 2, y: -style.h / 2, width: style.w, height: style.h))
            context.restoreGState()
        }
        if age >= style.life {
            link?.stop()
            DispatchQueue.main.async { self.removeFromSuperview() }
        }
    }
}

/// A flurry of the season's things drifting down from the top of the page,
/// swaying and turning, and fading as they go; it removes itself.
final class Flurry: UIView {
    private struct Bit { let art: UIImage; let x: CGFloat; let scale: CGFloat; let delay: Double; let life: Double; let drift: CGFloat; let spin: CGFloat }
    private let bits: [Bit]
    private let depth: CGFloat
    private let start = CACurrentMediaTime()
    private var link: DisplayLink?

    init(art: [UIImage], depth: CGFloat) {
        self.depth = depth
        bits = (0..<18).map { i in
            Bit(art: art[i % art.count], x: .random(in: 0...1), scale: .random(in: 0.45...0.9), delay: .random(in: 0...1.4),
                life: .random(in: 2.8...4.8), drift: .random(in: -60...60), spin: .random(in: -270...270))
        }
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isOpaque = false
        link = DisplayLink { [weak self] link in
            guard let self else { return link.stop() }
            self.setNeedsDisplay()
        }
        link?.start()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let age = CACurrentMediaTime() - start
        var alive = false
        guard let context = UIGraphicsGetCurrentContext() else { return }
        for bit in bits {
            let t = min(1, max(0, (age - bit.delay) / bit.life))
            if t < 1 { alive = true }
            guard t > 0, t < 1 else { continue }
            // In over the first 12%, out over the last 30%.
            let alpha = max(0, min(1, min(t / 0.12, (1 - t) / 0.3)))
            let size = 32 * bit.scale
            let x = bit.x * bounds.width + bit.drift * CGFloat(t)
            let y = -size + (depth + size) * CGFloat(t)
            context.saveGState()
            context.translateBy(x: x, y: y)
            context.rotate(by: bit.spin * CGFloat(t) * .pi / 180)
            bit.art.draw(in: CGRect(x: -size / 2, y: -size / 2, width: size, height: size), blendMode: .normal, alpha: CGFloat(alpha))
            context.restoreGState()
        }
        if !alive {
            link?.stop()
            DispatchQueue.main.async { self.removeFromSuperview() }
        }
    }
}

// ── Sheets ──────────────────────────────────────────────────────────────────

/// Just for fun: the gags' switches, each with a line about what it does.
final class JustForFunController: UITableViewController {
    private let changed: () -> Void

    init(changed: @escaping () -> Void) {
        self.changed = changed
        super.init(style: .insetGrouped)
        title = "Just for fun"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "gag")
        let done = UIButton(type: .system)
        done.setTitle("Done", for: .normal)
        done.titleLabel?.font = .medium(17)
        done.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        let head = UIStackView(arrangedSubviews: [UILabel(), done])
        (head.arrangedSubviews[0] as? UILabel)?.text = "Just for fun"
        (head.arrangedSubviews[0] as? UILabel)?.font = .medium(20)
        head.frame = CGRect(x: 0, y: 0, width: 300, height: 56)
        head.isLayoutMarginsRelativeArrangement = true
        head.layoutMargins = UIEdgeInsets(top: 12, left: 20, bottom: 4, right: 20)
        tableView.tableHeaderView = head
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { Gag.allCases.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let gag = Gag.allCases[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "gag", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = gag.title
        content.secondaryText = gag.about
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        let toggle = UISwitch()
        toggle.isOn = gag.on
        toggle.accessibilityLabel = gag.title
        toggle.addAction(UIAction { [weak self, unowned toggle] _ in
            gag.on = toggle.isOn
            self?.changed()
        }, for: .valueChanged)
        cell.accessoryView = toggle
        cell.selectionStyle = .none
        return cell
    }
}

/// What's new, under your dork.
final class WhatsNewController: UIViewController {
    private let releases: [WhatsNew.Release]
    private let dork: UIImage?
    private let palette: Palette

    init(releases: [WhatsNew.Release], dork: UIImage?, palette: Palette) {
        self.releases = releases
        self.dork = dork
        self.palette = palette
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        let head = UIStackView()
        head.spacing = 14
        head.alignment = .center
        if let dork {
            let face = UIImageView(image: dork)
            face.widthAnchor.constraint(equalToConstant: 56).isActive = true
            face.heightAnchor.constraint(equalToConstant: 56).isActive = true
            face.layer.cornerRadius = 28
            face.clipsToBounds = true
            head.addArrangedSubview(face)
        }
        let titles = UIStackView()
        titles.axis = .vertical
        let title = UILabel()
        title.text = "What’s new in Derp \(releases[0].version)"
        title.font = .medium(20)
        title.numberOfLines = 0
        let sub = UILabel()
        sub.text = releases[0].title
        sub.textColor = .secondaryLabel
        titles.addArrangedSubview(title)
        titles.addArrangedSubview(sub)
        head.addArrangedSubview(titles)
        stack.addArrangedSubview(head)
        for release in releases {
            if releases.count > 1 {
                let label = UILabel()
                label.text = "Derp \(release.version): \(release.title)"
                label.font = .medium(13)
                label.textColor = palette.accent
                stack.addArrangedSubview(label)
            }
            for item in release.items {
                let icon = UILabel()
                icon.text = item.icon
                icon.font = .systemFont(ofSize: 22)
                icon.textAlignment = .center
                icon.widthAnchor.constraint(equalToConstant: 40).isActive = true
                let name = UILabel()
                name.text = item.title
                name.font = .medium(16)
                let text = UILabel()
                text.text = item.text
                text.numberOfLines = 0
                text.font = .systemFont(ofSize: 14)
                let words = UIStackView(arrangedSubviews: [name, text])
                words.axis = .vertical
                words.spacing = 2
                if let place = item.where_ {
                    let where_ = UILabel()
                    where_.text = place
                    where_.font = .systemFont(ofSize: 13)
                    where_.textColor = .secondaryLabel
                    where_.numberOfLines = 0
                    words.addArrangedSubview(where_)
                }
                let row = UIStackView(arrangedSubviews: [icon, words])
                row.spacing = 12
                row.alignment = .top
                stack.addArrangedSubview(row)
            }
        }
        var config = UIButton.Configuration.filled()
        config.title = "Nice!"
        config.baseBackgroundColor = palette.accent
        config.baseForegroundColor = palette.onAccent
        config.cornerStyle = .capsule
        let nice = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        let actions = UIStackView(arrangedSubviews: [UIView(), nice])
        stack.addArrangedSubview(actions)
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])
    }
}

/// The camera, looking for the pairing code's QR code.
final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let found: (String?) -> Void
    private var done = false

    init(found: @escaping (String?) -> Void) {
        self.found = found
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let hint = UILabel()
        hint.text = "Point the camera at the code Derp on your computer shows."
        hint.textColor = .white
        hint.numberOfLines = 0
        hint.textAlignment = .center
        hint.font = .medium(16)
        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.tintColor = .white
        cancel.addAction(UIAction { [weak self] _ in self?.finish(nil) }, for: .touchUpInside)
        for view in [hint, cancel] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(view)
        }
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            hint.bottomAnchor.constraint(equalTo: cancel.topAnchor, constant: -16),
            cancel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { granted ? self.startCamera() : self.noCamera() }
        }
    }

    private func noCamera() {
        let alert = UIAlertController(title: "Derp can’t use the camera", message: "Let it in Settings to scan the pairing code. (In LiveContainer, the setting is LiveContainer’s.)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.finish(nil) })
        present(alert, animated: true)
    }

    private func startCamera() {
        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else {
            return noCamera()
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return noCamera() }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layer.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer }.forEach { $0.frame = view.bounds }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        finish(code)
    }

    private func finish(_ code: String?) {
        guard !done else { return }
        done = true
        session.stopRunning()
        dismiss(animated: true) { self.found(code) }
    }
}
