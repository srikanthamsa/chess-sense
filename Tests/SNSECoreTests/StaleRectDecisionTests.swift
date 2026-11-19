import XCTest
@testable import SNSECore

/// The phone keeps the board rect from whichever board was last calibrated. A lichess grid
/// sits 96 px below a TakeTakeTake one in the same screenshot — small enough that every colour
/// check still passes, and large enough that every square samples half of two squares. These
/// pin the rule that the locator, not the remembered rect, decides.
final class StaleRectDecisionTests: XCTestCase {

    private func image(_ name: String, _ ext: String = "png") throws -> PixelImage {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
        )
        return try XCTUnwrap(PixelImage(contentsOf: url))
    }

    func testStaleRectFromAnotherBoardIsIgnored() throws {
        let lichess = try image("lichess-theme", "jpg")
        let (book, _, _) = try BoardReader.calibrate(image: lichess)

        let takeTakeTake = try image("taketaketake-start")
        let (_, staleRect, _) = try BoardReader.calibrate(image: takeTakeTake)
        XCTAssertGreaterThan(abs(staleRect.y - 780), 40, "fixtures must disagree in placement")

        let read = try BoardReader.read(image: lichess, book: book, rect: staleRect)
        XCTAssertEqual(String(read.fen.split(separator: " ")[0]),
                       "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR")
        XCTAssertTrue(read.isTrustworthy)
    }

    func testStaleRectTheOtherWayRound() throws {
        let takeTakeTake = try image("taketaketake-start")
        let (book, _, _) = try BoardReader.calibrate(image: takeTakeTake)

        let lichess = try image("lichess-theme", "jpg")
        let (_, otherRect, _) = try BoardReader.calibrate(image: lichess)

        let read = try BoardReader.read(image: takeTakeTake, book: book, rect: otherRect)
        XCTAssertEqual(String(read.fen.split(separator: " ")[0]),
                       "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR")
        XCTAssertTrue(read.isTrustworthy)
    }

    func testBookFromAnotherBoardIsRefusedNotMisread() throws {
        let lichess = try image("lichess-theme", "jpg")
        let takeTakeTake = try image("taketaketake-start")
        let (staleBook, _, _) = try BoardReader.calibrate(image: takeTakeTake)

        XCTAssertThrowsError(try BoardReader.read(image: lichess, book: staleBook)) { error in
            guard case BoardError.differentBoard = error else {
                return XCTFail("expected a theme refusal, got \(error)")
            }
        }
    }
}
