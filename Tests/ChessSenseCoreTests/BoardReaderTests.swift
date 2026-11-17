import XCTest
@testable import ChessSenseCore

final class BoardReaderTests: XCTestCase {

    // MARK: - Fixture

    private func loadFixture() throws -> PixelImage {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "taketaketake-start",
                withExtension: "png",
                subdirectory: "Fixtures"
            ),
            "fixture missing from test bundle"
        )
        return try XCTUnwrap(PixelImage(contentsOf: url), "fixture failed to decode")
    }

    private static let startBoard = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"

    // MARK: - Board location

    func testLocatesFullWidthBoard() throws {
        let image = try loadFixture()
        let rect = try XCTUnwrap(BoardLocator.locate(image))

        XCTAssertEqual(rect.x, 0, "TakeTakeTake's board is full-bleed")
        XCTAssertEqual(rect.width, image.width)
        XCTAssertTrue(rect.isPlausible)
        // Square board: within one pixel of the screen width.
        XCTAssertLessThanOrEqual(abs(rect.height - rect.width), 2)
        // Sits in the upper half, below the player header.
        XCTAssertGreaterThan(rect.y, image.height / 5)
        XCTAssertLessThan(rect.y, image.height / 3)
    }

    func testBoardNotFoundOnBlankImage() {
        let blank = PixelImage(
            width: 300, height: 600,
            rgba: [UInt8](repeating: 0x20, count: 300 * 600 * 4)
        )
        XCTAssertNil(BoardLocator.locate(blank))
    }

    func testRowRunFinder() {
        let counts = [0, 0, 5, 6, 7, 0, 0, 9, 9, 0, 0]
        XCTAssertEqual(
            BoardLocator.longestRun(counts, threshold: 5),
            2..<5
        )
        XCTAssertEqual(
            BoardLocator.longestRun(counts, threshold: 9),
            7..<9
        )
        XCTAssertNil(BoardLocator.longestRun(counts, threshold: 100))
    }

    // MARK: - Palette

    func testPaletteSplitsLightAndDarkSquares() throws {
        let image = try loadFixture()
        let rect = try XCTUnwrap(BoardLocator.locate(image))
        let palette = BoardPalette.estimate(image: image, rect: rect)

        let lightLuma = palette.light.luminance
        let darkLuma = palette.dark.luminance
        XCTAssertGreaterThan(lightLuma, darkLuma + 0.05)
        XCTAssertTrue(palette.lightIsEvenParity, "a8 is a light square on a normal board")

        // a8 must be the light colour, a7 the dark one.
        XCTAssertEqual(
            palette.boardColour(rank: 0, file: 0),
            palette.light
        )
        XCTAssertEqual(
            palette.boardColour(rank: 1, file: 0),
            palette.dark
        )
    }

    // MARK: - Signature invariants

    func testWhiteAndBlackAreSameShapeButDifferentBrightness() throws {
        // This is the whole reason the colour channel exists.
        let image = try loadFixture()
        let rect = try XCTUnwrap(BoardLocator.locate(image))
        let sigs = SquareExtractor.extract(image: image, rect: rect)

        let whitePawn = sigs[6 * 8 + 0]   // a2
        let blackPawn = sigs[1 * 8 + 0]   // a7
        let whiteRook = sigs[7 * 8 + 0]   // a1
        let blackRook = sigs[0 * 8 + 0]   // a8

        XCTAssertLessThan(whitePawn.shapeDistance(to: blackPawn), 8,
                          "pawns are the same silhouette regardless of colour")
        XCTAssertLessThan(whiteRook.shapeDistance(to: blackRook), 8,
                          "Rooks are the SAME silhouette — shape alone cannot separate them")
        XCTAssertGreaterThan(whitePawn.colorDistance(to: blackPawn), 0.40)
        XCTAssertGreaterThan(whiteRook.colorDistance(to: blackRook), 0.30)
    }

    func testSamePieceRendersIdenticallyOnBothSquareColours() throws {
        // b1 and g1 are both white knights, on opposite-coloured squares.
        let image = try loadFixture()
        let rect = try XCTUnwrap(BoardLocator.locate(image))
        let sigs = SquareExtractor.extract(image: image, rect: rect)
        let b1 = sigs[7 * 8 + 1]
        let g1 = sigs[7 * 8 + 6]
        XCTAssertLessThanOrEqual(b1.shapeDistance(to: g1), 8)
        XCTAssertLessThan(b1.colorDistance(to: g1), 0.05,
                          "square colour must not leak into the white/black signal")
    }

    func testEmptySquaresAreIndistinguishable() throws {
        let image = try loadFixture()
        let rect = try XCTUnwrap(BoardLocator.locate(image))
        let sigs = SquareExtractor.extract(image: image, rect: rect)
        let empties = (3..<5).flatMap { rank in (0..<8).map { rank * 8 + $0 } }
        for i in empties.dropFirst() {
            XCTAssertEqual(sigs[empties[0]].shapeDistance(to: sigs[i]), 0)
            XCTAssertTrue(sigs[i].isEmpty)
        }
    }

    // MARK: - Calibration + read

    func testCalibrationProducesThirteenTemplates() throws {
        let image = try loadFixture()
        let (book, _, _) = try BoardReader.calibrate(image: image)

        XCTAssertEqual(book.entries.count, 13,
                       "six pieces x two colours + empty, one cluster each")
        XCTAssertEqual(book.pieces.count, 13)

        // Support counts must match the starting position exactly.
        let expected: [Piece: Int] = [
            .empty: 32,
            .piece(.pawn, .white): 8, .piece(.pawn, .black): 8,
            .piece(.knight, .white): 2, .piece(.knight, .black): 2,
            .piece(.bishop, .white): 2, .piece(.bishop, .black): 2,
            .piece(.rook, .white): 2, .piece(.rook, .black): 2,
            .piece(.queen, .white): 1, .piece(.queen, .black): 1,
            .piece(.king, .white): 1, .piece(.king, .black): 1,
        ]
        for entry in book.entries {
            XCTAssertEqual(entry.support, expected[entry.piece],
                           "support for \(entry.piece)")
        }
    }

    func testCalibrationReadsBackTheStartingPosition() throws {
        let image = try loadFixture()
        let (_, _, verification) = try BoardReader.calibrate(image: image)

        XCTAssertEqual(
            verification.fen,
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        )
        XCTAssertTrue(verification.isTrustworthy)
        XCTAssertGreaterThan(verification.minColorMargin, 0.20,
                            "white/black must separate decisively")
    }

    func testCalibrationRejectsAFrameThatDisagreesWithTheExpectedPosition() throws {
        let image = try loadFixture()
        // Claim the frame shows a position one move in — it doesn't.
        var wrong = TemplateBook.standardStartPlacement
        let e2 = 6 * 8 + 4
        let e4 = 4 * 8 + 4
        wrong[e4] = wrong[e2]
        wrong[e2] = .empty

        XCTAssertThrowsError(try BoardReader.calibrate(image: image, placement: wrong)) { error in
            guard case BoardError.verificationFailed = error else {
                return XCTFail("expected verificationFailed, got \(error)")
            }
        }
    }

    func testReadingIsDeterministic() throws {
        let image = try loadFixture()
        let (book, rect, _) = try BoardReader.calibrate(image: image)
        let a = try BoardReader.read(image: image, book: book, rect: rect)
        let b = try BoardReader.read(image: image, book: book, rect: rect)
        XCTAssertEqual(a.fen, b.fen)
        XCTAssertEqual(a.worstShapeDistance, b.worstShapeDistance)
    }

    func testUnknownSquareIsRejectedRatherThanGuessed() throws {
        let image = try loadFixture()
        let (book, rect, _) = try BoardReader.calibrate(image: image)

        // A dense checkerboard of bits matches no glyph (nor the empty template, whose
        // shape is all zeros) — 128 bits away from everything.
        let nonsense = SquareSignature(
            words: [0xAAAA_AAAA_AAAA_AAAA, 0x5555_5555_5555_5555,
                    0xAAAA_AAAA_AAAA_AAAA, 0x5555_5555_5555_5555],
            brightFraction: 0.5, ink: 0.5, backgroundLuma: 0.5
        )
        XCTAssertNil(book.classify(nonsense), "a non-square must not be forced into a class")

        // A flat, inkless square legitimately classifies as empty.
        let blank = SquareSignature(words: [0, 0, 0, 0], brightFraction: 0,
                                    ink: 0, backgroundLuma: 0.6)
        XCTAssertEqual(book.classify(blank)?.piece, .empty)
    }

    // MARK: - FEN

    func testFENEncoding() {
        let board = TemplateBook.standardStartPlacement
        XCTAssertEqual(
            FEN.encode(board),
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        )
        let empty = [Piece](repeating: .empty, count: 64)
        XCTAssertEqual(
            FEN.encode(empty, sideToMove: .black, castling: "", enPassant: "e3"),
            "8/8/8/8/8/8/8/8 b - e3 0 1"
        )
    }
}

/// A broadcast frame arrives at half resolution while the stored rectangle was learned from a
/// full-resolution screenshot. That mismatch used to index past the pixel buffer and crash.
final class StaleRectTests: XCTestCase {
    private func image(_ name: String) throws -> PixelImage {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Fixtures")
        )
        return try XCTUnwrap(PixelImage(contentsOf: url))
    }

    func testFullScaleRectRejectedOnHalfScaleImage() throws {
        let full = try image("taketaketake-start")
        let rect = try XCTUnwrap(BoardLocator.locate(full))
        XCTAssertTrue(BoardReader.fits(rect, in: full))

        let half = try full.scaled(by: 0.5)
        XCTAssertFalse(BoardReader.fits(rect, in: half), "a stale rect must not be trusted")
    }

    func testReadingAHalfScaleFrameDoesNotCrash() throws {
        let full = try image("taketaketake-start")
        let (book, rect, _) = try BoardReader.calibrate(image: full)
        let half = try full.scaled(by: 0.5)

        // Must either read the board at its new size or refuse -- never index out of bounds.
        do {
            let read = try BoardReader.read(image: half, book: book, rect: rect)
            XCTAssertFalse(read.fen.isEmpty)
        } catch {
            XCTAssertTrue(error is BoardError, "unexpected error: \(error)")
        }
    }
}

/// Broadcast frames arrive at a different scale than screenshots, and a book trained on one
/// misreads the other *confidently*: queens match pawns at a small distance and the position
/// still looks legal. Scale is therefore a reason to distrust a read, not a cosmetic detail.
final class ScaleMismatchTests: XCTestCase {

    private func image(_ name: String) throws -> PixelImage {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Fixtures")
        )
        return try XCTUnwrap(PixelImage(contentsOf: url))
    }

    /// Half-scale capture: rectangles, glyphs and video artefacts all differ, exactly like a
    /// ReplayKit frame.
    private func scaled(_ image: PixelImage, by factor: Double) -> PixelImage {
        let width = Int(Double(image.width) * factor)
        let height = Int(Double(image.height) * factor)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let sy = min(image.height - 1, Int(Double(y) / factor))
            for x in 0..<width {
                let sx = min(image.width - 1, Int(Double(x) / factor))
                let source = image.offset(sx, sy)
                let target = (y * width + x) * 4
                for channel in 0..<4 { rgba[target + channel] = image.rgba[source + channel] }
            }
        }
        return PixelImage(width: width, height: height, rgba: rgba)
    }

    func testBookRecordsTheScaleItLearned() throws {
        let (book, _, _) = try BoardReader.calibrate(image: try image("taketaketake-start"))
        let learned = try XCTUnwrap(book.squareSize)
        XCTAssertEqual(learned, 1206.0 / 8, accuracy: 0.5)
    }

    func testAScreenshotBookRefusesAScaledFrame() throws {
        let full = try image("taketaketake-start")
        let (book, _, _) = try BoardReader.calibrate(image: full)

        // Reading the same board at 70% scale: if the scale guard is present the read is
        // untrusted, which is the whole point -- silently wrong is worse than refused.
        let scaledImage = scaled(full, by: 0.70)
        if let read = try? BoardReader.read(image: scaledImage, book: book) {
            XCTAssertFalse(read.isTrustworthy, "a 151 px book must not bless a 105 px frame")
        }
    }
}

/// A book learned from one rendering must not be used on another, and re-anchoring must
/// recover from exactly that.
final class ScaleReheatTests: XCTestCase {

    private func image(_ name: String) throws -> PixelImage {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Fixtures")
        )
        return try XCTUnwrap(PixelImage(contentsOf: url))
    }

    /// Halves a board image the way ReplayKit halves a screen.
    private func halved(_ source: PixelImage, factor: Int) -> PixelImage {
        var rgba = [UInt8]()
        let w = source.width / factor, h = source.height / factor
        rgba.reserveCapacity(w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let o = source.offset(x * factor, y * factor)
                rgba.append(contentsOf: [source.rgba[o], source.rgba[o + 1],
                                         source.rgba[o + 2], 255])
            }
        }
        return PixelImage(width: w, height: h, rgba: rgba)
    }

    func testScreenshotBookRefusesAHalvedFrame() throws {
        let full = try image("taketaketake-start")
        let (book, rect, _) = try BoardReader.calibrate(image: full)
        XCTAssertGreaterThan(book.squareSize ?? 0, 140)

        let small = halved(full, factor: 2)
        let read = try BoardReader.read(image: small, book: book, rect: rect)
        // Either the scale check or the shape check must stop it; the unacceptable outcome is
        // a *confident* wrong answer.
        XCTAssertFalse(read.isTrustworthy, "a 151 px book must not bless a 75 px frame")
    }

    func testReanchoringOnTheStreamedFrameRecovers() throws {
        let full = try image("taketaketake-start")
        let small = halved(full, factor: 2)

        // The exact auto-heal path: anchor to the known position, learn from this frame.
        let (book, rect, verification) = try BoardReader.calibrate(
            image: small, placement: FEN.decode(FEN.start)!)
        XCTAssertTrue(verification.isTrustworthy)
        XCTAssertLessThan(book.squareSize ?? 0, 100)

        let read = try BoardReader.read(image: small, book: book, rect: rect)
        XCTAssertTrue(read.isTrustworthy)
        XCTAssertEqual(String(read.fen.split(separator: " ")[0]), FEN.start)
    }

    func testDecodeRoundTrips() {
        XCTAssertEqual(FEN.decode(FEN.start).map { FEN.encode($0).split(separator: " ").first.map(String.init) ?? "" },
                       FEN.start)
        XCTAssertEqual(FEN.decode("8/8/8/8/8/8/8/8")?.count, 64)
        XCTAssertNil(FEN.decode("not a fen"))
    }
}
