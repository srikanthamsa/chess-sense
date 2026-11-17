import Foundation

/// Board squares are indexed 0...63 with **0 = a8** (top-left, Black's back rank) and
/// **63 = h1**, matching the order `BoardReader` already emits and FEN's own rank order.
/// `file` is 0 = a, `rankIndex` is 0 = rank 8 (so White moves towards *lower* rankIndex).
public typealias Square = Int

@inline(__always) public func fileIndex(_ s: Square) -> Int { s & 7 }
@inline(__always) public func rankIndex(_ s: Square) -> Int { s >> 3 }

@inline(__always) public func square(file: Int, rankIndex: Int) -> Square {
    rankIndex * 8 + file
}

@inline(__always) public func isOnBoard(file: Int, rankIndex: Int) -> Bool {
    file >= 0 && file < 8 && rankIndex >= 0 && rankIndex < 8
}

/// `"e4"` style name.
public func squareName(_ s: Square) -> String {
    let f = Character(UnicodeScalar(UInt8(ascii: "a") + UInt8(fileIndex(s))))
    return "\(f)\(8 - rankIndex(s))"
}

public func squareName(_ file: Int, _ rankIndex: Int) -> String {
    squareName(square(file: file, rankIndex: rankIndex))
}

public func square(from name: String) -> Square? {
    guard name.count == 2, let f = name.first, let r = name.last,
          let fileValue = f.asciiValue, let rankValue = r.wholeNumberValue,
          fileValue >= 97, fileValue <= 104, rankValue >= 1, rankValue <= 8
    else { return nil }
    return square(file: Int(fileValue) - 97, rankIndex: 8 - rankValue)
}

/// Piece letter as used in SAN (`N` for knight, `""` for a pawn).
@inline(__always) public func sanLetter(_ kind: PieceKind) -> String {
    switch kind {
    case .pawn: return ""
    case .knight: return "N"
    case .bishop: return "B"
    case .rook: return "R"
    case .queen: return "Q"
    case .king: return "K"
    }
}

/// Uppercase letter for a promoted piece.
@inline(__always) public func promotionLetter(_ kind: PieceKind) -> String {
    sanLetter(kind).isEmpty ? "Q" : sanLetter(kind)
}
