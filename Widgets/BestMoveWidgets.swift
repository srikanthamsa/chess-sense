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
                DynamicIslandExpandedRegion(.leading) {
                    IslandExpandedLeading(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    IslandExpandedMove(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EvalPill(evalText: context.state.youEval,
                             trusted: context.state.trusted)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(state: context.state)
                }
            } compactLeading: {
                IslandCompactLeading(trusted: context.state.trusted, accent: accent)
            } compactTrailing: {
                IslandCompactTrailing(move: context.state.displayMove,
                                      trusted: context.state.trusted,
                                      accent: accent)
            } minimal: {
                IslandMinimal(move: context.state.displayMove,
                              presentation: IslandPresentation(context.state))
                    .foregroundStyle(accent)
            }
            .keylineTint(accent)
        }
    }
}

@main
struct ChessSenseWidgets: WidgetBundle {
    var body: some Widget {
        BestMoveLiveActivity()
    }
}
