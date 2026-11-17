import ActivityKit
import SwiftUI
import WidgetKit

private struct MoveFace: View {
    let state: BestMoveAttributes.ContentState

    var body: some View {
        VStack(spacing: 4) {
            Text(state.displayMove)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
            Text(state.evalText)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(state.evalText.hasPrefix("-") ? .secondary : .primary)
            Text(state.provenance)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct BestMoveLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BestMoveAttributes.self) { context in
            // Lock screen / banner presentation.
            HStack(spacing: 16) {
                Image(systemName: context.state.trusted ? "checkerboard.rectangle" : "exclamationmark.triangle")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.displayMove)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(context.state.trusted
                         ? context.state.principalVariation
                         : context.state.principalVariation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(context.state.evalText)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.55))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    MoveFace(state: context.state)
                }
            } compactLeading: {
                Image(systemName: context.state.trusted
                      ? "checkerboard.rectangle"
                      : "exclamationmark.triangle")
            } compactTrailing: {
                Text(context.state.displayMove)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } minimal: {
                Text(context.state.displayMove)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
            }
            .keylineTint(context.state.trusted ? .purple : .orange)
        }
    }
}

@main
struct ChessSenseWidgets: WidgetBundle {
    var body: some Widget {
        BestMoveLiveActivity()
    }
}
