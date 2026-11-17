import XCTest
@testable import ChessSenseCore

/// Regression fixtures captured from the phone mid-game.
///
/// TakeTakeTake paints the last move's squares with a blue highlight. Two separate bugs
/// came out of these captures:
///
/// 1. The board locator clipped the outer ranks (a full rank of pieces is only ~30%
///    board-coloured), giving a 1174 px tall rect for a 1206 px board — every square skewed.
/// 2. Highlight handling compared distance from the palette with a 60-unit tolerance. The
///    measured highlight moves a dark square by 91 units and a light square by 53, so it
///    worked on light squares and masked the entire square as ink on dark ones. That is why
///    the failure looked random ("no template matched e7, closest shape distance 59").
final class HighlightTests: XCTestCase {

    private func image(_ name: String) throws -> PixelImage {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Fixtures"),
            "missing fixture \(name)"
        )
        return try XCTUnwrap(PixelImage(contentsOf: url))
    }

    /// Black has played e7-e6 (highlighted), White pawns on c4/d4, Black on d5/e6.
    private static let placementAfterE6 =
        "rnbqkbnr/ppp2ppp/4p3/3p4/2PP4/8/PP2PPPP/RNBQKBNR"

    /// Measured from the capture: the highlight on a dark square and on a light square.
    private static let darkTint = RGB(159, 143, 254)
    private static let lightTint = RGB(187, 176, 254)

    // MARK: - Locator regression

    func testLocatorDoesNotClipTheOuterRanks() throws {
        // Same device, same app, two layouts: the rect must come out identical and square.
        let a = try XCTUnwrap(BoardLocator.locate(try image("taketaketake-start")))
        let b = try XCTUnwrap(BoardLocator.locate(try image("taketaketake-highlight")))
        XCTAssertEqual(a.width, 1206)
        XCTAssertEqual(a.height, 1206, "a clipped row band made the board 1174 tall")
        XCTAssertEqual(b.height, b.width, "the board must be square")
        XCTAssertLessThanOrEqual(abs(b.height - a.height), 2)
    }

    // MARK: - Highlight rule

    func testHighlightOnADarkSquareIsTreatedAsBackground() throws {
        let img = try image("taketaketake-highlight")
        let rect = try XCTUnwrap(BoardLocator.locate(img))
        let palette = BoardPalette.estimate(image: img, rect: rect)

        // e7: dark square, highlighted, empty.
        let ring = SquareExtractor.ringMode(image: img, rect: rect, rank: 1, file: 4)
        let base = palette.boardColour(rank: 1, file: 4)
        XCTAssertGreaterThan(rgbDistance(ring, base), 60,
                             "this tint is further than the old 60-unit tolerance, which is why it broke")
        XCTAssertTrue(BoardLocator.isBoardColor(ring.r, ring.g, ring.b),
                      "but it is still a board colour, so it must be used as the background")
        XCTAssertEqual(palette.background(rank: 1, file: 4, image: img, rect: rect), ring)

        // The signature must agree: an empty highlighted square has no ink.
        let sigs = SquareExtractor.extract(image: img, rect: rect, palette: palette)
        XCTAssertTrue(sigs[1 * 8 + 4].isEmpty)
    }

    func testSquaresBelowTheAlertReadAtZeroDistance() throws {
        let (book, _, _) = try BoardReader.calibrate(image: try image("taketaketake-start"))
        let img = try image("taketaketake-highlight")
        let rect = try XCTUnwrap(BoardLocator.locate(img))
        let sigs = SquareExtractor.extract(image: img, rect: rect)

        let expected = try XCTUnwrap(ChessPosition(fen: Self.placementAfterE6 + " w KQkq - 0 1"))
        // Rank 8 is covered by the app's own error banner in this capture, so it is checked
        // by the synthetic test below; everything else must match outright.
        for rank in 1..<8 {
            for file in 0..<8 {
                let sig = sigs[rank * 8 + file]
                let match = book.classify(sig)
                XCTAssertNotNil(match, "\(BoardRect.squareName(rank: rank, file: file)) did not match")
                XCTAssertEqual(match?.piece, expected.board[rank * 8 + file],
                               "\(BoardRect.squareName(rank: rank, file: file))")
            }
        }
    }

    // MARK: - Oversized glyph owning the ring

    /// Captured on the phone: a black knight on a highlighted f6. The knight is large
    /// enough that the square's border ring is *entirely the knight's own fill*
    /// (RGB(33,29,43)), so any rule that samples the ring takes the piece for the square
    /// and masks the whole square as ink: "no template matched f6, closest shape
    /// distance 59". Board corners are the fix — a glyph is centred, so at least one
    /// corner is pure square.
    func testOversizedGlyphOnAHighlightedSquareStillReads() throws {
        let (book, _, _) = try BoardReader.calibrate(image: try image("taketaketake-start"))
        let frame = try image("taketaketake-knight-highlight")

        let read = try BoardReader.read(image: frame, book: book)

        XCTAssertEqual(
            read.fen,
            "rnbqkb1r/ppp2ppp/4pn2/3p4/2PP4/2N5/PP2PPPP/R1BQKBNR w KQkq - 0 1"
        )
        XCTAssertTrue(read.isTrustworthy)
        XCTAssertLessThanOrEqual(read.worstShapeDistance, 8)

        // f6 is the highlighted square and holds the black knight that owns the ring.
        let rect = read.rect
        let ring = SquareExtractor.ringMode(image: frame, rect: rect, rank: 2, file: 5)
        XCTAssertTrue(BoardPalette.isPieceFill(ring),
                      "the ring really is the knight's fill: \(ring)")
        XCTAssertEqual(book.classify(read.signatures[2 * 8 + 5])?.piece,
                       .piece(.knight, .black))
        XCTAssertEqual(book.classify(read.signatures[0 * 8 + 6])?.piece, .empty,
                       "g8 is empty; the knight left it")
    }

    // MARK: - A clean frame with the same highlight

    /// Paints the position after e6 into a clean capture and applies the measured tint, so
    /// the whole frame — including the occupied back ranks — can be read end to end.
    func testSyntheticHighlightedFrameReadsTheWholePosition() throws {
        let clean = try image("taketaketake-start")
        let book = try BoardReader.calibrate(image: clean).book
        let frame = try renderHighlightedFrame(from: clean)

        // The synthetic frame is the starting position plus Black's e7-e6, highlighted.
        var expected = TemplateBook.standardStartPlacement
        expected[1 * 8 + 4] = .empty
        expected[2 * 8 + 4] = .piece(.pawn, .black)

        let read = try BoardReader.read(image: frame, book: book)
        XCTAssertEqual(
            String(read.fen.split(separator: " ")[0]),
            String(FEN.encode(expected).split(separator: " ")[0])
        )
        XCTAssertTrue(read.isTrustworthy)
        // And the highlight squares themselves behave: one empty, one a pawn.
        let sigs = SquareExtractor.extract(image: frame, rect: read.rect)
        let e7 = sigs[1 * 8 + 4]
        let e6 = sigs[2 * 8 + 4]
        XCTAssertTrue(e7.isEmpty)
        XCTAssertEqual(book.classify(e6)?.piece, .piece(.pawn, .black))
    }

    func testTrackerNamesTheMoveThatCausedTheHighlight() throws {
        let clean = try image("taketaketake-start")
        let book = try BoardReader.calibrate(image: clean).book
        let read = try BoardReader.read(image: try renderHighlightedFrame(from: clean), book: book)

        // Seed the tracker with the position before Black's reply, White to move.
        var before = read.pieces
        before[1 * 8 + 4] = .piece(.pawn, .black)   // e7
        before[2 * 8 + 4] = .empty                  // e6
        let seed = ChessPosition(
            board: before, sideToMove: .black, castling: .all,
            enPassant: nil, halfmoveClock: 0, fullmoveNumber: 1
        )
        var tracker = PositionTracker(position: seed)

        let sync = tracker.observe(read.pieces)
        XCTAssertEqual(sync.sans, ["e6"])
        XCTAssertFalse(sync.didResync)
    }

    // MARK: - Pixel surgery

    private func renderHighlightedFrame(from image: PixelImage) throws -> PixelImage {
        let rect = try XCTUnwrap(BoardLocator.locate(image))
        let palette = BoardPalette.estimate(image: image, rect: rect)
        var rgba = image.rgba

        func set(_ x: Int, _ y: Int, _ c: RGB) {
            let o = (y * image.width + x) * 4
            rgba[o] = UInt8(c.r); rgba[o + 1] = UInt8(c.g); rgba[o + 2] = UInt8(c.b)
        }
        func get(_ x: Int, _ y: Int) -> RGB {
            let o = (y * image.width + x) * 4
            return RGB(Int(rgba[o]), Int(rgba[o + 1]), Int(rgba[o + 2]))
        }

        // Move the e7 pawn to e6: copy ink pixels, then repaint the vacated square flat.
        let src = rect.squareRect(rank: 1, file: 4)
        let dst = rect.squareRect(rank: 2, file: 4)
        let srcBG = palette.boardColour(rank: 1, file: 4)
        let dstBG = palette.boardColour(rank: 2, file: 4)

        for dy in 0..<dst.h {
            let sy = src.y + dy * src.h / dst.h
            for dx in 0..<dst.w {
                let sx = src.x + dx * src.w / dst.w
                let px = get(sx, sy)
                if rgbDistance(px, srcBG) > SquareExtractor.inkThreshold {
                    set(dst.x + dx, dst.y + dy, px)
                }
            }
        }
        for y in src.y..<(src.y + src.h) {
            for x in src.x..<(src.x + src.w) where rgbDistance(get(x, y), srcBG) > SquareExtractor.inkThreshold {
                set(x, y, srcBG)
            }
        }

        // Tint the two squares' background, leaving the glyph alone.
        for (rank, file, tint, bg) in [(1, 4, Self.darkTint, srcBG), (2, 4, Self.lightTint, dstBG)] {
            let sq = rect.squareRect(rank: rank, file: file)
            for y in sq.y..<(sq.y + sq.h) {
                for x in sq.x..<(sq.x + sq.w) where rgbDistance(get(x, y), bg) <= SquareExtractor.inkThreshold {
                    set(x, y, tint)
                }
            }
        }

        return PixelImage(width: image.width, height: image.height, rgba: rgba)
    }
}

/// Continuous mode streams frames at half scale. A rectangle learned from a full-resolution
/// screenshot therefore lands outside the frame, and the crash on 2026-11-17 was an
/// out-of-range pixel read in exactly that situation. Geometry must degrade, never trap.
final class OversizedRectTests: XCTestCase {

    private func fixture(_ name: String) throws -> PixelImage {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Fixtures")
        )
        return try XCTUnwrap(PixelImage(contentsOf: url))
    }

    /// Half the pixels, same rectangle: every sampler is asked for coordinates it cannot have.
    func testFullScaleRectAgainstAHalfScaleFrameDoesNotTrap() throws {
        let full = try fixture("taketaketake-start")
        let rect = try XCTUnwrap(BoardLocator.locate(full))
        XCTAssertTrue(BoardReader.fits(rect, in: full))

        let half = try XCTUnwrap(full.downscaledForTest(by: 0.5))
        XCTAssertFalse(BoardReader.fits(rect, in: half),
                       "a 1206 pt rect cannot fit a 603 pt frame")

        // None of these may trap; the values they return are not the point.
        _ = BoardPalette.estimate(image: half, rect: rect)
        _ = SquareExtractor.ringMode(image: half, rect: rect, rank: 0, file: 0)
        let palette = BoardPalette.estimate(image: half, rect: rect)
        _ = SquareExtractor.extractSquare(image: half, rect: rect, palette: palette,
                                          rank: 7, file: 7)
    }

    /// The whole read path, which is what the app actually calls.
    func testReadingAHalfScaleFrameRejectsInsteadOfCrashing() throws {
        let full = try fixture("taketaketake-start")
        let (book, _, _) = try BoardReader.calibrate(image: full)
        let rect = try XCTUnwrap(BoardLocator.locate(full))
        let half = try XCTUnwrap(full.downscaledForTest(by: 0.5))

        do {
            let read = try BoardReader.read(image: half, book: book, rect: rect)
            XCTAssertTrue(read.fen.contains("/"), "a successful read must still be a FEN")
        } catch {
            // A rejected read is the correct outcome for a frame the book cannot resolve.
            XCTAssertNotNil(error as? BoardError)
        }
    }
}
