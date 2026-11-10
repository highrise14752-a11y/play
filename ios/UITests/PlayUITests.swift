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
        app.staticTexts["Animation style"].tap()
        XCTAssertTrue(app.staticTexts["Apple Music"].waitForExistence(timeout: 5))
        app.staticTexts["None"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["Text position"].tap()
        XCTAssertTrue(app.staticTexts["Right"].waitForExistence(timeout: 5))
        app.staticTexts["Right"].tap()
    }
}
