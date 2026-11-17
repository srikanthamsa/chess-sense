import ActivityKit
import Foundation

/// Starts, updates and ends the single `BestMoveAttributes` Live Activity.
///
/// An App Intent cannot hold a reference to the activity it created earlier, so every
/// call looks the activity up by type. Only one game is ever tracked, so "the first
/// activity" is unambiguous.
@available(iOS 16.2, *)
enum LiveActivityController {
    static var isRunning: Bool {
        !Activity<BestMoveAttributes>.activities.isEmpty
    }

    static var activitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Placeholder state so the Island appears as soon as you start tracking, before the
    /// first screenshot has been analysed.
    @discardableResult
    static func start() throws -> Bool {
        guard activitiesEnabled, !isRunning else { return isRunning }
        let state = BestMoveAttributes.ContentState(
            uci: "----",
            san: "",
            evalText: "---",
            principalVariation: "",
            provenance: "waiting for a screenshot",
            trusted: true
        )
        _ = try Activity<BestMoveAttributes>.request(
            attributes: BestMoveAttributes(),
            content: ActivityContent(state: state, staleDate: nil)
        )
        return true
    }

    static func end() async {
        for activity in Activity<BestMoveAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Pushes a new best move, or an explicit "I could not read the board" state.
    /// A low-confidence read must never be rendered as a move.
    static func update(_ move: EngineMove?, trusted: Bool) async {
        guard let activity = Activity<BestMoveAttributes>.activities.first else { return }
        let state: BestMoveAttributes.ContentState
        if let move, trusted {
            state = .init(
                uci: move.uci,
                san: move.san ?? "",
                evalText: move.evalText,
                principalVariation: move.principalVariation,
                provenance: move.provenance,
                trusted: true
            )
        } else {
            state = .init(
                uci: "--",
                san: "",
                evalText: "!",
                principalVariation: "board read was not confident",
                provenance: "rejected",
                trusted: false
            )
        }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }
}
