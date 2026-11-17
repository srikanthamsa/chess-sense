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
        // No evaluation yet: the board has not been read. Shipping "+0.0" here made the
        // Island claim "dead equal" for a position nobody had seen.
        let state = BestMoveAttributes.ContentState(
            uci: "----",
            san: "",
            evalText: "",
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

    /// Refines only the tip, in place. Used when the language model answers after the move
    /// has already been shown; the move itself never waits on the model.
    static func updateTip(_ text: String) async {
        guard let activity = Activity<BestMoveAttributes>.activities.first else { return }
        var state = activity.content.state
        guard state.tip != text else { return }
        state.tip = text
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    /// Pure: what the activity should hold for a given outcome.
    ///
    /// Split out from `update` because `activity.content.state` only reflects the last
    /// *delivered* update, so asserting a round-trip there measures ActivityKit's
    /// propagation latency rather than this mapping. It also pins the bug where `update`
    /// accepted `tip`, `pieceSymbol` and `playerEval` and then dropped them on the floor.
    static func makeState(
        _ move: EngineMove?, why: String, trusted: Bool,
        playerEval: String, pieceSymbol: String, tip: String
    ) -> BestMoveAttributes.ContentState {
        if let move, trusted {
            return .init(
                uci: move.uci,
                san: move.san ?? "",
                evalText: move.evalText,
                principalVariation: move.principalVariation,
                provenance: move.provenance,
                trusted: true,
                why: why,
                playerEval: playerEval,
                pieceSymbol: pieceSymbol,
                tip: tip
            )
        }
        return .init(
            uci: "--",
            san: "",
            evalText: "0.0",
            principalVariation: "",
            provenance: "rejected",
            trusted: false,
            // Prefer a caller-supplied explanation: it is the only one that can say what
            // actually went wrong in words the player can act on. The hard-coded sentence is
            // the fallback for callers that have nothing specific to add.
            why: why.isEmpty
                ? (trusted
                    ? "The engine had nothing for this position."
                    : "I could not read the board confidently, so I am not going to guess.")
                : why,
            playerEval: playerEval
        )
    }

    /// Pushes a new best move, or an explicit "I could not read the board" state.
    /// A low-confidence read must never be rendered as a move.
    ///
    /// If nothing is running yet it starts one first, so a Shortcut invoked on a cold app
    /// still produces an Island instead of silently doing nothing.
    static func update(
        _ move: EngineMove?, why: String, trusted: Bool,
        playerEval: String = "", pieceSymbol: String = "", tip: String = ""
    ) async {
        if Activity<BestMoveAttributes>.activities.isEmpty {
            _ = try? start()
        }
        guard let activity = Activity<BestMoveAttributes>.activities.first else { return }
        let state = makeState(move, why: why, trusted: trusted,
                              playerEval: playerEval, pieceSymbol: pieceSymbol, tip: tip)
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
