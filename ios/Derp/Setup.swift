import Foundation
import UIKit

/// Where Derp is running, and what that lets it do.
///
/// Derp for iOS is sideloaded, either installed on its own (SideStore or
/// AltStore sign it with your Apple ID) or run inside LiveContainer, which
/// runs apps without installing them. Each gives Derp different things:
///
/// - Installed on its own, iOS knows Derp: it has its own icon, its own
///   derp:// links, Home Screen quick actions, its own folder in Files, more
///   than one window on an iPad, and SideStore or AltStore refreshes it.
/// - In LiveContainer, iOS only knows LiveContainer: links come in through
///   LiveContainer (share a link to LiveContainer, pick Derp), Derp's files
///   are inside LiveContainer's, and LiveContainer can give Derp several data
///   containers, which Derp shows as profiles. LiveContainer can also run Derp
///   in one of its multitasking windows.
struct Setup: Equatable {
    enum Kind: Equatable {
        /// Installed on its own (SideStore, AltStore, or anything else that signs apps).
        case installed
        /// Run inside LiveContainer.
        case liveContainer
        /// Xcode's simulator (Derp's tests).
        case simulator
    }

    let kind: Kind
    /// Installed on its own: the app that keeps Derp signed, if Derp can tell.
    let store: String?
    /// LiveContainer: the name of Derp's data container ("Work"), if it has one.
    let containerName: String?
    /// LiveContainer: the data container's folder, to open Derp in it again.
    let containerFolder: String?
    /// LiveContainer: Derp is in one of its multitasking windows.
    let multitask: Bool
    /// LiveContainer: the URL scheme of the LiveContainer running Derp ("livecontainer").
    let host: String
    /// Derp's app folder (LiveContainer finds apps by it).
    let bundleFolder: String
    /// When Derp's signature (installed) or LiveContainer's runs out.
    let signedUntil: Date?
    /// Where Derp's Documents folder is, as Files shows it, if Files shows it.
    let filesPath: [String]?

    var inLiveContainer: Bool { kind == .liveContainer }

    /// Only an installed Derp has a derp:// scheme, quick actions and windows of its own.
    var ownsLinks: Bool { kind != .liveContainer }

    /// Each LiveContainer data container is its own Derp, with its own dork,
    /// tabs, bookmarks and passwords: a profile.
    var profile: String? {
        guard inLiveContainer, let name = containerName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        // LiveContainer names a container after its folder until you rename it.
        return name == containerFolder ? nil : name
    }

    /// A link that opens Derp (at [url], if given) from the Home Screen or another app.
    func launchLink(opening url: URL? = nil) -> URL? {
        // Values are encoded in full (& and = too), so the link survives any parser.
        if inLiveContainer {
            var query = "bundle-name=" + Address.encode(bundleFolder)
            if let folder = containerFolder { query += "&container-folder-name=" + Address.encode(folder) }
            if let url { query += "&open-url=" + Address.encode(Data(url.absoluteString.utf8).base64EncodedString()) }
            return URL(string: "\(host)://livecontainer-launch?" + query)
        }
        guard let url else { return URL(string: "derp://") }
        return URL(string: "derp://open?url=" + Address.encode(url.absoluteString))
    }

    /// How you open a link from another app in Derp, here.
    var linksHelp: String {
        switch kind {
        case .liveContainer:
            return "Share the link from any app, choose LiveContainer, then choose Derp. Or open LiveContainer, tap the link button at the top of its Apps tab, and paste the link."
        default:
            return "Derp has its own derp:// links: derp://open?url= followed by a web address opens it in Derp, from the Shortcuts app or a link. Long-press Derp’s icon for a new tab, a private tab or a search."
        }
    }

    /// What About Derp says about where Derp runs.
    var summary: String {
        var lines: [String] = []
        switch kind {
        case .liveContainer:
            var line = "Running in LiveContainer"
            if let profile { line += ", in the “\(profile)” container" }
            if multitask { line += ", in a multitasking window" }
            lines.append(line + ".")
            if let signedUntil { lines.append("LiveContainer is signed until \(Setup.day(signedUntil)).") }
        case .installed:
            lines.append(store.map { "Installed with \($0)." } ?? "Installed on its own.")
            if let signedUntil { lines.append("Signed until \(Setup.day(signedUntil)).") }
        case .simulator:
            lines.append("Running in the simulator.")
        }
        return lines.joined(separator: " ")
    }

    /// Where downloads go, in words.
    var downloadsHelp: String {
        if let filesPath { return "In the Files app: " + (filesPath + ["Downloads"]).joined(separator: " › ") }
        return "Use Share to save a download somewhere else."
    }

    /// How you update Derp, here.
    var updateHelp: String {
        switch kind {
        case .liveContainer:
            return "Update Derp in LiveContainer: add Derp’s source in its Sources tab (Copy source link), or install the new Derp.ipa over this one."
        case .installed where store != nil:
            return "Open \(store!) to install it. If you added Derp’s source there, it shows up under Updates."
        default:
            return "Install the new Derp.ipa the way you installed this one."
        }
    }

    static func day(_ date: Date) -> String {
        let format = DateFormatter()
        format.dateStyle = .medium
        format.timeStyle = .none
        return format.string(from: date)
    }

    // ── Finding out ─────────────────────────────────────────────────────────

    /// Everything [detect] needs, gathered from this process.
    struct Clues {
        var environment: [String: String]
        var containerInfo: [String: Any]?
        var host: String?
        var hostProvision: Data?
        var ownProvision: Data?
        var bundleFolder: String
        var store: String?
        var simulator: Bool
    }

    static let current = detect(clues())

    static func clues() -> Clues {
        let env = ProcessInfo.processInfo.environment
        let home = env["HOME"].map { URL(fileURLWithPath: $0) }
        let info = home.flatMap { NSDictionary(contentsOf: $0.appendingPathComponent("LCContainerInfo.plist")) as? [String: Any] }
        let hostBundle = lcAsk("lcMainBundle") as? Bundle
        var simulator = false
        #if targetEnvironment(simulator)
        simulator = true
        #endif
        var store: String?
        if Thread.isMainThread {
            store = ["SideStore": "sidestore://", "AltStore": "altstore://"].first { UIApplication.shared.canOpenURL(URL(string: $0.value)!) }?.key
        }
        return Clues(
            environment: env,
            containerInfo: info,
            host: lcAsk("lcAppUrlScheme") as? String,
            hostProvision: hostBundle.flatMap { try? Data(contentsOf: $0.bundleURL.appendingPathComponent("embedded.mobileprovision")) },
            ownProvision: try? Data(contentsOf: Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision")),
            bundleFolder: Bundle.main.bundleURL.lastPathComponent,
            store: store,
            simulator: simulator
        )
    }

    /// LiveContainer adds class methods to NSUserDefaults for the apps it runs
    /// (lcAppUrlScheme, lcMainBundle…); nil outside it.
    static func lcAsk(_ name: String) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        guard let method = class_getClassMethod(UserDefaults.self, selector) else { return nil }
        typealias Getter = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>?
        let getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        return getter(UserDefaults.self, selector)?.takeUnretainedValue()
    }

    static func detect(_ clues: Clues) -> Setup {
        let env = clues.environment
        if let lcHome = env["LC_HOME_PATH"] {
            // LiveContainer sets HOME to Derp's data container, inside its own.
            let home = env["HOME"] ?? ""
            let folder = (clues.containerInfo?["folderName"] as? String) ?? URL(fileURLWithPath: home).lastPathComponent
            return Setup(
                kind: .liveContainer,
                store: nil,
                containerName: clues.containerInfo?["name"] as? String,
                containerFolder: folder.isEmpty ? nil : folder,
                multitask: env["LP_HOME_PATH"] != nil,
                host: clues.host ?? "livecontainer",
                bundleFolder: clues.bundleFolder,
                signedUntil: clues.hostProvision.flatMap(expiry),
                filesPath: filesPath(documents: home + "/Documents", root: lcHome + "/Documents", app: "LiveContainer")
            )
        }
        return Setup(
            kind: clues.simulator ? .simulator : .installed,
            store: clues.store,
            containerName: nil,
            containerFolder: nil,
            multitask: false,
            host: "derp",
            bundleFolder: clues.bundleFolder,
            signedUntil: clues.ownProvision.flatMap(expiry),
            filesPath: [UIDevice.current.userInterfaceIdiom == .pad ? "On My iPad" : "On My iPhone", "Derp"]
        )
    }

    /// Derp's Documents folder as Files shows it: under [app]'s folder when
    /// it's inside [root] (LiveContainer's Documents), else not at all.
    static func filesPath(documents: String, root: String, app: String) -> [String]? {
        let docs = URL(fileURLWithPath: documents).standardizedFileURL.pathComponents
        let base = URL(fileURLWithPath: root).standardizedFileURL.pathComponents
        guard docs.count > base.count, Array(docs.prefix(base.count)) == base else { return nil }
        let place = UIDevice.current.userInterfaceIdiom == .pad ? "On My iPad" : "On My iPhone"
        return [place, app] + docs.dropFirst(base.count)
    }

    /// The expiry date in a provisioning profile (a signed plist).
    static func expiry(_ provision: Data) -> Date? {
        guard let start = provision.range(of: Data("<?xml".utf8)),
              let end = provision.range(of: Data("</plist>".utf8), in: start.upperBound..<provision.count) else { return nil }
        let plist = try? PropertyListSerialization.propertyList(from: provision.subdata(in: start.lowerBound..<end.upperBound), format: nil)
        return (plist as? [String: Any])?["ExpirationDate"] as? Date
    }
}
