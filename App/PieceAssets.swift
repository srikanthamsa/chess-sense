import SwiftUI

/// The board's piece art.
///
/// Drawn from Colin M.L. Burnett's chess set (CC BY-SA 3.0), the set lichess and Wikipedia
/// use. It is the widely recognised free set — chess.com's Neo pieces are proprietary artwork
/// and cannot be redistributed, so this is the closest legitimate equivalent: a clean outline
/// style that stays legible on both square colours, because every piece carries its own
/// black outline.
enum PieceAssets {
    static func name(for piece: Piece) -> String? {
        guard case let .piece(kind, color) = piece else { return nil }
        let letter: String
        switch kind {
        case .king: letter = "K"
        case .queen: letter = "Q"
        case .rook: letter = "R"
        case .bishop: letter = "B"
        case .knight: letter = "N"
        case .pawn: letter = "P"
        }
        return (color == .white ? "w" : "b") + letter
    }

    static func attribution() -> String {
        "Pieces: Colin M.L. Burnett, CC BY-SA 3.0"
    }
}
