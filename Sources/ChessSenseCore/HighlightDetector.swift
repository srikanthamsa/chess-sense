import Foundation

/// Reads the side to move out of TakeTakeTake's last-move tint.
///
/// This matters because tracked history can drift. One poisoned frame — a mirrored read, a
/// resync, a new game without re-calibrating — leaves the side to move half a move out
/// forever, and the board then gets evaluated for the wrong player: the app confidently
/// recommends the *opponent's* best move. That was a real report.
///
/// The frame knows: the tinted square that still holds a piece is where the move landed, so
/// that piece's colour is who moved, and the opponent is to move.
public enum HighlightDetector {
    /// Measured tints: 91 RGB units from the palette on a dark square, 54 on a light one, 0 on
    /// untouched squares.
    public static let threshold = 40.0

    /// Squares whose *background* is tinted.
    ///
    /// Uses `BoardPalette.background`, which samples square corners, not the border ring.
    /// The ring is unreliable here for the same reason it broke classification once: the
    /// destination square of a move usually holds a large piece that covers the whole ring.
    /// In the flipped capture only the vacated square passed a ring test, so the pair was
    /// never seen and the side-to-move hint never fired.
    public static func highlightedSquares(
        image: PixelImage,
        rect: BoardRect,
        palette: BoardPalette
    ) -> [Square] {
        var out: [Square] = []
        for rank in 0..<8 {
            for file in 0..<8 {
                let bg = palette.background(rank: rank, file: file, image: image, rect: rect)
                let base = palette.boardColour(rank: rank, file: file)
                if rgbDistance(bg, base) > threshold { out.append(rank * 8 + file) }
            }
        }
        return out
    }

    /// Side to move for a board given in raw reading order (no orientation applied).
    ///
    /// Returns nil when the frame does not say: no tint, or a tint covering two pieces, which
    /// is what castling looks like.
    public static func sideToMove(
        image: PixelImage,
        rect: BoardRect,
        palette: BoardPalette,
        pieces: [Piece]
    ) -> PieceColor? {
        let tinted = highlightedSquares(image: image, rect: rect, palette: palette)
        let occupied = tinted.filter { !pieces[$0].isEmpty }
        guard occupied.count == 1, case let .piece(_, mover) = pieces[occupied[0]] else {
            return nil
        }
        return mover == .white ? .black : .white
    }
}
