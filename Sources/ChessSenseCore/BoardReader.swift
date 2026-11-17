import Foundation

public struct BoardRead: Sendable {
    public let fen: String
    /// The 64 recognised squares in FEN order. This is what `PositionTracker` consumes —
    /// the rules engine never parses FEN text to get the board.
    public let pieces: [Piece]
    public let rect: BoardRect
    /// Fraction of squares matched at shape distance 0.
    public let exactRate: Double
    /// Worst shape distance across the board, 0 = perfect.
    public let worstShapeDistance: Int
    /// Smallest colour margin across occupied squares. Low = ambiguous read.
    public let minColorMargin: Double
    public let signatures: [SquareSignature]
    /// Which side was at the bottom of the screen when this was read.
    public let orientation: BoardOrientation
    /// Side to move as reported by the last-move tint, when the frame says. Direct evidence,
    /// unlike the tracked history — see `HighlightDetector`.
    public let sideToMove: PieceColor?

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
        let palette = BoardPalette.estimate(image: image, rect: board)
        let sigs = SquareExtractor.extract(image: image, rect: board, palette: palette)
        let orientation = OrientationDetector.detect(image: image, rect: board, palette: palette)

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

        let rawPieces = pieces

        // A flipped board is the same position rotated 180°: rotate the squares so every
        // consumer downstream (tracker, engine, SAN) sees White at the bottom.
        if orientation.isFlipped { pieces = rotated180(pieces) }

        // Direct evidence of whose turn it is, computed in raw reading order so it does not
        // need the orientation treatment the board does.
        let sideToMove = HighlightDetector.sideToMove(
            image: image, rect: board, palette: palette, pieces: rawPieces
        )

        return BoardRead(
            fen: FEN.encode(pieces),
            pieces: pieces,
            rect: board,
            exactRate: Double(exact) / 64.0,
            worstShapeDistance: worst,
            minColorMargin: minMargin.isFinite ? minMargin : 1.0,
            signatures: sigs,
            orientation: orientation,
            sideToMove: sideToMove
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
        let palette = BoardPalette.estimate(image: image, rect: board)
        let sigs = SquareExtractor.extract(image: image, rect: board, palette: palette)
        let orientation = OrientationDetector.detect(image: image, rect: board, palette: palette)
        // If the calibration frame is shown from Black's side, the signatures are rotated
        // relative to the standard placement array; rotate the expectation to match.
        let aligned = orientation.isFlipped ? rotated180(placement) : placement
        let book = try TemplateBook.bootstrap(signatures: sigs, placement: aligned)
        let verification = try read(image: image, book: book, rect: board)

        let expected = FEN.encode(aligned)
        let gotBoard = String(verification.fen.split(separator: " ")[0])
        let wantBoard = String(expected.split(separator: " ")[0])
        guard gotBoard == wantBoard else {
            throw BoardError.verificationFailed(expected: wantBoard, got: gotBoard)
        }
        return (book, board, verification)
    }
}

/// Rotates a FEN-ordered 64-square array by 180°: both rank order and file order reverse.
func rotated180(_ pieces: [Piece]) -> [Piece] {
    precondition(pieces.count == 64)
    var out = [Piece](repeating: .empty, count: 64)
    for i in 0..<64 { out[63 - i] = pieces[i] }
    return out
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
