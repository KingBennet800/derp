import WebKit
import XCTest
@testable import Derp

final class EngineTests: XCTestCase {
    func testAddresses() {
        XCTAssertEqual(Address.toURL("example.com", engine: .doodle), "https://example.com")
        XCTAssertEqual(Address.toURL("localhost:8765/a", engine: .doodle), "http://localhost:8765/a")
        XCTAssertEqual(Address.toURL("https://x.org/?q=1", engine: .doodle), "https://x.org/?q=1")
        XCTAssertEqual(Address.toURL("how do ducks sleep", engine: .doodle, doodle: .google), "https://www.google.com/search?q=how%20do%20ducks%20sleep&doodle=1")
        XCTAssertEqual(Address.toURL("ducks", engine: .bing), "https://www.bing.com/search?q=ducks")
    }

    func testDoodleOnDuckDuckGo() {
        let light = Address.toURL("ducks", engine: .doodle, doodle: .duckduckgo, dark: false)
        XCTAssertEqual(light, "https://duckduckgo.com/?q=ducks&k9=2f6feb&kaa=7a52c7&kx=0f8a74&kt=system-ui&ka=system-ui")
        let dark = Address.toURL("ducks", engine: .doodle, doodle: .duckduckgo, dark: true)
        XCTAssertTrue(dark.contains("kae=d&k9=86b1ff"))
        XCTAssertEqual(Engine.doodle.terms(light), "ducks")
        XCTAssertEqual(Engine.doodle.terms("https://www.google.com/search?q=hi%20there&doodle=1"), "hi there")
        XCTAssertNil(Engine.doodle.terms("https://example.com/?q=x"))
        let google = URL(string: "https://www.google.com/search?q=quack&doodle=1")!
        XCTAssertEqual(Address.doodleOnDuck(google, doodle: .duckduckgo), Engine.doodle.search("quack", doodle: .duckduckgo))
        XCTAssertNil(Address.doodleOnDuck(google, doodle: .google))
        XCTAssertNil(Address.doodleOnDuck(URL(string: "https://www.google.com/search?q=quack")!, doodle: .duckduckgo))
    }

    func testTrackers() {
        let url = URL(string: "https://shop.example/item?id=7&utm_source=x&fbclid=abc")!
        XCTAssertEqual(Address.stripped(url)?.absoluteString, "https://shop.example/item?id=7")
        XCTAssertNil(Address.stripped(URL(string: "https://example.com/?id=7")!))
        // YouTube's si is a tracker; elsewhere it may mean something.
        XCTAssertEqual(Address.stripped(URL(string: "https://www.youtube.com/watch?v=1&si=2")!)?.absoluteString, "https://www.youtube.com/watch?v=1")
        XCTAssertNil(Address.stripped(URL(string: "https://example.com/?si=2")!))
    }
}

final class ImportsTests: XCTestCase {
    func testBookmarks() {
        let html = """
        <DT><A HREF="https://example.com/a?x=1&amp;y=2" ADD_DATE="1">Example &amp; Co</A>
        <DT><H3>Folder</H3><DL><p><DT><A HREF="https://duck.example/">  <b>Duck</b> </A></DL>
        <DT><A HREF="javascript:alert(1)">Nope</A>
        <DT><A HREF="https://example.com/a?x=1&amp;y=2">Again</A>
        """
        XCTAssertEqual(Imports.bookmarks(html), [
            Imports.Bookmark(url: "https://example.com/a?x=1&y=2", title: "Example & Co"),
            Imports.Bookmark(url: "https://duck.example/", title: "Duck"),
        ])
    }

    func testPasswords() {
        let csv = "\u{FEFF}name,url,username,password\r\nEx,https://Example.com:8443/login,me,\"p,\"\"w\"\"\"\r\nApp,android://app,x,y\r\n,https://b.example/,,\r\n"
        XCTAssertEqual(Imports.logins(csv), [Imports.Login(origin: "https://example.com:8443", username: "me", password: "p,\"w\"")])
        XCTAssertEqual(Imports.unescape("&#x2014;&#39;&amp;&bogus;"), "—'&&bogus;")
    }
}

final class FunTests: XCTestCase {
    private func store() -> UserDefaults {
        let name = "derp.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    func testPetDays() {
        Gag.pet.on = true
        defer { Gag.pet.on = false }
        let defaults = store()
        let day = TimeInterval(86_400)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(Pet.count(today: start, store: defaults))
        XCTAssertNil(Pet.count(today: start, store: defaults))
        XCTAssertNil(Pet.count(today: start.addingTimeInterval(day), store: defaults))
        XCTAssertEqual(Pet.count(today: start.addingTimeInterval(2 * day), store: defaults)?.value, "flower")
        XCTAssertNil(Pet.count(today: start.addingTimeInterval(2 * day), store: defaults))
    }

    func testWhatsNew() {
        let json = Data("""
        [{"version":"2.3.0","title":"Three","items":[{"icon":"🍎","title":"A","text":"a","android":"⋮ → Look","ios":"⋯ → Look"}]},
         {"version":"2.2.0","title":"Two","items":[{"icon":"🦆","title":"B","text":"b","android":"⋮ → Search engine"}]}]
        """.utf8)
        let all = WhatsNew.releases(json)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[1].items[0].where_, "⋯ → Search engine")
        let defaults = store()
        XCTAssertTrue(WhatsNew.since(made: false, all: all, version: "2.3.0", store: defaults).isEmpty)
        defaults.set("2.1.0", forKey: "whatsNewSeen")
        XCTAssertEqual(WhatsNew.since(made: true, all: all, version: "2.3.0", store: defaults).map(\.version), ["2.3.0", "2.2.0"])
        XCTAssertTrue(WhatsNew.since(made: true, all: all, version: "2.3.0", store: defaults).isEmpty)
        XCTAssertTrue(WhatsNew.newer("2.10.0", "2.9.9"))
        XCTAssertFalse(WhatsNew.newer("2.2", "2.2.0"))
        XCTAssertFalse(WhatsNew.releases().isEmpty, "the app has whatsnew.json")
    }

    func testSeasons() {
        func day(_ m: Int, _ d: Int) -> Date { Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: m, day: d))! }
        XCTAssertEqual(Seasons.of(day(2, 10)), ["heart"])
        XCTAssertEqual(Seasons.of(day(10, 30)), ["pumpkin", "leaf", "redLeaf"])
        XCTAssertEqual(Seasons.of(day(1, 3)), ["snow"])
        XCTAssertEqual(Seasons.of(day(4, 3)), ["blossom"])
        XCTAssertEqual(Seasons.of(day(7, 3)), ["sun"])
        XCTAssertEqual(Seasons.of(day(9, 3)), ["leaf", "redLeaf"])
        XCTAssertFalse(Seasons.art(day(1, 3)).isEmpty, "the season art is in the asset catalog")
        for name in ["duck", "snail", "ghost", "parcel", "logo"] { XCTAssertNotNil(Icon.art(name), name) }
        for name in ["back", "forward", "reload", "stop", "menu", "plus", "close", "star", "star-filled", "mask", "search", "globe", "share"] {
            XCTAssertNotNil(Icon.named(name), name)
        }
    }
}

final class SetupTests: XCTestCase {
    private func clues(_ env: [String: String], info: [String: Any]? = nil) -> Setup.Clues {
        Setup.Clues(environment: env, containerInfo: info, host: nil, hostProvision: nil, ownProvision: nil, bundleFolder: "Derp.app", store: "SideStore", simulator: false)
    }

    func testInstalled() {
        let setup = Setup.detect(clues(["HOME": "/var/mobile/Containers/Data/Application/X"]))
        XCTAssertEqual(setup.kind, .installed)
        XCTAssertEqual(setup.store, "SideStore")
        XCTAssertTrue(setup.ownsLinks)
        XCTAssertNil(setup.profile)
        let link = setup.launchLink(opening: URL(string: "https://example.com/?a=b&c=d")!)!
        XCTAssertEqual(link.scheme, "derp")
        XCTAssertEqual(link.host, "open")
        XCTAssertEqual(URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "https://example.com/?a=b&c=d")
    }

    func testLiveContainer() {
        let lc = "/var/mobile/Containers/Data/Application/LC"
        let home = lc + "/Documents/Data/Application/1234-ABCD"
        let setup = Setup.detect(clues(["LC_HOME_PATH": lc, "HOME": home], info: ["name": "Work", "folderName": "1234-ABCD"]))
        XCTAssertEqual(setup.kind, .liveContainer)
        XCTAssertFalse(setup.ownsLinks)
        XCTAssertEqual(setup.profile, "Work")
        XCTAssertFalse(setup.multitask)
        XCTAssertEqual(Array(setup.filesPath?.dropFirst() ?? []), ["LiveContainer", "Data", "Application", "1234-ABCD", "Documents"])
        let link = setup.launchLink(opening: URL(string: "https://example.com/")!)!
        let items = URLComponents(url: link, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(link.scheme, "livecontainer")
        XCTAssertEqual(link.host, "livecontainer-launch")
        XCTAssertEqual(items.first { $0.name == "bundle-name" }?.value, "Derp.app")
        XCTAssertEqual(items.first { $0.name == "container-folder-name" }?.value, "1234-ABCD")
        XCTAssertEqual(items.first { $0.name == "open-url" }?.value.flatMap { Data(base64Encoded: $0) }.flatMap { String(data: $0, encoding: .utf8) }, "https://example.com/")
        // A container named after its folder isn't a profile; a multitasking window is noticed.
        let plain = Setup.detect(clues(["LC_HOME_PATH": lc, "HOME": home, "LP_HOME_PATH": "/x"], info: ["name": "1234-ABCD", "folderName": "1234-ABCD"]))
        XCTAssertNil(plain.profile)
        XCTAssertTrue(plain.multitask)
    }

    func testProvisionExpiry() {
        let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>ExpirationDate</key><date>2026-12-01T10:00:00Z</date></dict></plist>"
        let signed = Data([0x30, 0x80, 0x06]) + Data(plist.utf8) + Data([0, 0, 1])
        XCTAssertEqual(Setup.expiry(signed), ISO8601DateFormatter().date(from: "2026-12-01T10:00:00Z"))
        XCTAssertNil(Setup.expiry(Data("nothing".utf8)))
    }
}

final class PairingTests: XCTestCase {
    // From tests/pairing.py (the reference), with the secret 00 01 02 … 1f.
    let secret = Data(0..<32)

    func testKeys() {
        let keys = PairKeys(secret: secret)
        XCTAssertEqual(keys.box, "2a86655fb8d6d7b920b0b62c85111b06bdc44011d371747738831e97e6668905")
        XCTAssertEqual(keys.token, "d294c1cfff9148da26130d42e70379dcab77d260ab4692dbab618f68a90b7a9a")
        XCTAssertEqual(keys.hash("hunter2"), "2e88b20b0da456d569f7fb0d2d4c50c8")
    }

    func testOpensWhatDesktopSeals() throws {
        let blob = Data(base64Encoded: "AWRlZmdoaWprbG1ub0LM96kKXQDqUjbEYAv46F7Y3juzsNOWY8ACJ4C7jT03wqmdvAY5LKMRrjHWJ495lkxZDmS/koFB7MlN5JpTl2Oq2V/Pw/iNbQt2rvLUhI9OoZp9AWWrKcXFxFNtX0Mv4mRCoUPY1zkTZ7W253+xXTq4JF1i")!
        let json = try PairKeys(secret: secret).unseal(device: "0123456789abcdef0123456789abcdef", blob: blob)
        let snapshot = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        XCTAssertEqual(snapshot?["name"] as? String, "Derp on a test")
        XCTAssertThrowsError(try PairKeys(secret: secret).unseal(device: "ffffffffffffffffffffffffffffffff", blob: blob))
    }

    func testSealsForDesktop() throws {
        let keys = PairKeys(secret: secret)
        let body = Data("{\"v\":1,\"name\":\"Derp on iPad\"}".utf8)
        let blob = try keys.seal(device: "0123456789abcdef0123456789abcdef", json: body)
        XCTAssertEqual(try keys.unseal(device: "0123456789abcdef0123456789abcdef", blob: blob), body)
        // Kept for CI, which opens it with tests/pairing.py.
        let attachment = XCTAttachment(string: blob.base64EncodedString())
        attachment.name = "pairing-sealed"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testGzip() throws {
        let text = Data(String(repeating: "Derp quacks. ", count: 200).utf8)
        let zipped = try Gzip.compress(text)
        XCTAssertEqual(Array(zipped.prefix(3)), [0x1F, 0x8B, 0x08])
        XCTAssertLessThan(zipped.count, text.count / 5)
        XCTAssertEqual(try Gzip.decompress(zipped), text)
        XCTAssertEqual(Gzip.crc32(Data("123456789".utf8)), 0xCBF4_3926)
    }

    func testLinks() {
        let link = "https://kingbennet800.github.io/derp/pair/#AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"
        XCTAssertEqual(Pairing.parse(link)?.0, secret)
        XCTAssertEqual(Pairing.parse(link)?.1, Pairing.relay)
        XCTAssertEqual(Pairing.parse(link + "~http%3A%2F%2Flocalhost%3A8080%2Frelay")?.1, "http://localhost:8080/relay")
        XCTAssertNil(Pairing.parse(link + "~http%3A%2F%2Fevil.example%2F"))
        XCTAssertNil(Pairing.parse("https://example.com/#abc"))
    }
}

final class LibraryTests: XCTestCase {
    func testBookmarksAndHistory() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let library = Library(directory: folder)
        library.bookmark("https://a.example/", title: "A")
        XCTAssertTrue(library.isBookmarked("https://a.example/"))
        XCTAssertEqual(library.importBookmarks([.init(url: "https://a.example/", title: "A"), .init(url: "https://b.example/", title: "B_%")]), 1)
        XCTAssertEqual(library.bookmarks(query: "_%").count, 1)
        library.visit("https://a.example/")
        library.visit("https://a.example/")
        library.title("https://a.example/", title: "Hello")
        XCTAssertEqual(library.history().count, 1)
        XCTAssertEqual(library.history().first?["title"] as? String, "Hello")
        XCTAssertEqual(library.suggestions("hel").first?.url, "https://a.example/")
        library.forget("https://a.example/")
        XCTAssertTrue(library.history().isEmpty)
    }
}

final class BlockerTests: XCTestCase {
    /// WebKit compiles the ad blocker's rules (all of them: one bad rule sinks the list).
    func testRulesCompile() {
        let file = Bundle(for: DerpApp.self).url(forResource: "blocklist", withExtension: "json")!
        let rules = try! String(contentsOf: file)
        let compiled = expectation(description: "compiled")
        let started = Date()
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "derp-test", encodedContentRuleList: rules) { list, error in
            XCTAssertNil(error, "\(String(describing: error))")
            XCTAssertNotNil(list)
            print("Derp: \(rules.count / 1024) KB of rules compiled in \(Date().timeIntervalSince(started))s")
            compiled.fulfill()
        }
        wait(for: [compiled], timeout: 240)
    }
}
