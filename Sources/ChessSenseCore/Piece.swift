import Foundation

public enum PieceColor: Sendable, Hashable {
    case white, black
}

public enum PieceKind: Sendable, Hashable {
    case pawn, knight, bishop, rook, queen, king

    public var letter: Character {
        switch self {
        case .pawn: return "p"
        case .knight: return "n"
        case .bishop: return "b"
        case .rook: return "r"
        case .queen: return "q"
        case .king: return "k"
        }
    }
}

/// A square's contents. `.empty` is a first-class case rather than an optional so
/// empty squares take part in template calibration like everything else.
public enum Piece: Sendable, Hashable {
    case empty
    case piece(PieceKind, PieceColor)

    public var fenLetter: Character? {
        switch self {
        case .empty: return nil
        case let .piece(kind, color):
            let l = kind.letter
            return color == .white ? Character(l.uppercased()) : l
        }
    }

    public var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }
}

extension Piece: CustomStringConvertible {
    public var description: String {
        switch self {
        case .empty: return "."
        case let .piece(kind, color):
            var c = String(kind.letter)
            if color == .white { c = c.uppercased() }
            return c
        }
    }
}

public enum BoardError: Error, CustomStringConvertible {
    case unreadableImage
    case boardNotFound
    case implausibleRect(BoardRect)
    case inconsistentCalibration(square: String, expected: Piece, got: Piece)
    case unknownSquare(rank: Int, file: Int, bestDistance: Int)
    case verificationFailed(expected: String, got: String)

    public var description: String {
        switch self {
        case .unreadableImage: return "image could not be decoded"
        case .boardNotFound: return "no 8x8 board-like region found"
        case let .implausibleRect(r): return "implausible board rect \(r)"
        case let .inconsistentCalibration(sq, expected, got):
            return "calibration frame mismatch at \(sq): expected \(expected), saw \(got)"
        case let .unknownSquare(rank, file, best):
            return "no template matched \(BoardRect.squareName(rank: rank, file: file)) "
                + "(closest shape distance \(best))"
        case let .verificationFailed(expected, got):
            return "calibration did not reproduce the frame: expected \(expected), got \(got)"
        }
    }
}
