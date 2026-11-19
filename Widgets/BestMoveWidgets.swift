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
                // Apple's own layout: identifier across the top, detail underneath. The glow
                // lives on the detail strip so it traces something real.
                DynamicIslandExpandedRegion(.leading) {
                    IslandExpandedLeading(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EvalPill(evalText: context.state.youEval, trusted: context.state.trusted)
                }
                DynamicIslandExpandedRegion(.center) {
                    IslandExpandedMove(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedDetail(state: context.state)
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
                                      evalText: context.state.youEval)
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
