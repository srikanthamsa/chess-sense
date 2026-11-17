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
                    // The trailing/leading content sits close to the corner curve; a small
                    // inset keeps the eval badge from being clipped by it.
                    IslandExpandedLeading(state: context.state)
                        .padding(.leading, 2)
                }
                DynamicIslandExpandedRegion(.center) {
                    IslandExpandedMove(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EvalPill(evalText: context.state.youEval,
                             trusted: context.state.trusted)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(state: context.state)
                }
            } compactLeading: {
                IslandCompactLeading(move: context.state.displayMove,
                                     trusted: context.state.trusted,
                                     accent: accent,
                                     presentation: IslandPresentation(context.state))
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
struct ChessSenseWidgets: WidgetBundle {
    var body: some Widget {
        BestMoveLiveActivity()
    }
}
