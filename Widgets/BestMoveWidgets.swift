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
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandExpandedLeading(trusted: context.state.trusted, thinking: false)
                }
                DynamicIslandExpandedRegion(.center) {
                    IslandExpandedMove(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EvalPill(evalText: context.state.evalText, trusted: context.state.trusted)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(state: context.state)
                }
            } compactLeading: {
                IslandCompactLeading(trusted: context.state.trusted)
            } compactTrailing: {
                IslandCompactTrailing(move: context.state.displayMove,
                                      trusted: context.state.trusted)
            } minimal: {
                IslandMinimal(move: context.state.displayMove,
                          presentation: IslandPresentation(context.state))
            }
            .keylineTint(context.state.trusted
                         ? advantageTint(context.state.evalText)
                         : .orange)
        }
    }
}

@main
struct ChessSenseWidgets: WidgetBundle {
    var body: some Widget {
        BestMoveLiveActivity()
    }
}
