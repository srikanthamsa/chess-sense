import ActivityKit
import SwiftUI
import WidgetKit

struct BestMoveLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BestMoveAttributes.self) { context in
            LockScreenCard(state: context.state)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let accent = IslandAccent.resolve(context.state)
            return DynamicIsland {
                // One inset block in `center`, below the camera. Leading and trailing stay
                // empty so nothing touches the rounded top corners, and no separate bottom
                // region creates a visible edge.
                DynamicIslandExpandedRegion(.center) {
                    IslandExpandedCard(state: context.state)
                }
            } compactLeading: {
                IslandCompactLeading(move: context.state.displayMove,
                                     trusted: context.state.trusted,
                                     accent: accent,
                                     presentation: IslandPresentation(context.state),
                                     symbol: context.state.pieceSymbol)
            } compactTrailing: {
                IslandCompactTrailing(move: context.state.displayMove,
                                      trusted: context.state.trusted,
                                      accent: accent,
                                      evalText: context.state.youEval,
                                      presentation: IslandPresentation(context.state))
            } minimal: {
                IslandMinimal(move: context.state.displayMove,
                              presentation: IslandPresentation(context.state),
                              symbol: context.state.pieceSymbol,
                              accent: accent)
            }
            .keylineTint(accent)
        }
    }
}

@main
struct SNSEWidgets: WidgetBundle {
    var body: some Widget {
        BestMoveLiveActivity()
    }
}
