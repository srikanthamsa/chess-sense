import Foundation

public struct CastlingRights: Sendable, Equatable, OptionSet {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let whiteKingside = CastlingRights(rawValue: 1 << 0)
    public static let whiteQueenside = CastlingRights(rawValue: 1 << 1)
    public static let blackKingside = CastlingRights(rawValue: 1 << 2)
    public static let blackQueenside = CastlingRights(rawValue: 1 << 3)
    public static let all: CastlingRights = [
        .whiteKingside, .whiteQueenside, .blackKingside, .blackQueenside,
    ]

    public var fenString: String {
        var s = ""
        if contains(.whiteKingside) { s += "K" }
        if contains(.whiteQueenside) { s += "Q" }
        if contains(.blackKingside) { s += "k" }
        if contains(.blackQueenside) { s += "q" }
        return s.isEmpty ? "-" : s
    }

    public init(fenString: String) {
        var rights: CastlingRights = []
        for c in fenString {
            switch c {
            case "K": rights.insert(.whiteKingside)
            case "Q": rights.insert(.whiteQueenside)
            case "k": rights.insert(.blackKingside)
            case "q": rights.insert(.blackQueenside)
            default: break
            }
        }
        self = rights
    }
}

/// A complete chess position. Board indexing is 0 = a8 ... 63 = h1 (see `Square`).
public struct ChessPosition: Sendable, Equatable {
    public var board: [Piece]
    public var sideToMove: PieceColor
    public var castling: CastlingRights
    public var enPassant: Square?
    public var halfmoveClock: Int
    public var fullmoveNumber: Int

    public init(
        board: [Piece],
        sideToMove: PieceColor = .white,
        castling: CastlingRights = [],
        enPassant: Square? = nil,
        halfmoveClock: Int = 0,
        fullmoveNumber: Int = 1
    ) {
        precondition(board.count == 64)
        self.board = board
        self.sideToMove = sideToMove
        self.castling = castling
        self.enPassant = enPassant
        self.halfmoveClock = halfmoveClock
        self.fullmoveNumber = fullmoveNumber
    }

    public init?(fen: String) {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 4 else { return nil }

        var board = [Piece](repeating: .empty, count: 64)
        let ranks = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { return nil }
        for (rankIdx, rankText) in ranks.enumerated() {
            var file = 0
            for ch in rankText {
                if let digit = ch.wholeNumberValue, digit >= 1, digit <= 8 {
                    file += digit
                } else if let piece = Piece(fenLetter: ch) {
                    guard file < 8 else { return nil }
                    board[rankIdx * 8 + file] = piece
                    file += 1
                } else {
                    return nil
                }
            }
            guard file == 8 else { return nil }
        }

        self.board = board
        self.sideToMove = fields[1] == "b" ? .black : .white
        self.castling = CastlingRights(fenString: fields[2])
        self.enPassant = fields[3] == "-" ? nil : square(from: fields[3])
        self.halfmoveClock = fields.count > 4 ? (Int(fields[4]) ?? 0) : 0
        self.fullmoveNumber = fields.count > 5 ? (Int(fields[5]) ?? 1) : 1
    }

    public var fen: String {
        var ranks: [String] = []
        for rankIdx in 0..<8 {
            var s = ""
            var gap = 0
            for file in 0..<8 {
                let p = board[rankIdx * 8 + file]
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
        let ep = enPassant.map(squareName) ?? "-"
        return ranks.joined(separator: "/")
            + " \(turn) \(castling.fenString) \(ep) \(halfmoveClock) \(fullmoveNumber)"
    }

    // MARK: - Queries

    @inline(__always)
    public func piece(at s: Square) -> Piece { board[s] }

    public func kingSquare(of color: PieceColor) -> Square? {
        board.firstIndex { $0 == .piece(.king, color) }
    }

    public var opponent: PieceColor { sideToMove == .white ? .black : .white }

    /// True when `square` is attacked by any piece of `color`. Used for check detection
    /// and for castling through-check rules.
    public func isAttacked(_ square: Square, by color: PieceColor) -> Bool {
        let f = fileIndex(square)
        let r = rankIndex(square)

        // Pawns: a White pawn attacks towards lower rankIndex, so it must sit one rank
        // *below* the target in index terms.
        let pawnRank = color == .white ? r + 1 : r - 1
        for df in [-1, 1] {
            let pf = f + df
            guard isOnBoard(file: pf, rankIndex: pawnRank) else { continue }
            if board[pf + pawnRank * 8] == .piece(.pawn, color) { return true }
        }

        // Knights
        for (df, dr) in [(1, 2), (2, 1), (2, -1), (1, -2),
                         (-1, -2), (-2, -1), (-2, 1), (-1, 2)] {
            let nf = f + df, nr = r + dr
            guard isOnBoard(file: nf, rankIndex: nr) else { continue }
            if board[nf + nr * 8] == .piece(.knight, color) { return true }
        }

        // King
        for (df, dr) in [(0, 1), (1, 1), (1, 0), (1, -1),
                         (0, -1), (-1, -1), (-1, 0), (-1, 1)] {
            let kf = f + df, kr = r + dr
            guard isOnBoard(file: kf, rankIndex: kr) else { continue }
            if board[kf + kr * 8] == .piece(.king, color) { return true }
        }

        // Sliders
        func rayHits(_ directions: [(Int, Int)], _ kinds: [PieceKind]) -> Bool {
            for (df, dr) in directions {
                var nf = f + df, nr = r + dr
                while isOnBoard(file: nf, rankIndex: nr) {
                    let p = board[nf + nr * 8]
                    if case let .piece(kind, c) = p {
                        if c == color && kinds.contains(kind) { return true }
                        break
                    }
                    nf += df; nr += dr
                }
            }
            return false
        }
        let diagonal = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        let orthogonal = [(0, 1), (1, 0), (0, -1), (-1, 0)]
        if rayHits(diagonal, [.bishop, .queen]) { return true }
        if rayHits(orthogonal, [.rook, .queen]) { return true }
        return false
    }

    public var isInCheck: Bool {
        guard let k = kingSquare(of: sideToMove) else { return false }
        return isAttacked(k, by: opponent)
    }

    // MARK: - Applying a move

    public func applying(_ move: Move) -> ChessPosition {
        var next = self
        var nextBoard = board
        let mover = board[move.from]
        var kind: PieceKind = .pawn
        var moverColor: PieceColor = .white
        if case let .piece(k, c) = mover { kind = k; moverColor = c }

        // Lift the moving piece, handle the captured piece.
        nextBoard[move.from] = .empty
        if move.isEnPassant {
            let capturedSquare = move.to + (moverColor == .white ? 8 : -8)
            nextBoard[capturedSquare] = .empty
        }
        nextBoard[move.to] = move.promotion.map { .piece($0, moverColor) } ?? mover

        // Castling moves the rook too.
        if move.isCastle {
            if move.isKingsideCastle {
                let rookFrom = move.from + 3
                nextBoard[move.to - 1] = nextBoard[rookFrom]
                nextBoard[rookFrom] = .empty
            } else {
                let rookFrom = move.from - 4
                nextBoard[move.to + 1] = nextBoard[rookFrom]
                nextBoard[rookFrom] = .empty
            }
        }

        // Castling rights: lost by moving the king or a rook, or by a rook being captured.
        if kind == .king {
            next.castling.remove(moverColor == .white
                ? [.whiteKingside, .whiteQueenside]
                : [.blackKingside, .blackQueenside])
        }
        if kind == .rook {
            switch move.from {
            case 63: next.castling.remove(.whiteKingside)
            case 56: next.castling.remove(.whiteQueenside)
            case 7: next.castling.remove(.blackKingside)
            case 0: next.castling.remove(.blackQueenside)
            default: break
            }
        }
        switch move.to {
        case 63: next.castling.remove(.whiteKingside)
        case 56: next.castling.remove(.whiteQueenside)
        case 7: next.castling.remove(.blackKingside)
        case 0: next.castling.remove(.blackQueenside)
        default: break
        }

        // En passant target: only set by a double pawn push.
        next.enPassant = nil
        if kind == .pawn, abs(rankIndex(move.to) - rankIndex(move.from)) == 2 {
            next.enPassant = (move.from + move.to) / 2
        }

        // Clocks.
        let isCapture = board[move.to] != .empty || move.isEnPassant
        next.halfmoveClock = (kind == .pawn || isCapture) ? 0 : halfmoveClock + 1
        if sideToMove == .black { next.fullmoveNumber = fullmoveNumber + 1 }

        next.board = nextBoard
        next.sideToMove = opponent
        return next
    }

    /// Resolves a UCI string (`"e2e4"`, `"e7e8q"`) against the legal moves here.
    public func move(uci: String) -> Move? {
        let legal = MoveGenerator.legalMoves(in: self)
        return legal.first {
            $0.uci == uci.lowercased()
        } ?? legal.first {
            $0.from == square(from: String(uci.prefix(2)))
                && $0.to == square(from: String(uci.dropFirst(2).prefix(2)))
        }
    }
}

extension ChessPosition: CustomStringConvertible {
    public var description: String { fen }
}
