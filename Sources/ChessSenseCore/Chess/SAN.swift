import Foundation

public enum SAN {
    /// Standard algebraic notation for a move that is legal in `position`, including
    /// disambiguation, capture marks, promotion and check/mate suffix.
    public static func san(for move: Move, in position: ChessPosition) -> String {
        let mover = position.board[move.from]
        var kind: PieceKind = .pawn
        var color: PieceColor = .white
        if case let .piece(k, c) = mover { kind = k; color = c }

        var text: String
        if move.isCastle {
            text = move.isKingsideCastle ? "O-O" : "O-O-O"
        } else {
            let isCapture = position.board[move.to] != .empty || move.isEnPassant

            if kind == .pawn {
                if isCapture {
                    text = String(Character(UnicodeScalar(
                        UInt8(ascii: "a") + UInt8(fileIndex(move.from))
                    ))) + "x" + squareName(move.to)
                } else {
                    text = squareName(move.to)
                }
            } else {
                text = sanLetter(kind)
                    + disambiguation(for: move, kind: kind, color: color, in: position)
                    + (isCapture ? "x" : "")
                    + squareName(move.to)
            }

            if let promotion = move.promotion {
                text += "=" + promotionLetter(promotion)
            }
        }

        let next = position.applying(move)
        if next.isInCheck {
            text += MoveGenerator.legalMoves(in: next).isEmpty ? "#" : "+"
        }
        return text
    }

    /// SAN omits the origin square only when it is unambiguous. Otherwise it adds the
    /// file, or the rank when the file is also shared, or both.
    private static func disambiguation(
        for move: Move,
        kind: PieceKind,
        color: PieceColor,
        in position: ChessPosition
    ) -> String {
        let rivals = MoveGenerator.legalMoves(in: position).filter { other in
            other.from != move.from
                && other.to == move.to
                && other.promotion == move.promotion
                && position.board[other.from] == .piece(kind, color)
        }
        guard !rivals.isEmpty else { return "" }

        let sameFile = rivals.contains { fileIndex($0.from) == fileIndex(move.from) }
        let sameRank = rivals.contains { rankIndex($0.from) == rankIndex(move.from) }

        if !sameFile {
            return String(Character(UnicodeScalar(
                UInt8(ascii: "a") + UInt8(fileIndex(move.from))
            )))
        }
        if !sameRank {
            return String(8 - rankIndex(move.from))
        }
        return squareName(move.from)
    }

    /// A compact list of moves with their SAN, for logs and the expanded Island view.
    public static func numberedLine(from position: ChessPosition, plies: Int = 6) -> String {
        var pos = position
        var parts: [String] = []
        for _ in 0..<plies {
            let moves = MoveGenerator.legalMoves(in: pos)
            guard let best = moves.first else { break }
            parts.append(san(for: best, in: pos))
            pos = pos.applying(best)
        }
        return parts.joined(separator: " ")
    }
}
