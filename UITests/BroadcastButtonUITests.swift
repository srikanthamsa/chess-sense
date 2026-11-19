import XCTest

/// Proves the broadcast control actually fires.
///
/// Three rounds of "nothing happens" on the device were spent without evidence about whether
/// the touch arrived, so this test asserts on the tap counter the card itself displays.
final class BroadcastButtonUITests: XCTestCase {
    func testStartBroadcastRowRegistersATap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-snse-ui-test", "YES"]
        app.launch()

        let row = app.buttons["start-broadcast"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "row not found: \(app.debugDescription)")
        row.tap()

        // The card renders the counter; a tap that never arrived leaves it at zero.
        let counter = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "taps")).firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        let deadline = Date().addingTimeInterval(6)
        var label = counter.label
        while Date() < deadline, label.contains("taps 0") {
            usleep(200_000)
            label = counter.label
        }
        XCTAssertFalse(label.contains("taps 0"), "tap did not reach the handler: \(label)")
    }
}
