import Foundation

/// Which side of the board is at the bottom of the screen.
///
/// TakeTakeTake flips the board when you are Black, and the coordinate labels flip with it:
/// files run H→A left to right and ranks 1→8 top to bottom. A reader that assumes White is
/// at the bottom then produces a position rotated 180°, and every suggested move is a mirror
/// of reality — which is how "Nxc2" appeared in a position where the knight could not get
/// anywhere near that square.
public enum BoardOrientation: String, Sendable {
    case whiteAtBottom
    case blackAtBottom

    public var isFlipped: Bool { self == .blackAtBottom }
}

public enum OrientationDetector {
    /// The board draws its rank digits in a narrow strip at the right edge, centred in each
    /// row. Rank 8 is the densest digit and rank 1 the sparsest, so comparing the ink in the
    /// top-right cell against the bottom-right cell is enough — no OCR, no templates, and it
    /// survives font or size changes because only the *ordering* is used.
    public static func detect(
        image: PixelImage,
        rect: BoardRect,
        palette: BoardPalette
    ) -> BoardOrientation {
        let topDensity = labelDensity(image: image, rect: rect, palette: palette, rank: 0)
        let bottomDensity = labelDensity(image: image, rect: rect, palette: palette, rank: 7)

        // Too faint to read: assume the ordinary layout rather than guessing.
        let minimumSignal = 0.01
        guard max(topDensity, bottomDensity) > minimumSignal else { return .whiteAtBottom }

        return topDensity > bottomDensity ? .whiteAtBottom : .blackAtBottom
    }

    /// Ink fraction of the coordinate digit drawn for one rank row.
    ///
    /// Measured on the captures: the digits sit in the top ~20% of each square, in a strip
    /// of the outer 15% of the board width (x 1183...1197 of 1206). Not vertically centred —
    /// an earlier version sampled the middle band and read exactly zero every time. Both
    /// edges are sampled so a layout that moves the labels left still works.
    static func labelDensity(
        image: PixelImage,
        rect: BoardRect,
        palette: BoardPalette,
        rank: Int
    ) -> Double {
        var best = 0.0
        for file in [0, 7] {
            let sq = rect.squareRect(rank: rank, file: file)
            let bg = palette.background(rank: rank, file: file, image: image, rect: rect)
            let x0 = file == 0
                ? sq.x
                : sq.x + Int(Double(sq.w) * 0.85)
            let x1 = file == 0
                ? sq.x + Int(Double(sq.w) * 0.15)
                : sq.x + sq.w
            let y0 = sq.y
            let y1 = sq.y + Int(Double(sq.h) * 0.22)
            guard x1 > x0, y1 > y0 else { continue }

            var ink = 0
            var total = 0
            for y in y0..<min(image.height, y1) {
                var o = image.offset(max(0, x0), y)
                for _ in max(0, x0)..<min(image.width, x1) {
                    total += 1
                    let px = RGB(Int(image.rgba[o]), Int(image.rgba[o + 1]), Int(image.rgba[o + 2]))
                    if rgbDistance(px, bg) > 40 { ink += 1 }
                    o += 4
                }
            }
            if total > 0 { best = max(best, Double(ink) / Double(total)) }
        }
        return best
    }
}
