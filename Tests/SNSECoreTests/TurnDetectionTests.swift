import XCTest
@testable import SNSECore

/// The reported bug: after a move the app recommended the *opponent's* best move, because the
/// tracked side to move was half a move out. The frame's last-move tint says whose turn it is,
/// and must win over history.
final class TurnDetectionTests: XCTestCase {

    private func image(_ name: String) throws -> PixelImage {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Fixtures")
        )
        return try XCTUnwrap(PixelImage(contentsOf: url))
    }

    func testFlippedFrameReportsBlackToMove() throws {
        // White's knight has just landed on a tinted square, so Black is to move.
        let clean = try image("taketaketake-start")
        let (book, _, _) = try BoardReader.calibrate(image: clean)
        let read = try BoardReader.read(image: try image("taketaketake-flipped"), book: book)
        XCTAssertEqual(read.sideToMove, .black)
    }

    func testStartPositionHasNoTurnHint() throws {
        // Nothing has moved, so there is no tint and no evidence either way.
        let img = try image("taketaketake-start")
        let read = try BoardReader.calibrate(image: img).verification
        XCTAssertNil(read.sideToMove)
    }

    func testTintOnAnOversizedGlyphStillYieldsTheTurn() throws {
        // The destination square of a move usually holds a large piece whose body covers the
        // square's border ring; backgrounds are read from corners precisely so this works.
        let img = try image("taketaketake-flipped")
        let rect = try XCTUnwrap(BoardLocator.locate(img))
        let palette = BoardPalette.estimate(image: img, rect: rect)
        let tinted = HighlightDetector.highlightedSquares(image: img, rect: rect, palette: palette)
        XCTAssertEqual(tinted.count, 2, "a normal move tints exactly two squares: \(tinted)")
        XCTAssertNotNil(HighlightDetector.sideToMove(
            image: img, rect: rect, palette: palette,
            pieces: SquareExtractor.extract(image: img, rect: rect, palette: palette)
                .map { $0.isEmpty ? .empty : .piece(.pawn, .white) }
        ))
    }

    func testTrackerAcceptsTheFramesVerdictOverItsOwnHistory() throws {
        let clean = try image("taketaketake-start")
        let (book, _, _) = try BoardReader.calibrate(image: clean)
        let read = try BoardReader.read(image: try image("taketaketake-flipped"), book: book)

        // A tracker poisoned with the wrong side, as a mirrored read would leave it.
        var tracker = PositionTracker(position: try XCTUnwrap(ChessPosition(fen: read.fen)))
        XCTAssertEqual(tracker.position.sideToMove, .white)

        _ = tracker.observe(read.pieces)
        if let direct = read.sideToMove, tracker.position.sideToMove != direct {
            tracker.forceSideToMove(direct)
        }
        XCTAssertEqual(tracker.position.sideToMove, .black)
        XCTAssertFalse(MoveGenerator.legalMoves(in: tracker.position).isEmpty,
                       "Black must have legal moves in this position")
    }
}
