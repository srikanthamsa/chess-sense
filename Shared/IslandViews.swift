import SwiftUI

public enum Island {
    public static let moveSize: CGFloat = 30
    public static let whySize: CGFloat = 11.5
    public static let barHeight: CGFloat = 4
    public static let capsule = Color(red: 0.38, green: 0.84, blue: 0.56)
    public static let crimson = Color(red: 0.95, green: 0.45, blue: 0.45)
    public static let neutral = Color(red: 0.66, green: 0.70, blue: 0.78)
}

/// Three distinguishable situations. Collapsing "waiting" and "could not read" into one
/// empty state is what made the rejected face render as a skeleton forever, with an eval pill
/// reading "? ?".
public enum IslandPresentation {
    case move, pending, rejected

    public init(_ state: BestMoveAttributes.ContentState) {
        if !state.trusted { self = .rejected }
        else if state.san.isEmpty || state.uci == "----" { self = .pending }
        else { self = .move }
    }
}

extension String {
    /// Clamped to one Island line without slicing a word in half.
    var islandShort: String {
        let limit = 52
        guard count > limit else { return self }
        let head = prefix(limit)
        guard let cut = head.lastIndex(of: " ") else { return head + "…" }
        return head[..<cut] + "…"
    }
}

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
            HStack(spacing: gap) {
                cell(1)
                cell(0.32)
            }
            HStack(spacing: gap) {
                cell(0.32)
                cell(1)
            }
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

// MARK: - Evaluation semantics

/// 0...1, 0.5 = level. Squashed so everyday edges stay near the middle.
public func advantageFraction(_ text: String) -> Double {
    if text.hasPrefix("#") { return 1 }
    if text.hasPrefix("-#") { return 0 }
    let value = Double(text.replacingOccurrences(of: "+", with: "")) ?? 0
    return 0.5 + 0.5 * tanh(value / 2.5)
}

public func advantageTint(_ text: String) -> Color {
    let f = advantageFraction(text)
    if f > 0.56 { return Island.capsule }
    if f < 0.44 { return Island.crimson }
    return Island.neutral
}

/// Diverging bar: grows out of the centre, right when you are better, left when you are worse.
/// A left-anchored fill was wrong — it made "you are winning" and "you are losing" occupy the
/// same side of the track and only the colour told them apart.
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
            let magnitude = abs(f - 0.5) * 2           // 0...1
            let growRight = f >= 0.5
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.075))
                Capsule()
                    .fill(LinearGradient(
                        colors: [tint.opacity(0.75), tint],
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

/// The eval as a pill: arrow shows direction for *you*, value shows the number.
public struct EvalPill: View {
    let evalText: String
    let trusted: Bool

    public init(evalText: String, trusted: Bool) {
        self.evalText = evalText
        self.trusted = trusted
    }

    public var body: some View {
        if !trusted {
            Text("unclear")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Capsule(style: .continuous).fill(.white.opacity(0.07)))
        } else {
            pill
        }
    }

    private var pill: some View {
        HStack(spacing: 3) {
            Image(systemName: glyph)
                .font(.system(size: 8.5, weight: .black))
            Text(evalText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(advantageTint(evalText))
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(
            Capsule(style: .continuous).fill(advantageTint(evalText).opacity(0.15))
        )
        .animation(.snappy(duration: 0.45), value: evalText)
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
    public init(trusted: Bool) { self.trusted = trusted }

    public var body: some View {
        Group {
            if trusted {
                CheckerMark(size: 3.4, gap: 2.4, tint: .white.opacity(0.92))
            } else {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.orange)
            }
        }
        .frame(width: 15, height: 15)
    }
}

public struct IslandCompactTrailing: View {
    let move: String
    let trusted: Bool

    let presentation: IslandPresentation

    public init(move: String, trusted: Bool) {
        self.move = move
        self.trusted = trusted
        self.presentation = trusted
            ? (move.isEmpty || move == "----" ? .pending : .move)
            : .rejected
    }

    public var body: some View {
        if presentation == .rejected {
            EmptyView()
        } else if presentation == .pending {
            Capsule()
                .fill(.white.opacity(0.16))
                .frame(width: 30, height: 12)
                .phaseAnimator([false, true]) { view, phase in
                    view.opacity(phase ? 0.5 : 1)
                } animation: { _ in .easeInOut(duration: 1.1) }
        } else {
            text
        }
    }

    private var text: some View {
        Text(move)
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .tracking(-0.4)
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.35), value: move)
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
                .foregroundStyle(.orange)
        case .pending:
            Capsule().fill(.white.opacity(0.16)).frame(width: 22, height: 9)
        case .move:
            text
        }
    }

    private var text: some View {
        Text(move)
            .font(.system(size: 10.5, weight: .heavy, design: .rounded))
            .tracking(-0.3)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

// MARK: - Expanded

public struct IslandExpandedLeading: View {
    let trusted: Bool
    let thinking: Bool

    public init(trusted: Bool, thinking: Bool) {
        self.trusted = trusted
        self.thinking = thinking
    }

    public var body: some View {
        Group {
            if thinking {
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                    .foregroundStyle(.white.opacity(0.7))
            } else if trusted {
                CheckerMark(size: 3.2, gap: 2.4, tint: .white.opacity(0.85))
            } else {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
            }
        }
        .frame(width: 18, height: 18)
    }
}

public struct IslandExpandedMove: View {
    let state: BestMoveAttributes.ContentState
    public init(state: BestMoveAttributes.ContentState) { self.state = state }

    public var body: some View {
        switch IslandPresentation(state) {
        case .move:
            moveText
        case .pending:
            SkeletonBar()
        case .rejected:
            Text("Couldn't read")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var moveText: some View {
        Text(state.displayMove)
            .font(.system(size: Island.moveSize, weight: .heavy, design: .rounded))
            .tracking(-1.0)
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.4), value: state.displayMove)
    }
}

/// Quiet placeholder: a rounded slab that breathes.
public struct SkeletonBar: View {
    public init() {}

    public var body: some View {
        Capsule()
            .fill(.white.opacity(0.13))
            .frame(width: 96, height: 26)
            .phaseAnimator([false, true]) { view, phase in
                view.opacity(phase ? 0.55 : 1)
            } animation: { _ in .easeInOut(duration: 1.1) }
    }
}

public struct IslandExpandedBottom: View {
    let state: BestMoveAttributes.ContentState
    public init(state: BestMoveAttributes.ContentState) { self.state = state }

    private var presentation: IslandPresentation { IslandPresentation(state) }

    /// Exactly one line, clamped at a word boundary.
    ///
    /// Three lines of prose turned the Island into a notification banner: it grew over the
    /// host app's header and clipped inside its own corner curve. The Island is a glance. The
    /// full sentence lives on the lock screen, where there is room for it.
    public var body: some View {
        Text(detailText)
            .font(.system(size: Island.whySize, weight: .medium))
            .foregroundStyle(.white.opacity(0.72))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.25), value: detailText)
    }

    private var detailText: String {
        switch presentation {
        case .rejected:
            return "Couldn't read the board — move again"
        case .pending:
            return "Reading the board…"
        case .move:
            if !state.why.isEmpty { return state.why.islandShort }
            if !state.principalVariation.isEmpty { return state.principalVariation.islandShort }
            return state.provenance
        }
    }
}

// MARK: - Lock screen

public struct LockScreenCard: View {
    let state: BestMoveAttributes.ContentState
    public init(state: BestMoveAttributes.ContentState) { self.state = state }

    private var presentation: IslandPresentation { IslandPresentation(state) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            HStack(alignment: .center, spacing: 10) {
                if presentation == .rejected {
                    Text("Couldn't read")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                } else if presentation == .pending {
                    SkeletonBar()
                } else {
                    Text(state.displayMove)
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .tracking(-1.1)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                EvalPill(evalText: state.youEval, trusted: state.trusted)
                Spacer(minLength: 0)
            }
            if presentation != .rejected {
                AdvantageBar(evalText: state.youEval, height: 5)
            }
            if !state.why.isEmpty {
                Text(state.why)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineSpacing(1.5)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(3)
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
            CheckerMark(size: 3, gap: 2, tint: .white.opacity(0.55))
            Text("chess-sense")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(state.trusted ? "BEST MOVE" : "UNCLEAR")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.32))
        }
    }
}
