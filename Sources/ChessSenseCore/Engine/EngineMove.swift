import Foundation

/// One engine answer. `san` is filled in by the caller once the move is resolved against
/// the position, because only then is the notation unambiguous.
public struct EngineMove: Sendable, Equatable {
    public let uci: String
    public var san: String?
    public let principalVariation: String
    public let evalText: String
    public let provenance: String

    public init(
        uci: String,
        san: String? = nil,
        principalVariation: String,
        evalText: String,
        provenance: String
    ) {
        self.uci = uci
        self.san = san
        self.principalVariation = principalVariation
        self.evalText = evalText
        self.provenance = provenance
    }

    /// What the Island shows. Prefers SAN, falls back to unambiguous from-to.
    public var displayMove: String {
        if let san, !san.isEmpty { return san }
        guard uci.count >= 4 else { return uci }
        return "\(uci.prefix(2))\u{2013}\(uci.dropFirst(2).prefix(2))"
    }

    /// Principal variation rendered as SAN using the position it was computed from.
    public func principalVariationSAN(from position: ChessPosition, plies: Int = 5) -> String {
        var pos = position
        var parts: [String] = []
        for uciMove in principalVariation.split(separator: " ").prefix(plies) {
            guard let move = pos.move(uci: String(uciMove)) else { break }
            parts.append(SAN.san(for: move, in: pos))
            pos = pos.applying(move)
        }
        return parts.joined(separator: " ")
    }
}
