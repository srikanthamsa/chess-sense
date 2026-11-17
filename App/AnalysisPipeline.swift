import Foundation
import UIKit

/// The whole pipeline, shared by the in-app button and the App Intent.
enum AnalysisPipeline {
    struct Result: Sendable {
        let fen: String
        let rectangle: BoardRect
        let trusted: Bool
        let move: EngineMove?
        let failure: String?
    }

    static func analyze(
        imageData: Data,
        store: CalibrationStore = CalibrationStore()
    ) async throws -> Result {
        guard let image = PixelImage(data: imageData) else {
            throw BoardError.unreadableImage
        }
        return try await analyze(image: image, store: store)
    }

    static func analyze(
        image: PixelImage,
        store: CalibrationStore = CalibrationStore()
    ) async throws -> Result {
        guard let book = store.loadBook() else {
            throw BoardError.notCalibrated
        }

        let read = try BoardReader.read(image: image, book: book, rect: store.loadRect())

        // A rejected read must never become a move, no matter what the engine says.
        guard read.isTrustworthy else {
            return Result(
                fen: read.fen,
                rectangle: read.rect,
                trusted: false,
                move: nil,
                failure: "low-confidence read (worst shape \(read.worstShapeDistance), "
                    + "colour margin \(String(format: "%.2f", read.minColorMargin)))"
            )
        }

        do {
            let move = try await EngineClient.bestMove(fen: read.fen)
            return Result(
                fen: read.fen,
                rectangle: read.rect,
                trusted: true,
                move: move,
                failure: nil
            )
        } catch {
            return Result(
                fen: read.fen,
                rectangle: read.rect,
                trusted: true,
                move: nil,
                failure: "engine: \(error)"
            )
        }
    }

    /// Calibrates from a screenshot of a fresh game, then immediately verifies by
    /// re-reading the same frame.
    static func calibrate(
        imageData: Data,
        store: CalibrationStore = CalibrationStore()
    ) throws -> BoardRead {
        guard let image = PixelImage(data: imageData) else {
            throw BoardError.unreadableImage
        }
        let (book, rect, verification) = try BoardReader.calibrate(image: image)
        try store.save(book: book, rect: rect)
        return verification
    }

    static func analyzeAndPublish(imageData: Data) async throws -> Result {
        let result = try await analyze(imageData: imageData)
        if result.trusted {
            await LiveActivityController.update(result.move, trusted: true)
        } else {
            await LiveActivityController.update(nil, trusted: false)
        }
        return result
    }
}
