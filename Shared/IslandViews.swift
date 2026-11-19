import SwiftUI

/// The Island uses a dark glass tile, white type, and semantic colour only.
/// Green and red show the position's value, and gold marks a check or a mate.
/// There is no decorative colour, no gradient, and no loader.
public enum Island {
    public static let moveSize: CGFloat = 30
    public static let whySize: CGFloat = 12.5
    public static let tileFill = Color.white.opacity(0.055)
    public static let tileStroke = Color.white.opacity(0.10)
}

// MARK: - State

public enum IslandPresentation {
    case move, pending, rejected

    public init(_ state: BestMoveAttributes.ContentState) {
        if !state.trusted { self = .rejected }
        else if state.san.isEmpty || state.uci == "----" { self = .pending }
        else { self = .move }
    }
}

/// Each state has one accent. Green and red show the position's value, and gold marks a check
/// or a mate. A neutral position uses the muted text colour.
public enum IslandAccent {
    public static func resolve(_ state: BestMoveAttributes.ContentState) -> Color {
        if !state.trusted { return Theme.bad }
        let san = state.san
        if san.contains("#") || san.contains("+") { return Theme.gold }
        let f = advantageFraction(state.youEval)
        if f > 0.58 { return Theme.good }
        if f < 0.42 { return Theme.bad }
        return Theme.mute
    }
}

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
    return Color.white.opacity(0.7)
}

private func hasEval(_ text: String) -> Bool { !text.isEmpty }

// MARK: - Piece art

/// The bundled art is black line work on transparency. White pieces are outlines and black
/// pieces are solid silhouettes. Template tinting keeps both visible on black, and the
/// outline still shows which side the piece belongs to.
public struct IslandPiece: View {
    let symbol: String
    var size: CGFloat = 20
    var tint: Color = .white

    public init(symbol: String, size: CGFloat = 20, tint: Color = .white) {
        self.symbol = symbol
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        Group {
            if let asset = PieceAsset.name(for: symbol) {
                Image(asset)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .foregroundStyle(tint)
            } else if symbol.isEmpty {
                Circle()
                    .fill(tint.opacity(0.45))
                    .padding(size * 0.4)
            } else {
                Image(systemName: "knight")
                    .font(.system(size: size * 0.66, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
    }
}

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

/// A rounded dark-glass square holds the piece. While the board is being read it holds the
/// app's muted knight, so the wait shows a chess mark, not a loading control.
public struct PieceTile: View {
    let symbol: String
    let presentation: IslandPresentation
    var size: CGFloat = 34
    var showsTile: Bool = true

    public init(symbol: String, presentation: IslandPresentation,
                size: CGFloat = 34, showsTile: Bool = true) {
        self.symbol = symbol
        self.presentation = presentation
        self.size = size
        self.showsTile = showsTile
    }

    private var cornerRadius: CGFloat {
        if size >= 30 { return 10 }
        if size >= 20 { return 8 }
        return 6
    }

    public var body: some View {
        ZStack {
            if showsTile {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Island.tileFill)
                    .frame(width: size, height: size)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(presentation == .rejected
                                  ? Theme.bad.opacity(0.35)
                                  : Island.tileStroke,
                                  lineWidth: 1)
                    .frame(width: size, height: size)
            }
            content
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var content: some View {
        switch presentation {
        case .move:
            IslandPiece(symbol: symbol,
                        size: size * (showsTile ? 0.62 : 0.86),
                        tint: .white)
        case .pending:
            IslandPiece(symbol: "bN",
                        size: size * (showsTile ? 0.62 : 0.86),
                        tint: Theme.mute)
        case .rejected:
            Image(systemName: "xmark")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(Theme.bad)
        }
    }
}

// MARK: - Evaluation

/// A dark chip holds the evaluation. It has a hairline in the position's colour and a tabular
/// number.
public struct EvalPill: View {
    let evalText: String
    let trusted: Bool

    public init(evalText: String, trusted: Bool) {
        self.evalText = evalText
        self.trusted = trusted
    }

    private var isMate: Bool {
        evalText.hasPrefix("#") || evalText.hasPrefix("-#")
    }

    private var tint: Color {
        guard trusted else { return Color.white.opacity(0.55) }
        return isMate ? Theme.gold : advantageTint(evalText)
    }

    private var caret: String {
        let f = advantageFraction(evalText)
        if f > 0.54 { return "chevron.up" }
        if f < 0.46 { return "chevron.down" }
        return "equal"
    }

    private var display: String {
        guard trusted else { return "—" }
        if isMate { return evalText }
        return evalText.hasPrefix("-") ? evalText : "+" + evalText.replacingOccurrences(of: "+", with: "")
    }

    private var spoken: String {
        guard trusted else { return "No reliable evaluation" }
        if isMate { return "Forced mate, \(display)" }
        let f = advantageFraction(evalText)
        if f > 0.54 { return "You are better, \(display)" }
        if f < 0.46 { return "You are worse, \(display)" }
        return "Position is level, \(display)"
    }

    public var body: some View {
        Group {
            if trusted && !hasEval(evalText) {
                EmptyView()
            } else if !trusted {
                Text("—")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .accessibilityLabel("No reliable evaluation")
            } else {
                HStack(spacing: 4) {
                    Image(systemName: caret)
                        .font(.system(size: 9, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(display)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tint.opacity(0.28), lineWidth: 1)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
            }
        }
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
        PieceTile(symbol: symbol, presentation: presentation,
                  size: 20, showsTile: false)
            .accessibilityHidden(true)
    }
}

public struct IslandCompactTrailing: View {
    let move: String
    let trusted: Bool
    let accent: Color
    let evalText: String
    let presentation: IslandPresentation

    public init(move: String, trusted: Bool, accent: Color,
                evalText: String, presentation: IslandPresentation) {
        self.move = move
        self.trusted = trusted
        self.accent = accent
        self.evalText = evalText
        self.presentation = presentation
    }

    private var caret: String {
        let f = advantageFraction(evalText)
        if f > 0.54 { return "chevron.up" }
        if f < 0.46 { return "chevron.down" }
        return "equal"
    }

    public var body: some View {
        Group {
            switch presentation {
            case .move:
                HStack(spacing: 6) {
                    Text(move)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Image(systemName: caret)
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Best move \(move)")
            case .pending:
                Text("…")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .accessibilityLabel("Reading the board")
            case .rejected:
                Text("—")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .accessibilityLabel("No move because the board could not be read")
            }
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

    private var spoken: String {
        switch presentation {
        case .move: return "Best move \(move)"
        case .pending: return "Reading the board"
        case .rejected: return "No move because the board could not be read"
        }
    }

    public var body: some View {
        PieceTile(symbol: symbol, presentation: presentation,
                  size: 18, showsTile: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
    }
}

// MARK: - Expanded

/// The expanded view is one block. The art tile, notation, and state sit on one row, and one
/// bounded line sits beneath. Everything is on the Island's black. There is no region
/// background, no nested card, and nothing in the rounded top corners.
public struct IslandExpandedCard: View {
    let state: BestMoveAttributes.ContentState

    public init(state: BestMoveAttributes.ContentState) { self.state = state }

    private var presentation: IslandPresentation { IslandPresentation(state) }

    private var title: String {
        switch presentation {
        case .move: return state.displayMove
        case .pending: return "Reading the board"
        case .rejected: return "Couldn't read the board"
        }
    }

    /// The text is bounded at the source by `MoveExplainer.islandTipLimit`. The view never
    /// ellipsizes a generated sentence.
    private var subline: String {
        switch presentation {
        case .move: return state.tip
        case .pending: return state.why
        case .rejected: return state.why.isEmpty ? "Frame the whole board and try again" : state.why
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                PieceTile(symbol: state.pieceSymbol, presentation: presentation, size: 34)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.system(size: presentation == .move ? Island.moveSize : 19,
                                  weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                Spacer(minLength: 8)

                if presentation == .move {
                    EvalPill(evalText: state.youEval, trusted: state.trusted)
                }
            }

            if !subline.isEmpty {
                Text(subline)
                    .font(.system(size: Island.whySize, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .lineSpacing(1.5)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Lock screen

/// The lock card uses the same block on a dark card. It has one hairline and no gradient
/// border.
public struct LockScreenCard: View {
    let state: BestMoveAttributes.ContentState
    public init(state: BestMoveAttributes.ContentState) { self.state = state }

    private var presentation: IslandPresentation { IslandPresentation(state) }

    private var title: String {
        switch presentation {
        case .move: return state.displayMove
        case .pending: return "Reading the board"
        case .rejected: return "Couldn't read"
        }
    }

    private var subline: String {
        switch presentation {
        case .move: return state.tip
        case .pending: return state.why
        case .rejected: return state.why.isEmpty ? "Frame the whole board and try again" : state.why
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                PieceTile(symbol: state.pieceSymbol, presentation: presentation, size: 36)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.system(size: presentation == .move ? 26 : 19,
                                  weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                Spacer(minLength: 8)

                if presentation == .move {
                    EvalPill(evalText: state.youEval, trusted: state.trusted)
                }
            }

            if !subline.isEmpty {
                Text(subline)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineSpacing(1.5)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color(red: 0.048, green: 0.048, blue: 0.056),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
