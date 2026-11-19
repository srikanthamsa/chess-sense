import Foundation

/// Pixel bounds of the board in a decoded screen, origin top-left.
public struct BoardRect: Sendable, Equatable, Codable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Size of one square in pixels.
    public var squareSize: Double {
        Double(min(width, height)) / 8.0
    }

    /// `file` 0...7 left-to-right from the viewer, `rank` 0...7 top-to-bottom
    /// from the viewer. With white at the bottom, rank 0 is rank 8.
    public func squareRect(rank: Int, file: Int) -> (x: Int, y: Int, w: Int, h: Int) {
        let w = Double(width) / 8.0
        let h = Double(height) / 8.0
        return (
            x: x + Int((Double(file) * w).rounded()),
            y: y + Int((Double(rank) * h).rounded()),
            w: Int(((Double(file + 1) * w).rounded() - (Double(file) * w).rounded())),
            h: Int(((Double(rank + 1) * h).rounded() - (Double(rank) * h).rounded()))
        )
    }

    public static func squareName(rank: Int, file: Int) -> String {
        let f = Character(UnicodeScalar(UInt8(ascii: "a") + UInt8(file)))
        return "\(f)\(8 - rank)"
    }

    public var isPlausible: Bool {
        guard width > 100, height > 100 else { return false }
        let aspect = Double(width) / Double(height)
        return aspect > 0.9 && aspect < 1.1
    }

    public var description: String {
        "BoardRect(x: \(x), y: \(y), w: \(width), h: \(height))"
    }
}

extension BoardRect: CustomStringConvertible {}

public enum BoardLocator {
    /// True for the lavender family TakeTakeTake (and most chess UIs) paint squares with:
    /// neither near-black UI chrome nor near-white pieces, and blue-dominant.
    @inline(__always)
    public static func isBoardColor(_ r: Int, _ g: Int, _ b: Int) -> Bool {
        let l = luma(r, g, b)
        guard l > 0.34, l < 0.90 else { return false }
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        guard maxC - minC >= 10, maxC - minC <= 150 else { return false }
        // purple / blue-leaning squares
        return b >= r && b > g
    }

    /// Finds the board by row/column density.
    ///
    /// A chess board is the only UI element that produces a *long contiguous run*
    /// of rows that are mostly board-colored. Small lavender chrome (avatars, buttons)
    /// never reaches the per-row density threshold, so it can't corrupt the result.
    public static func locate(_ image: PixelImage) -> BoardRect? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }

        var rowCounts = [Int](repeating: 0, count: h)
        for y in 0..<h {
            var c = 0
            var o = y * w * 4
            for _ in 0..<w {
                if isBoardColor(Int(image.rgba[o]), Int(image.rgba[o + 1]), Int(image.rgba[o + 2])) {
                    c += 1
                }
                o += 4
            }
            rowCounts[y] = c
        }

        // Deliberately low. A board's outer ranks are full of pieces, so their rows are
        // only ~30% board-coloured — a 25% threshold clips them and yields a rect ~30 px
        // short, which skews every square and made real game screenshots unreadable
        // ("no template matched a8, closest shape distance 65"). Lavender chrome like an
        // avatar tile clears 6% too, but it is far shorter than the board, so the longest
        // contiguous run still selects the board.
        let rowThreshold = max(8, Int(Double(w) * 0.06))
        guard let band = longestRun(rowCounts, threshold: rowThreshold) else { return nil }

        var colCounts = [Int](repeating: 0, count: w)
        for x in 0..<w {
            var c = 0
            for y in band.lowerBound..<band.upperBound {
                let o = (y * w + x) * 4
                if isBoardColor(Int(image.rgba[o]), Int(image.rgba[o + 1]), Int(image.rgba[o + 2])) {
                    c += 1
                }
            }
            colCounts[x] = c
        }

        let bandHeight = band.upperBound - band.lowerBound
        let colThreshold = max(8, Int(Double(bandHeight) * 0.06))
        guard let cols = longestRun(colCounts, threshold: colThreshold) else { return nil }

        var rect = BoardRect(
            x: cols.lowerBound,
            y: band.lowerBound,
            width: cols.upperBound - cols.lowerBound,
            height: bandHeight
        )

        // A chessboard is square. If the row band came out short (or long) by a fraction,
        // trust the horizontal extent and re-centre, so squares stay square.
        if abs(rect.height - rect.width) > max(2, rect.width / 50) {
            let centre = rect.y + rect.height / 2
            rect.y = max(0, centre - rect.width / 2)
            rect.height = rect.width
        }

        return rect.isPlausible ? rect : nil
    }

    /// Longest contiguous index range where `counts[i] >= threshold`.
    static func longestRun(_ counts: [Int], threshold: Int) -> Range<Int>? {
        var best: Range<Int>?
        var start = -1
        for i in 0...counts.count {
            let above = i < counts.count && counts[i] >= threshold
            if above {
                if start < 0 { start = i }
            } else if start >= 0 {
                let run = start..<i
                if best == nil || run.count > best!.count { best = run }
                start = -1
            }
        }
        return best
    }
}
