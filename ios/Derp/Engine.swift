import Foundation

// Doodle's DuckDuckGo settings: links and addresses in Derp's colors, light
// and dark (DuckDuckGo stays light unless asked); they mark its pages as
// Doodle's, for Doodle's look. The same as desktop Derp's (DDG_LIGHT and
// DDG_DARK in src/features/DerpDoodle.sys.mjs) and Derp for Android's.
let doodleLight = "k9=2f6feb&kaa=7a52c7&kx=0f8a74"
let doodleDark = "kae=d&k9=86b1ff&kaa=a98bf0&kx=34c6a0"
let doodleDuck = "https://duckduckgo.com/?q=%s&\(doodleLight)&kt=system-ui&ka=system-ui"

/// Where Doodle's results come from: picked when you first start Derp (right
/// after making your dork), or later in ⋯ → Search engine.
enum DoodleResults: String, CaseIterable {
    case google = "GOOGLE", duckduckgo = "DUCKDUCKGO"

    var label: String { self == .google ? "Google" : "DuckDuckGo" }

    static var current: DoodleResults {
        get { DoodleResults(rawValue: Prefs.store.string(forKey: "doodle") ?? "") ?? .google }
        set { Prefs.set("doodle", newValue.rawValue) }
    }

    /// Whether you've picked Doodle's results (when first starting Derp).
    static var picked: Bool { Prefs.store.string(forKey: "doodle") != nil }
}

enum Engine: String, CaseIterable {
    // Google's results, marked doodle=1 for Doodle's look, or DuckDuckGo's,
    // as you pick (desktop Derp's Doodle is in config/policies.json).
    case doodle = "DOODLE", google = "GOOGLE", duckduckgo = "DUCKDUCKGO", bing = "BING", startpage = "STARTPAGE", ecosia = "ECOSIA"

    var label: String {
        switch self {
        case .doodle: return "Doodle"
        case .google: return "Google"
        case .duckduckgo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .startpage: return "Startpage"
        case .ecosia: return "Ecosia"
        }
    }

    var template: String {
        switch self {
        case .doodle: return "https://www.google.com/search?q=%s&doodle=1"
        case .google: return "https://www.google.com/search?q=%s"
        case .duckduckgo: return "https://duckduckgo.com/?q=%s"
        case .bing: return "https://www.bing.com/search?q=%s"
        case .startpage: return "https://www.startpage.com/do/search?q=%s"
        case .ecosia: return "https://www.ecosia.org/search?q=%s"
        }
    }

    static var current: Engine {
        get { Engine(rawValue: Prefs.store.string(forKey: "engine") ?? "") ?? .doodle }
        set { Prefs.set("engine", newValue.rawValue) }
    }

    /// What the menu says: "Doodle (DuckDuckGo)".
    static var label: String {
        current == .doodle ? "Doodle (\(DoodleResults.current.label))" : current.label
    }

    /// A search for [encoded] (already URL-encoded); Doodle's gets [doodle]'s
    /// results, on DuckDuckGo dark or not as Derp is ([dark]).
    func search(_ encoded: String, doodle: DoodleResults = .google, dark: Bool = false) -> String {
        if self == .doodle && doodle == .duckduckgo {
            let url = doodleDuck.replacingOccurrences(of: "%s", with: encoded)
            return dark ? url.replacingOccurrences(of: doodleLight, with: doodleDark) : url
        }
        return template.replacingOccurrences(of: "%s", with: encoded)
    }

    /// The words searched for, if [url] is a search on this engine.
    func terms(_ url: String) -> String? {
        let templates = self == .doodle ? [template, doodleDuck] : [template]
        guard templates.contains(where: { url.hasPrefix($0.components(separatedBy: "%s")[0]) }) else { return nil }
        let q = URLComponents(string: url)?.queryItems?.first { $0.name == "q" }?.value?.trimmingCharacters(in: .whitespaces)
        return (q?.isEmpty ?? true) ? nil : q
    }
}

enum Address {
    /// Encodes text for a search URL's query.
    static func encode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    /// Text from the address bar: a web address, or a search.
    static func toURL(_ input: String, engine: Engine = .current, doodle: DoodleResults = .current, dark: Bool = false) -> String {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: "^(https?|about|file|data|view-source|derp):", options: [.regularExpression, .caseInsensitive]) != nil {
            return text
        }
        if !text.contains(" "), text.range(of: "^localhost(:\\d+)?(/.*)?$", options: .regularExpression) != nil {
            return "http://" + text
        }
        if !text.contains(" "), text.range(of: "^[^/\\s]+\\.[a-zA-Z]{2,}(:\\d+)?(/.*)?$", options: .regularExpression) != nil {
            return "https://" + text
        }
        return engine.search(encode(text), doodle: doodle, dark: dark)
    }

    /// With DuckDuckGo picked for Doodle, a Doodle search on Google (from
    /// Doodle's home page, say) goes to DuckDuckGo instead.
    static func doodleOnDuck(_ url: URL, doodle: DoodleResults = .current, dark: Bool = false) -> String? {
        guard doodle == .duckduckgo, url.host == "www.google.com", url.path == "/search" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.contains(where: { $0.name == "doodle" && $0.value == "1" }) else { return nil }
        let q = items.first { $0.name == "q" }?.value ?? ""
        return Engine.doodle.search(encode(q), doodle: doodle, dark: dark)
    }

    static func isWeb(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.hasPrefix("https://") || lower.hasPrefix("http://")
    }

    static func host(_ url: String) -> String? {
        guard let host = URL(string: url)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Tracking parameters in links (utm_source, fbclid…), stripped before a
    /// page loads, as Derp for Android's engine does.
    static let trackers: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "mc_cid", "mc_eid", "yclid", "_hsenc", "_hsmi",
        "mkt_tok", "igshid", "si", "oly_anon_id", "oly_enc_id", "vero_id", "__s", "rb_clickid", "s_cid", "ml_subscriber",
        "ml_subscriber_hash", "twclid", "ttclid",
    ]

    /// [url] without tracking parameters, or nil if it had none.
    static func stripped(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = components.queryItems, !items.isEmpty else { return nil }
        // YouTube's "si" is a tracker; elsewhere it may mean something.
        let host = url.host ?? ""
        let kept = items.filter { item in
            let name = item.name.lowercased()
            if name.hasPrefix("utm_") { return false }
            if name == "si" { return !(host.hasSuffix("youtube.com") || host.hasSuffix("youtu.be") || host.hasSuffix("spotify.com")) }
            return !trackers.contains(name)
        }
        guard kept.count != items.count else { return nil }
        components.queryItems = kept.isEmpty ? nil : kept
        return components.url
    }
}
