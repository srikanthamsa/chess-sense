import Foundation

/// Keeps a legal position alive across screenshots.
///
/// A frame only contains piece placement. Side to move, castling rights and en passant —
/// which a FEN needs and a move's legality depends on — come from *history*, which is
/// strictly more reliable than inferring them from pixels. Each `observe` finds the move
/// or moves that turn the tracked position into the observed one, then advances.
public struct PositionTracker: Sendable {
    public private(set) var position: ChessPosition

    public init(position: ChessPosition) {
        self.position = position
    }

    public init?(fen: String) {
        guard let position = ChessPosition(fen: fen) else { return nil }
        self.position = position
    }

    /// Starting position with full castling rights.
    public init() {
        self.position = ChessPosition(
            board: TemplateBook.standardStartPlacement,
            sideToMove: .white,
            castling: .all
        )
    }

    public struct Sync: Sendable {
        /// Moves matched, oldest first. Empty when the board is unchanged.
        public let moves: [Move]
        public let sans: [String]
        /// Position after applying `moves`.
        public let fen: String
        /// True when the observation could not be explained by legal play and the
        /// tracker adopted the observed board wholesale.
        public let didResync: Bool

        public var lastMove: Move? { moves.last }
        public var lastSAN: String? { sans.last }
    }

    /// Feeds one observed placement (64 squares, FEN order) and advances as far as needed.
    public mutating func observe(_ placement: [Piece]) -> Sync {
        if placement == position.board {
            return Sync(moves: [], sans: [], fen: position.fen, didResync: false)
        }

        // One ply: the common case, one move has been played since the last screenshot.
        let onePly = self.moves(in: position, reaching: placement)
        if onePly.count == 1, let move = onePly.first {
            let san = SAN.san(for: move, in: position)
            position = position.applying(move)
            return Sync(moves: [move], sans: [san], fen: position.fen, didResync: false)
        }

        // Two plies: the screenshot came after both sides moved (or a frame was missed).
        if onePly.isEmpty {
            var twoPly: [(Move, Move, ChessPosition)] = []
            for first in MoveGenerator.legalMoves(in: position) {
                let afterFirst = position.applying(first)
                for second in self.moves(in: afterFirst, reaching: placement) {
                    twoPly.append((first, second, afterFirst))
                }
                if twoPly.count > 1 { break }
            }
            if twoPly.count == 1 {
                let (first, second, afterFirst) = twoPly[0]
                let san1 = SAN.san(for: first, in: position)
                let san2 = SAN.san(for: second, in: afterFirst)
                position = afterFirst.applying(second)
                return Sync(moves: [first, second], sans: [san1, san2],
                            fen: position.fen, didResync: false)
            }
        }

        // Not explainable by legal play: adopt the board and keep what can be derived.
        position = resynced(to: placement)
        return Sync(moves: [], sans: [], fen: position.fen, didResync: true)
    }

    private func moves(
        in position: ChessPosition, reaching placement: [Piece]
    ) -> [Move] {
        MoveGenerator.legalMoves(in: position).filter {
            position.applying($0).board == placement
        }
    }

    /// Rebuilds what the pixels can support: the board, and castling rights inferred from
    /// kings and rooks still sitting on their home squares.
    ///
    /// Side to move is unknowable from one frame, with one useful exception: if the board
    /// is exactly the starting position then this is a fresh game, so White is to move and
    /// every castling right is intact. That covers the common case of starting another game
    /// without taking a new calibration screenshot. Anything else keeps the previous turn,
    /// and `didResync` tells the caller the position is an assumption.
    private func resynced(to placement: [Piece]) -> ChessPosition {
        if placement == TemplateBook.standardStartPlacement {
            return ChessPosition(
                board: placement,
                sideToMove: .white,
                castling: .all,
                enPassant: nil,
                halfmoveClock: 0,
                fullmoveNumber: 1
            )
        }

        var rights: CastlingRights = []
        if placement[60] == .piece(.king, .white) {
            if placement[63] == .piece(.rook, .white) { rights.insert(.whiteKingside) }
            if placement[56] == .piece(.rook, .white) { rights.insert(.whiteQueenside) }
        }
        if placement[4] == .piece(.king, .black) {
            if placement[7] == .piece(.rook, .black) { rights.insert(.blackKingside) }
            if placement[0] == .piece(.rook, .black) { rights.insert(.blackQueenside) }
        }
        var next = position
        next.board = placement
        next.castling = rights
        next.enPassant = nil
        return next
    }
}
