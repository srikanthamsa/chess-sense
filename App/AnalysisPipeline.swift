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
        /// Plain-English reason for the move, no notation.
        let why: String
        /// Position and move as rules objects, so callers can refine the explanation.
        let position: ChessPosition
        let explainedMove: Move?
        /// The engine value re-signed for the player whose turn it is, so green always means
        /// "you are better" no matter which colour you are playing.
        let playerEval: String
        /// Unicode glyph of the piece that moves, for the Island badge.
        let pieceSymbol: String
        /// One short sentence for the Island. Never ellipsized: the length is bounded here.
        let tip: String
        /// Where the time went, e.g. "read 28 · engine 96 · total 141 ms".
        let timings: String
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

        let readStart = Date()
        var read: BoardRead
        do {
            read = try BoardReader.read(image: image, book: book, rect: store.loadRect())
        } catch {
            // Keep the frame so the failure can be turned into a test instead of a guess.
            Diagnostics.record(image: image, reason: "\(error)", book: book,
                               rectOverride: store.loadRect())
            throw error
        }

        let readMs = Date().timeIntervalSince(readStart)
        // A book learned from a screenshot cannot read a broadcast frame: different scale,
        // different rendering. Rather than making the user re-calibrate and retry, re-learn
        // the book from this very frame, anchored to the position we already know, and read
        // again. Verification still has to pass, so a wrong anchor produces a refusal.
        if read.scaleMismatch, let healed = try? autoHeal(from: image, store: store) {
            read = healed
        }

        guard read.isTrustworthy else {
            Diagnostics.record(image: image, reason: "rejected-read", book: book,
                               rectOverride: read.rect)
            let position = store.trackedFEN.flatMap(PositionTracker.init(fen:))?.position
                ?? PositionTracker().position
            return Outcome(
                fen: read.fen,
                readFEN: read.fen,
                rectangle: read.rect,
                trusted: false,
                trackingNote: "",
                move: nil,
                failure: read.scaleMismatch
                    ? "This frame is \(Int(read.squareSize)) px per square but the templates "
                        + "were learned at \(Int(read.bookSquareSize ?? 0)) px. Recalibrate "
                        + "from the broadcast."
                    : "low-confidence read (worst shape \(read.worstShapeDistance), "
                        + "colour margin \(String(format: "%.2f", read.minColorMargin)))",
                why: "",
                position: position,
                explainedMove: nil,
                playerEval: "",
                pieceSymbol: "",
                tip: "",
                timings: ""
            )
        }

        // History supplies what a single frame cannot.
        let trackStart = Date()
        var tracker = store.trackedFEN.flatMap(PositionTracker.init(fen:)) ?? PositionTracker()
        let before = tracker.position
        var sync = tracker.observe(read.pieces)

        // The frame's own tint beats accumulated history. Without this, one bad frame leaves
        // the side to move wrong for the rest of the game and the app recommends the
        // opponent's best move -- which is exactly what was reported.
        var turnCorrected = false
        if let direct = read.sideToMove, tracker.position.sideToMove != direct {
            tracker.forceSideToMove(direct)
            turnCorrected = true
            sync = PositionTracker.Sync(
                moves: sync.moves,
                sans: sync.sans,
                fen: tracker.position.fen,
                didResync: true
            )
        }
        store.trackedFEN = tracker.position.fen

        var note: String
        if turnCorrected {
            note = "turn corrected from the board"
        } else if sync.didResync {
            note = "board did not match legal play — resynced"
        } else if let last = sync.lastSAN {
            note = sync.moves.count > 1
                ? "detected \(sync.sans.joined(separator: " "))"
                : "detected \(last)"
        } else {
            note = "position unchanged"
        }

        let trackMs = Date().timeIntervalSince(trackStart)
        let position = tracker.position

        let engineStart = Date()
        do {
            var move = try await cache.value(for: position.fen, chain: .default)
            var resolved: Move?
            if let engineMove = position.move(uci: move.uci) {
                resolved = engineMove
                move.san = SAN.san(for: engineMove, in: position)
                let pv = move.principalVariationSAN(from: position)
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
            // Coaching for the move about to be played; falls back to the move just played.
            let explained = resolved ?? sync.lastMove
            let why = explained.map {
                MoveExplainer.explain(move: $0, in: position, evalText: move.evalText)
            } ?? ""

            return Outcome(
                fen: position.fen,
                readFEN: read.fen,
                rectangle: read.rect,
                trusted: true,
                trackingNote: note.isEmpty ? "" : "\(note), from \(before.sideToMove)",
                move: move,
                failure: nil,
                why: why,
                position: position,
                explainedMove: explained,
                playerEval: position.sideToMove == .black
                    ? flippedEvaluation(move.evalText)
                    : move.evalText,
                pieceSymbol: explained.map { piece -> String in
                    if case let .piece(kind, color) = position.board[piece.from] {
                        return MoveExplainer.symbol(for: kind, color: color)
                    }
                    return ""
                } ?? "",
                tip: explained.map {
                    MoveExplainer.order(move: $0, in: position, evalText: move.evalText)
                } ?? "",
                timings: describe(read: readMs, track: trackMs,
                                  engine: Date().timeIntervalSince(engineStart),
                                  total: Date().timeIntervalSince(readStart))
            )
        } catch {
            return Outcome(
                fen: position.fen,
                readFEN: read.fen,
                rectangle: read.rect,
                trusted: true,
                trackingNote: note,
                move: nil,
                failure: "engine: \(error)",
                why: "",
                position: position,
                explainedMove: sync.lastMove,
                playerEval: "",
                pieceSymbol: "",
                tip: "",
                timings: ""
            )
        }
    }

    /// Re-learns the templates from the frame that just failed, anchored to the last position
    /// the tracker knew (or the start position on a fresh game), then reads it back.
    private static func autoHeal(
        from image: PixelImage,
        store: CalibrationStore
    ) throws -> BoardRead {
        let anchorFEN = store.trackedFEN ?? FEN.start
        guard let placement = FEN.decode(anchorFEN) else { throw BoardError.notCalibrated }
        let (book, rect, verification) = try BoardReader.calibrate(
            image: image, placement: placement, rect: store.loadRect())
        try store.save(book: book, rect: rect)
        return try BoardReader.read(image: image, book: book, rect: rect)
    }

    /// Milliseconds, rounded, for the line the app shows. Cheap, and the only way to see
    /// where a shutter-to-answer delay actually goes on the device.
    private static func describe(read: TimeInterval, track: TimeInterval,
                                 engine: TimeInterval, total: TimeInterval) -> String {
        func ms(_ value: TimeInterval) -> Int { Int((value * 1000).rounded()) }
        return "read \(ms(read)) · track \(ms(track)) · engine \(ms(engine)) "
            + "· total \(ms(total)) ms"
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

    /// `calibrate` is synchronous, so calling it from a `@MainActor` view runs a full
    /// 1206x1206 pixel scan on the main thread and freezes the UI — including the spinner
    /// that exists to cover the wait. This hops to a background task and awaits the result.
    /// (`analyze` needs no wrapper: it is `async` and nonisolated, so SE-0338 already moves
    /// it off the caller's actor.) `UserDefaults` is thread-safe, so the store is built
    /// inside the task rather than captured across the boundary.
    static func calibrateOffMain(imageData: Data) async throws -> BoardRead {
        try await Task.detached(priority: .userInitiated) {
            try calibrate(imageData: imageData)
        }.value
    }

    // MARK: - Publish

    /// Shows the engine's move immediately with the offline explanation, then upgrades the
    /// coaching line in place when the language model answers. The move never waits on the
    /// model, and the model never supplies the move.
    static func analyzeAndPublish(imageData: Data) async throws -> Outcome {
        // Bring the island up while the frame is being read, not after.
        async let islandReady: Void = LiveActivityController.ensureRunning()
        let started = Date()
        let outcome = try await analyze(imageData: imageData)
        await islandReady
        _ = started

        guard outcome.trusted, outcome.move != nil else {
            await LiveActivityController.update(nil, why: outcome.why,
                                                trusted: outcome.trusted,
                                                playerEval: outcome.playerEval)
            return outcome
        }

        await LiveActivityController.update(outcome.move, why: outcome.why, trusted: true,
                                            playerEval: outcome.playerEval,
                                            pieceSymbol: outcome.pieceSymbol,
                                            tip: outcome.tip)

        if let key = APIKeyStore.key, !key.isEmpty,
           let move = outcome.move, let resolved = outcome.explainedMove {
            let position = outcome.position
            let san = move.san ?? ""
            let pv = move.principalVariation
            let evalText = move.evalText
            Task.detached(priority: .utility) {
                let coach = DeepSeekCoach(apiKey: key)
                if let better = try? await coach.tip(
                    move: resolved, in: position, san: san
                ) {
                    await LiveActivityController.updateTip(better)
                }
                if let better = try? await coach.explain(
                    move: resolved,
                    in: position,
                    evalText: evalText,
                    san: san,
                    principalVariation: pv
                ), !better.isEmpty {
                    await LiveActivityController.updateWhy(better)
                }
            }
        }
        return outcome
    }
}
