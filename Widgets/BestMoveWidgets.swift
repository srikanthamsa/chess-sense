import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Palette

private enum Ink {
    /// Sampled from the TakeTakeTake board so the Island feels like it belongs to the game.
    static let accent = Color(red: 0.62, green: 0.55, blue: 0.86)
    static let accentDeep = Color(red: 0.42, green: 0.35, blue: 0.66)
    static let good = Color(red: 0.42, green: 0.82, blue: 0.60)
    static let bad = Color(red: 0.96, green: 0.45, blue: 0.44)
    static let neutral = Color.white.opacity(0.72)
    static let hairline = Color.white.opacity(0.12)

    static func eval(_ state: BestMoveAttributes.ContentState) -> Color {
        if !state.trusted { return .orange }
        if state.evalText.hasPrefix("-#") { return bad }
        if state.evalText.hasPrefix("#") { return good }
        guard let v = Double(state.evalText.replacingOccurrences(of: "+", with: "")) else {
            return neutral
        }
        if v > 0.6 { return good }
        if v < -0.6 { return bad }
        return neutral
    }
}

// MARK: - Pieces

/// Horizontal advantage bar, white's share growing from the left.
private struct AdvantageBar: View {
    let advantage: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let split = max(3, min(w - 3, w * advantage))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Ink.accentDeep, Ink.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: split)
                Rectangle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 1.5)
                    .offset(x: w / 2 - 0.75)
            }
        }
        .frame(height: 5)
        .animation(.snappy(duration: 0.45), value: advantage)
    }
}

private struct EvalPill: View {
    let state: BestMoveAttributes.ContentState
    var compact = false

    var body: some View {
        Text(compact ? state.compactEval : state.evalText)
            .font(.system(size: compact ? 12 : 13, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Ink.eval(state))
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 3)
            .background(
                Capsule().fill(Ink.eval(state).opacity(0.16))
            )
            .contentTransition(.numericText())
            .animation(.snappy, value: state.evalText)
    }
}

private struct MoveDisplay: View {
    let state: BestMoveAttributes.ContentState
    var size: CGFloat = 34

    var body: some View {
        Group {
            if state.trusted {
                Text(state.displayMove)
                    .font(.system(size: size, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.35), value: state.displayMove)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(.orange)
                    Text("unclear")
                        .font(.system(size: size * 0.62, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

// MARK: - Live Activity

struct BestMoveLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BestMoveAttributes.self) { context in
            // Lock screen / notification presentation.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    MoveDisplay(state: context.state, size: 32)
                    Spacer(minLength: 8)
                    EvalPill(state: context.state)
                }
                AdvantageBar(advantage: context.state.advantage)
                if !context.state.why.isEmpty {
                    Text(context.state.why)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(3)
                }
                Text(context.state.provenance)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.40))
            }
            .padding(16)
            .activityBackgroundTint(Color(red: 0.07, green: 0.06, blue: 0.10))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MoveDisplay(state: context.state, size: 38)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 3) {
                        EvalPill(state: context.state)
                        Text(context.state.provenance)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Ink.neutral.opacity(0.55))
                            .lineLimit(1)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    AdvantageBar(advantage: context.state.advantage)
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.why.isEmpty
                         ? context.state.principalVariation
                         : context.state.why)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Ink.neutral)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 2)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: context.state.why)
                }
            } compactLeading: {
                EvalPill(state: context.state, compact: true)
            } compactTrailing: {
                MoveDisplay(state: context.state, size: 15)
            } minimal: {
                MoveDisplay(state: context.state, size: 12)
            }
            .keylineTint(Ink.accent)
        }
    }
}

@main
struct ChessSenseWidgets: WidgetBundle {
    var body: some Widget {
        BestMoveLiveActivity()
    }
}
