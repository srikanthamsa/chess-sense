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
        /// Plain-English reason, with no chess notation anywhere in it.
        public var why: String

        public init(
            uci: String,
            san: String,
            evalText: String,
            principalVariation: String,
            provenance: String,
            trusted: Bool,
            why: String = ""
        ) {
            self.uci = uci
            self.san = san
            self.evalText = evalText
            self.principalVariation = principalVariation
            self.provenance = provenance
            self.trusted = trusted
            self.why = why
        }

        public var displayMove: String {
            if !san.isEmpty { return san }
            guard uci.count >= 4 else { return uci }
            let from = uci.prefix(2)
            let to = uci.dropFirst(2).prefix(2)
            return "\(from)\u{2013}\(to)"
        }

        /// 0...1 for an advantage bar, 0.5 = equal. Mate maps to the extremes.
        public var advantage: Double {
            if evalText.hasPrefix("-#") { return 0.02 }
            if evalText.hasPrefix("#") { return 0.98 }
            guard let value = Double(evalText.replacingOccurrences(of: "+", with: "")) else {
                return 0.5
            }
            // Squash so small edges stay near the middle and big edges saturate.
            let squashed = tanh(value / 2.4)
            return min(0.98, max(0.02, 0.5 + squashed / 2))
        }

        /// Short, sign-only value for the compact Island: "+0.2", "-1.4", "#3".
        public var compactEval: String {
            if evalText.hasPrefix("#") || evalText.hasPrefix("-#") { return evalText }
            guard let value = Double(evalText.replacingOccurrences(of: "+", with: "")) else {
                return evalText
            }
            return String(format: "%+.1f", value)
        }
    }

    public var startedAt: Date

    public init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }
}
#endif
