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

public extension Piece {
    /// Parses a FEN piece letter (`"."` for empty).
    init?(fenLetter: Character) {
        if fenLetter == "." { self = .empty; return }
        let color: PieceColor = fenLetter.isUppercase ? .white : .black
        switch Character(fenLetter.lowercased()) {
        case "p": self = .piece(.pawn, color)
        case "n": self = .piece(.knight, color)
        case "b": self = .piece(.bishop, color)
        case "r": self = .piece(.rook, color)
        case "q": self = .piece(.queen, color)
        case "k": self = .piece(.king, color)
        default: return nil
        }
    }

    /// Stable single-character code: FEN letter, `"."` for empty.
    var code: String {
        fenLetter.map(String.init) ?? "."
    }
}

extension Piece: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let first = raw.first, let parsed = Piece(fenLetter: first) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "bad piece code \(raw)"
            ))
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(code)
    }
}

public enum BoardError: Error, CustomStringConvertible {
    case unreadableImage
    case notCalibrated
    case boardNotFound
    case implausibleRect(BoardRect)
    case inconsistentCalibration(square: String, expected: Piece, got: Piece)
    case unknownSquare(rank: Int, file: Int, bestDistance: Int)
    case verificationFailed(expected: String, got: String)
    case differentBoard(calibrated: String, found: String)

    public var description: String {
        switch self {
        case .unreadableImage: return "image could not be decoded"
        case .notCalibrated: return "no template book — calibrate from a fresh game first"
        case .boardNotFound: return "no 8x8 board-like region found"
        case let .implausibleRect(r): return "implausible board rect \(r)"
        case let .inconsistentCalibration(sq, expected, got):
            return "calibration frame mismatch at \(sq): expected \(expected), saw \(got)"
        case let .unknownSquare(rank, file, best):
            return "no template matched \(BoardRect.squareName(rank: rank, file: file)) "
                + "(closest shape distance \(best))"
        case let .differentBoard(c, f):
            return "this board looks different from your calibration (\(c) vs \(f))"
        case let .verificationFailed(expected, got):
            return "calibration did not reproduce the frame: expected \(expected), got \(got)"
        }
    }

    /// `description` above is for diagnostics and logs: it names internal machinery
    /// ("template", "shape distance", "board-like region") that means nothing to a player.
    /// This is the version that is allowed in front of a person — it says what happened and
    /// what to do about it, and nothing else.
    ///
    /// Kept under ~60 characters because the same string renders inside the Dynamic Island's
    /// two-line tip slot, which never ellipsizes. A longer sentence would be cut mid-word.
    public var userFacingDescription: String {
        switch self {
        case .unreadableImage:
            return "That screenshot couldn't be opened. Try again."
        case .notCalibrated:
            return "Pick a starting-position screenshot first."
        case .boardNotFound:
            return "No chess board found there. Screenshot the whole game."
        case .differentBoard:
            return "Different board than your calibration. Calibrate for this one."
        case .implausibleRect, .inconsistentCalibration, .unknownSquare, .verificationFailed:
            return "Couldn't read that board. Screenshot it again."
        }
    }
}
