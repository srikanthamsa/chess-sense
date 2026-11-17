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
    /// Usually the square's own ring colour, so last-move and check highlights are picked
    /// up for free. The trap is that a big glyph can own the ring, and then the "ring
    /// colour" is piece fill, not board.
    ///
    /// The discriminator is *what kind of colour it is*, not how far it moved from the
    /// palette. A board square and a highlight are both mid-tone blue-leaning lavender;
    /// piece fills are not — white sits near luma 0.95 with almost no chroma, and the
    /// black set sits near luma 0.10. An earlier version compared RGB distance to the
    /// palette with a 60-unit tolerance and broke on real games: TakeTakeTake's blue
    /// last-move highlight on a *dark* square moves further than 60 units, so the square
    /// fell back to the palette colour and the entire highlight was masked as ink
    /// ("no template matched e7, closest shape distance 59"). The same highlight on a
    /// light square moved less than 60 and worked, which is why it looked intermittent.
    public func background(rank: Int, file: Int) -> RGB {
        let ring = ringModes[rank * 8 + file]
        if BoardLocator.isBoardColor(ring.r, ring.g, ring.b) { return ring }
        return boardColour(rank: rank, file: file)
    }

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
