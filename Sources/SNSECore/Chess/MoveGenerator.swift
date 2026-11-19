import Foundation

public enum MoveGenerator {
    /// Fully legal moves for the side to move (pseudo-legal, then filtered by leaving
    /// your own king in check).
    public static func legalMoves(in position: ChessPosition) -> [Move] {
        pseudoLegalMoves(in: position).filter { move in
            let next = position.applying(move)
            guard let king = next.kingSquare(of: position.sideToMove) else { return false }
            return !next.isAttacked(king, by: next.sideToMove)
        }
    }

    static func pseudoLegalMoves(in position: ChessPosition) -> [Move] {
        let us = position.sideToMove
        let them: PieceColor = us == .white ? .black : .white
        var moves: [Move] = []
        moves.reserveCapacity(64)

        for from in 0..<64 {
            guard case let .piece(kind, color) = position.board[from], color == us else { continue }
            let f = fileIndex(from)
            let r = rankIndex(from)

            switch kind {
            case .pawn:
                // Forward one rank as seen by the mover: White goes to lower rankIndex.
                let dr = us == .white ? -1 : 1
                let startRank = us == .white ? 6 : 1
                let promoRank = us == .white ? 0 : 7

                let oneR = r + dr
                if isOnBoard(file: f, rankIndex: oneR) {
                    let oneSquare = f + oneR * 8
                    if position.board[oneSquare] == .empty {
                        if oneR == promoRank {
                            for p in promotions() {
                                moves.append(Move(from: from, to: oneSquare, promotion: p))
                            }
                        } else {
                            moves.append(Move(from: from, to: oneSquare))
                            let twoR = r + 2 * dr
                            if r == startRank, isOnBoard(file: f, rankIndex: twoR) {
                                let twoSquare = f + twoR * 8
                                if position.board[twoSquare] == .empty {
                                    moves.append(Move(from: from, to: twoSquare))
                                }
                            }
                        }
                    }
                }

                for df in [-1, 1] {
                    let cf = f + df
                    let cr = r + dr
                    guard isOnBoard(file: cf, rankIndex: cr) else { continue }
                    let target = cf + cr * 8
                    if case let .piece(_, targetColor) = position.board[target], targetColor == them {
                        if cr == promoRank {
                            for p in promotions() {
                                moves.append(Move(from: from, to: target, promotion: p))
                            }
                        } else {
                            moves.append(Move(from: from, to: target))
                        }
                    } else if position.board[target] == .empty,
                              let ep = position.enPassant, ep == target {
                        moves.append(Move(from: from, to: target, isEnPassant: true))
                    }
                }

            case .knight:
                for (df, dr) in [(1, 2), (2, 1), (2, -1), (1, -2),
                                 (-1, -2), (-2, -1), (-2, 1), (-1, 2)] {
                    guard let t = squareIf(inside: f + df, r + dr) else { continue }
                    if canLand(on: t, mover: us, board: position.board) {
                        moves.append(Move(from: from, to: t))
                    }
                }

            case .bishop, .rook, .queen:
                let dirs: [(Int, Int)]
                switch kind {
                case .bishop: dirs = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
                case .rook: dirs = [(0, 1), (1, 0), (0, -1), (-1, 0)]
                default: dirs = [(1, 1), (1, -1), (-1, 1), (-1, -1),
                                 (0, 1), (1, 0), (0, -1), (-1, 0)]
                }
                for (df, dr) in dirs {
                    var cf = f + df, cr = r + dr
                    while let t = squareIf(inside: cf, cr) {
                        if position.board[t] == .empty {
                            moves.append(Move(from: from, to: t))
                        } else {
                            if canLand(on: t, mover: us, board: position.board) {
                                moves.append(Move(from: from, to: t))
                            }
                            break
                        }
                        cf += df; cr += dr
                    }
                }

            case .king:
                for (df, dr) in [(0, 1), (1, 1), (1, 0), (1, -1),
                                 (0, -1), (-1, -1), (-1, 0), (-1, 1)] {
                    guard let t = squareIf(inside: f + df, r + dr) else { continue }
                    if canLand(on: t, mover: us, board: position.board) {
                        moves.append(Move(from: from, to: t))
                    }
                }
                moves.append(contentsOf: castlingMoves(in: position, kingSquare: from))
            }
        }
        return moves
    }

    private static func promotions() -> [PieceKind] { [.queen, .rook, .bishop, .knight] }

    @inline(__always)
    private static func squareIf(inside file: Int, _ rank: Int) -> Square? {
        isOnBoard(file: file, rankIndex: rank) ? file + rank * 8 : nil
    }

    @inline(__always)
    private static func canLand(on square: Square, mover: PieceColor, board: [Piece]) -> Bool {
        switch board[square] {
        case .empty: return true
        case let .piece(_, color): return color != mover
        }
    }

    /// Castling needs three things the pseudo-legal filter can't express: the squares
    /// between king and rook are empty, the king is not currently in check, and the
    /// square it passes over is not attacked.
    private static func castlingMoves(
        in position: ChessPosition, kingSquare from: Square
    ) -> [Move] {
        let us = position.sideToMove
        guard let king = position.kingSquare(of: us), king == from else { return [] }
        // King must be on its home square for castling to be legal at all.
        guard from == (us == .white ? 60 : 4) else { return [] }

        var moves: [Move] = []
        let homeKingside = us == .white ? CastlingRights.whiteKingside : .blackKingside
        let homeQueenside = us == .white ? CastlingRights.whiteQueenside : .blackQueenside

        if position.castling.contains(homeKingside) {
            let f1 = from + 1, g1 = from + 2
            let rookSquare = from + 3
            if position.board[f1] == .empty,
               position.board[g1] == .empty,
               position.board[rookSquare] == .piece(.rook, us),
               !position.isAttacked(from, by: position.opponent),
               !position.isAttacked(f1, by: position.opponent) {
                moves.append(Move(from: from, to: g1, isCastle: true))
            }
        }

        if position.castling.contains(homeQueenside) {
            let d1 = from - 1, c1 = from - 2, b1 = from - 3
            let rookSquare = from - 4
            if position.board[d1] == .empty,
               position.board[c1] == .empty,
               position.board[b1] == .empty,
               position.board[rookSquare] == .piece(.rook, us),
               !position.isAttacked(from, by: position.opponent),
               !position.isAttacked(d1, by: position.opponent) {
                moves.append(Move(from: from, to: c1, isCastle: true))
            }
        }
        return moves
    }

    /// Move count at a fixed depth. Used by tests to anchor the rules against known
    /// perft values — the cheapest way to prove a move generator is correct.
    public static func perft(_ position: ChessPosition, depth: Int) -> Int {
        if depth == 0 { return 1 }
        var nodes = 0
        for move in legalMoves(in: position) {
            nodes += perft(position.applying(move), depth: depth - 1)
        }
        return nodes
    }
}
