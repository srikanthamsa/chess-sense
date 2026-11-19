import SwiftUI

/// Visual language for the Live Activity, shared by the widget extension and the in-app
/// design studio so what you preview is literally what the Island renders.
///
/// This is a chess set, not a dashboard: charcoal, cream, one gold. The island borrows the
/// presentation model the web's best island component (islandcn) converged on — a compact
/// face, a split face, and an expanded card — but the parts are chess parts: a piece on a
/// walnut square, the move, the evaluation ring, and one line of reasoning.
public enum Island {
    public static let moveSize: CGFloat = 30
    public static let whySize: CGFloat = 11.5
    public static let barHeight: CGFloat = 4

    public static let jade = Theme.good
    public static let crimson = Theme.bad
    public static let amber = Theme.gold
    public static let gold = Theme.gold
    public static let violet = Theme.ink
    public static let sky = Theme.ink
    public static let lavender = Theme.mute
    public static let neutral = Theme.mute
}

// MARK: - State

/// Three distinguishable situations. Collapsing "waiting" and "could not read" into one
/// empty state made the rejected face render as a skeleton forever.
public enum IslandPresentation {
    case move, pending, rejected

    public init(_ state: BestMoveAttributes.ContentState) {
        if !state.trusted { self = .rejected }
        else if state.san.isEmpty || state.uci == "----" { self = .pending }
        else { self = .move }
    }
}

/// One accent per state, and every accent has a reason: a finishing blow, a promotion, a
/// capture, castling, a check, then how the position stands.
public enum IslandAccent {
    public static func resolve(_ state: BestMoveAttributes.ContentState) -> Color {
        if !state.trusted { return Theme.gold }
        let san = state.san
        if san.contains("#") { return Theme.gold }
        if san.contains("=") { return Theme.ink }
        if san.contains("x") { return Theme.gold }
        if san.contains("O-O") { return Theme.gold }
        if san.contains("+") { return Theme.gold }
        let f = advantageFraction(state.youEval)
        if f > 0.58 { return Theme.good }
        if f < 0.42 { return Theme.bad }
        return Theme.gold
    }
}

/// Signed value in pawns, squashed so everyday edges stay near the centre.
public func advantageFraction(_ text: String) -> Double {
    if text.hasPrefix("#") { return 1 }
    if text.hasPrefix("-#") { return 0 }
    let value = Double(text.replacingOccurrences(of: "+", with: "")) ?? 0
    return 0.5 + 0.5 * tanh(value / 2.5)
}

public func advantageTint(_ text: String) -> Color {
    let f = advantageFraction(text)
    if f > 0.56 { return Theme.good }
    if f < 0.44 { return Theme.bad }
    return Theme.mute
}

// MARK: - Small parts

/// The board square a piece sits on: the island's one literal reference to a chess set.
public struct CheckerMark: View {
    let light: Bool
    public init(light: Bool) { self.light = light }

    public var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(light ? Theme.squareLight : Theme.squareDark)
    }
}

/// A piece, drawn from the same asset set the reader matches against.

/// The piece art on its own — no tile, no background. Used inside the island, where a filled
/// square behind a transparent glyph reads as a coloured block.
public struct IslandPiece: View {
    let symbol: String
    var size: CGFloat = 20

    public init(symbol: String, size: CGFloat = 20) {
        self.symbol = symbol
        self.size = size
    }

    public var body: some View {
        Group {
            if let asset = PieceAsset.name(for: symbol) {
                Image(asset)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "knight")
                    .font(.system(size: size * 0.6, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Maps either convention — an asset name ("bQ") or a Unicode glyph ("♛") — to a bundled piece.
enum PieceAsset {
    static func name(for symbol: String) -> String? {
        if symbol.count >= 2, symbol.first == "w" || symbol.first == "b" {
            let kind = symbol.dropFirst().uppercased()
            return ["K", "Q", "R", "B", "N", "P"].contains(kind) ? String(symbol.prefix(1)) + kind : nil
        }
        guard symbol.unicodeScalars.count == 1, let scalar = symbol.unicodeScalars.first else { return nil }
        switch scalar.value {
        case 0x2654: return "wK"
        case 0x2655: return "wQ"
        case 0x2656: return "wR"
        case 0x2657: return "wB"
        case 0x2658: return "wN"
        case 0x2659: return "wP"
        case 0x265A: return "bK"
        case 0x265B: return "bQ"
        case 0x265C: return "bR"
        case 0x265D: return "bB"
        case 0x265E: return "bN"
        case 0x265F: return "bP"
        default: return nil
        }
    }
}

public struct PieceBadge: View {
    let symbol: String
    let accent: Color
    var diameter: CGFloat = 30

    public init(symbol: String, accent: Color, diameter: CGFloat = 30) {
        self.symbol = symbol
        self.accent = accent
        self.diameter = diameter
    }

    /// No tile behind the art. The pieces are transparent graphics; a filled square behind
    /// them reads as a coloured block, which is what the island was showing.
    public var body: some View {
        IslandPiece(symbol: symbol, size: diameter)
    }
}

public struct EvalPill: View {
    let evalText: String
    let trusted: Bool

    public init(evalText: String, trusted: Bool) {
        self.evalText = evalText
        self.trusted = trusted
    }

    private var tint: Color { trusted ? advantageTint(evalText) : Theme.mute }

    public var body: some View {
        HStack(spacing: 4) {
            LevelMeter(value: advantageFraction(evalText), tint: tint)
            SteadyText(display, size: 12, weight: .semibold, tint: tint)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Theme.panel)
        )
        .overlay(
            Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 0.5)
        )
    }

    private var display: String {
        guard trusted else { return "—" }
        if evalText.hasPrefix("#") || evalText.hasPrefix("-#") { return evalText }
        return evalText.hasPrefix("-") ? evalText : "+" + evalText.replacingOccurrences(of: "+", with: "")
    }
}

/// Diverging bar: the centre is level, the fill is who is better.
public struct AdvantageBar: View {
    let evalText: String
    var height: CGFloat = Island.barHeight
    var tint: Color = Theme.mute

    public init(evalText: String, height: CGFloat = Island.barHeight, tint: Color = Theme.mute) {
        self.evalText = evalText
        self.height = height
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { geo in
            let f = advantageFraction(evalText)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule()
                    .fill(tint)
                    .frame(width: max(2, geo.size.width * abs(f - 0.5) * 2))
                    .offset(x: f >= 0.5 ? geo.size.width / 2 : geo.size.width / 2 - geo.size.width * (0.5 - f) * 2)
            }
        }
        .frame(height: height)
        .animation(Spring.snappy, value: evalText)
    }
}

// MARK: - Compact

public struct IslandCompactLeading: View {
    let move: String
    let trusted: Bool
    let accent: Color
    let presentation: IslandPresentation
    var symbol: String = ""

    public init(move: String, trusted: Bool, accent: Color,
                presentation: IslandPresentation, symbol: String = "") {
        self.move = move
        self.trusted = trusted
        self.accent = accent
        self.presentation = presentation
        self.symbol = symbol
    }

    public var body: some View {
        ZStack {
            if presentation == .pending {
                ProgressRing(value: 0.62, lineWidth: 2, tint: Theme.gold, track: Theme.line)
                    .frame(width: 16, height: 16)
            } else if presentation == .rejected {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.gold)
            } else {
                // The piece on its own: no tile behind it. The art is transparent, so a
                // background here reads as a coloured square inside the island.
                IslandPiece(symbol: symbol.isEmpty ? "N" : symbol, size: 19)
            }
        }
    }
}

public struct IslandCompactTrailing: View {
    let move: String
    let trusted: Bool
    let accent: Color
    let evalText: String

    public init(move: String, trusted: Bool, accent: Color, evalText: String) {
        self.move = move
        self.trusted = trusted
        self.accent = accent
        self.evalText = evalText
    }

    public var body: some View {
        HStack(spacing: 5) {
            SteadyText(trusted ? move : "—", size: 13, weight: .semibold, tint: Theme.ink)
            Circle()
                .fill(trusted ? advantageTint(evalText) : Theme.mute)
                .frame(width: 5, height: 5)
        }
    }
}

public struct IslandMinimal: View {
    let move: String
    let presentation: IslandPresentation
    let symbol: String
    let accent: Color

    public init(move: String, presentation: IslandPresentation, symbol: String, accent: Color) {
        self.move = move
        self.presentation = presentation
        self.symbol = symbol
        self.accent = accent
    }

    public var body: some View {
        Group {
            switch presentation {
            case .move:
                PieceBadge(symbol: symbol, accent: accent, diameter: 18)
            case .pending:
                ProgressRing(value: 0.62, lineWidth: 2, tint: Theme.gold)
                    .frame(width: 15, height: 15)
            case .rejected:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.gold)
            }
        }
    }
}

// MARK: - Expanded regions

public struct IslandExpandedLeading: View {
    let state: BestMoveAttributes.ContentState
    var thinking: Bool = false

    public init(state: BestMoveAttributes.ContentState, thinking: Bool = false) {
        self.state = state
        self.thinking = thinking
    }

    private var presentation: IslandPresentation { IslandPresentation(state) }

    public var body: some View {
        Group {
            switch presentation {
            case .move:
                PieceBadge(symbol: state.pieceSymbol,
                           accent: IslandAccent.resolve(state),
                           diameter: 36)
            case .pending:
                ProgressRing(value: 0.62, lineWidth: 2.5, tint: Theme.gold)
                    .frame(width: 30, height: 30)
            case .rejected:
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.panel)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.gold)
                    )
            }
        }
    }
}

public struct IslandExpandedMove: View {
    let state: BestMoveAttributes.ContentState

    public init(state: BestMoveAttributes.ContentState) { self.state = state }

    private var presentation: IslandPresentation { IslandPresentation(state) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if presentation == .move {
                SteadyText(state.displayMove, size: 24, weight: .semibold, tint: Theme.ink)
                Text(state.youEval.isEmpty ? "best move" : "you are " + state.youEval)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Theme.mute)
            } else if presentation == .pending {
                Text("Waiting for a screenshot")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink.opacity(0.75))
                    .lineLimit(1)
            } else {
                Text("Couldn't read that board")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .animation(Spring.snappy, value: presentation == .move)
    }
}

/// The strip under the move: the reason, or the waiting state.
public struct IslandExpandedDetail: View {
    let state: BestMoveAttributes.ContentState

    public init(state: BestMoveAttributes.ContentState) { self.state = state }

    private var presentation: IslandPresentation { IslandPresentation(state) }
    private var accent: Color { IslandAccent.resolve(state) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if presentation == .move {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Rectangle()
                        .fill(accent)
                        .frame(width: 2, height: 12)
                        .offset(y: 1)
                    Text(state.why)
                        .font(.system(size: Island.whySize, weight: .regular))
                        .lineSpacing(1.5)
                        .foregroundStyle(Theme.ink.opacity(0.82))
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                AdvantageBar(evalText: state.youEval, height: 3, tint: advantageTint(state.youEval))
                    .frame(maxWidth: 150)
            } else if presentation == .pending {
                HStack(spacing: 6) {
                    ShimmerText("Reading the board", size: 12)
                    Spacer(minLength: 0)
                }
            } else {
                Text("Frame the whole board and try again")
                    .font(.system(size: Island.whySize))
                    .foregroundStyle(Theme.mute)
            }
        }
    }
}

/// Kept for the studio and older call sites.
public struct IslandExpandedBottom: View {
    let state: BestMoveAttributes.ContentState
    public init(state: BestMoveAttributes.ContentState) { self.state = state }
    public var body: some View { IslandExpandedDetail(state: state) }
}

/// The expanded card as one piece, for the in-app studio.
public struct IslandExpandedCard: View {
    let state: BestMoveAttributes.ContentState
    public init(state: BestMoveAttributes.ContentState) { self.state = state }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                IslandExpandedLeading(state: state)
                IslandExpandedMove(state: state)
                Spacer(minLength: 4)
                EvalPill(evalText: state.youEval, trusted: state.trusted)
            }
            IslandExpandedDetail(state: state)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Lock screen

public struct LockScreenCard: View {
    let state: BestMoveAttributes.ContentState
    public init(state: BestMoveAttributes.ContentState) { self.state = state }

    private var presentation: IslandPresentation { IslandPresentation(state) }
    private var accent: Color { IslandAccent.resolve(state) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Rectangle().fill(accent).frame(width: 14, height: 2)
                Text("SNSE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Theme.mute)
                Spacer()
                if presentation == .move {
                    EvalPill(evalText: state.youEval, trusted: state.trusted)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                if presentation == .move {
                    PieceBadge(symbol: state.pieceSymbol, accent: accent, diameter: 30)
                    SteadyText(state.displayMove, size: 28, weight: .semibold, tint: Theme.ink)
                } else if presentation == .pending {
                    ShimmerText("Reading the board", size: 15)
                } else {
                    Text("Couldn't read")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink.opacity(0.85))
                }
                Spacer(minLength: 0)
            }

            if presentation == .move, !state.why.isEmpty {
                Text(state.why)
                    .font(.system(size: 13, weight: .medium))
                    .lineSpacing(1.2)
                    .foregroundStyle(Theme.ink.opacity(0.78))
                    .lineLimit(2)
            }

            if presentation == .move, !state.youEval.isEmpty {
                AdvantageBar(evalText: state.youEval, height: 3, tint: advantageTint(state.youEval))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
