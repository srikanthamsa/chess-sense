import XCTest
@testable import SNSECore

/// The tracker is what turns "the board changed" into "this move was played", and it is
/// the reason side-to-move, castling and en passant never have to be read off pixels.
final class PositionTrackerTests: XCTestCase {

    private func position(_ fen: String) throws -> ChessPosition {
        try XCTUnwrap(ChessPosition(fen: fen))
    }

    private func placement(of position: ChessPosition) -> [Piece] {
        position.board
    }

    // MARK: - One ply

    func testDetectsSingleMove() throws {
        var tracker = PositionTracker()
        let start = tracker.position
        let afterE4 = start.applying(try XCTUnwrap(start.move(uci: "e2e4")))

        let sync = tracker.observe(placement(of: afterE4))

        XCTAssertEqual(sync.sans, ["e4"])
        XCTAssertFalse(sync.didResync)
        XCTAssertEqual(sync.fen, afterE4.fen)
        XCTAssertEqual(tracker.position.sideToMove, .black)
        XCTAssertEqual(tracker.position.enPassant, square(from: "e3"), "double push sets the ep target")
    }

    func testUnchangedBoardIsNotAMove() throws {
        var tracker = PositionTracker()
        let sync = tracker.observe(tracker.position.board)
        XCTAssertTrue(sync.moves.isEmpty)
        XCTAssertFalse(sync.didResync)
    }

    // MARK: - Two plies (missed frame)

    func testDetectsTwoPliesWhenAFrameWasMissed() throws {
        var tracker = PositionTracker()
        let start = tracker.position
        let afterE4 = start.applying(try XCTUnwrap(start.move(uci: "e2e4")))
        let afterE5 = afterE4.applying(try XCTUnwrap(afterE4.move(uci: "e7e5")))

        let sync = tracker.observe(placement(of: afterE5))

        XCTAssertEqual(sync.sans, ["e4", "e5"])
        XCTAssertFalse(sync.didResync)
        XCTAssertEqual(tracker.position.fen, afterE5.fen)
    }

    // MARK: - Special moves

    func testCastlingComesBackAsOnePly() throws {
        var tracker = PositionTracker(position: try position("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
        let before = tracker.position
        let after = before.applying(try XCTUnwrap(before.move(uci: "e1g1")))

        let sync = tracker.observe(placement(of: after))

        XCTAssertEqual(sync.sans, ["O-O"])
        XCTAssertTrue(try XCTUnwrap(sync.lastMove).isCastle)
        // Rook must have come along, or the diff would not have matched.
        XCTAssertEqual(tracker.position.board[square(from: "f1")!], .piece(.rook, .white))
        XCTAssertEqual(tracker.position.board[square(from: "h1")!], .empty)
    }

    func testPromotionCarriesThePiece() throws {
        var tracker = PositionTracker(position: try position("4k3/P7/8/8/8/8/8/4K3 w - - 0 1"))
        let before = tracker.position
        let move = try XCTUnwrap(before.move(uci: "a7a8q"))
        let after = before.applying(move)

        let sync = tracker.observe(placement(of: after))

        XCTAssertEqual(sync.sans, ["a8=Q+"])
        XCTAssertEqual(try XCTUnwrap(sync.lastMove).promotion, .queen)
        XCTAssertEqual(tracker.position.board[square(from: "a8")!], .piece(.queen, .white))
    }

    func testEnPassantRemovesTheCapturedPawn() throws {
        // White pawn e5, black pawn just double-pushed to d5, ep target d6.
        let before = try position("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
        var tracker = PositionTracker(position: before)
        let move = try XCTUnwrap(before.move(uci: "e5d6"))
        let after = before.applying(move)

        let sync = tracker.observe(placement(of: after))

        XCTAssertEqual(sync.sans, ["exd6"])
        XCTAssertEqual(tracker.position.board[square(from: "d5")!], .empty,
                       "the captured pawn is on d5, not d6")
    }

    // MARK: - Failure paths

    func testImpossibleBoardResyncs() throws {
        var tracker = PositionTracker()
        var crazy = tracker.position.board
        crazy[square(from: "a4")!] = .piece(.queen, .black)   // appears from nowhere

        let sync = tracker.observe(crazy)

        XCTAssertTrue(sync.didResync)
        XCTAssertTrue(sync.moves.isEmpty)
        XCTAssertEqual(tracker.position.board, crazy)
    }

    func testResyncRecoversCastlingRightsFromTheBoard() throws {
        var tracker = PositionTracker()
        // Nothing but the two kings and the four home rooks: every right is inferable.
        var board = [Piece](repeating: .empty, count: 64)
        board[square(from: "e1")!] = .piece(.king, .white)
        board[square(from: "e8")!] = .piece(.king, .black)
        for rook in ["a1", "h1"] { board[square(from: rook)!] = .piece(.rook, .white) }
        for rook in ["a8", "h8"] { board[square(from: rook)!] = .piece(.rook, .black) }

        let sync = tracker.observe(board)

        XCTAssertTrue(sync.didResync)
        XCTAssertEqual(tracker.position.castling, .all)
        XCTAssertNil(tracker.position.enPassant)
    }

    func testResyncIntoTheStartPositionStartsAFreshGame() throws {
        // Guard against the nastiest stale-state bug: a new game beginning while the
        // tracker still thinks it is Black's move from the previous one.
        var tracker = PositionTracker(position: try position(
            "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        ))

        let sync = tracker.observe(TemplateBook.standardStartPlacement)

        XCTAssertTrue(sync.didResync)
        XCTAssertEqual(tracker.position.sideToMove, .white)
        XCTAssertEqual(tracker.position.castling, .all)
        XCTAssertNil(tracker.position.enPassant)
    }

    // MARK: - Against a real read

    func testTrackerConsumesTheReadersSquares() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "taketaketake-start", withExtension: "png",
                              subdirectory: "Fixtures")
        )
        let image = try XCTUnwrap(PixelImage(contentsOf: url))
        let (book, rect, _) = try BoardReader.calibrate(image: image)
        let read = try BoardReader.read(image: image, book: book, rect: rect)

        // The 64 Piece values the reader produced go straight into the rules engine.
        var tracker = PositionTracker(position: try position(read.fen))

        XCTAssertTrue(tracker.observe(read.signatures.isEmpty ? [] : tracker.position.board).moves.isEmpty,
                      "the calibrated start position is not a move")

        let after = tracker.position.applying(
            try XCTUnwrap(tracker.position.move(uci: "e2e4"))
        )
        let sync = tracker.observe(after.board)
        XCTAssertEqual(sync.sans, ["e4"])
        XCTAssertFalse(sync.didResync)
    }
}
