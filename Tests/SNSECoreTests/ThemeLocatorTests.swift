import XCTest
@testable import SNSECore

/// The locator had one job and did it for exactly one theme: TakeTakeTake's lavender.
/// Lichess is green on cream, so it found nothing at all. These tests pin the portable path.
final class ThemeLocatorTests: XCTestCase {

    private func image(_ name: String, _ ext: String = "png") throws -> PixelImage {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
        )
        return try XCTUnwrap(PixelImage(contentsOf: url))
    }

    /// A real lichess screenshot, 1206x2622, board flush to both edges.
    func testFindsLichessBoard() throws {
        let board = try image("lichess-theme", "jpg")
        let rect = try XCTUnwrap(BoardLocator.locateGeneric(board))

        XCTAssertEqual(rect.x, 0, accuracy: 4)
        XCTAssertEqual(rect.width, 1206, accuracy: 8)
        XCTAssertEqual(rect.height, rect.width, accuracy: 8)
        // The board sits under the header and above the player row.
        XCTAssertGreaterThan(rect.y, 600)
        XCTAssertLessThan(rect.y, 1000)
    }

    /// The themed path must keep working, and must not be needed for the new one.
    func testFindsTakeTakeTakeBoardEitherWay() throws {
        let board = try image("taketaketake-highlight")
        let themed = try XCTUnwrap(BoardLocator.locate(board))
        let generic = try XCTUnwrap(BoardLocator.locateGeneric(board))

        XCTAssertEqual(Double(generic.width), Double(themed.width), accuracy: 12)
        XCTAssertEqual(Double(generic.y), Double(themed.y), accuracy: 40)
    }

    /// A flat UI screen is not a board: the checkerboard check has to reject it.
    func testRejectsNonBoard() throws {
        let size = 400
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for index in 0..<(size * size) {
            let value: UInt8 = index % 97 == 0 ? 40 : 240
            pixels[index * 4] = value
            pixels[index * 4 + 1] = value
            pixels[index * 4 + 2] = value
            pixels[index * 4 + 3] = 255
        }
        let flat = PixelImage(width: size, height: size, rgba: pixels)
        XCTAssertNil(BoardLocator.locateGeneric(flat))
    }
}
