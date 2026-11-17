import Foundation

// Compiled into both the app (which starts and updates the activity) and the
// widget extension (which renders it). Keep it dependency-free.
#if canImport(ActivityKit)
import ActivityKit

public struct BestMoveAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// UCI move, e.g. "e2e4".
        public var uci: String
        /// Standard algebraic notation, e.g. "Nf3". Preferred for display.
        public var san: String
        /// Human-readable evaluation, e.g. "+0.34" or "#3".
        public var evalText: String
        /// Principal variation, space separated UCI moves.
        public var principalVariation: String
        /// e.g. "SF d31 / lichess cloud"
        public var provenance: String
        /// Whether the reader was confident enough to bet on this move.
        public var trusted: Bool

        public init(
            uci: String,
            san: String,
            evalText: String,
            principalVariation: String,
            provenance: String,
            trusted: Bool
        ) {
            self.uci = uci
            self.san = san
            self.evalText = evalText
            self.principalVariation = principalVariation
            self.provenance = provenance
            self.trusted = trusted
        }

        public var displayMove: String {
            if !san.isEmpty { return san }
            guard uci.count >= 4 else { return uci }
            let from = uci.prefix(2)
            let to = uci.dropFirst(2).prefix(2)
            return "\(from)\u{2013}\(to)"
        }
    }

    public var startedAt: Date

    public init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }
}
#endif
