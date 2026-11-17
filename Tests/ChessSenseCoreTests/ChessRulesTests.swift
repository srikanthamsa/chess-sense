import XCTest
@testable import ChessSenseCore

/// The rules module is anchored to published perft counts. A move generator that gets
/// these right is almost certainly right about legality, castling, en passant and
/// promotion — which is what the tracker depends on to infer a move from a board diff.
final class ChessRulesTests: XCTestCase {

    private func position(_ fen: String) throws -> ChessPosition {
        try XCTUnwrap(ChessPosition(fen: fen), "bad FEN: \(fen)")
    }

    // MARK: - Perft

    func testPerftStartPosition() throws {
        let start = try position("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        XCTAssertEqual(MoveGenerator.perft(start, depth: 1), 20)
        XCTAssertEqual(MoveGenerator.perft(start, depth: 2), 400)
        XCTAssertEqual(MoveGenerator.perft(start, depth: 3), 8_902)
    }

    func testPerftKiwipete() throws {
        // The classic stress position: castling both ways, pins, en passant, promotions.
        let kiwipete = try position(
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
        )
        XCTAssertEqual(MoveGenerator.perft(kiwipete, depth: 1), 48)
        XCTAssertEqual(MoveGenerator.perft(kiwipete, depth: 2), 2_039)
    }

    func testPerftPositionThree() throws {
        // Rook endgame with an en passant capture and a pin.
        let p3 = try position("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1")
        XCTAssertEqual(MoveGenerator.perft(p3, depth: 1), 14)
        XCTAssertEqual(MoveGenerator.perft(p3, depth: 2), 191)
        XCTAssertEqual(MoveGenerator.perft(p3, depth: 3), 2_812)
    }

    // MARK: - FEN

    func testFENRoundTrip() throws {
        let fens = [
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
            "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
            "4k3/8/8/8/8/8/8/4K2R w K - 7 42",
        ]
        for fen in fens {
            XCTAssertEqual(try position(fen).fen, fen)
        }
    }

    func testPiecePlacementMatchesReaderOutput() throws {
        // The reader emits FEN-order squares; the rules board must be the same order.
        let start = try position("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        XCTAssertEqual(start.board, TemplateBook.standardStartPlacement)
    }

    // MARK: - SAN

    func testSANBasics() throws {
        let start = try position("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        XCTAssertEqual(san("e2e4", start), "e4")
        XCTAssertEqual(san("g1f3", start), "Nf3")
        XCTAssertEqual(san("e2e3", start), "e3")
        XCTAssertEqual(san("b1a3", start), "Na3")
    }

    func testSANCastling() throws {
        let white = try position("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        XCTAssertEqual(san("e1g1", white), "O-O")
        XCTAssertEqual(san("e1c1", white), "O-O-O")

        let black = try position("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1")
        XCTAssertEqual(san("e8g8", black), "O-O")
        XCTAssertEqual(san("e8c8", black), "O-O-O")
    }

    func testSANDisambiguation() throws {
        // Two knights can reach d2: file disambiguation.
        let knights = try position("4k3/8/8/8/8/8/8/1N1K1N2 w - - 0 1")
        XCTAssertEqual(san("b1d2", knights), "Nbd2")
        XCTAssertEqual(san("f1d2", knights), "Nfd2")

        // Same file, different ranks: rank disambiguation.
        let stacked = try position("4k3/8/8/8/8/1N6/8/1N2K3 w - - 0 1")
        XCTAssertEqual(san("b1d2", stacked), "N1d2")
        XCTAssertEqual(san("b3d2", stacked), "N3d2")
    }

    func testSANCapturePromotionAndMate() throws {
        let promotion = try position("4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
        XCTAssertEqual(san("a7a8q", promotion), "a8=Q+")

        let capture = try position("4k3/8/8/3p4/4Q3/8/8/4K3 w - - 0 1")
        XCTAssertEqual(san("e4d5", capture), "Qxd5")

        // Back rank mate.
        let mate = try position("6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1")
        XCTAssertEqual(san("a1a8", mate), "Ra8#")
    }

    func testSANEnPassant() throws {
        let ep = try position("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
        XCTAssertEqual(san("e5d6", ep), "exd6")
    }

    private func san(_ uci: String, _ position: ChessPosition) -> String? {
        guard let move = position.move(uci: uci) else { return nil }
        return SAN.san(for: move, in: position)
    }

    // MARK: - Castling rights bookkeeping

    func testCastlingRightsDisappearWhenRookIsCaptured() throws {
        let pos = try position("r3k2r/8/8/8/8/8/6b1/R3K2R b KQkq - 0 1")
        // Black bishop on g2 takes the h1 rook: White loses the right for that side only.
        let after = pos.applying(try XCTUnwrap(pos.move(uci: "g2h1")))
        XCTAssertFalse(after.castling.contains(.whiteKingside))
        XCTAssertTrue(after.castling.contains(.whiteQueenside))
        XCTAssertNotNil(after.kingSquare(of: .white))
    }
}
