import XCTest
@testable import SNSECore

/// A book belongs to one board. These pin that a mismatched frame says so, instead of failing
/// as a generic "couldn't read" that reads like a bug in the app.
final class ThemeGuardTests: XCTestCase {
    private func image(_ name: String, _ ext: String = "png") throws -> PixelImage {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
        )
        return try XCTUnwrap(PixelImage(contentsOf: url))
    }

    func testBookFromOneSiteRefusesAnotherSitesBoard() throws {
        let (book, _, _) = try BoardReader.calibrate(image: try image("taketaketake-start"))
        XCTAssertNotNil(book.lightRGB, "calibration must record the square colours")
        XCTAssertThrowsError(try BoardReader.read(image: try image("lichess-theme", "jpg"),
                                                book: book)) { error in
            guard case BoardError.differentBoard = error else {
                return XCTFail("expected differentBoard, got \(error)")
            }
        }
    }

    func testLichessBookReadsItsOwnFrame() throws {
        let lichess = try image("lichess-theme", "jpg")
        let (book, _, _) = try BoardReader.calibrate(image: lichess)
        let read = try BoardReader.read(image: lichess, book: book)
        XCTAssertEqual(String(read.fen.split(separator: " ")[0]),
                       "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR")
    }
}
