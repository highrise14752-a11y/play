// SPDX-License-Identifier: GPL-3.0-only
import XCTest

final class PlayUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        XCTAssertTrue(app.staticTexts["page.title"].waitForExistence(timeout: 15))
        return app
    }
    private func tap(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<7 {
            if element.exists && element.isHittable { element.tap(); return }
            app.swipeUp()
        }
        XCTFail("Control could not be reached: \(element)")
    }
    private func back(_ app: XCUIApplication) { app.navigationBars.buttons.element(boundBy: 0).tap() }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testFourAndroidTabsAndPlaylistCreation() {
        let app = launch()
        capture(app, "Home")
        for (tab, title) in [("stats", "Stats"), ("history", "History"), ("library", "Library")] {
            app.buttons["tab.\(tab)"].tap()
            XCTAssertEqual(app.staticTexts["page.title"].label, title)
            capture(app, title)
        }
        XCTAssertTrue(app.buttons["Import audio"].firstMatch.exists)
        app.buttons["New playlist"].tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("UI Playlist")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI Playlist")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["tab.home"].tap()
        XCTAssertEqual(app.staticTexts["page.title"].label, "Play")
        app.buttons["Search"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
    }

    func testSettingsPagesAndLyricsControls() {
        let app = launch()
        app.buttons["open.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture(app, "Settings")
        tap(app.buttons["settings.appearance"], app: app)
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 5))
        capture(app, "Appearance")
        app.buttons["Lyrics appearance"].tap()
        app.buttons["lyrics.animation"].tap()
        XCTAssertTrue(app.buttons["None"].waitForExistence(timeout: 5)); app.buttons["None"].tap()
        app.buttons["lyrics.position"].tap()
        XCTAssertTrue(app.buttons["Right"].waitForExistence(timeout: 5)); app.buttons["Right"].tap()
        capture(app, "Lyrics settings")
        back(app); back(app)
        tap(app.buttons["settings.player"], app: app)
        app.buttons["Music haptics"].tap()
        XCTAssertTrue(app.navigationBars["Music haptics"].waitForExistence(timeout: 5))
        capture(app, "Haptics")
        back(app)
        app.buttons["Sleep timer"].tap()
        XCTAssertTrue(app.buttons["30 minutes"].waitForExistence(timeout: 5))
        app.buttons["30 minutes"].tap()
        XCTAssertTrue(app.staticTexts["Stops at"].waitForExistence(timeout: 5))
        app.buttons["Turn off timer"].tap()
        back(app); back(app)
        tap(app.buttons["settings.together"], app: app)
        XCTAssertTrue(app.buttons["Start Music Together"].waitForExistence(timeout: 5))
        back(app)
        for (id, title) in [("content", "Content"), ("privacy", "Privacy"), ("storage", "Storage"), ("backup", "Backup and restore"), ("about", "About")] {
            tap(app.buttons["settings.\(id)"], app: app)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            capture(app, title)
            back(app)
        }
        app.buttons["Search settings"].tap()
        let field = app.textFields["settings.search.query"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("crossfade")
        app.buttons["settings.result.Player and audio"].tap()
        XCTAssertTrue(app.navigationBars["Player and audio"].waitForExistence(timeout: 5))
    }
}
