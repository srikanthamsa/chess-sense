import XCTest
@testable import SNSECore

/// TakeTakeTake flips the board when you are Black, and the coordinate labels flip too.
/// A reader that assumes White is always at the bottom returns a position rotated 180°, so
/// every suggested move is a mirror — the reported symptom was "Nxc2" in a position the
/// knight could not possibly reach.
final class OrientationTests: XCTestCase {

    private func image(_ name: String) throws -> PixelImage {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Fixtures")
        )
        return try XCTUnwrap(PixelImage(contentsOf: url))
    }

    /// White at the bottom: a8 at the top-left is a light square and the top label is "8".
    func testStandardBoardDetectsWhiteAtBottom() throws {
        let img = try image("taketaketake-start")
        let rect = try XCTUnwrap(BoardLocator.locate(img))
        let palette = BoardPalette.estimate(image: img, rect: rect)
        XCTAssertEqual(OrientationDetector.detect(image: img, rect: rect, palette: palette),
                       .whiteAtBottom)
    }

    /// Black at the bottom: labels read H..A across and 1..8 down, so rank 1 is on top.
    func testFlippedBoardDetectsBlackAtBottom() throws {
        let img = try image("taketaketake-flipped")
        let rect = try XCTUnwrap(BoardLocator.locate(img))
        let palette = BoardPalette.estimate(image: img, rect: rect)
        XCTAssertEqual(OrientationDetector.detect(image: img, rect: rect, palette: palette),
                       .blackAtBottom)
        // And the raw label densities must actually differ, not tie by luck.
        let top = OrientationDetector.labelDensity(image: img, rect: rect, palette: palette, rank: 0)
        let bottom = OrientationDetector.labelDensity(image: img, rect: rect, palette: palette, rank: 7)
        XCTAssertGreaterThan(bottom, top, "rank 8 sits at the bottom in this capture")
    }

    func testFlippedFrameIsRotatedBackToWhiteAtBottom() throws {
        let clean = try image("taketaketake-start")
        let (book, _, _) = try BoardReader.calibrate(image: clean)

        let read = try BoardReader.read(image: try image("taketaketake-flipped"), book: book)
        XCTAssertEqual(read.orientation, .blackAtBottom)

        // The same board seen from Black's side, expressed with White at the bottom.
        XCTAssertEqual(
            String(read.fen.split(separator: " ")[0]),
            "r3kbnr/pp3ppp/1qn1p3/3pNbB1/3P4/1B6/PPP2PPP/RN1QK2R"
        )
        XCTAssertTrue(read.isTrustworthy)
    }

    func testCalibratingOnAMidGameFrameStillFails() throws {
        // A flipped mid-game capture is not a starting position: calibration must refuse it
        // rather than bake a book from the wrong layout.
        XCTAssertThrowsError(try BoardReader.calibrate(image: try image("taketaketake-flipped"))) { error in
            guard case BoardError.verificationFailed = error else {
                return XCTFail("expected verificationFailed, got \(error)")
            }
        }
    }

    func testRotationIsItsOwnInverse() {
        let start = TemplateBook.standardStartPlacement
        XCTAssertEqual(rotated180(rotated180(start)), start)
        // Rank 8 becomes rank 1 and file a becomes file h.
        var board = [Piece](repeating: .empty, count: 64)
        board[0] = .piece(.rook, .white)          // a8
        let rotated = rotated180(board)
        XCTAssertEqual(rotated[63], .piece(.rook, .white))   // h1
    }
}
