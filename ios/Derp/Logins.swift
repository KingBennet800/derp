import Foundation
import Security

/// Secrets in the iOS keychain: passwords and the pairing secret. (In
/// LiveContainer, it gives each of Derp's data containers its own share of
/// the keychain.)
enum Keychain {
    private static let service = "io.github.kingbennet800.derp"

    @discardableResult
    static func set(_ value: Data?, for account: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard let value else { return true }
        var add = query
        add[kSecValueData as String] = value
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess { NSLog("Derp: keychain error %d", status) }
        return status == errSecSuccess
    }

    static func get(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess ? item as? Data : nil
    }
}

/// Saved passwords. Derp offers to save one when you sign in somewhere and
/// fills it in next time (logins.js). The site and username are kept in the
/// Library's database; each password is kept in the keychain. Like Derp for
/// Android's (Logins.kt), on this device only, unless you pair your devices.
final class Logins {
    struct Login {
        let guid: String
        let origin: String
        let formAction: String?
        let realm: String?
        let username: String
    }

    /// For syncing with your other devices.
    struct Synced: Equatable {
        let origin: String
        let realm: String
        let form: String
        let username: String
        let password: String
    }

    private let db: Database
    var changed: (() -> Void)?

    init(library: Library) {
        db = library.db
    }

    /// Whether Derp offers to save a password when you sign in somewhere.
    var offerToSave: Bool {
        get { Prefs.bool("savePasswords", true) }
        set { Prefs.set("savePasswords", newValue) }
    }

    private func rows(_ clause: String = "", _ args: [Any?] = []) -> [Login] {
        db.rows("SELECT guid, origin, form_action, realm, username FROM logins \(clause)", args).map {
            Login(guid: $0[0] as? String ?? "", origin: $0[1] as? String ?? "", formAction: $0[2] as? String, realm: $0[3] as? String, username: $0[4] as? String ?? "")
        }
    }

    func password(_ guid: String) -> String? {
        Keychain.get("login." + guid).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// The logins saved for [host] (and its subdomains, or the site it's part of).
    func forSite(_ host: String) -> [Login] {
        rows().filter { Logins.matches($0.origin, host) }
    }

    /// Sites and usernames (not passwords), optionally only those matching [query].
    func list(query: String = "") -> [[String: Any]] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return rows()
            .filter { q.isEmpty || $0.origin.lowercased().contains(q) || $0.username.lowercased().contains(q) }
            .sorted { (Logins.host($0.origin), $0.username) < (Logins.host($1.origin), $1.username) }
            .map { ["guid": $0.guid, "origin": $0.origin, "username": $0.username] }
    }

    func remove(_ guid: String) {
        db.run("DELETE FROM logins WHERE guid = ?", [guid])
        Keychain.set(nil, for: "login." + guid)
    }

    func used(_ guid: String) {
        db.run("UPDATE logins SET used = ? WHERE guid = ?", [now(), guid])
    }

    /// What saving [password] for [username] on [origin] would do: nil if
    /// it's saved already, "update" if the password changed, else "save".
    func offer(origin: String, username: String, password: String) -> String? {
        guard let existing = rows("WHERE origin = ? AND username = ?", [origin, username]).first else { return "save" }
        return self.password(existing.guid) == password ? nil : "update"
    }

    /// Updates the login with [guid] (or this site and username), or adds it.
    func save(guid: String? = nil, origin: String, formAction: String?, realm: String?, username: String, password: String) {
        let time = now()
        let target = guid.flatMap { g in rows("WHERE guid = ?", [g]).first?.guid }
            ?? rows("WHERE origin = ? AND username = ?", [origin, username]).first?.guid
        let id = target ?? "{\(UUID().uuidString.lowercased())}"
        if target != nil {
            db.run("UPDATE logins SET origin = ?, form_action = ?, realm = ?, username = ?, used = ? WHERE guid = ?", [origin, formAction, realm, username, time, id])
        } else {
            db.run("INSERT INTO logins (guid, origin, form_action, realm, username, created, used) VALUES (?, ?, ?, ?, ?, ?, ?)", [id, origin, formAction, realm, username, time, time])
        }
        Keychain.set(Data(password.utf8), for: "login." + id)
    }

    /// Adds the logins you don't have yet, and updates changed passwords.
    func importLogins(_ logins: [Imports.Login]) -> (added: Int, updated: Int) {
        var added = 0, updated = 0
        for login in logins {
            let existing = rows("WHERE origin = ? AND username = ?", [login.origin, login.username]).first
            if existing == nil {
                added += 1
            } else if password(existing!.guid) != login.password {
                updated += 1
            } else {
                continue
            }
            save(guid: existing?.guid, origin: login.origin, formAction: nil, realm: nil, username: login.username, password: login.password)
        }
        return (added, updated)
    }

    func count() -> Int { Int(db.rows("SELECT COUNT(*) FROM logins").first?[0] as? Int64 ?? 0) }

    // ── For syncing ────────────────────────────────────────────────────────

    func all() -> [Synced] {
        rows().compactMap { row in
            password(row.guid).map { Synced(origin: row.origin, realm: row.realm ?? "", form: row.formAction ?? "", username: row.username, password: $0) }
        }
    }

    /// Saves a password from another device (new, or a changed one).
    func put(_ login: Synced) {
        let existing = rows("WHERE origin = ? AND username = ?", [login.origin, login.username]).first { ($0.realm ?? "") == login.realm }
        save(guid: existing?.guid, origin: login.origin, formAction: login.form.isEmpty ? nil : login.form, realm: login.realm.isEmpty ? nil : login.realm, username: login.username, password: login.password)
    }

    /// Removes a password another device deleted.
    func delete(origin: String, realm: String, username: String) {
        for row in rows("WHERE origin = ? AND username = ?", [origin, username]) where (row.realm ?? "") == realm {
            remove(row.guid)
        }
    }

    static func host(_ origin: String) -> String { URL(string: origin)?.host ?? origin }

    /// Whether a login saved for [origin] belongs on [domain] (or its subdomains).
    static func matches(_ origin: String, _ domain: String) -> Bool {
        func bare(_ s: String) -> String { s.hasPrefix("www.") ? String(s.dropFirst(4)) : s }
        let h = bare(host(origin).lowercased())
        let d = bare(domain.lowercased())
        return h == d || h.hasSuffix("." + d) || d.hasSuffix("." + h)
    }
}

/// Reading other browsers' exports, for Import data: a bookmarks .html file
/// and a passwords .csv file. The same as Derp for Android's (Imports.kt).
enum Imports {
    struct Bookmark: Equatable { let url: String; let title: String }
    struct Login: Equatable { let origin: String; let username: String; let password: String }

    private static let anchor = try! NSRegularExpression(pattern: "<a\\s[^>]*?href\\s*=\\s*\"([^\"]*)\"[^>]*>(.*?)</a\\s*>", options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let tags = try! NSRegularExpression(pattern: "<[^>]*>")

    /// Every web link in a bookmarks file, folders flattened, each address once.
    static func bookmarks(_ html: String) -> [Bookmark] {
        let ns = html as NSString
        var seen = Set<String>()
        var out: [Bookmark] = []
        for match in anchor.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let url = unescape(ns.substring(with: match.range(at: 1))).trimmingCharacters(in: .whitespacesAndNewlines)
            guard Address.isWeb(url), !seen.contains(url) else { continue }
            seen.insert(url)
            let inner = ns.substring(with: match.range(at: 2))
            let plain = tags.stringByReplacingMatches(in: inner, range: NSRange(location: 0, length: (inner as NSString).length), withTemplate: "")
            let title = unescape(plain).trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(Bookmark(url: url, title: title.isEmpty ? url : title))
        }
        return out
    }

    /// The saved logins in a passwords file, for websites (not apps).
    static func logins(_ text: String) -> [Login] {
        let table = csv(text)
        guard let head = table.first?.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) else { return [] }
        func column(_ names: String...) -> Int { head.firstIndex { names.contains($0) } ?? -1 }
        let site = column("url", "origin", "website", "login_uri")
        let user = column("username", "login", "login_username", "user")
        let pass = column("password", "login_password")
        guard site >= 0, pass >= 0 else { return [] }
        var out: [Login] = []
        for row in table.dropFirst() {
            func cell(_ i: Int) -> String { i >= 0 && i < row.count ? row[i] : "" }
            guard let origin = origin(cell(site)) else { continue }
            let password = cell(pass)
            guard !password.isEmpty else { continue }
            let login = Login(origin: origin, username: cell(user), password: password)
            if !out.contains(login) { out.append(login) }
        }
        return out
    }

    /// A web address's origin (https://example.com:8443), or nil for anything else.
    static func origin(_ url: String) -> String? {
        guard let components = URLComponents(string: url.trimmingCharacters(in: .whitespaces)),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        return "\(scheme)://\(host)" + (components.port.map { ":\($0)" } ?? "")
    }

    /// RFC 4180 CSV: quoted fields may hold commas, quotes ("") and line breaks.
    static func csv(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        let chars = Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": quoted = true
                case ",":
                    row.append(field)
                    field = ""
                case "\r": break
                case "\n", "\r\n":
                    row.append(field)
                    field = ""
                    rows.append(row)
                    row = []
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    private static let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
    private static let entity = try! NSRegularExpression(pattern: "&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);")

    /// HTML character references (&amp; &#39; &#x2014; …) back to text.
    static func unescape(_ text: String) -> String {
        let ns = text as NSString
        var out = ""
        var last = 0
        for match in entity.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let name = ns.substring(with: match.range(at: 1))
            var replacement: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                replacement = UInt32(name.dropFirst(2), radix: 16).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
            } else if name.hasPrefix("#") {
                replacement = UInt32(name.dropFirst(), radix: 10).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
            } else {
                replacement = named[name.lowercased()]
            }
            out += replacement ?? ns.substring(with: match.range)
            last = match.range.location + match.range.length
        }
        return out + ns.substring(from: last)
    }
}
