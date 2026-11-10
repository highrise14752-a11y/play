// SPDX-License-Identifier: GPL-3.0-only
import XCTest

final class PlayUITests: XCTestCase {
    func testLaunchLibraryAndLyricsSettings() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Play"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["Import audio"].firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Animation style"].waitForExistence(timeout: 5))
        app.buttons["lyrics.animation"].tap()
        XCTAssertTrue(app.buttons["None"].waitForExistence(timeout: 5))
        app.buttons["None"].tap()
        app.buttons["lyrics.position"].tap()
        XCTAssertTrue(app.buttons["Right"].waitForExistence(timeout: 5))
        app.buttons["Right"].tap()
        app.buttons["Music haptics"].tap()
        XCTAssertTrue(app.navigationBars["Music haptics"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Music Together"].tap()
        XCTAssertTrue(app.buttons["Start Music Together"].waitForExistence(timeout: 5))
    }
}
