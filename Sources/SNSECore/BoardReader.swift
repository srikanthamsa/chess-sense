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
    /// True when the templates were learned at a different board scale than this frame.
    ///
    /// A screenshot-trained book (151 px squares) landing on broadcast frames (110 px) does not
    /// fail loudly: stroke weight changes enough that it matches the wrong glyph with a small
    /// distance, so queens read as pawns and the position looks legal. Scale is therefore a
    /// first-class reason to distrust a read.
    public let scaleMismatch: Bool
    /// Pixels per square this frame was read at, and the scale the book was learned at.
    public let squareSize: Double
    public let bookSquareSize: Double?
    /// Side to move as reported by the last-move tint, when the frame says. Direct evidence,
    /// unlike the tracked history — see `HighlightDetector`.
    public let sideToMove: PieceColor?

    /// Gate for "would I bet a move on this read?".
    /// Every square already matched inside the book's tolerances to get here, so the
    /// meaningful extra signal is how decisively colour separated the candidates.
    public var isTrustworthy: Bool {
        !scaleMismatch && worstShapeDistance <= 8 && minColorMargin >= 0.08
    }
}

public enum BoardReader {
    /// Locates the board and classifies all 64 squares.
    public static func read(
        image: PixelImage,
        book: TemplateBook,
        rect: BoardRect? = nil
    ) throws -> BoardRead {
        // A supplied rect is a fast path, not an authority. Broadcast frames arrive at half
        // resolution, so a rect learned from a full-resolution screenshot indexes past the
        // end of the pixel buffer -- that crashed the app on the first streamed frame.
        // Accept it only when it still fits this image; otherwise locate the board again.
        let supplied = rect.flatMap { fits($0, in: image) ? $0 : nil }
        guard let board = supplied ?? BoardLocator.locate(image) ?? BoardLocator.locateGeneric(image) else {
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
            scaleMismatch: scaleMismatch(book: book, board: board),
            squareSize: Double(board.width) / 8,
            bookSquareSize: book.squareSize,
            sideToMove: sideToMove
        )
    }

    /// More than ~6% difference in pixels-per-square changes stroke weight enough to matter:
    /// 151 px screenshot squares against 110 px broadcast squares misread confidently.
    static func scaleMismatch(book: TemplateBook, board: BoardRect) -> Bool {
        guard let learned = book.squareSize, learned > 0 else { return false }
        let now = Double(board.width) / 8
        return abs(now - learned) / learned > 0.06
    }

    /// One-shot calibration: learns templates from a frame known to show `placement`
    /// (the standard start position by default) and verifies the book by re-reading
    /// the same frame. A broken theme, a mid-animation frame or the wrong position
    /// throws here rather than producing a silently wrong book.
    /// Whether a rectangle can be sampled from this image without leaving it.
    ///
    /// Square-ness is checked too: a scaled image with a stale rect is usually still
    /// in-bounds vertically and hugely wrong horizontally, and sampling that produces
    /// nonsense signatures instead of a clean rejection.
    public static func fits(_ rect: BoardRect, in image: PixelImage) -> Bool {
        let slack = 8
        guard rect.width >= 64, rect.height >= 64,
              rect.x >= -slack, rect.y >= -slack,
              rect.x + rect.width <= image.width + slack,
              rect.y + rect.height <= image.height + slack
        else { return false }
        let longer = Double(max(rect.width, rect.height))
        return Double(abs(rect.width - rect.height)) <= longer * 0.06
    }

    public static func calibrate(
        image: PixelImage,
        placement: [Piece] = TemplateBook.standardStartPlacement,
        rect: BoardRect? = nil
    ) throws -> (book: TemplateBook, rect: BoardRect, verification: BoardRead) {
        // A supplied rect is a fast path, not an authority. Broadcast frames arrive at half
        // resolution, so a rect learned from a full-resolution screenshot indexes past the
        // end of the pixel buffer -- that crashed the app on the first streamed frame.
        // Accept it only when it still fits this image; otherwise locate the board again.
        let supplied = rect.flatMap { fits($0, in: image) ? $0 : nil }
        guard let board = supplied ?? BoardLocator.locate(image) ?? BoardLocator.locateGeneric(image) else {
            throw BoardError.boardNotFound
        }
        let palette = BoardPalette.estimate(image: image, rect: board)
        let sigs = SquareExtractor.extract(image: image, rect: board, palette: palette)
        let orientation = OrientationDetector.detect(image: image, rect: board, palette: palette)
        // If the calibration frame is shown from Black's side, the signatures are rotated
        // relative to the standard placement array; rotate the expectation to match.
        let aligned = orientation.isFlipped ? rotated180(placement) : placement
        let book = try TemplateBook.bootstrap(
            signatures: sigs, placement: aligned,
            squareSize: Double(board.width) / 8
        )
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
    /// The standard starting position, in FEN order. Used as the anchor when a fresh game is
    /// on screen and the tracker has no history yet.
    public static let start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"

    /// Decodes the board field of a FEN into 64 squares in FEN order.
    ///
    /// Used to re-anchor calibration: the book can be learned from any frame as long as we
    /// can say which position that frame shows, and the side to move is irrelevant here.
    public static func decode(_ fen: String) -> [Piece]? {
        let board = fen.split(separator: " ").first.map(String.init) ?? fen
        var pieces: [Piece] = []
        pieces.reserveCapacity(64)
        for character in board {
            if character == "/" { continue }
            if let digit = character.wholeNumberValue {
                pieces.append(contentsOf: Array(repeating: Piece.empty, count: digit))
                continue
            }
            let isWhite = character.isUppercase
            let color: PieceColor = isWhite ? .white : .black
            switch character.lowercased() {
            case "p": pieces.append(.piece(.pawn, color))
            case "n": pieces.append(.piece(.knight, color))
            case "b": pieces.append(.piece(.bishop, color))
            case "r": pieces.append(.piece(.rook, color))
            case "q": pieces.append(.piece(.queen, color))
            case "k": pieces.append(.piece(.king, color))
            default: return nil
            }
        }
        return pieces.count == 64 ? pieces : nil
    }

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
