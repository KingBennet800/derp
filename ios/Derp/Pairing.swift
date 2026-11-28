import CryptoKit
import Foundation
import Compression
import UIKit

/// gzip, as desktop Derp's pairing writes it (CompressionStream("gzip")).
enum Gzip {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    private static func little(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }

    static func compress(_ data: Data) throws -> Data {
        // Apple's "zlib" is raw DEFLATE (RFC 1951): the gzip header and trailer go around it.
        let deflated = try (data as NSData).compressed(using: .zlib) as Data
        var out = Data([0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xFF])
        out.append(deflated)
        out.append(contentsOf: little(crc32(data)))
        out.append(contentsOf: little(UInt32(truncatingIfNeeded: data.count)))
        return out
    }

    struct Bad: Error {}

    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 0x08 else { throw Bad() }
        let flags = bytes[3]
        var at = 10
        if flags & 0x04 != 0 {  // FEXTRA
            guard at + 2 <= bytes.count else { throw Bad() }
            at += 2 + Int(bytes[at]) + Int(bytes[at + 1]) << 8
        }
        if flags & 0x08 != 0 { while at < bytes.count && bytes[at] != 0 { at += 1 }; at += 1 }  // FNAME
        if flags & 0x10 != 0 { while at < bytes.count && bytes[at] != 0 { at += 1 }; at += 1 }  // FCOMMENT
        if flags & 0x02 != 0 { at += 2 }  // FHCRC
        guard at < bytes.count - 8 else { throw Bad() }
        let body = Data(bytes[at..<(bytes.count - 8)])
        let out = try (body as NSData).decompressed(using: .zlib) as Data
        let crc = UInt32(bytes[bytes.count - 8]) | UInt32(bytes[bytes.count - 7]) << 8 | UInt32(bytes[bytes.count - 6]) << 16 | UInt32(bytes[bytes.count - 5]) << 24
        guard crc == crc32(out) else { throw Bad() }
        return out
    }
}

/// The keys a pair's secret gives, and the pair's crypto: the same as desktop
/// Derp's (src/features/DerpPair.sys.mjs), Derp for Android's (Pairing.kt)
/// and tests/pairing.py's.
struct PairKeys {
    let box: String
    let token: String
    let key: SymmetricKey
    let hash: SymmetricKey

    init(secret: Data) {
        box = PairKeys.hex(PairKeys.hkdf(secret, "derp pair box"))
        token = PairKeys.hex(PairKeys.hkdf(secret, "derp pair write"))
        key = SymmetricKey(data: PairKeys.hkdf(secret, "derp pair key"))
        hash = SymmetricKey(data: PairKeys.hkdf(secret, "derp pair hash"))
    }

    static func hex<D: Sequence>(_ bytes: D) -> String where D.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// HKDF-SHA256 with no salt, 32 bytes.
    static func hkdf(_ secret: Data, _ info: String) -> Data {
        let derived = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: secret), info: Data(info.utf8), outputByteCount: 32)
        return derived.withUnsafeBytes { Data($0) }
    }

    func seal(device: String, json: Data, nonce: Data? = nil) throws -> Data {
        let zipped = try Gzip.compress(json)
        let n = try AES.GCM.Nonce(data: nonce ?? Data((0..<12).map { _ in UInt8.random(in: 0...255) }))
        let box = try AES.GCM.seal(zipped, using: key, nonce: n, authenticating: Data("derp pair v1 \(device)".utf8))
        return Data([1]) + n.withUnsafeBytes { Data($0) } + box.ciphertext + box.tag
    }

    func unseal(device: String, blob: Data) throws -> Data {
        guard blob.count > 29, blob.first == 1 else { throw Gzip.Bad() }
        let b = [UInt8](blob)
        let sealed = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: Data(b[1..<13])), ciphertext: Data(b[13..<(b.count - 16)]), tag: Data(b[(b.count - 16)...]))
        let zipped = try AES.GCM.open(sealed, using: key, authenticating: Data("derp pair v1 \(device)".utf8))
        return try Gzip.decompress(zipped)
    }

    /// A keyed hash of a password, to notice changes without keeping it.
    func hash(_ password: String) -> String {
        String(PairKeys.hex(HMAC<SHA256>.authenticationCode(for: Data(password.utf8), using: hash)).prefix(32))
    }
}

/// Your devices: Derp here paired with Derp on your computer, sharing
/// bookmarks, passwords and open tabs, end-to-end encrypted, with no account.
/// Desktop Derp shows a QR code; scanning it here pairs. The protocol is
/// desktop Derp's: keys come from the shared secret, each device keeps one
/// encrypted snapshot on a relay that can't read them, and the newest change
/// to anything wins. The ledger keeps a keyed hash of each password, never
/// the password; the secret itself is kept in the keychain.
final class Pairing {
    static let relay = "https://bennettholland.com/derp-relay.php"
    static let link = "https://kingbennet800.github.io/derp/pair/#"
    private static let tabsMax = 50
    private static let maxText = 4096
    private static let day: Int64 = 86_400_000
    private static let every: TimeInterval = 10 * 60

    private let file: URL
    private let queue = DispatchQueue(label: "derp.pairing")
    private var state: [String: Any]?
    private var keys: PairKeys?
    private var loaded = false
    private var timer: Timer?
    private unowned let app: DerpApp

    /// What the Your devices page shows, as of the last sync.
    private(set) var summary: [String: Any] = ["paired": false]
    var paired: Bool { summary["paired"] as? Bool ?? false }

    init(app: DerpApp, directory: URL) {
        self.app = app
        file = directory.appendingPathComponent("devices.json")
    }

    func start() {
        queue.async {
            self.load()
            if self.state != nil { DispatchQueue.main.async { self.syncSoon(10) } }
        }
    }

    // ── When to sync ───────────────────────────────────────────────────────

    /// Derp came to the screen: sync soon, then every ten minutes while it's there.
    func resumed() {
        if paired, now() - ((summary["syncedAt"] as? Int64) ?? 0) > 60_000 { syncSoon(2) }
    }

    /// Derp left the screen: send your open tabs, and stop syncing on a timer.
    func paused() {
        timer?.invalidate()
        if paired { go(again: false) }
    }

    /// Something you keep changed here (a bookmark, a password).
    func changed() {
        if paired { syncSoon(5) }
    }

    func syncSoon(_ delay: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in self?.go() }
    }

    private func go(again: Bool = true, done: (() -> Void)? = nil) {
        let tabs = openTabs()
        queue.async {
            self.sync(tabs: tabs)
            DispatchQueue.main.async { done?() }
        }
        if again { syncSoon(Pairing.every) }
    }

    func syncNow(_ done: @escaping () -> Void) {
        timer?.invalidate()
        go(done: done)
    }

    /// Your open tabs (not private ones), most recently seen first.
    private func openTabs() -> [[String: Any]] {
        app.allTabs()
            .filter { !$0.isPrivate && Pairing.isWeb($0.url) }
            .sorted { $0.seen > $1.seen }
            .prefix(Pairing.tabsMax)
            .map { ["url": $0.url, "title": String($0.title.prefix(300))] }
    }

    // ── Pairing and leaving ────────────────────────────────────────────────

    /// The secret and relay in a pairing link, or nil if it isn't one.
    static func parse(_ link: String) -> (Data, String)? {
        guard link.hasPrefix(Pairing.link) else { return nil }
        let rest = String(link.dropFirst(Pairing.link.count))
        let code = rest.components(separatedBy: "~")[0]
        var base64 = code.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let secret = Data(base64Encoded: base64), secret.count == 32 else { return nil }
        var relay = Pairing.relay
        if let tilde = rest.firstIndex(of: "~") {
            guard let decoded = String(rest[rest.index(after: tilde)...]).removingPercentEncoding else { return nil }
            relay = decoded
        }
        let local = relay.range(of: "^http://(localhost|127\\.0\\.0\\.1)(:\\d+)?/", options: .regularExpression) != nil
        guard relay.hasPrefix("https://") || local else { return nil }
        return (secret, relay)
    }

    /// Joins the pair in [link] (leaving any other first); [done] gets what to tell you.
    func join(_ link: String, done: @escaping (String) -> Void) {
        guard let (secret, relay) = Pairing.parse(link) else {
            return done("That pairing code didn’t work. Make a new one on your computer.")
        }
        let tabs = openTabs()
        queue.async {
            if self.state != nil { self.leaveNow() }
            Keychain.set(secret, for: "pairing.secret")
            self.state = [
                "relay": relay,
                "device": PairKeys.hex((0..<16).map { _ in UInt8.random(in: 0...255) }),
                "ledger": ["bookmarks": [String: Any](), "logins": [String: Any]()],
                "devices": [String: Any](),
            ]
            self.keys = PairKeys(secret: secret)
            self.save()
            self.sync(tabs: tabs)
            let names = self.deviceNames()
            DispatchQueue.main.async {
                done(names.isEmpty ? "Paired. Your computer shows up here once it syncs." : "Paired with \(names)")
                self.syncSoon(Pairing.every)
            }
        }
    }

    /// Stop syncing: this device leaves the pair. Its bookmarks and passwords stay.
    func leave(_ done: @escaping () -> Void) {
        timer?.invalidate()
        queue.async {
            self.leaveNow()
            DispatchQueue.main.async(execute: done)
        }
    }

    private func leaveNow() {
        guard let state, let keys, let relay = state["relay"] as? String, let device = state["device"] as? String else { return }
        _ = try? request(relay, "POST", keys, ["X-Derp-Token": keys.token, "X-Derp-Device": device, "X-Derp-Delete": "1"], Data())
        self.state = nil
        self.keys = nil
        try? FileManager.default.removeItem(at: file)
        Keychain.set(nil, for: "pairing.secret")
        summary = ["paired": false]
    }

    // ── Syncing (on the queue) ─────────────────────────────────────────────

    private struct Local {
        var bookmarks: [String: String]
        var logins: [String: Logins.Synced]
    }

    private func sync(tabs: [[String: Any]]) {
        load()
        guard var state, let keys else { return }
        var local = Local(
            bookmarks: Dictionary(app.library.allBookmarks().filter { Pairing.isWeb($0.0) }, uniquingKeysWith: { _, b in b }),
            logins: Dictionary(app.logins.all().filter { Pairing.isWeb($0.origin) }.map { (Pairing.loginKey($0.origin, $0.realm, $0.username), $0) }, uniquingKeysWith: { _, b in b })
        )
        var ledger = state["ledger"] as? [String: Any] ?? [:]
        noteLocal(&ledger, keys, local)
        var changes = 0
        do {
            if let slots = try pull(&state, keys) {
                var seen: [String: Any] = [:]
                for (device, slot) in slots {
                    guard device != state["device"] as? String, device.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
                          let data = (slot as? [String: Any])?["data"] as? String, let blob = Data(base64Encoded: data),
                          let json = try? keys.unseal(device: device, blob: blob),
                          let snapshot = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { continue }
                    let theirTabs: [[String: Any]] = (snapshot["tabs"] as? [[String: Any]] ?? []).prefix(Pairing.tabsMax).compactMap { tab in
                        guard let url = tab["url"] as? String, Pairing.isWeb(url) else { return nil }
                        return ["url": url, "title": String((tab["title"] as? String ?? "").prefix(300))]
                    }
                    let kind = snapshot["kind"] as? String ?? ""
                    let device_: [String: Any] = [
                        "name": String((snapshot["name"] as? String ?? "Derp").prefix(80)),
                        "kind": ["phone", "tablet", "desktop"].contains(kind) ? kind : "desktop",
                        "at": (snapshot["at"] as? NSNumber)?.int64Value ?? 0,
                        "tabs": theirTabs,
                    ]
                    seen[device] = device_
                    changes += merge(&ledger, keys, snapshot, &local)
                }
                state["devices"] = seen
            }
            forgetOld(&ledger)
            state["ledger"] = ledger
            try push(&state, keys, local, tabs)
            state["syncedAt"] = now()
            state["problem"] = ""
        } catch {
            state["ledger"] = ledger
            state["problem"] = (error as? Problem)?.message ?? error.localizedDescription
            NSLog("Derp: Your devices: sync failed: %@", "\(error)")
        }
        self.state = state
        save()
        NSLog("Derp: Your devices: synced (%d change(s))", changes)
    }

    private func entry(_ origin: String, _ realm: String, _ form: String, _ username: String) -> [String: Any] {
        ["origin": origin, "realm": realm, "form": form, "username": username]
    }

    /// Your changes since the last sync go in the ledger, as of now.
    private func noteLocal(_ ledger: inout [String: Any], _ keys: PairKeys, _ local: Local) {
        let time = now()
        var bookmarks = ledger["bookmarks"] as? [String: [String: Any]] ?? [:]
        for (url, title) in local.bookmarks {
            let known = bookmarks[url]
            if known == nil || known?["gone"] as? Bool == true || known?["title"] as? String != title {
                bookmarks[url] = ["title": title, "at": time, "gone": false]
            }
        }
        for (url, known) in bookmarks where known["gone"] as? Bool != true && local.bookmarks[url] == nil {
            bookmarks[url] = ["title": known["title"] as? String ?? "", "at": time, "gone": true]
        }
        var logins = ledger["logins"] as? [String: [String: Any]] ?? [:]
        for (key, login) in local.logins {
            let hash = keys.hash(login.password)
            let known = logins[key]
            if known == nil || known?["gone"] as? Bool == true || known?["hash"] as? String != hash {
                var e = entry(login.origin, login.realm, login.form, login.username)
                e["hash"] = hash; e["at"] = time; e["gone"] = false
                logins[key] = e
            }
        }
        for (key, known) in logins where known["gone"] as? Bool != true && local.logins[key] == nil {
            var e = known
            e["hash"] = ""; e["at"] = time; e["gone"] = true
            logins[key] = e
        }
        ledger["bookmarks"] = bookmarks
        ledger["logins"] = logins
    }

    private func at(_ value: Any?) -> Int64 { (value as? NSNumber)?.int64Value ?? -1 }

    /// Takes another device's newer changes; returns how many.
    private func merge(_ ledger: inout [String: Any], _ keys: PairKeys, _ snapshot: [String: Any], _ local: inout Local) -> Int {
        var changes = 0
        var bookmarks = ledger["bookmarks"] as? [String: [String: Any]] ?? [:]
        for (url, value) in snapshot["bookmarks"] as? [String: Any] ?? [:] {
            guard let e = value as? [String: Any] else { continue }
            let when = at(e["at"])
            guard Pairing.isWeb(url), when >= 0, at(bookmarks[url]?["at"]) < when else { continue }
            let title = String((e["title"] as? String ?? "").prefix(1000))
            let gone = e["gone"] as? Bool ?? false
            if gone {
                if local.bookmarks.removeValue(forKey: url) != nil { app.library.unbookmark(url); changes += 1 }
            } else if local.bookmarks[url] == nil {
                app.library.bookmark(url, title: title); local.bookmarks[url] = title; changes += 1
            } else if local.bookmarks[url] != title {
                app.library.retitle(url, title: title); local.bookmarks[url] = title; changes += 1
            }
            bookmarks[url] = ["title": title, "at": when, "gone": gone]
        }
        var logins = ledger["logins"] as? [String: [String: Any]] ?? [:]
        for (_, value) in snapshot["logins"] as? [String: Any] ?? [:] {
            guard let e = value as? [String: Any], let origin = Pairing.origin(e["origin"] as? String ?? "") else { continue }
            let when = at(e["at"])
            let username = e["username"] as? String ?? ""
            guard when >= 0, username.count <= Pairing.maxText else { continue }
            let realm = String((e["realm"] as? String ?? "").prefix(1000))
            let form = String((e["form"] as? String ?? "").prefix(1000))
            let key = Pairing.loginKey(origin, realm, username)
            guard at(logins[key]?["at"]) < when else { continue }
            let gone = e["gone"] as? Bool ?? false
            let password = e["password"] as? String ?? ""
            if !gone && (password.isEmpty || password.count > Pairing.maxText) { continue }
            var out = entry(origin, realm, form, username)
            out["at"] = when
            out["gone"] = gone
            if gone {
                if local.logins[key] != nil {
                    app.logins.delete(origin: origin, realm: realm, username: username)
                    local.logins.removeValue(forKey: key)
                    changes += 1
                }
                out["hash"] = ""
            } else {
                if local.logins[key]?.password != password {
                    let login = Logins.Synced(origin: origin, realm: realm, form: form, username: username, password: password)
                    app.logins.put(login)
                    local.logins[key] = login
                    changes += 1
                }
                out["hash"] = keys.hash(password)
            }
            logins[key] = out
        }
        ledger["bookmarks"] = bookmarks
        ledger["logins"] = logins
        return changes
    }

    /// Deletions are remembered for 90 days, so the other devices hear of them.
    private func forgetOld(_ ledger: inout [String: Any]) {
        let old = now() - 90 * Pairing.day
        for list in ["bookmarks", "logins"] {
            var entries = ledger[list] as? [String: [String: Any]] ?? [:]
            entries = entries.filter { !($0.value["gone"] as? Bool == true && at($0.value["at"]) < old) }
            ledger[list] = entries
        }
    }

    private func pull(_ state: inout [String: Any], _ keys: PairKeys) throws -> [String: Any]? {
        let etag = state["etag"] as? String ?? ""
        let (status, body, tag) = try request(state["relay"] as? String ?? Pairing.relay, "GET", keys, etag.isEmpty ? [:] : ["If-None-Match": etag], nil)
        if status == 304 { return nil }
        state["etag"] = tag ?? ""
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        return json?["slots"] as? [String: Any] ?? [:]
    }

    /// Uploads this device's snapshot when it changed (or once a week, so the relay keeps it).
    private func push(_ state: inout [String: Any], _ keys: PairKeys, _ local: Local, _ tabs: [[String: Any]]) throws {
        let ledger = state["ledger"] as? [String: Any] ?? [:]
        var logins: [String: Any] = [:]
        for (key, e) in ledger["logins"] as? [String: [String: Any]] ?? [:] {
            var out = entry(e["origin"] as? String ?? "", e["realm"] as? String ?? "", e["form"] as? String ?? "", e["username"] as? String ?? "")
            out["at"] = at(e["at"])
            if e["gone"] as? Bool == true {
                out["gone"] = true
            } else {
                guard let mine = local.logins[key] else { continue }
                out["password"] = mine.password
                out["gone"] = false
            }
            logins[key] = out
        }
        let device = state["device"] as? String ?? ""
        var snapshot: [String: Any] = [
            "v": 1,
            "device": device,
            "name": "Derp on \(UIDevice.current.model)",
            "kind": UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone",
            "tabs": tabs,
            "bookmarks": ledger["bookmarks"] ?? [String: Any](),
            "logins": logins,
        ]
        let body = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
        let fingerprint = PairKeys.hex(SHA256.hash(data: body))
        let time = now()
        if fingerprint == state["pushed"] as? String, time - at(state["pushedAt"]) < 7 * Pairing.day { return }
        snapshot["at"] = time
        let sealed = try keys.seal(device: device, json: JSONSerialization.data(withJSONObject: snapshot))
        _ = try request(state["relay"] as? String ?? Pairing.relay, "POST", keys, [
            "X-Derp-Token": keys.token, "X-Derp-Device": device, "Content-Type": "application/octet-stream",
        ], sealed)
        state["pushed"] = fingerprint
        state["pushedAt"] = time
        state["etag"] = ""
    }

    struct Problem: Error { let message: String }

    private func request(_ relay: String, _ method: String, _ keys: PairKeys, _ headers: [String: String], _ body: Data?) throws -> (Int, Data, String?) {
        guard let url = URL(string: relay) else { throw Problem(message: "bad relay") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue(keys.box, forHTTPHeaderField: "X-Derp-Box")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = body
        var result: (Int, Data, String?)?
        var failure: Error?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { failure = error } else if let http = response as? HTTPURLResponse {
                result = (http.statusCode, data ?? Data(), http.value(forHTTPHeaderField: "ETag"))
            }
            done.signal()
        }.resume()
        done.wait()
        if let failure { throw failure }
        guard let result else { throw Problem(message: "no answer") }
        if result.0 != 304 && !(200..<300).contains(result.0) {
            let why = (try? JSONSerialization.jsonObject(with: result.1) as? [String: Any])?["error"] as? String
            throw Problem(message: "relay \(result.0)" + (why.map { ": \($0)" } ?? ""))
        }
        return result
    }

    // ── Kept here ──────────────────────────────────────────────────────────

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: file), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let secret = Keychain.get("pairing.secret") {
            state = json
            keys = PairKeys(secret: secret)
        }
        publish()
    }

    private func save() {
        if let state, let data = try? JSONSerialization.data(withJSONObject: state) {
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        publish()
    }

    private func deviceNames() -> String {
        let devices = state?["devices"] as? [String: [String: Any]] ?? [:]
        return devices.values.compactMap { $0["name"] as? String }.joined(separator: " and ")
    }

    /// What the Your devices page shows.
    private func publish() {
        guard let state else { summary = ["paired": false]; return }
        let devices = (state["devices"] as? [String: Any] ?? [:]).values.map { $0 }
        summary = ["paired": true, "devices": devices, "syncedAt": state["syncedAt"] ?? 0, "problem": state["problem"] ?? ""]
    }

    static func isWeb(_ url: String) -> Bool {
        url.count <= maxText && url.range(of: "^https?://\\S+$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func origin(_ url: String) -> String? {
        guard let c = URLComponents(string: url), let scheme = c.scheme, scheme == "http" || scheme == "https", let host = c.host, !host.isEmpty else { return nil }
        return "\(scheme)://\(host)" + (c.port.map { ":\($0)" } ?? "")
    }

    static func loginKey(_ origin: String, _ realm: String, _ username: String) -> String { "\(origin)\n\(realm)\n\(username)" }
}
