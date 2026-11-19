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

    // MARK: - Theme-agnostic location

    /// A square is "boardish" if it is either coloured or bright.
    ///
    /// Every chess board is one or the other: lichess is green on cream, TakeTakeTake is
    /// lavender, chess.com is green on buff. The chrome around a board -- dark backgrounds,
    /// translucent headers, photographic blur -- is neither, which is what makes this a
    /// portable filter where "cube of two specific colours" was not.
    @inline(__always)
    public static func isBoardish(_ r: Int, _ g: Int, _ b: Int) -> Bool {
        let l = luma(r, g, b)
        // A floor well above black chrome: the blurred photographic backgrounds these apps
        // put behind a board sit near 0.15 and would otherwise read as board everywhere.
        guard l > 0.34 else { return false }
        let maxC = Double(max(r, g, b)) / 255.0
        let minC = Double(min(r, g, b)) / 255.0
        let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
        return saturation >= 0.10 || l >= 0.68
    }

    /// Finds a board without knowing its theme.
    ///
    /// Longest run of rows that are mostly "boardish", then columns within it, then the
    /// checkerboard check: two parities must genuinely differ. Every threshold is tried and
    /// the best-scoring candidate wins, because the right threshold depends on how much of
    /// the frame the board occupies -- a single guess picked a 749 px band out of a 1206 px
    /// board on the first lichess screenshot.
    public static func locateGeneric(_ image: PixelImage) -> BoardRect? {
        let w = image.width, h = image.height
        guard w > 200, h > 200 else { return nil }

        var rowHits = [Double](repeating: 0, count: h)
        for y in 0..<h {
            var hit = 0
            var o = y * w * 4
            for _ in 0..<w {
                if isBoardish(Int(image.rgba[o]), Int(image.rgba[o + 1]), Int(image.rgba[o + 2])) {
                    hit += 1
                }
                o += 4
            }
            rowHits[y] = Double(hit) / Double(w)
        }

        var best: (BoardRect, Double)?
        for threshold in [0.55, 0.45, 0.35, 0.25] {
            guard let rows = longestFractionRun(rowHits, threshold: threshold) else { continue }
            let bandHeight = rows.upperBound - rows.lowerBound
            guard bandHeight > 120 else { continue }

            var colHits = [Double](repeating: 0, count: w)
            for x in 0..<w {
                var hit = 0
                for y in rows.lowerBound..<rows.upperBound {
                    let o = (y * w + x) * 4
                    if isBoardish(Int(image.rgba[o]), Int(image.rgba[o + 1]), Int(image.rgba[o + 2])) {
                        hit += 1
                    }
                }
                colHits[x] = Double(hit) / Double(bandHeight)
            }
            guard let cols = longestFractionRun(colHits, threshold: threshold)
                    ?? longestFractionRun(colHits, threshold: threshold * 0.7)
            else { continue }

            var rect = BoardRect(
                x: cols.lowerBound,
                y: rows.lowerBound,
                width: cols.upperBound - cols.lowerBound,
                height: bandHeight
            )
            guard rect.isPlausible, rect.width >= 200 else { continue }
            if abs(rect.height - rect.width) > max(4, rect.width / 12) {
                let centre = rect.y + rect.height / 2
                rect.y = max(0, centre - rect.width / 2)
                rect.height = rect.width
            }
            guard rect.isPlausible else { continue }
            let agreement = checkerboardAgreement(image, rect)
            guard agreement > 0.35 else { continue }
            let score = Double(rect.width * rect.height) * agreement
            if best == nil || score > best!.1 { best = (rect, score) }
        }
        return best?.0
    }

    /// Longest contiguous run where the fraction values stay at or above a threshold.
    static func longestFractionRun(_ values: [Double], threshold: Double) -> Range<Int>? {
        var best: Range<Int>?
        var start = -1
        for i in 0...values.count {
            let above = i < values.count && values[i] >= threshold
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

    /// How much the candidate rect looks like a chessboard: the two parities must differ.
    private static func checkerboardAgreement(_ image: PixelImage, _ rect: BoardRect) -> Double {
        guard rect.width > 0, rect.height > 0 else { return 0 }
        var light: [Double] = []
        var dark: [Double] = []
        for rank in 0..<8 {
            for file in 0..<8 {
                let cell = rect.squareRect(rank: rank, file: file)
                // Corners avoid the piece in the middle of a square.
                for (fx, fy) in [(0.2, 0.2), (0.8, 0.2), (0.2, 0.8), (0.8, 0.8)] {
                    let x = cell.x + Int(Double(cell.w) * fx)
                    let y = cell.y + Int(Double(cell.h) * fy)
                    guard x >= 0, y >= 0, x < image.width, y < image.height else { continue }
                    let o = (y * image.width + x) * 4
                    let l = luma(Int(image.rgba[o]), Int(image.rgba[o + 1]), Int(image.rgba[o + 2]))
                    if (rank + file) % 2 == 0 { light.append(l) } else { dark.append(l) }
                }
            }
        }
        guard !light.isEmpty, !dark.isEmpty else { return 0 }
        let lightMean = light.reduce(0, +) / Double(light.count)
        let darkMean = dark.reduce(0, +) / Double(dark.count)
        return min(1, abs(lightMean - darkMean) / 0.18)
    }
}