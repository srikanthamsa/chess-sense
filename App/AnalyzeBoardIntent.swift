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

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let result = try await AnalysisPipeline.analyzeAndPublish(imageData: screenshot.data)
            if let move = result.move, result.trusted {
                // Interpolated literal, not a String variable: `IntentDialog` is
                // ExpressibleByStringInterpolation, so only literals convert implicitly.
                return .result(dialog: "\(move.displayMove)  \(move.evalText)")
            }
            if !result.trusted {
                return .result(dialog: "Board read was not confident — nothing shown.")
            }
            return .result(dialog: "\(result.failure ?? "No move available.")")
        } catch BoardError.notCalibrated {
            return .result(dialog: "Calibrate chess-sense from a fresh game first.")
        } catch {
            return .result(dialog: "Failed: \(error)")
        }
    }
}
