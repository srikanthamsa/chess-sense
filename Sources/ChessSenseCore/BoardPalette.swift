import Foundation

/// The two square colours of a board, and which checkerboard parity is the light one.
///
/// A chessboard is a checkerboard: square colour is a function of `(rank + file) % 2`.
/// That structural prior is what makes this robust — a background colour is never
/// inferred from a square's *content* (a big glyph can own the largest flat area inside
/// its square and hijack a per-square colour mode; that failure inverted white/black for
/// knights, queens and kings when it was tried).
public struct BoardPalette: Sendable {
    public let light: RGB
    public let dark: RGB
    /// True when `(rank + file) % 2 == 0` squares are the light ones.
    public let lightIsEvenParity: Bool
    /// Per-square ring colours recorded at estimation time, used for tint detection.
    private let ringModes: [RGB]

    public init(light: RGB, dark: RGB, lightIsEvenParity: Bool, ringModes: [RGB]) {
        self.light = light
        self.dark = dark
        self.lightIsEvenParity = lightIsEvenParity
        self.ringModes = ringModes
    }

    public func boardColour(rank: Int, file: Int) -> RGB {
        let isEven = (rank + file) % 2 == 0
        return isEven == lightIsEvenParity ? light : dark
    }

    /// Background for one square.
    ///
    /// Normally the square's own ring colour, which follows last-move / check tints
    /// automatically. If that ring colour is far from the palette — i.e. the glyph, not
    /// the board, owns the ring — fall back to the structural palette colour. Tints move
    /// a square by a few tens of RGB units; a hijack by a glyph moves it by ~90+.
    public func background(rank: Int, file: Int) -> RGB {
        let expected = boardColour(rank: rank, file: file)
        let ring = ringModes[rank * 8 + file]
        return rgbDistance(ring, expected) <= Self.tintTolerance ? ring : expected
    }

    /// Max RGB distance from the palette colour still treated as a board tint.
    public static let tintTolerance = 60.0

    public static func estimate(image: PixelImage, rect: BoardRect) -> BoardPalette {
        var modes: [RGB] = []
        modes.reserveCapacity(64)
        for rank in 0..<8 {
            for file in 0..<8 {
                modes.append(SquareExtractor.ringMode(
                    image: image, rect: rect, rank: rank, file: file
                ))
            }
        }

        // One representative per parity, chosen as the medoid so a few contaminated
        // squares (giant glyphs, a promotion dialog) cannot drag the palette.
        func medoid(_ indices: [Int]) -> RGB {
            var best = indices[0]
            var bestSum = Double.infinity
            for i in indices {
                var sum = 0.0
                for j in indices {
                    sum += rgbDistance(modes[i], modes[j])
                }
                if sum < bestSum { bestSum = sum; best = i }
            }
            return modes[best]
        }

        let even = (0..<64).filter { (($0 / 8) + ($0 % 8)) % 2 == 0 }
        let odd = (0..<64).filter { (($0 / 8) + ($0 % 8)) % 2 == 1 }
        let evenColour = medoid(even)
        let oddColour = medoid(odd)

        let evenLuma = evenColour.luminance
        let oddLuma = oddColour.luminance
        let lightIsEven = evenLuma >= oddLuma

        return BoardPalette(
            light: lightIsEven ? evenColour : oddColour,
            dark: lightIsEven ? oddColour : evenColour,
            lightIsEvenParity: lightIsEven,
            ringModes: modes
        )
    }
}
