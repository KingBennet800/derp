import XCTest

/// Derp for iOS, tried like Derp for Android's emulator test (android/ci/smoke.sh):
/// first start (make your dork, pick Doodle's results), a password saved and
/// shown, a download, Reader view, a Doodle search, the menu, Just for fun,
/// tabs, dark mode, and Derp in LiveContainer. CI serves ios/ci/site on
/// localhost:8765. Screenshots are kept as attachments.
final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private let site = "http://localhost:8765/"
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone" }

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ args: [String] = [], env: [String: String] = [:]) {
        app = XCUIApplication()
        app.launchArguments = ["-derpStill"] + args
        app.launchEnvironment = env
        app.launch()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(device)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private var web: XCUIElement { app.webViews.firstMatch }

    private func open(_ text: String) {
        let field = app.textFields["address"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "No address bar")
        field.tap()
        field.typeText(text + "\n")
    }

    private func menu(_ title: String) {
        app.buttons["menu"].tap()
        let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "No \(title) in the menu")
        var tries = 0
        while !item.isHittable && tries < 5 {
            app.collectionViews.firstMatch.swipeUp()
            tries += 1
        }
        item.tap()
    }

    private func page(contains text: String, timeout: TimeInterval = 15) -> Bool {
        web.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.waitForExistence(timeout: timeout)
    }

    func testDerp() throws {
        launch(["-derpFresh"])

        // First start: make your dork…
        let thatsMe = web.buttons["That’s me!"]
        XCTAssertTrue(thatsMe.waitForExistence(timeout: 60), "No That’s me! on the welcome")
        shot("1-welcome")
        thatsMe.tap()
        // …then Doodle asks where its results come from.
        let duck = web.buttons.matching(NSPredicate(format: "label CONTAINS 'DuckDuckGo'")).firstMatch
        XCTAssertTrue(duck.waitForExistence(timeout: 15), "Doodle didn’t ask where its results come from")
        shot("2-doodle-ask")
        duck.tap()
        XCTAssertTrue(app.textFields["address"].waitForExistence(timeout: 10))
        sleep(2)
        shot("3-newtab")

        // A password: sign in on the test site, and Derp offers to save it.
        open(site + "login.html")
        let user = web.textFields["Username"]
        XCTAssertTrue(user.waitForExistence(timeout: 20), "The test site didn’t load")
        user.tap()
        user.typeText("tester")
        let password = web.secureTextFields["Password"]
        password.tap()
        password.typeText("hunter2hunter2")
        web.buttons["Sign in"].tap()
        let save = app.alerts.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 15), "Derp didn’t offer to save the password")
        shot("4-save-password")
        save.tap()
        XCTAssertTrue(page(contains: "Derp’s iOS test site"), "No signed-in page")

        // Reader view lights up for the article-ish page (once Derp's script has looked at it).
        sleep(4)
        menu("Reader view")
        sleep(3)
        shot("5-reader")
        app.buttons["Back"].tap()
        XCTAssertTrue(page(contains: "Derp’s iOS test site"))

        // A download: saved to Downloads, and shown.
        web.links["Download a file"].tap()
        sleep(3)
        shot("6-download")
        if app.buttons["Done"].waitForExistence(timeout: 5) { app.buttons["Done"].tap() }

        // The Passwords page lists the one Derp saved.
        menu("Passwords")
        XCTAssertTrue(page(contains: "tester"), "The saved password isn’t on the Passwords page")
        shot("7-passwords")

        // A search with Doodle (DuckDuckGo's results, in Doodle's look).
        open("derp browser quacks")
        sleep(6)
        shot("8-search")

        // The menu.
        app.buttons["menu"].tap()
        sleep(1)
        shot("9-menu")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Just for fun'")).firstMatch.tap()

        // Just for fun.
        XCTAssertTrue(app.switches["Duck mode"].waitForExistence(timeout: 5), "No Just for fun")
        shot("10-fun")
        app.buttons["Done"].tap()

        // Tabs: a new one, and (on an iPhone) the tabs view.
        menu("New tab")
        sleep(2)
        if device == "iphone" {
            app.buttons["tabs"].tap()
            XCTAssertTrue(app.otherElements["tabs panel"].waitForExistence(timeout: 5), "No tabs view")
        }
        shot("11-tabs")
    }

    func testDark() {
        launch(["-derpDark"])
        sleep(6)
        shot("12-dark")
    }

    /// Derp running in LiveContainer notices, and says how links get to it there.
    func testLiveContainer() {
        launch(env: ["LC_HOME_PATH": NSTemporaryDirectory()])
        XCTAssertTrue(app.textFields["address"].waitForExistence(timeout: 30))
        menu("Open links in Derp (LiveContainer)")
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS 'LiveContainer'")).firstMatch.exists)
        shot("13-livecontainer")
    }
}
