import UIKit

/// Just for fun: joke settings, all off until you turn them on (⋯ → Just for
/// fun). Desktop Derp and Derp for Android have the same ones.
enum Gag: String, CaseIterable {
    case duck, pet, snail, peekaboo, party, sleepy, power, hiccups, ghosts, rainbow, seasons, downloadDuck

    var title: String {
        switch self {
        case .duck: return "Duck mode"
        case .pet: return "Dork pet"
        case .snail: return "Snail mode"
        case .peekaboo: return "Peekaboo"
        case .party: return "Party mode"
        case .sleepy: return "Sleepy tabs"
        case .power: return "Power typing"
        case .hiccups: return "Hiccups"
        case .ghosts: return "Tab ghosts"
        case .rainbow: return "Rainbow mode"
        case .seasons: return "Seasons"
        case .downloadDuck: return "Download duck"
        }
    }

    var about: String {
        switch self {
        case .duck: return "1 in 10 times you press Go in the address bar, a duck eats what you typed."
        case .pet: return "Your dork becomes a pet: it naps while you’re away and earns new outfits the more days you spend together."
        case .snail: return "When a page takes its time, a snail crawls along the loading bar."
        case .peekaboo: return "Now and then, your dork peeks up when you open a new tab."
        case .party: return "Confetti when you bookmark a page."
        case .sleepy: return "Tabs Memory Saver has put to sleep snore. 💤"
        case .power: return "Sparks fly from the address bar as you type."
        case .hiccups: return "Now and then, a page gets the hiccups. Hic!"
        case .ghosts: return "A tab you close floats away as a little ghost."
        case .rainbow: return "The loading bar is a rainbow."
        case .seasons: return "Now and then the season drifts down: snow, blossoms, sunshine or leaves, with hearts for Valentine’s Day and pumpkins for Halloween."
        case .downloadDuck: return "A duck carries each download across the toolbar."
        }
    }

    var on: Bool {
        get { Prefs.bool("gag." + rawValue) }
        nonmutating set { Prefs.set("gag." + rawValue, newValue) }
    }

    /// Whether the gags may move: not with Reduce Motion on (or in the tests).
    static var motion: Bool {
        !UIAccessibility.isReduceMotionEnabled && !ProcessInfo.processInfo.arguments.contains("-derpStill")
    }
}

/// Dork pet: each day you use Derp is a day together, and some days unlock an
/// outfit for your dork. The same outfits as desktop Derp (UNLOCKS in
/// DerpDork.sys.mjs, which dork-art.js has too) and Derp for Android.
enum Pet {
    struct Unlock: Equatable {
        let part: String
        let value: String
        let days: Int
        let what: String
    }

    static let unlocks = [
        Unlock(part: "hair", value: "flower", days: 3, what: "a flower"),
        Unlock(part: "extras", value: "bowtie", days: 7, what: "a bow tie"),
        Unlock(part: "hair", value: "crown", days: 14, what: "a crown"),
        Unlock(part: "hair", value: "wizard", days: 30, what: "a wizard hat"),
        Unlock(part: "extras", value: "monocle", days: 45, what: "a monocle"),
        Unlock(part: "backdrop", value: "stars", days: 60, what: "a starry night"),
    ]

    /// Your days together, or nil if your dork isn't a pet.
    static var days: Int? { Gag.pet.on ? Prefs.store.integer(forKey: "petDays") : nil }

    static func dayString(_ date: Date) -> String {
        let format = DateFormatter()
        format.calendar = Calendar(identifier: .gregorian)
        format.dateFormat = "yyyy-MM-dd"
        return format.string(from: date)
    }

    /// Today counts as a day together (once); an outfit it just earned, if any.
    static func count(today: Date = Date(), store: UserDefaults = Prefs.store) -> Unlock? {
        guard Gag.pet.on else { return nil }
        var days = store.integer(forKey: "petDays")
        let day = dayString(today)
        if store.string(forKey: "petLastDay") != day {
            days += 1
            store.set(day, forKey: "petLastDay")
            store.set(days, forKey: "petDays")
        }
        let shown = store.integer(forKey: "petShown")
        let earned = unlocks.filter { $0.days > shown && $0.days <= days }
        guard let last = earned.last else { return nil }
        store.set(days, forKey: "petShown")
        return last
    }
}

/// What's new: after an update brings something new, Derp shows what came
/// with it (src/features/whatsnew.json, which desktop Derp and Derp for
/// Android show too), each with where to find it.
enum WhatsNew {
    struct Item { let icon: String; let title: String; let text: String; let where_: String? }
    struct Release { let version: String; let title: String; let items: [Item] }

    /// Whether version [a] (like "2.1.0") is newer than [b].
    static func newer(_ a: String, _ b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    static func releases(_ data: Data? = Bundle.main.url(forResource: "whatsnew", withExtension: "json", subdirectory: "derp").flatMap { try? Data(contentsOf: $0) }) -> [Release] {
        guard let data, let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list.map { release in
            Release(
                version: release["version"] as? String ?? "",
                title: release["title"] as? String ?? "",
                items: (release["items"] as? [[String: Any]] ?? []).map {
                    // Where to find it: iOS's own words if given, else Android's (the same menus).
                    Item(icon: $0["icon"] as? String ?? "", title: $0["title"] as? String ?? "", text: $0["text"] as? String ?? "",
                         where_: ($0["ios"] as? String ?? $0["android"] as? String).map { $0.replacingOccurrences(of: "⋮", with: "⋯") })
                }
            )
        }
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// This version's news (About Derp → What's new).
    static func current(_ all: [Release] = releases(), version: String = version) -> [Release] {
        Array(all.filter { !newer($0.version, version) }.prefix(1))
    }

    /// What's new since you last looked, if anything; remembers you've looked.
    /// [made]: whether you've made your dork (if not, Derp is new to you).
    static func since(made: Bool, all: [Release] = releases(), version: String = version, store: UserDefaults = Prefs.store) -> [Release] {
        let seen = store.string(forKey: "whatsNewSeen")
        store.set(version, forKey: "whatsNewSeen")
        guard made, let seen, newer(version, seen) else { return [] }
        return all.filter { newer($0.version, seen) && !newer($0.version, version) }
    }
}

/// Seasons: what drifts down on a given day, the same as desktop Derp
/// (seasonOf in DerpFun.sys.mjs) and Derp for Android.
enum Seasons {
    static func of(_ date: Date) -> [String] {
        let parts = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: date)
        let month = parts.month ?? 1, day = parts.day ?? 1
        switch true {
        case month == 2 && (7...14).contains(day): return ["heart"]
        case month == 10 && day >= 24: return ["pumpkin", "leaf", "redLeaf"]
        case month == 12 || month <= 2: return ["snow"]
        case month <= 5: return ["blossom"]
        case month <= 8: return ["sun"]
        default: return ["leaf", "redLeaf"]
        }
    }

    static func art(_ date: Date = Date()) -> [UIImage] {
        of(date).compactMap { UIImage(named: "season-" + $0) }
    }
}

/// Your dork, Derp's account: a cartoon you design, kept only on this device
/// (in LiveContainer, in this data container). Derp's pages draw and edit it
/// with the same code as desktop Derp, and send it here as a picture.
final class Dork {
    private let folder: URL
    private var cached: UIImage?

    init(directory: URL) {
        folder = directory
    }

    var json: [String: Any]? {
        Prefs.store.string(forKey: "dork").flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    var name: String {
        let name = (json?["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Your dork" : name
    }

    /// Set once you've pressed "That's me!"; until then Derp opens with the editor.
    var made: Bool {
        get { Prefs.bool("made") }
        set {
            Prefs.set("made", newValue)
            NotificationCenter.default.post(name: Dork.changed, object: nil)
        }
    }

    static let changed = Notification.Name("DerpDorkChanged")

    /// [png] and [sleepy] (eyes shut, for when your dork pet naps) come drawn by the page.
    func save(_ dork: [String: Any], png: Data?, sleepy: Data?) {
        if let data = try? JSONSerialization.data(withJSONObject: dork) {
            Prefs.set("dork", String(data: data, encoding: .utf8))
        }
        if let png { try? png.write(to: folder.appendingPathComponent("dork.png"), options: .atomic) }
        if let sleepy { try? sleepy.write(to: folder.appendingPathComponent("dork-sleepy.png"), options: .atomic) }
        Prefs.set("dorkSleepy", sleepy != nil)
        cached = nil
        NotificationCenter.default.post(name: Dork.changed, object: nil)
    }

    var hasSleepy: Bool { Prefs.bool("dorkSleepy") }

    /// Your dork, or nil before you have one.
    var picture: UIImage? {
        if cached == nil { cached = UIImage(contentsOfFile: folder.appendingPathComponent("dork.png").path) }
        return cached
    }

    var sleepy: UIImage? { UIImage(contentsOfFile: folder.appendingPathComponent("dork-sleepy.png").path) }
}
