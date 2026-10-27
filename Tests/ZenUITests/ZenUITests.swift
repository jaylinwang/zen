import XCTest

final class ZenUITests: XCTestCase {
    @MainActor func testLocalFolderAndAbandonFlow() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["当下"].waitForExistence(timeout: 15))
        if app.buttons["选择数据文件夹"].exists {
            app.buttons["选择数据文件夹"].tap()
            let picker = XCUIApplication(bundleIdentifier: "com.apple.DocumentManagerUICore.Service")
            _ = picker.buttons["Browse"].waitForExistence(timeout: 10)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "System folder picker"; shot.lifetime = .keepAlways; add(shot)
            print("ZEN_FOLDER_PICKER_TREE\n\(picker.debugDescription)")
            // The simulator setup creates this folder in Zen's shared Documents directory.
            for name in ["Browse", "浏览", "On My iPhone", "我的 iPhone", "禅", "Zen-iOS", "ZenRecords"] {
                let item = picker.buttons[name].firstMatch
                if item.waitForExistence(timeout: 1) { item.tap() }
                else if picker.staticTexts[name].firstMatch.exists { picker.staticTexts[name].firstMatch.tap() }
            }
            let open = picker.buttons["Open"].exists ? picker.buttons["Open"] : picker.buttons["打开"]
            XCTAssertTrue(open.waitForExistence(timeout: 5), picker.debugDescription)
            open.tap()
        }
        XCTAssertTrue(app.buttons["开始专注"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["开始专注"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = springboard.buttons["Don’t Allow"].exists ? springboard.buttons["Don’t Allow"] : springboard.buttons["不允许"]
        if deny.waitForExistence(timeout: 2) { deny.tap() }
        XCTAssertTrue(app.buttons["放弃本次"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["放弃本次"].tap()
        XCTAssertTrue(app.buttons["开始专注"].waitForExistence(timeout: 5))
        app.buttons["留痕"].tap()
        XCTAssertFalse(app.staticTexts["待补记"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Abandoned focus leaves no record"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["当下"].tap()
        app.buttons["开始专注"].tap()
        XCTAssertTrue(app.buttons["放弃本次"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 5)
        app.activate()
        XCTAssertTrue(app.buttons["放弃本次"].waitForExistence(timeout: 5), "Backgrounding must not abandon focus")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["放弃本次"].waitForExistence(timeout: 5), "iOS relaunch in the same boot must recover the running focus")
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 75), "At completion, the annotation must open automatically")
        XCTAssertTrue(app.staticTexts["这段时间做了什么？"].exists)
        app.textViews.firstMatch.tap(); app.textViews.firstMatch.typeText("Read one page.")
        app.buttons["保存到本地"].tap()
        XCTAssertTrue(app.staticTexts["Read one page."].waitForExistence(timeout: 5), app.debugDescription)
        let completed = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        completed.name = "Completed focus and saved annotation"; completed.lifetime = .keepAlways; add(completed)
    }
}
