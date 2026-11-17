import Foundation

/// A learned set of square templates for one (board theme x piece set) combination.
///
/// Built once from a calibration frame whose position is already known — by default
/// the standard starting position, which happens to contain 12 of the 13 classes
/// (all six piece types in both colours) plus empty squares.
///
/// Calibration is *self-verifying*: after learning, the frame is re-read and must
/// reproduce the expected position exactly. A wrong theme, a mid-animation frame or
/// a finished game therefore fails loudly instead of baking a broken book.
public struct TemplateBook: Sendable {
    public struct Entry: Sendable {
        public let piece: Piece
        public let signature: SquareSignature
        /// How many calibration squares produced this entry.
        public let support: Int
    }

    public struct Match: Sendable {
        public let piece: Piece
        public let shapeDistance: Int
        public let colorDistance: Double
        /// Margin to the runner-up in the other colour class. Small margin = unsure.
        public let colorMargin: Double
    }

    public let entries: [Entry]
    /// Max Hamming distance on the shape grid before a square is rejected.
    public let maxShapeDistance: Int
    /// Max |Δ ink luma| between the square and its template.
    public let maxColorDistance: Double
    public let createdAt: Date

    public init(
        entries: [Entry],
        maxShapeDistance: Int,
        maxColorDistance: Double,
        createdAt: Date = Date()
    ) {
        self.entries = entries
        self.maxShapeDistance = maxShapeDistance
        self.maxColorDistance = maxColorDistance
        self.createdAt = createdAt
    }

    public var pieces: Set<Piece> { Set(entries.map(\.piece)) }

    /// Two-stage classify, in the order the discriminative power actually lives:
    /// shape narrows to candidates, colour picks between them.
    /// Returns nil instead of guessing when nothing is close enough.
    public func classify(_ sig: SquareSignature) -> Match? {
        guard !entries.isEmpty else { return nil }

        let scored = entries.map {
            (entry: $0, shape: $0.signature.shapeDistance(to: sig))
        }
        guard let minShape = scored.map(\.shape).min() else { return nil }

        // Keep every entry within a small band of the best shape, then discriminate
        // by colour. The band absorbs anti-aliasing noise between square colours.
        let band = minShape + max(6, maxShapeDistance / 2)
        let candidates = scored.filter { $0.shape <= band && $0.shape <= maxShapeDistance }
        guard !candidates.isEmpty else { return nil }

        var best = candidates[0]
        var bestColor = best.entry.signature.colorDistance(to: sig)
        for c in candidates.dropFirst() {
            let cd = c.entry.signature.colorDistance(to: sig)
            if cd < bestColor { best = c; bestColor = cd }
        }

        // Runner-up from a *different colour class* tells us how ambiguous the call is.
        var margin = Double.infinity
        for c in candidates where c.entry.piece != best.entry.piece {
            let cd = c.entry.signature.colorDistance(to: sig)
            margin = min(margin, cd - bestColor)
        }
        if !margin.isFinite { margin = 1.0 }

        guard bestColor <= maxColorDistance else { return nil }

        return Match(
            piece: best.entry.piece,
            shapeDistance: best.shape,
            colorDistance: bestColor,
            colorMargin: margin
        )
    }

    public func bestShapeDistance(_ sig: SquareSignature) -> Int {
        entries.map { $0.signature.shapeDistance(to: sig) }.min() ?? Int.max
    }
}

public extension TemplateBook {
    /// The 64 square contents of the standard starting position, in FEN order
    /// (rank 8 first, file a first).
    static var standardStartPlacement: [Piece] {
        let back: [PieceKind] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        var p: [Piece] = []
        for kind in back { p.append(.piece(kind, .black)) }
        for _ in 0..<8 { p.append(.piece(.pawn, .black)) }
        for _ in 0..<32 { p.append(.empty) }
        for _ in 0..<8 { p.append(.piece(.pawn, .white)) }
        for kind in back { p.append(.piece(kind, .white)) }
        return p
    }

    /// Learns templates from a calibration frame that is known to show `placement`.
    ///
    /// Squares sharing a piece get sub-clustered, so a piece that renders slightly
    /// differently on light vs dark squares yields two entries instead of one
    /// smeared average.
    static func bootstrap(
        signatures: [SquareSignature],
        placement: [Piece],
        shapeTolerance: Int = 12,
        colorTolerance: Double = 0.10
    ) throws -> TemplateBook {
        precondition(signatures.count == 64 && placement.count == 64)

        var entries: [Entry] = []
        for piece in Set(placement) {
            let indices = (0..<64).filter { placement[$0] == piece }
            guard !indices.isEmpty else { continue }

            // Greedy sub-clustering within one piece class.
            var clusters: [[Int]] = []
            for idx in indices {
                var placed = false
                for ci in clusters.indices {
                    let medoid = clusters[ci][0]
                    if signatures[idx].shapeDistance(to: signatures[medoid]) <= shapeTolerance,
                       signatures[idx].colorDistance(to: signatures[medoid]) <= colorTolerance {
                        clusters[ci].append(idx)
                        placed = true
                        break
                    }
                }
                if !placed { clusters.append([idx]) }
            }

            for cluster in clusters {
                // Medoid = member with the smallest total distance to its peers.
                var medoid = cluster[0]
                var bestSum = Int.max
                for m in cluster {
                    var sum = 0
                    for other in cluster where other != m {
                        sum += signatures[m].shapeDistance(to: signatures[other])
                    }
                    if sum < bestSum { bestSum = sum; medoid = m }
                }
                entries.append(Entry(
                    piece: piece,
                    signature: signatures[medoid],
                    support: cluster.count
                ))
            }
        }

        entries.sort { "\($0.piece)" < "\($1.piece)" }
        return TemplateBook(
            entries: entries,
            maxShapeDistance: shapeTolerance,
            maxColorDistance: colorTolerance
        )
    }
}
