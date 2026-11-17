import XCTest
@testable import ChessSenseCore

/// Error copy shown to a player must be short enough for the Dynamic Island's two-line
/// tip slot, and must not leak internal machinery.
///
/// The island never ellipsizes: a sentence that is too long gets cut mid-word, which is
/// exactly the "unfinished sentence" the Island was fixed to avoid. The length bound is
/// therefore a correctness requirement, not a style preference.
final class ErrorCopyTests: XCTestCase {

    private var allErrors: [BoardError] {
        [
            .unreadableImage,
            .notCalibrated,
            .boardNotFound,
            .implausibleRect(BoardRect(x: 0, y: 0, width: 10, height: 10)),
            .inconsistentCalibration(
                square: "e4",
                expected: .piece(.rook, .white),
                got: .piece(.pawn, .black)
            ),
            .unknownSquare(rank: 0, file: 0, bestDistance: 100),
            .verificationFailed(expected: "start position", got: "something else"),
        ]
    }

    /// Same bound the Island tip uses, so anything that fits there fits here.
    private let islandLimit = 60

    func testEveryUserFacingErrorFitsTheIslandSlot() {
        for error in allErrors {
            let text = error.userFacingDescription
            XCTAssertLessThanOrEqual(
                text.count, islandLimit,
                "\(error) is \(text.count) chars; the Island tip slot is \(islandLimit)"
            )
        }
    }

    func testEveryUserFacingErrorSaysSomethingActionable() {
        for error in allErrors {
            let text = error.userFacingDescription
            XCTAssertFalse(text.isEmpty, "\(error) has no user-facing copy")
            // A sentence, not a fragment: starts capitalised and ends with punctuation.
            XCTAssertTrue(text.first?.isUppercase ?? false, "\(error) does not start a sentence: \(text)")
            XCTAssertTrue(text.hasSuffix("."), "\(error) does not end a sentence: \(text)")
        }
    }

    func testUserFacingCopyNamesNoInternalMachinery() {
        // Words that mean nothing to a player and belong only in `description` / logs.
        let jargon = [
            "template", "shape distance", "board-like", "rect", "parity",
            "FEN", "calibration", "epsilon", "stack", "nil", "error",
        ]
        for error in allErrors {
            let text = error.userFacingDescription
            for word in jargon {
                XCTAssertFalse(
                    text.localizedCaseInsensitiveContains(word),
                    "\(error) exposes internal term '\(word)' to the player: \(text)"
                )
            }
        }
    }

    func testDiagnosticDescriptionIsStillDetailed() {
        // The log/diagnostic string is allowed to be technical — that is its job. Guard
        // against the two being accidentally collapsed into one.
        let detailed = BoardError
            .unknownSquare(rank: 0, file: 0, bestDistance: 100).description
        XCTAssertTrue(
            detailed.contains("100"),
            "diagnostic description should keep the measurement, got: \(detailed)"
        )
    }
}
