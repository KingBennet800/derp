import UIKit
import WebKit

/// Derp's own pages (the new tab, your dork, bookmarks, history, passwords,
/// Reader view…), served from the app at derp://pages/. They're the same pages
/// Derp for Android shows, and they ask the app things the same way.
final class Pages: NSObject, WKURLSchemeHandler {
    static let scheme = "derp"
    static let base = "derp://pages/"
    private let folder = Bundle.main.bundleURL.appendingPathComponent("derp")

    static func url(_ page: String) -> URL { URL(string: base + page)! }

    static func isPage(_ url: String) -> Bool { url.hasPrefix(base) }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, url.host == "pages" else {
            task.didFailWithError(URLError(.unsupportedURL))
            return
        }
        let name = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let file = folder.appendingPathComponent(name).standardizedFileURL
        guard !name.isEmpty, file.path.hasPrefix(folder.standardizedFileURL.path + "/"), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let types = ["html": "text/html", "js": "text/javascript", "css": "text/css", "svg": "image/svg+xml", "json": "application/json", "png": "image/png"]
        let type = types[file.pathExtension.lowercased()] ?? "application/octet-stream"
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": type.hasPrefix("text/") || type.hasSuffix("json") || type.hasSuffix("xml") ? type + "; charset=utf-8" : type,
            "Content-Length": String(data.count),
            "Cache-Control": "no-cache",
        ])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    // ── The scripts every tab gets ─────────────────────────────────────────

    /// Derp's own world for its scripts in web pages, apart from the pages' own.
    static let world = WKContentWorld.world(name: "derp")

    private static func script(_ name: String) -> String {
        (Bundle.main.url(forResource: name, withExtension: "js").flatMap { try? String(contentsOf: $0) }) ?? ""
    }

    private static func shared(_ name: String) -> String {
        (try? String(contentsOf: Bundle.main.bundleURL.appendingPathComponent("derp/" + name))) ?? ""
    }

    /// Doodle's look on its results (Google's and DuckDuckGo's): desktop Derp's
    /// content scripts and styles, on the pages they're for.
    private static func look(host: String, path: String?, css: String, js: String) -> [WKUserScript] {
        let test = path.map { "location.host === \"\(host)\" && location.pathname === \"\($0)\"" } ?? "location.host === \"\(host)\""
        let style = """
        (() => {
          if (!(\(test))) return;
          const style = document.createElement("style");
          style.textContent = \(jsString(css));
          (document.head || document.documentElement).append(style);
        })();
        """
        let code = "if (\(test)) {\n\(js)\n}"
        return [
            WKUserScript(source: style, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world),
            WKUserScript(source: code, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: world),
        ]
    }

    static func jsString(_ text: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [text])
        let array = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }

    /// The content controller all tabs share: the scripts above, and the app's
    /// two message handlers (one for Derp's pages, one for its scripts in web pages).
    func contentController(bridge: Bridge) -> WKUserContentController {
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: Pages.script("shim"), injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        controller.addUserScript(WKUserScript(source: Pages.script("page"), injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Pages.world))
        controller.addUserScript(WKUserScript(source: Pages.script("logins"), injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: Pages.world))
        for script in Pages.look(host: "www.google.com", path: "/search", css: Pages.shared("doodle-page.css"), js: Pages.shared("doodle-page.js"))
            + Pages.look(host: "duckduckgo.com", path: nil, css: Pages.shared("doodle-ddg.css"), js: Pages.shared("doodle-ddg.js")) {
            controller.addUserScript(script)
        }
        controller.addScriptMessageHandler(bridge, contentWorld: .page, name: "derp")
        controller.add(WeakHandler(bridge), contentWorld: Pages.world, name: "derpPage")
        return controller
    }
}

/// WebKit keeps its message handlers; this keeps it from keeping the bridge.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// Answers Derp's pages, and hears from its scripts in web pages.
final class Bridge: NSObject, WKScriptMessageHandlerWithReply, WKScriptMessageHandler {
    private unowned let app: DerpApp

    init(app: DerpApp) {
        self.app = app
    }

    private func json(_ object: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) } ?? "{\"ok\":false}"
    }

    // Derp's pages (only they: the page world's handler checks where it's asked from).
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == Pages.scheme,
              let body = message.body as? [String: Any], let type = body["type"] as? String,
              let webView = message.webView, let (browser, tab) = app.find(webView) else {
            replyHandler(json(["ok": false]), nil)
            return
        }
        let done: ([String: Any]) -> Void = { [weak self] reply in replyHandler(self?.json(reply) ?? "{}", nil) }
        if later(type, body, tab, browser, done) { return }
        var reply: [String: Any] = ["ok": true]
        answer(type, body, &reply, tab, browser)
        done(reply)
    }

    private func dataURL(_ value: Any?) -> Data? {
        guard let text = value as? String, let comma = text.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(text[text.index(after: comma)...]))
    }

    private func answer(_ type: String, _ msg: [String: Any], _ reply: inout [String: Any], _ tab: Tab, _ browser: Browser) {
        let library = app.library
        switch type {
        case "getState":
            if let dork = app.dork.json { reply["dork"] = dork }
            reply["made"] = app.dork.made
            reply["version"] = WhatsNew.version
            reply["engine"] = Engine.current.label
            reply["sleepy"] = app.dork.hasSleepy
            reply["doodle"] = DoodleResults.current.rawValue
            reply["doodlePicked"] = DoodleResults.picked
            if let days = Pet.days { reply["petDays"] = days }
            let (light, dark) = Look.current.accents
            reply["accent"] = [light, dark]
            reply["scan"] = true
            reply["here"] = UIDevice.current.userInterfaceIdiom == .pad ? "this iPad" : "this iPhone"
            if let profile = app.setup.profile { reply["profile"] = profile }
        case "setDork":
            if let dork = msg["dork"] as? [String: Any] {
                app.dork.save(dork, png: dataURL(msg["png"]), sleepy: dataURL(msg["sleepyPng"]))
            }
        case "stickers.get":
            if let shot = browser.stickerShot { reply["image"] = shot }
            if let dork = app.dork.json { reply["dork"] = dork }
        case "stickers.close":
            browser.closeStickers(tab)
        case "doodle.set":
            DoodleResults.current = DoodleResults(rawValue: msg["results"] as? String ?? "") ?? .google
        case "made":
            app.dork.made = true
        case "focusUrl":
            browser.ui?.focusAddress()
        case "bookmarks.list":
            reply["items"] = library.bookmarks(query: msg["query"] as? String ?? "", limit: msg["limit"] as? Int ?? 500)
        case "bookmarks.remove":
            library.unbookmark(msg["url"] as? String ?? "")
            app.pairing.changed()
        case "history.list":
            let before = (msg["before"] as? NSNumber)?.int64Value ?? Int64.max
            reply["items"] = library.history(query: msg["query"] as? String ?? "", before: before, limit: msg["limit"] as? Int ?? 200)
        case "history.remove":
            library.forget(msg["url"] as? String ?? "")
        case "history.clear":
            library.clearHistory()
        case "logins.list":
            reply["items"] = app.logins.list(query: msg["query"] as? String ?? "")
            reply["save"] = app.logins.offerToSave
        case "logins.remove":
            app.logins.remove(msg["guid"] as? String ?? "")
            app.pairing.changed()
        case "logins.offer":
            app.logins.offerToSave = msg["on"] as? Bool ?? true
        case "devices.get":
            reply["devices"] = app.pairing.summary
        case "reader.get":
            if let reading = tab.reading {
                reply["url"] = reading.url
                reply["html"] = reading.html
            }
        default:
            reply["ok"] = false
        }
    }

    /// Questions answered later: ones that need you (a file to pick, Face ID, the camera).
    private func later(_ type: String, _ msg: [String: Any], _ tab: Tab, _ browser: Browser, _ done: @escaping ([String: Any]) -> Void) -> Bool {
        guard let ui = browser.ui else {
            if ["import", "logins.reveal", "logins.copy", "devices.sync", "devices.leave", "devices.scan", "stickers.save"].contains(type) {
                done(["ok": false])
                return true
            }
            return false
        }
        switch type {
        case "stickers.save":
            ui.saveStickers(dataURL(msg["png"])) { saved in
                done(["ok": saved])
                if saved { browser.closeStickers(tab) }
            }
        case "devices.sync":
            app.pairing.syncNow { done(["ok": true, "devices": self.app.pairing.summary]) }
        case "devices.leave":
            app.pairing.leave { done(["ok": true, "devices": self.app.pairing.summary]) }
        case "devices.scan":
            ui.scanPairingCode { done(["ok": true, "devices": self.app.pairing.summary]) }
        case "import":
            ui.importFile(kind: msg["kind"] as? String ?? "") { reply in
                done(reply)
                self.app.pairing.changed()
            }
        case "logins.reveal", "logins.copy":
            let guid = msg["guid"] as? String ?? ""
            ui.unlock { unlocked in
                let password = unlocked ? self.app.logins.password(guid) : nil
                if !unlocked {
                    done(["ok": false, "cancelled": true])
                } else if let password {
                    if type == "logins.copy" {
                        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: password]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
                        done(["ok": true])
                    } else {
                        done(["ok": true, "password": password])
                    }
                } else {
                    done(["ok": false])
                }
            }
        default:
            return false
        }
        return true
    }

    // Derp's scripts in web pages (page.js, logins.js), in Derp's own world.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String,
              let webView = message.webView, let (browser, tab) = app.find(webView) else { return }
        switch type {
        case "page":
            tab.pageURL = body["url"] as? String ?? ""
            tab.readable = body["readable"] as? Bool ?? false
            tab.icon = body["icon"] as? String
        case "login.submit":
            browser.offerToSaveLogin(tab, origin: message.frameInfo.securityOrigin, body: body)
        case "login.focus":
            browser.offerLogins(tab, frame: message.frameInfo)
        default:
            break
        }
    }
}

extension WKSecurityOrigin {
    /// https://example.com[:port]
    var origin: String { "\(`protocol`)://\(host)" + (port == 0 || port == 443 || port == 80 ? "" : ":\(port)") }
}
