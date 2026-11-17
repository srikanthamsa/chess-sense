import AppIntents
import Foundation

/// Entry point for the Action Button / Shortcuts / Back Tap.
///
/// Wire it in Shortcuts: **Take Screenshot** -> **Best Move** (this intent) -> the move
/// lands in the Dynamic Island. Runs without bringing the app to the foreground.
struct AnalyzeBoardIntent: AppIntent {
    static let title: LocalizedStringResource = "Best Move"
    static let description = IntentDescription(
        "Reads the chess board in a screenshot and puts the best move in the Dynamic Island."
    )
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Screenshot")
    var screenshot: IntentFile

    init() {}

    init(screenshot: IntentFile) {
        self.screenshot = screenshot
    }

    /// Everything this intent has to say goes to the Dynamic Island. It deliberately
    /// returns no dialog: a Shortcut run from the Action Button used to pop a "Failed:
    /// no template matched a8 (closest shape distance 100)" banner over the game, which is
    /// both a second surface to read and internal machinery the player cannot act on.
    func perform() async throws -> some IntentResult {
        do {
            let result = try await AnalysisPipeline.analyzeAndPublish(imageData: screenshot.data)
            // analyseAndPublish already pushed the move to the Island, including the
            // rejected case, so there is nothing left to say here.
            _ = result
            return .result()
        } catch let error as BoardError {
            // Keep the failure in the Island too, in words a player can act on.
            await LiveActivityController.update(
                nil, why: error.userFacingDescription, trusted: false
            )
            return .result()
        } catch {
            await LiveActivityController.update(
                nil,
                why: "I couldn't read that board. Screenshot the position again and give it another go.",
                trusted: false
            )
            return .result()
        }
    }
}
