import XCTest
@testable import SNSECore

/// Proves the pixel path end to end: take the real screenshot, move a piece *in the pixels*,
/// read the new frame, and let the tracker name the move.
///
/// The board renders flat, so a source square can be repainted with its palette colour and
/// the result is byte-identical to what the app would actually draw. That makes these
/// synthetic frames legitimate fixtures rather than approximations.
final class PixelMoveTests: XCTestCase {

    private func fixture() throws -> PixelImage {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "taketaketake-start", withExtension: "png",
                              subdirectory: "Fixtures")
        )
        return try XCTUnwrap(PixelImage(contentsOf: url))
    }

    /// Moves whatever is on `from` to `to` and repaints `from` with its flat board colour.
    private func moving(
        _ image: PixelImage,
        rect: BoardRect,
        palette: BoardPalette,
        from: (rank: Int, file: Int),
        to: (rank: Int, file: Int)
    ) -> PixelImage {
        var bytes = image.rgba
        let source = rect.squareRect(rank: from.rank, file: from.file)
        let target = rect.squareRect(rank: to.rank, file: to.file)

        // Snapshot, then write into the destination.
        var block: [UInt8] = []
        block.reserveCapacity(source.w * source.h * 4)
        for dy in 0..<source.h {
            let row = image.offset(source.x, source.y + dy)
            block.append(contentsOf: bytes[row..<(row + source.w * 4)])
        }
        // Nearest-neighbour copy: square rects can differ by a pixel because the board
        // divides 1206 by 8 with rounding, so a straight block copy is not valid.
        for dy in 0..<target.h {
            let row = (image.offset(target.x, target.y + dy))
            let sy = min(source.h - 1, dy * source.h / target.h)
            for dx in 0..<target.w {
                let o = row + dx * 4
                let sx = min(source.w - 1, dx * source.w / target.w)
                let s = sy * source.w * 4 + sx * 4
                bytes[o] = block[s]
                bytes[o + 1] = block[s + 1]
                bytes[o + 2] = block[s + 2]
                bytes[o + 3] = block[s + 3]
            }
        }

        // Repaint the vacated square with the colour the board would draw there.
        let fill = palette.boardColour(rank: from.rank, file: from.file)
        for dy in 0..<source.h {
            let row = image.offset(source.x, source.y + dy)
            for dx in 0..<source.w {
                let o = row + dx * 4
                bytes[o] = UInt8(fill.r)
                bytes[o + 1] = UInt8(fill.g)
                bytes[o + 2] = UInt8(fill.b)
                bytes[o + 3] = 255
            }
        }

        return PixelImage(width: image.width, height: image.height, rgba: bytes)
    }

    func testPawnPushIsDetectedFromPixels() throws {
        let image = try fixture()
        let (book, rect, _) = try BoardReader.calibrate(image: image)
        let palette = BoardPalette.estimate(image: image, rect: rect)

        // e2 -> e4 (rank 6 -> rank 4 in reader indexing)
        let after = moving(image, rect: rect, palette: palette,
                           from: (6, 4), to: (4, 4))
        let read = try BoardReader.read(image: after, book: book, rect: rect)
        XCTAssertTrue(read.isTrustworthy)
        XCTAssertEqual(
            String(read.fen.split(separator: " ")[0]),
            "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR"
        )

        var tracker = PositionTracker(position: try XCTUnwrap(ChessPosition(
            fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        )))
        let sync = tracker.observe(read.pieces)
        XCTAssertEqual(sync.sans, ["e4"])
        XCTAssertFalse(sync.didResync)
        XCTAssertEqual(tracker.position.enPassant, square(from: "e3"))
    }

    /// The board is 1206 px wide over 8 columns, so columns land on 150 or 151 px.
    /// That is why every synthetic frame in this file moves a piece *along its own file*:
    /// a same-file move copies an exactly-sized block, while a cross-file move would have
    /// to rescale the glyph by a pixel and the resulting frame would not be a faithful
    /// rendering. (First attempt at a b1->c3 frame did exactly that and read back at shape
    /// distance 59, while the same knight reads at 0 in the real screenshot.)
    func testColumnWidthsVaryByOnePixel() throws {
        let image = try fixture()
        let rect = try XCTUnwrap(BoardLocator.locate(image))
        let widths = (0..<8).map { rect.squareRect(rank: 0, file: $0).w }
        let heights = (0..<8).map { rect.squareRect(rank: $0, file: 0).h }

        XCTAssertEqual(Set(widths).count, 2, "columns are 150 or 151 px: \(widths)")
        XCTAssertEqual(Set(heights).count, 2, "rows are 150 or 151 px: \(heights)")
        XCTAssertLessThanOrEqual(Set(widths).max()! - Set(widths).min()!, 1)
        XCTAssertEqual(widths.reduce(0, +), rect.width, "columns must tile the board exactly")
    }

    func testPawnDoublePushIsDetectedFromPixels() throws {
        let image = try fixture()
        let (book, rect, _) = try BoardReader.calibrate(image: image)
        let palette = BoardPalette.estimate(image: image, rect: rect)

        // a2 -> a4 (rank 6 file 0 -> rank 4 file 0): pawn, fully contained in its square.
        let after = moving(image, rect: rect, palette: palette,
                           from: (6, 0), to: (4, 0))
        let read = try BoardReader.read(image: after, book: book, rect: rect)

        var tracker = PositionTracker()
        let sync = tracker.observe(read.pieces)
        XCTAssertEqual(sync.sans, ["a4"])
        XCTAssertFalse(sync.didResync)
    }

    func testTwoPliesInThePixelsAreBothRecovered() throws {
        let image = try fixture()
        let (book, rect, _) = try BoardReader.calibrate(image: image)
        let palette = BoardPalette.estimate(image: image, rect: rect)

        // 1. e4 e5, rendered into one frame.
        var after = moving(image, rect: rect, palette: palette, from: (6, 4), to: (4, 4))
        after = moving(after, rect: rect, palette: palette, from: (1, 4), to: (3, 4))
        let read = try BoardReader.read(image: after, book: book, rect: rect)

        var tracker = PositionTracker()
        let sync = tracker.observe(read.pieces)
        XCTAssertEqual(sync.sans, ["e4", "e5"])
        XCTAssertFalse(sync.didResync)
    }

    func testUnchangedPixelsAreNotAMove() throws {
        let image = try fixture()
        let (book, rect, _) = try BoardReader.calibrate(image: image)
        let read = try BoardReader.read(image: image, book: book, rect: rect)

        var tracker = PositionTracker()
        let sync = tracker.observe(read.pieces)
        XCTAssertTrue(sync.moves.isEmpty)
        XCTAssertFalse(sync.didResync)
    }
}
