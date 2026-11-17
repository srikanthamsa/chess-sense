import Foundation

public struct BoardRead: Sendable {
    public let fen: String
    public let rect: BoardRect
    /// Fraction of squares matched at shape distance 0.
    public let exactRate: Double
    /// Worst shape distance across the board, 0 = perfect.
    public let worstShapeDistance: Int
    /// Smallest colour margin across occupied squares. Low = ambiguous read.
    public let minColorMargin: Double
    public let signatures: [SquareSignature]

    /// Gate for "would I bet a move on this read?".
    /// Every square already matched inside the book's tolerances to get here, so the
    /// meaningful extra signal is how decisively colour separated the candidates.
    public var isTrustworthy: Bool {
        worstShapeDistance <= 8 && minColorMargin >= 0.08
    }
}

public enum BoardReader {
    /// Locates the board and classifies all 64 squares.
    public static func read(
        image: PixelImage,
        book: TemplateBook,
        rect: BoardRect? = nil
    ) throws -> BoardRead {
        guard let board = rect ?? BoardLocator.locate(image) else {
            throw BoardError.boardNotFound
        }
        let sigs = SquareExtractor.extract(image: image, rect: board)

        var pieces: [Piece] = []
        pieces.reserveCapacity(64)
        var worst = 0
        var exact = 0
        var minMargin = Double.infinity

        for (i, sig) in sigs.enumerated() {
            guard let match = book.classify(sig) else {
                throw BoardError.unknownSquare(
                    rank: i / 8,
                    file: i % 8,
                    bestDistance: book.bestShapeDistance(sig)
                )
            }
            if match.shapeDistance == 0 { exact += 1 }
            worst = max(worst, match.shapeDistance)
            if !match.piece.isEmpty { minMargin = min(minMargin, match.colorMargin) }
            pieces.append(match.piece)
        }

        return BoardRead(
            fen: FEN.encode(pieces),
            rect: board,
            exactRate: Double(exact) / 64.0,
            worstShapeDistance: worst,
            minColorMargin: minMargin.isFinite ? minMargin : 1.0,
            signatures: sigs
        )
    }

    /// One-shot calibration: learns templates from a frame known to show `placement`
    /// (the standard start position by default) and verifies the book by re-reading
    /// the same frame. A broken theme, a mid-animation frame or the wrong position
    /// throws here rather than producing a silently wrong book.
    public static func calibrate(
        image: PixelImage,
        placement: [Piece] = TemplateBook.standardStartPlacement,
        rect: BoardRect? = nil
    ) throws -> (book: TemplateBook, rect: BoardRect, verification: BoardRead) {
        guard let board = rect ?? BoardLocator.locate(image) else {
            throw BoardError.boardNotFound
        }
        let sigs = SquareExtractor.extract(image: image, rect: board)
        let book = try TemplateBook.bootstrap(signatures: sigs, placement: placement)
        let verification = try read(image: image, book: book, rect: board)

        let expected = FEN.encode(placement)
        let gotBoard = String(verification.fen.split(separator: " ")[0])
        let wantBoard = String(expected.split(separator: " ")[0])
        guard gotBoard == wantBoard else {
            throw BoardError.verificationFailed(expected: wantBoard, got: gotBoard)
        }
        return (book, board, verification)
    }
}

public enum FEN {
    /// Encodes 64 squares given in FEN order (rank 8 first, file a first).
    /// Side-to-move and castling are supplied by the caller — for this app they come
    /// from move history rather than being read off the screen.
    public static func encode(
        _ pieces: [Piece],
        sideToMove: PieceColor = .white,
        castling: String = "KQkq",
        enPassant: String = "-",
        halfmove: Int = 0,
        fullmove: Int = 1
    ) -> String {
        precondition(pieces.count == 64)
        var ranks: [String] = []
        for rank in 0..<8 {
            var s = ""
            var gap = 0
            for file in 0..<8 {
                let p = pieces[rank * 8 + file]
                if let c = p.fenLetter {
                    if gap > 0 { s += String(gap); gap = 0 }
                    s.append(c)
                } else {
                    gap += 1
                }
            }
            if gap > 0 { s += String(gap) }
            ranks.append(s)
        }
        let turn = sideToMove == .white ? "w" : "b"
        let castle = castling.isEmpty ? "-" : castling
        return ranks.joined(separator: "/")
            + " \(turn) \(castle) \(enPassant) \(halfmove) \(fullmove)"
    }
}
