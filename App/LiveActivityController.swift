import ActivityKit
import Foundation

/// Starts, updates and ends the single `BestMoveAttributes` Live Activity.
///
/// An App Intent cannot hold a reference to the activity it created earlier, so every call
/// looks the activity up by type. Only one game is ever tracked, so "the first activity" is
/// unambiguous.
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
            evalText: "+0.0",
            principalVariation: "",
            provenance: "waiting for a position",
            trusted: true,
            why: "Play a move, then screenshot the board."
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
    ///
    /// If nothing is running yet it starts one first, so a Shortcut invoked on a cold app
    /// still produces an Island instead of silently doing nothing.
    static func update(_ move: EngineMove?, why: String, trusted: Bool, playerEval: String = "") async {
        if Activity<BestMoveAttributes>.activities.isEmpty {
            _ = try? start()
        }
        guard let activity = Activity<BestMoveAttributes>.activities.first else { return }
        let state: BestMoveAttributes.ContentState
        if let move, trusted {
            state = .init(
                uci: move.uci,
                san: move.san ?? "",
                evalText: move.evalText,
                principalVariation: move.principalVariation,
                provenance: move.provenance,
                trusted: true,
                why: why
            )
        } else {
            state = .init(
                uci: "--",
                san: "",
                evalText: "0.0",
                principalVariation: "",
                provenance: "rejected",
                trusted: false,
                why: trusted
                    ? "The engine had nothing for this position."
                    : "I could not read the board confidently, so I am not going to guess."
            )
        }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    /// Refines only the coaching line, leaving the move on screen untouched. Used when the
    /// language model's answer arrives after the engine's.
    static func updateWhy(_ why: String) async {
        guard let activity = Activity<BestMoveAttributes>.activities.first else { return }
        var state = activity.content.state
        guard !why.isEmpty, why != state.why else { return }
        state.why = why
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }
}
