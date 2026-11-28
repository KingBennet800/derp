import UIKit
import WebKit
import QuickLook

/// Downloads go to Derp's Downloads folder: in the Files app under Derp when
/// Derp is installed, or inside LiveContainer's folder when it runs there
/// (Setup.downloadsHelp says which). Each one can be opened or shared.
final class Downloads: NSObject, WKDownloadDelegate {
    let folder: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        return docs
    }()

    private var targets: [ObjectIdentifier: URL] = [:]
    private var windows: [ObjectIdentifier: () -> BrowserUI?] = [:]

    func start(_ download: WKDownload, ui: BrowserUI?) {
        download.delegate = self
        weak var weakUI = ui
        windows[ObjectIdentifier(download)] = { weakUI }
        ui?.downloadStarted()
    }

    /// A name not taken yet in Downloads: "report.pdf", "report 2.pdf"…
    func free(_ name: String) -> URL {
        let clean = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        let base = (clean.isEmpty ? "download" : clean) as NSString
        var url = folder.appendingPathComponent(base as String)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let ext = base.pathExtension
            let stem = base.deletingPathExtension
            url = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            n += 1
        }
        return url
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let url = free(suggestedFilename)
        targets[ObjectIdentifier(download)] = url
        completionHandler(url)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        guard let url = targets.removeValue(forKey: id), let ui = windows.removeValue(forKey: id)?() as? BrowserViewController else { return }
        ui.downloaded(url)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let id = ObjectIdentifier(download)
        targets.removeValue(forKey: id)
        windows.removeValue(forKey: id)?()?.toast("The download didn’t finish")
    }
}

/// Quick Look for a finished download.
final class Preview: NSObject, QLPreviewControllerDataSource {
    let url: URL
    init(_ url: URL) { self.url = url }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
}

/// Derp checks its GitHub releases for a newer Derp (at most once an hour),
/// like desktop Derp and Derp for Android. iOS doesn't let an app install
/// itself, so the update goes in the way Derp did: SideStore or AltStore
/// (with Derp's source, it shows under Updates), or LiveContainer.
enum Updater {
    static let releases = "https://github.com/KingBennet800/derp/releases"
    static let ipa = releases + "/latest/download/Derp.ipa"
    static let source = releases + "/latest/download/derp-source.json"

    /// The newest release's version, from its SHA256SUMS (which names it).
    static func latest(_ done: @escaping (String?) -> Void) {
        var request = URLRequest(url: URL(string: releases + "/latest/download/SHA256SUMS")!, timeoutInterval: 20)
        request.setValue("Derp/\(WhatsNew.version)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let version = text.range(of: "derp-(\\d+(\\.\\d+)*)\\.tar\\.gz", options: .regularExpression).map {
                String(text[$0].dropFirst(5).dropLast(7))
            }
            DispatchQueue.main.async { done((response as? HTTPURLResponse)?.statusCode == 200 ? version : nil) }
        }.resume()
    }

    static func check(_ window: BrowserViewController, manual: Bool) {
        let now = Date().timeIntervalSince1970
        if !manual && now - Prefs.store.double(forKey: "updateChecked") < 3600 { return }
        if manual { window.toast("Checking for updates…") }
        latest { version in
            Prefs.set("updateChecked", now)
            guard let version else {
                if manual { window.toast("Couldn’t reach GitHub to check for updates") }
                return
            }
            if WhatsNew.newer(version, WhatsNew.version) {
                // You said "Later" to this version less than a day ago: wait (unless you asked).
                let putOff = Prefs.store.string(forKey: "updateLater") == version && now - Prefs.store.double(forKey: "updateLaterAt") < 86_400
                if manual || !putOff { window.offerUpdate(version) }
            } else if manual {
                window.toast("Derp is up to date (\(WhatsNew.version))")
            }
        }
    }
}

/// Add to Home Screen. iOS lets only Safari put a website on the Home Screen,
/// but a configuration profile can add a Web Clip, an icon that opens a link
/// (LiveContainer adds its apps the same way). The link opens the site in
/// Derp: a derp:// link for an installed Derp, a LiveContainer launch link
/// (with this data container) when Derp runs in LiveContainer.
enum HomeScreen {
    static func profile(label: String, link: URL, icon: UIImage, note: String) -> Data? {
        let id = "io.github.kingbennet800.derp.clip." + UUID().uuidString.lowercased()
        let clip: [String: Any] = [
            "FullScreen": false,
            "Icon": icon.pngData() ?? Data(),
            "IgnoreManifestScope": true,
            "IsRemovable": true,
            "Label": String(label.prefix(40)),
            "Precomposed": true,
            "PayloadDescription": note,
            "PayloadDisplayName": label,
            "PayloadIdentifier": id + ".webclip",
            "PayloadType": "com.apple.webClip.managed",
            "PayloadUUID": UUID().uuidString,
            "PayloadVersion": 1,
            "URL": link.absoluteString,
        ]
        let profile: [String: Any] = [
            "PayloadContent": [clip],
            "PayloadDescription": note,
            "PayloadDisplayName": "\(label) (Derp)",
            "PayloadIdentifier": id,
            "PayloadOrganization": "Derp",
            "PayloadRemovalDisallowed": false,
            "PayloadType": "Configuration",
            "PayloadUUID": UUID().uuidString,
            "PayloadVersion": 1,
        ]
        return try? PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
    }

    /// A site's icon on white, or its first letter on a color from its address
    /// (like the new tab page's tiles), 180px.
    static func icon(picture: UIImage?, name: String, address: String) -> UIImage {
        let size = CGSize(width: 180, height: 180)
        return UIGraphicsImageRenderer(size: size).image { context in
            if let picture, picture.size.width >= 16 {
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                let box: CGFloat = 112
                let scale = box / max(picture.size.width, picture.size.height)
                let w = picture.size.width * scale, h = picture.size.height * scale
                picture.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
            } else {
                let host = Address.host(address) ?? ""
                var hash: Int32 = 0
                for ch in host.unicodeScalars { hash = hash &* 31 &+ Int32(truncatingIfNeeded: ch.value) }
                UIColor(hue: CGFloat(abs(Int(hash)) % 360) / 360, saturation: 0.55, brightness: 0.78, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                let letter = String((name.trimmingCharacters(in: .whitespaces).first ?? host.first ?? "?")).uppercased()
                let text = NSAttributedString(string: letter, attributes: [.font: UIFont.systemFont(ofSize: 84, weight: .medium), .foregroundColor: UIColor.white])
                let bounds = text.size()
                text.draw(at: CGPoint(x: (size.width - bounds.width) / 2, y: (size.height - bounds.height) / 2))
            }
        }
    }
}
