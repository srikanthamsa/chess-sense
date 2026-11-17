import Foundation

/// Compact, background-relative description of one square.
///
/// Two independent channels, mirroring how chessvision.ai splits the problem:
///
///  - **shape** — a 16x16 coverage grid of "pixels that differ from this square's
///    background". Invariant to the square's base colour, to last-move / check /
///    selection tints, and to the board theme.
///  - **bright fraction** — the share of ink pixels meaningfully brighter than that
///    background. This is what separates white pieces from black pieces, which are
///    otherwise the *same silhouette* (measured at Hamming distance 1 on the fixture —
///    shape alone literally cannot do it).
public struct SquareSignature: Sendable, Hashable, Codable {
    public var words: [UInt64]
    /// Fraction of ink pixels brighter than `backgroundLuma + brightenMargin`.
    public var brightFraction: Double
    /// Fraction of the square covered by ink.
    public var ink: Double
    public var backgroundLuma: Double

    public static let grid = 16
    /// Below this ink fraction the square is treated as empty and colour is ignored.
    public static let emptyInkThreshold = 0.015

    public var isEmpty: Bool { ink < Self.emptyInkThreshold }

    /// Hamming distance in bits over the shape grid, 0...256.
    public func shapeDistance(to other: SquareSignature) -> Int {
        var d = 0
        for i in 0..<words.count {
            d += (words[i] ^ other.words[i]).nonzeroBitCount
        }
        return d
    }

    /// |Δ bright fraction|, 0 when either square is empty (an empty square has no piece).
    public func colorDistance(to other: SquareSignature) -> Double {
        if isEmpty || other.isEmpty { return 0 }
        return abs(brightFraction - other.brightFraction)
    }
}

public enum SquareExtractor {
    /// Fraction of each square's edge that is ignored, to dodge grid lines,
    /// coordinate labels and highlight borders.
    public static let inset = 0.15
    /// Width of the border band sampled for a square's background colour, as a fraction
    /// of the square.
    public static let ringWidth = 0.22
    /// RGB distance from the square's background above which a pixel counts as ink.
    public static let inkThreshold = 60.0
    /// Sub-cell coverage above which a shape bit is set.
    public static let bitThreshold = 0.40
    /// An ink pixel counts as "bright" when it is this much lighter than the background.
    public static let brightenMargin = 0.15
    /// Cap on the bright threshold, so a white body still reads as bright on a pale square.
    public static let brightThresholdCap = 0.92

    public static func extract(image: PixelImage, rect: BoardRect) -> [SquareSignature] {
        extract(image: image, rect: rect, palette: .estimate(image: image, rect: rect))
    }

    public static func extract(
        image: PixelImage,
        rect: BoardRect,
        palette: BoardPalette
    ) -> [SquareSignature] {
        var out: [SquareSignature] = []
        out.reserveCapacity(64)
        for rank in 0..<8 {
            for file in 0..<8 {
                out.append(extractSquare(
                    image: image, rect: rect, palette: palette, rank: rank, file: file
                ))
            }
        }
        return out
    }

    /// Inner bounds of a square, after the inset that dodges grid lines and labels.
    static func innerBounds(
        rect: BoardRect, rank: Int, file: Int
    ) -> (x0: Int, y0: Int, x1: Int, y1: Int, w: Int, h: Int) {
        let sq = rect.squareRect(rank: rank, file: file)
        let insetX = Int(Double(sq.w) * inset)
        let insetY = Int(Double(sq.h) * inset)
        let x0 = sq.x + insetX
        let y0 = sq.y + insetY
        let x1 = sq.x + sq.w - insetX
        let y1 = sq.y + sq.h - insetY
        return (x0, y0, x1, y1, max(1, x1 - x0), max(1, y1 - y0))
    }

    /// Most common colour in a square's border ring. The ring is usually pure board
    /// colour, so this is a reliable local background sample that follows tints.
    public static func ringMode(
        image: PixelImage, rect: BoardRect, rank: Int, file: Int
    ) -> RGB {
        let b = innerBounds(rect: rect, rank: rank, file: file)
        let ringW = max(2, Int(Double(min(b.w, b.h)) * ringWidth))
        var hist = [Int](repeating: 0, count: 4096)
        for y in b.y0..<b.y1 {
            let inRingRow = (y - b.y0) < ringW || (b.y1 - 1 - y) < ringW
            var o = image.offset(b.x0, y)
            for x in b.x0..<b.x1 {
                if inRingRow || (x - b.x0) < ringW || (b.x1 - 1 - x) < ringW {
                    let idx = (Int(image.rgba[o]) >> 4) << 8
                        | (Int(image.rgba[o + 1]) >> 4) << 4
                        | (Int(image.rgba[o + 2]) >> 4)
                    hist[idx] += 1
                }
                o += 4
            }
        }
        var bestBin = 0
        for (i, c) in hist.enumerated() where c > hist[bestBin] { bestBin = i }

        var sr = 0, sg = 0, sb = 0, n = 0
        for y in b.y0..<b.y1 {
            let inRingRow = (y - b.y0) < ringW || (b.y1 - 1 - y) < ringW
            var o = image.offset(b.x0, y)
            for x in b.x0..<b.x1 {
                if inRingRow || (x - b.x0) < ringW || (b.x1 - 1 - x) < ringW {
                    let idx = (Int(image.rgba[o]) >> 4) << 8
                        | (Int(image.rgba[o + 1]) >> 4) << 4
                        | (Int(image.rgba[o + 2]) >> 4)
                    if idx == bestBin {
                        sr += Int(image.rgba[o])
                        sg += Int(image.rgba[o + 1])
                        sb += Int(image.rgba[o + 2])
                        n += 1
                    }
                }
                o += 4
            }
        }
        return n > 0 ? RGB(sr / n, sg / n, sb / n) : RGB(0, 0, 0)
    }

    static func extractSquare(
        image: PixelImage,
        rect: BoardRect,
        palette: BoardPalette,
        rank: Int,
        file: Int
    ) -> SquareSignature {
        let b = innerBounds(rect: rect, rank: rank, file: file)
        let bg = palette.background(rank: rank, file: file)
        let bgLuma = bg.luminance
        let brightThreshold = min(bgLuma + brightenMargin, brightThresholdCap)

        var cells = [Int](repeating: 0, count: SquareSignature.grid * SquareSignature.grid)
        var cellTotals = [Int](repeating: 0, count: cells.count)
        var inkPixels = 0
        var brightPixels = 0

        for y in b.y0..<b.y1 {
            let gy = min(SquareSignature.grid - 1, (y - b.y0) * SquareSignature.grid / b.h)
            var o = image.offset(b.x0, y)
            for x in b.x0..<b.x1 {
                let gx = min(SquareSignature.grid - 1, (x - b.x0) * SquareSignature.grid / b.w)
                let idx = gy * SquareSignature.grid + gx
                cellTotals[idx] += 1
                let r = Int(image.rgba[o]), g = Int(image.rgba[o + 1]), bl = Int(image.rgba[o + 2])
                if rgbDistance(RGB(r, g, bl), bg) > inkThreshold {
                    cells[idx] += 1
                    inkPixels += 1
                    if luma(r, g, bl) > brightThreshold { brightPixels += 1 }
                }
                o += 4
            }
        }

        var words = [UInt64](repeating: 0, count: (cells.count + 63) / 64)
        for i in 0..<cells.count {
            let total = max(1, cellTotals[i])
            if Double(cells[i]) / Double(total) >= bitThreshold {
                words[i >> 6] |= (1 << UInt64(i & 63))
            }
        }

        return SquareSignature(
            words: words,
            brightFraction: inkPixels > 0 ? Double(brightPixels) / Double(inkPixels) : 0,
            ink: Double(inkPixels) / Double(max(1, b.w * b.h)),
            backgroundLuma: bgLuma
        )
    }
}

extension SquareSignature: CustomStringConvertible {
    public var description: String {
        isEmpty
            ? "empty(bg \(String(format: "%.2f", backgroundLuma)))"
            : "ink \(String(format: "%.2f", ink)) bright \(String(format: "%.2f", brightFraction))"
    }
}
