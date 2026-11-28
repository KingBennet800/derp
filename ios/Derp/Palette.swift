import UIKit

/// Derp's settings, kept on this device (in LiveContainer, in Derp's data container).
enum Prefs {
    static let store = UserDefaults.standard

    static func bool(_ key: String, _ fallback: Bool = false) -> Bool {
        store.object(forKey: key) == nil ? fallback : store.bool(forKey: key)
    }

    static func set(_ key: String, _ value: Any?) {
        store.set(value, forKey: key)
    }
}

extension UIColor {
    /// #rrggbb or #aarrggbb (Android's order, for the tables copied from it).
    convenience init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        let value = UInt64(text, radix: 16) ?? 0
        let alpha = text.count == 8 ? CGFloat((value >> 24) & 0xFF) / 255 : 1
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }

    var hex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

/// Derp's colors: desktop Derp's theme tokens (theme/derp-theme.css), for
/// light, dark and private tabs, in the look you pick (⋯ → Look). The same
/// as Derp for Android's (Ui.kt).
struct Palette: Equatable {
    /// Behind the tab strip.
    var frame: UIColor
    var toolbar: UIColor
    /// The address bar while you type in it.
    var fieldFocus: UIColor
    /// Menus and cards.
    var box: UIColor
    /// Behind pages, until they paint.
    var content: UIColor
    var text: UIColor
    var dim: UIColor
    var icon: UIColor
    /// Hairlines in the toolbar and tab strip.
    var line: UIColor
    /// The hairline between the toolbar and the page.
    var contentLine: UIColor
    var accent: UIColor
    var dark: Bool

    /// Pressed buttons and rows: the text color, faintly.
    var press: UIColor { text.withAlphaComponent(0.14) }
    /// Text on the accent color.
    var onAccent: UIColor { dark ? UIColor(hex: "#0F1115") : .white }

    static let light = Palette(
        frame: UIColor(hex: "#ECECEE"), toolbar: UIColor(hex: "#FAFAFA"), fieldFocus: UIColor(hex: "#FFFFFF"), box: UIColor(hex: "#FFFFFF"),
        content: UIColor(hex: "#FFFFFF"), text: UIColor(hex: "#1D1D1F"), dim: UIColor(hex: "#6E6E73"), icon: UIColor(hex: "#5A5A60"),
        line: UIColor(hex: "#D8D8DC"), contentLine: UIColor(hex: "#E0E0E4"), accent: UIColor(hex: "#2F6FEB"), dark: false
    )
    static let darkMode = Palette(
        frame: UIColor(hex: "#1B1B1C"), toolbar: UIColor(hex: "#272728"), fieldFocus: UIColor(hex: "#303032"), box: UIColor(hex: "#26272A"),
        content: UIColor(hex: "#1E1E1F"), text: UIColor(hex: "#ECECEC"), dim: UIColor(hex: "#A3A3A6"), icon: UIColor(hex: "#B4B4B8"),
        line: UIColor(hex: "#3A3A3C"), contentLine: UIColor(hex: "#333335"), accent: UIColor(hex: "#86B1FF"), dark: true
    )
    /// Private tabs are always dark, with a violet tint so they stand out.
    static let privateTabs = Palette(
        frame: UIColor(hex: "#1C1925"), toolbar: UIColor(hex: "#2A2633"), fieldFocus: UIColor(hex: "#343040"), box: UIColor(hex: "#2A2633"),
        content: UIColor(hex: "#1F1C27"), text: UIColor(hex: "#ECEBF2"), dim: UIColor(hex: "#BDB8CC"), icon: UIColor(hex: "#CBC5DA"),
        line: UIColor(hex: "#3D3848"), contentLine: UIColor(hex: "#3A3546"), accent: UIColor(hex: "#B8A4FF"), dark: true
    )

    static func of(dark: Bool, private isPrivate: Bool) -> Palette {
        isPrivate ? privateTabs : Look.current.palette(dark: dark)
    }
}

/// Looks (⋯ → Look): Derp's colors, the same as desktop Derp's (the derp.look
/// pref there; theme/derp-theme.css) and Derp for Android's.
enum Look: String, CaseIterable {
    case derp = "DERP", grape = "GRAPE", mint = "MINT", peach = "PEACH", bubblegum = "BUBBLEGUM", graphite = "GRAPHITE"

    var label: String {
        switch self {
        case .derp: return "Derp (blue)"
        case .grape: return "Grape"
        case .mint: return "Mint"
        case .peach: return "Peach"
        case .bubblegum: return "Bubblegum"
        case .graphite: return "Graphite"
        }
    }

    private var light: [String: String] {
        switch self {
        case .derp: return [:]
        case .grape: return ["accent": "#7C4DFF", "frame": "#E7DEF7", "toolbar": "#F8F4FF", "fieldFocus": "#FFFFFF", "line": "#D4C7EC", "contentLine": "#DDD3F0", "content": "#FFFFFF"]
        case .mint: return ["accent": "#0D9A80", "frame": "#DBEFE7", "toolbar": "#F4FBF8", "fieldFocus": "#FFFFFF", "line": "#C3E0D4", "contentLine": "#CFE6DC", "content": "#FFFFFF"]
        case .peach: return ["accent": "#E2540A", "frame": "#F8E6D9", "toolbar": "#FFF8F2", "fieldFocus": "#FFFFFF", "line": "#ECD2BF", "contentLine": "#F1DCCC", "content": "#FFFFFF"]
        case .bubblegum: return ["accent": "#D93A74", "frame": "#F8E1EC", "toolbar": "#FFF6FA", "fieldFocus": "#FFFFFF", "line": "#ECC9D9", "contentLine": "#F1D4E1", "content": "#FFFFFF"]
        case .graphite: return ["accent": "#3A3A3C"]
        }
    }

    private var dark: [String: String] {
        switch self {
        case .derp: return [:]
        case .grape: return ["accent": "#B8A4FF", "frame": "#1E1829", "toolbar": "#2A2336", "fieldFocus": "#352C44", "line": "#3F3550", "contentLine": "#382F48", "content": "#201B28"]
        case .mint: return ["accent": "#4FD8B8", "frame": "#15211D", "toolbar": "#1F2D28", "fieldFocus": "#283A33", "line": "#31453D", "contentLine": "#2D3F38", "content": "#1A2320"]
        case .peach: return ["accent": "#FFA56B", "frame": "#241B15", "toolbar": "#2F251E", "fieldFocus": "#3A2E26", "line": "#45372D", "contentLine": "#3F3229", "content": "#221B17"]
        case .bubblegum: return ["accent": "#FF8FB6", "frame": "#25171E", "toolbar": "#302129", "fieldFocus": "#3B2A33", "line": "#47323D", "contentLine": "#403039", "content": "#22191E"]
        case .graphite: return ["accent": "#D4D4D8"]
        }
    }

    /// The accent, light and dark, as #rrggbb (for Derp's pages).
    var accents: (String, String) { (light["accent"] ?? "#2F6FEB", dark["accent"] ?? "#86B1FF") }

    func palette(dark night: Bool) -> Palette {
        var base = night ? Palette.darkMode : Palette.light
        let colors = night ? dark : light
        func c(_ name: String, _ fallback: UIColor) -> UIColor { colors[name].map { UIColor(hex: $0) } ?? fallback }
        base.frame = c("frame", base.frame)
        base.toolbar = c("toolbar", base.toolbar)
        base.fieldFocus = c("fieldFocus", base.fieldFocus)
        base.content = c("content", base.content)
        base.line = c("line", base.line)
        base.contentLine = c("contentLine", base.contentLine)
        base.accent = c("accent", base.accent)
        return base
    }

    static var current: Look {
        get { Look(rawValue: Prefs.store.string(forKey: "look") ?? "") ?? .derp }
        set { Prefs.set("look", newValue.rawValue) }
    }
}

/// Derp's icons: desktop Derp's toolbar icons and Derp for Android's, as templates.
enum Icon {
    static func named(_ name: String) -> UIImage? {
        UIImage(named: "icon-" + name)?.withRenderingMode(.alwaysTemplate)
    }

    static func art(_ name: String) -> UIImage? {
        UIImage(named: "art-" + name)
    }
}

extension UIFont {
    static func medium(_ size: CGFloat) -> UIFont { .systemFont(ofSize: size, weight: .medium) }
}
