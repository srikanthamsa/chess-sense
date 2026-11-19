import Foundation

/// One ply. Derived facts (capture, check) are read off the position rather than stored,
/// so a `Move` can never disagree with the board it was generated from.
public struct Move: Sendable, Hashable {
    public let from: Square
    public let to: Square
    public let promotion: PieceKind?
    public let isEnPassant: Bool
    /// King moves two squares — the rook leg is implied.
    public let isCastle: Bool

    public init(
        from: Square,
        to: Square,
        promotion: PieceKind? = nil,
        isEnPassant: Bool = false,
        isCastle: Bool = false
    ) {
        self.from = from
        self.to = to
        self.promotion = promotion
        self.isEnPassant = isEnPassant
        self.isCastle = isCastle
    }

    /// Long algebraic, e.g. `"e2e4"`, `"e7e8q"`.
    public var uci: String {
        squareName(from) + squareName(to) + (promotion.map(promotionLetter) ?? "")
    }

    public var isKingsideCastle: Bool {
        isCastle && fileIndex(to) == 6
    }

    public var isQueensideCastle: Bool {
        isCastle && fileIndex(to) == 2
    }
}

extension Move: CustomStringConvertible {
    public var description: String { uci }
}
