import SwiftUI

/// Visual language for the Live Activity, shared by the widget extension and the in-app
/// design studio so what you preview is literally what the Island renders.

public enum Island {
    public static let moveSize: CGFloat = 30
    public static let whySize: CGFloat = 11.5
    public static let barHeight: CGFloat = 4

    public static let jade = Color(red: 0.36, green: 0.85, blue: 0.58)
    public static let crimson = Color(red: 0.97, green: 0.44, blue: 0.44)
    public static let amber = Color(red: 1.00, green: 0.66, blue: 0.26)
    public static let gold = Color(red: 1.00, green: 0.80, blue: 0.34)
    public static let violet = Color(red: 0.71, green: 0.56, blue: 1.00)
    public static let sky = Color(red: 0.42, green: 0.72, blue: 1.00)
    public static let lavender = Color(red: 0.72, green: 0.66, blue: 0.94)
    public static let neutral = Color(red: 0.66, green: 0.70, blue: 0.78)
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

/// One accent per state, and every accent has a reason.
///
/// Colour that encodes nothing reads as decoration. This order is what the move *is*: a
/// finishing blow, a promotion, a capture, castling, a check, then how the position stands.
public enum IslandAccent {
    public static func resolve(_ state: BestMoveAttributes.ContentState) -> Color {
        if !state.trusted { return Island.amber }
        let san = state.san
        if san.contains("#") { return Island.gold }
        if san.contains("=") { return Island.violet }
        if san.contains("x") { return Island.amber }
        if san.contains("O-O") { return Island.sky }
        if san.contains("+") { return Island.amber }
        let f = advantageFraction(state.youEval)
        if f > 0.58 { return Island.jade }
        if f < 0.42 { return Island.crimson }
        return Island.lavender
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
    if f > 0.56 { return Island.jade }
    if f < 0.44 { return Island.crimson }
    return Island.neutral
}

extension String {
    /// Clamped to one Island line without slicing a word in half.
    var islandShort: String {
        let limit = 46
        guard count > limit else { return self }
        let head = prefix(limit)
        guard let cut = head.lastIndex(of: " ") else { return head + "…" }
        return head[..<cut] + "…"
    }
}

// MARK: - Small parts

/// A four-dot checker mark: the app's own glyph, legible at 11 pt.
public struct CheckerMark: View {
    var size: CGFloat
    var gap: CGFloat
    var tint: Color

    public init(size: CGFloat = 3.2, gap: CGFloat = 2.4, tint: Color = .white) {
        self.size = size
        self.gap = gap
        self.tint = tint
    }

    public var body: some View {
        VStack(spacing: gap) {
            HStack(spacing: gap) { cell(1); cell(0.30) }
            HStack(spacing: gap) { cell(0.30); cell(1) }
        }
        .foregroundStyle(tint)
        .accessibilityHidden(true)
    }

    private func cell(_ opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
            .frame(width: size, height: size)
            .opacity(opacity)
    }
}

/// The piece that is moving: the glyph alone, in its accent.
///
/// It had a filled circle with a stroke, which read as a thick inner border against the
/// black Island and competed with the move. The glyph carries the same information with no
/// chrome at all.
public struct PieceBadge: View {
    let symbol: String
    let accent: Color
    var diameter: CGFloat = 26

    public init(symbol: String, accent: Color, diameter: CGFloat = 26) {
        self.symbol = symbol
        self.accent = accent
        self.diameter = diameter
    }

    public var body: some View {
        Group {
            if symbol.isEmpty {
                CheckerMark(size: 2.8, gap: 2.2, tint: accent)
            } else {
                Text(symbol)
                    .font(.system(size: diameter * 0.82))
                    .foregroundStyle(accent)
                    .shadow(color: accent.opacity(0.45), radius: 6)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

public struct SkeletonBar: View {
    var width: CGFloat = 96
    var height: CGFloat = 24
    public init(width: CGFloat = 96, height: CGFloat = 24) {
        self.width = width
        self.height = height
    }

    public var body: some View {
        Capsule()
            .fill(.white.opacity(0.13))
            .frame(width: width, height: height)
            .phaseAnimator([false, true]) { view, phase in
                view.opacity(phase ? 0.5 : 1).scaleEffect(phase ? 0.985 : 1, anchor: .leading)
            } animation: { _ in .easeInOut(duration: 1.1) }
    }
}

/// Diverging bar: grows out of the centre, right when you are better, left when worse.
public struct AdvantageBar: View {
    let evalText: String
    var height: CGFloat = Island.barHeight
    let tint: Color

    public init(evalText: String, height: CGFloat = Island.barHeight, tint: Color? = nil) {
        self.evalText = evalText
        self.height = height
        self.tint = tint ?? advantageTint(evalText)
    }

    public var body: some View {
        GeometryReader { geo in
            let f = advantageFraction(evalText)
            let half = geo.size.width / 2
            let magnitude = abs(f - 0.5) * 2
            let growRight = f >= 0.5
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.075))
                Capsule()
                    .fill(LinearGradient(
                        colors: [tint.opacity(0.7), tint],
                        startPoint: growRight ? .leading : .trailing,
                        endPoint: growRight ? .trailing : .leading
                    ))
                    .frame(width: max(2, half * magnitude))
                    .offset(x: growRight ? half : half - half * magnitude)
                    .animation(.snappy(duration: 0.5), value: f)
                Capsule()
                    .fill(.white.opacity(0.32))
                    .frame(width: 2, height: height * 1.6)
                    .offset(x: half - 1, y: -height * 0.3)
            }
        }
        .frame(height: height)
        .accessibilityLabel("Advantage, \(evalText)")
    }
}

public struct EvalPill: View {
    let evalText: String
    let trusted: Bool
    var accent: Color?

    public init(evalText: String, trusted: Bool, accent: Color? = nil) {
        self.evalText = evalText
        self.trusted = trusted
        self.accent = accent
    }

    private var colour: Color { accent ?? (trusted ? advantageTint(evalText) : Island.amber) }

    public var body: some View {
        if !trusted {
            Text("unclear")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 7).padding(.vertical, 3.5)
                .background(Capsule(style: .continuous).fill(.white.opacity(0.07)))
        } else {
            HStack(spacing: 3) {
                Image(systemName: glyph)
                    .font(.system(size: 8.5, weight: .black))
                Text(evalText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(colour)
            .padding(.horizontal, 7).padding(.vertical, 3.5)
            .background(Capsule(style: .continuous).fill(colour.opacity(0.16)))
            .overlay(Capsule(style: .continuous).strokeBorder(colour.opacity(0.18), lineWidth: 0.5))
            .animation(.snappy(duration: 0.45), value: evalText)
        }
    }

    private var glyph: String {
        let f = advantageFraction(evalText)
        if f > 0.56 { return "arrow.up.right" }
        if f < 0.44 { return "arrow.down.right" }
        return "equal"
    }
}

// MARK: - Compact and minimal

public struct IslandCompactLeading: View {
    let trusted: Bool
    let accent: Color
    public init(trusted: Bool, accent: Color = .white) {
        self.trusted = trusted
        self.accent = accent
    }

    public var body: some View {
        Group {
            if trusted {
                CheckerMark(size: 3.4, gap: 2.4, tint: accent.opacity(0.95))
            } else {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Island.amber)
            }
        }
        .frame(width: 15, height: 15)
    }
}

public struct IslandCompactTrailing: View {
    let move: String
    let trusted: Bool
    let accent: Color

    public init(move: String, trusted: Bool, accent: Color = .white) {
        self.move = move
        self.trusted = trusted
        self.accent = accent
    }

    private var presentation: IslandPresentation {
        guard trusted else { return .rejected }
        return (move.isEmpty || move == "----") ? .pending : .move
    }

    public var body: some View {
        switch presentation {
        case .rejected:
            EmptyView()
        case .pending:
            SkeletonBar(width: 28, height: 11)
        case .move:
            Text(move)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .tracking(-0.4)
                .monospacedDigit()
                .foregroundStyle(accent)
                .shadow(color: accent.opacity(0.35), radius: 5)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.35), value: move)
        }
    }
}

public struct IslandMinimal: View {
    let move: String
    var presentation: IslandPresentation = .move

    public init(move: String, presentation: IslandPresentation = .move) {
        self.move = move
        self.presentation = presentation
    }

    public var body: some View {
        switch presentation {
        case .rejected:
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Island.amber)
        case .pending:
            SkeletonBar(width: 20, height: 8)
        case .move:
            Text(move)
                .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                .tracking(-0.3)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}

// MARK: - Expanded

public struct IslandExpandedLeading: View {
    let state: BestMoveAttributes.ContentState
    let thinking: Bool

    public init(state: BestMoveAttributes.ContentState, thinking: Bool = false) {
        self.state = state
        self.thinking = thinking
    }

    public var body: some View {
        if thinking {
            Image(systemName: "sparkle")
                .font(.system(size: 12, weight: .semibold))
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .foregroundStyle(Island.lavender)
                .frame(width: 18, height: 18)
        } else {
            PieceBadge(symbol: state.pieceSymbol,
                       accent: IslandAccent.resolve(state),
                       diameter: 24)
        }
    }
}

public struct IslandExpandedMove: View {
    let state: BestMoveAttributes.ContentState
    public init(state: BestMoveAttributes.ContentState) { self.state = state }

    public var body: some View {
        switch IslandPresentation(state) {
        case .move:
            let accent = IslandAccent.resolve(state)
            Text(state.displayMove)
                .font(.system(size: Island.moveSize, weight: .heavy, design: .rounded))
                .tracking(-1.0)
                .monospacedDigit()
                .foregroundStyle(.white)
                .shadow(color: accent.opacity(0.45), radius: 10, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.4), value: state.uci)
        case .pending:
            SkeletonBar(width: 84, height: 22)
        case .rejected:
            Text("Couldn't read")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

public struct IslandExpandedBottom: View {
    let state: BestMoveAttributes.ContentState
    public init(state: BestMoveAttributes.ContentState) { self.state = state }

    private var presentation: IslandPresentation { IslandPresentation(state) }
    private var accent: Color { IslandAccent.resolve(state) }

    /// One line, with a colour-coded spine, and inset from the card's corner curve.
    ///
    /// Full-bleed text was being sliced by the bottom-left curve of the Island, and three
    /// lines turned the whole thing into a notification banner.
    public var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Capsule()
                .fill(LinearGradient(colors: [accent, accent.opacity(0.25)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 2.5, height: 12)
                .padding(.top, 2)
                .opacity(presentation == .rejected ? 0.9 : 1)

            Text(detailText)
                .font(.system(size: Island.whySize, weight: .medium))
                .lineSpacing(1.2)
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.25), value: detailText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 5)
    }

    private var detailText: String {
        switch presentation {
        case .rejected:
            return "Couldn't read the board — move again"
        case .pending:
            return "Reading the board…"
        case .move:
            if !state.why.isEmpty { return state.why }
            if !state.principalVariation.isEmpty { return state.principalVariation }
            return state.provenance
        }
    }
}

// MARK: - Lock screen

public struct LockScreenCard: View {
    let state: BestMoveAttributes.ContentState
    public init(state: BestMoveAttributes.ContentState) { self.state = state }

    private var presentation: IslandPresentation { IslandPresentation(state) }
    private var accent: Color { IslandAccent.resolve(state) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header

            HStack(alignment: .center, spacing: 10) {
                if presentation == .rejected {
                    Text("Couldn't read")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                } else if presentation == .pending {
                    SkeletonBar(width: 130, height: 30)
                } else {
                    Text(state.displayMove)
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .tracking(-1.1)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .shadow(color: accent.opacity(0.4), radius: 12, y: 1)
                }
                if presentation == .move {
                    PieceBadge(symbol: state.pieceSymbol, accent: accent, diameter: 26)
                }
                EvalPill(evalText: state.youEval, trusted: state.trusted)
                Spacer(minLength: 0)
            }

            if presentation != .rejected {
                AdvantageBar(evalText: state.youEval, height: 5, tint: advantageTint(state.youEval))
            }

            if !state.why.isEmpty, presentation == .move {
                Text(state.why)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineSpacing(1.5)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(presentation == .rejected ? "move again to retry" : state.provenance.lowercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.3))
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var header: some View {
        HStack(spacing: 6) {
            CheckerMark(size: 3, gap: 2, tint: accent.opacity(0.7))
            Text("chess-sense")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(presentation == .rejected ? "UNCLEAR" : "BEST MOVE")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.32))
        }
    }
}
