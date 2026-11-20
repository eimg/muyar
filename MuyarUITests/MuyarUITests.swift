import XCTest

final class MuyarUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testWatchlistP2PAndAllChartRanges() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-chart-style", "Candles"]
        app.launch()
        XCTAssertTrue(app.staticTexts["p2p-buy-price"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["p2p-buy-price"].label, "5,160")
        XCTAssertEqual(app.staticTexts["p2p-sell-price"].label, "5,148")
        XCTAssertTrue(app.staticTexts["Reference prices"].exists)
        XCTAssertFalse(app.buttons["p2p-open-offers"].exists)
        app.buttons["filter-Crypto"].tap()
        app.buttons["instrument-BTCUSDT"].tap()
        XCTAssertTrue(app.staticTexts["detail-price"].waitForExistence(timeout: 5))
        for range in ["4H", "1D", "1W", "1M"] {
            app.buttons["range-\(range)"].tap()
            XCTAssertTrue(app.otherElements["price-chart"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.otherElements["candle-ohlc"].exists)
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Muyar Bitcoin chart"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testChartStyleAndDateNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-open-instrument", "BTCUSDT", "-chart-range", "1M", "-chart-style", "Candles"]
        app.launch()
        XCTAssertTrue(app.otherElements["candle-ohlc"].waitForExistence(timeout: 10))
        app.buttons["chart-style-line"].tap()
        XCTAssertFalse(app.otherElements["candle-ohlc"].exists)
        app.buttons["chart-earlier"].tap()
        app.buttons["chart-date"].tap()
        XCTAssertTrue(app.navigationBars["Go to date"].waitForExistence(timeout: 5))
        app.buttons["Go"].tap()
        XCTAssertTrue(app.otherElements["price-chart"].waitForExistence(timeout: 5))
        app.buttons["chart-latest"].tap()
        app.buttons["chart-style-candles"].tap()
        XCTAssertTrue(app.otherElements["candle-ohlc"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAppearanceChoicePersistsAcrossLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-preview-appearance", "light"]
        app.launch()
        for _ in 0..<6 {
            if app.buttons["appearance-dark"].isHittable { break }
            app.swipeUp()
        }
        app.buttons["appearance-dark"].tap()
        XCTAssertTrue(app.buttons["appearance-dark"].isSelected)
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        for _ in 0..<6 {
            if app.buttons["appearance-dark"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["appearance-dark"].isSelected)
        app.buttons["appearance-system"].tap()
        XCTAssertTrue(app.buttons["appearance-system"].isSelected)
    }

    @MainActor
    func testSearchAddAndRemoveInstrument() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.swipeUp()
        app.buttons["add-instrument"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("TSLA")
        let result = app.buttons["add-result-TSLA"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertFalse(result.isEnabled)
        app.buttons["Done"].tap()
        app.buttons["filter-Stocks"].tap()
        XCTAssertTrue(app.buttons["instrument-TSLA"].waitForExistence(timeout: 5))
        app.buttons["edit-watchlist"].tap()
        let delete = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Delete Tesla'")).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        if app.buttons["Delete"].exists { app.buttons["Delete"].tap() }
        app.buttons["Done"].tap()
        XCTAssertFalse(app.buttons["instrument-TSLA"].exists)
    }
}
