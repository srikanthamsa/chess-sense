import Foundation

/// The whole pipeline, shared by the in-app button and the App Intent.
///
/// Order matters: read the board, hand the 64 squares to the tracker so *history* supplies
/// side-to-move / castling / en passant, then ask the engine about the tracked position.
/// A rejected read never reaches the engine.
enum AnalysisPipeline {
    /// Shared across calls so a screenshot of the same position is free.
    private static let cache = EngineCache()

    struct Outcome: Sendable {
        /// Position that was actually analysed (after tracking).
        let fen: String
        /// Raw read, before tracking.
        let readFEN: String
        let rectangle: BoardRect
        let trusted: Bool
        /// e.g. "detected e4" or "board did not match play — resynced".
        let trackingNote: String
        let move: EngineMove?
        let failure: String?
    }

    // MARK: - Analyse

    static func analyze(
        imageData: Data,
        store: CalibrationStore = CalibrationStore()
    ) async throws -> Outcome {
        guard let image = PixelImage(data: imageData) else {
            throw BoardError.unreadableImage
        }
        return try await analyze(image: image, store: store)
    }

    static func analyze(
        image: PixelImage,
        store: CalibrationStore = CalibrationStore()
    ) async throws -> Outcome {
        guard let book = store.loadBook() else { throw BoardError.notCalibrated }

        let read: BoardRead
        do {
            read = try BoardReader.read(image: image, book: book, rect: store.loadRect())
        } catch {
            // Keep the frame so the failure can be turned into a test instead of a guess.
            Diagnostics.record(image: image, reason: "\(error)", book: book,
                               rectOverride: store.loadRect())
            throw error
        }

        guard read.isTrustworthy else {
            Diagnostics.record(image: image, reason: "rejected-read", book: book, rectOverride: read.rect)
            return Outcome(
                fen: read.fen,
                readFEN: read.fen,
                rectangle: read.rect,
                trusted: false,
                trackingNote: "",
                move: nil,
                failure: "low-confidence read (worst shape \(read.worstShapeDistance), "
                    + "colour margin \(String(format: "%.2f", read.minColorMargin)))"
            )
        }

        // History supplies what a single frame cannot.
        var tracker = store.trackedFEN.flatMap(PositionTracker.init(fen:)) ?? PositionTracker()
        let before = tracker.position
        let sync = tracker.observe(read.pieces)
        store.trackedFEN = tracker.position.fen

        let note: String
        if sync.didResync {
            note = "board did not match legal play — resynced"
        } else if let last = sync.lastSAN {
            note = sync.moves.count > 1
                ? "detected \(sync.sans.joined(separator: " "))"
                : "detected \(last)"
        } else {
            note = "position unchanged"
        }

        // Sanity: if tracking produced something whose turn doesn't match the engine's
        // expectation, the board read and the history disagree — say so rather than guess.
        let fen = tracker.position.fen
        do {
            var move = try await cache.value(for: fen, chain: .default)
            if let resolved = tracker.position.move(uci: move.uci) {
                move.san = SAN.san(for: resolved, in: tracker.position)
                let pv = move.principalVariationSAN(from: tracker.position)
                if !pv.isEmpty {
                    move = EngineMove(
                        uci: move.uci,
                        san: move.san,
                        principalVariation: pv,
                        evalText: move.evalText,
                        provenance: move.provenance
                    )
                }
            }
            return Outcome(
                fen: fen,
                readFEN: read.fen,
                rectangle: read.rect,
                trusted: true,
                trackingNote: note.isEmpty ? "" : "\(note), from \(before.sideToMove)",
                move: move,
                failure: nil
            )
        } catch {
            return Outcome(
                fen: fen,
                readFEN: read.fen,
                rectangle: read.rect,
                trusted: true,
                trackingNote: note,
                move: nil,
                failure: "engine: \(error)"
            )
        }
    }

    // MARK: - Calibrate

    /// Learns the templates from a screenshot of a fresh game and verifies itself.
    /// Also resets tracking, since calibration means "this is a new game".
    static func calibrate(
        imageData: Data,
        store: CalibrationStore = CalibrationStore()
    ) throws -> BoardRead {
        guard let image = PixelImage(data: imageData) else {
            throw BoardError.unreadableImage
        }
        let (book, rect, verification) = try BoardReader.calibrate(image: image)
        try store.save(book: book, rect: rect)
        store.resetTracking()
        return verification
    }

    // MARK: - Publish

    static func analyzeAndPublish(imageData: Data) async throws -> Outcome {
        let outcome = try await analyze(imageData: imageData)
        if outcome.trusted {
            await LiveActivityController.update(outcome.move, trusted: outcome.move != nil)
        } else {
            await LiveActivityController.update(nil, trusted: false)
        }
        return outcome
    }
}
