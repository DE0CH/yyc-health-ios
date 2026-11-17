// The phone replica (Deyao, 2026-10-10/16): the Release build on an iPhone 17 simulator, every flow tapped, against
// stub/stub.py on the simulator's loopback (the real page needs Deyao's Google login; its own tests are in
// DE0CH/yyc-code news-stream/tests/test_health_page.py).
// 1. No token: the sign-in sheet opens by itself; Continue → the stub signs in → the page shows, with the token as its
//    cookie, in a window exactly the safe area (402 x 778 on an iPhone 17).
// 2. The token is kept: a relaunch shows the page with no sign-in.
// 3. A spent token (the stub sends the WebView to Access's login): the app drops it and asks to sign in again; Cancel
//    leaves the sign-in screen with its button, which opens the sheet again.
import XCTest

final class ReplicaUITests: XCTestCase {
    let base = ProcessInfo.processInfo.environment["STUB_BASE"] ?? "http://127.0.0.1:8765"
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() { continueAfterFailure = false }

    private func app(_ extra: [String] = []) -> XCUIApplication {
        let a = XCUIApplication()
        a.launchArguments = ["-base", base] + extra
        return a
    }

    private func shot(_ name: String) {
        let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        s.name = name
        s.lifetime = .keepAlways
        add(s)
    }

    /** the system's "wants to use … to sign in" alert: tap `button` */
    private func sheetAlert(_ button: String) {
        let b = springboard.buttons[button]
        XCTAssertTrue(b.waitForExistence(timeout: 20), "the sign-in alert")
        shot("sign-in-alert")
        b.tap()
    }

    func test1_signInThenThePage() {
        let a = app(["-reset"])
        a.launch()
        XCTAssertTrue(a.buttons["signin"].waitForExistence(timeout: 10))
        sheetAlert("Continue")
        let ok = a.webViews.staticTexts["stub ok"]
        XCTAssertTrue(ok.waitForExistence(timeout: 30), "the page after sign-in")
        XCTAssertTrue(a.webViews.staticTexts["cookie ok"].exists)
        let size = a.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'window '")).firstMatch
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        print("WINDOW \(size.label)")
        let web = a.webViews["health-web"].frame, win = a.windows.firstMatch.frame
        print("SAFE \(web) in \(win)")
        if win.width == 402 { XCTAssertEqual(size.label, "window 402x778") }  // an iPhone 17
        shot("page")
    }

    func test2_tokenKept() {
        let a = app()
        a.launch()
        XCTAssertTrue(a.webViews.staticTexts["stub ok"].waitForExistence(timeout: 30), "the page with the kept token")
        XCTAssertFalse(springboard.buttons["Continue"].exists)
        shot("relaunch")
    }

    func test3_spentToken() {
        // the stub forgets nothing between tests, but a fresh stub run (the CI step restarts it) knows no token:
        // restart it through its own URL is not possible, so this test uses a token the stub never minted
        let a = app(["-reset", "-token", "x.eyJleHAiOjQxMDI0NDQ4MDB9.y"])
        a.launch()
        sheetAlert("Cancel")
        XCTAssertTrue(a.buttons["signin"].waitForExistence(timeout: 10))
        XCTAssertTrue(a.staticTexts.matching(NSPredicate(format: "label CONTAINS 'expired'")).firstMatch.exists ||
                      a.staticTexts.matching(NSPredicate(format: "label CONTAINS 'cancelled'")).firstMatch.exists)
        shot("signed-out")
        a.buttons["signin"].tap()
        sheetAlert("Cancel")
    }
}
