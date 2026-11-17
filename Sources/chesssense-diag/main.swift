import ChessSenseCore
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: chesssense-diag <screenshot.png>")
    exit(2)
}
let url = URL(fileURLWithPath: args[1])
guard let image = PixelImage(contentsOf: url) else {
    print("could not decode \(url.path)")
    exit(1)
}

print("image: \(image.width)x\(image.height)")

guard let rect = BoardLocator.locate(image) else {
    print("board: NOT FOUND")
    exit(1)
}
print("board: \(rect)  square=\(String(format: "%.2f", rect.squareSize))px")

let palette = BoardPalette.estimate(image: image, rect: rect)
print("palette: light=\(palette.light) dark=\(palette.dark) lightIsEven=\(palette.lightIsEvenParity)")
let sigs = SquareExtractor.extract(image: image, rect: rect, palette: palette)

print("\nbrightness map: ink fraction, then bright-fraction (empty = '-')")
for rank in 0..<8 {
    var inkLine = ""
    var lumaLine = ""
    for file in 0..<8 {
        let s = sigs[rank * 8 + file]
        inkLine += String(format: " %4.2f", s.ink)
        lumaLine += s.isEmpty ? "    -" : String(format: " %4.2f", s.brightFraction)
    }
    print("\(8 - rank) ink " + inkLine)
    print("  brt " + lumaLine)
}

func d(_ a: (Int, Int), _ b: (Int, Int)) -> (Int, Double) {
    let x = sigs[a.0 * 8 + a.1], y = sigs[b.0 * 8 + b.1]
    return (x.shapeDistance(to: y), x.colorDistance(to: y))
}

print("\nsame-piece pairs (shape hamming, bright delta):")
for (label, a, b) in [
    ("rook   a1-h1", (7, 0), (7, 7)),
    ("knight b1-g1", (7, 1), (7, 6)),
    ("bishop c1-f1", (7, 2), (7, 5)),
    ("pawn   a2-b2", (6, 0), (6, 1)),
    ("pawn   a2-h2", (6, 0), (6, 7)),
    ("empty  a4-b4", (4, 0), (4, 1)),
    ("empty  a4-a5", (4, 0), (3, 0)),
] as [(String, (Int, Int), (Int, Int))] {
    let (sh, cd) = d(a, b)
    print(String(format: "  %@  shape=%3d  colour=%.3f", label.padding(toLength: 12, withPad: " ", startingAt: 0), sh, cd))
}

print("\ncross-colour pairs (bright delta must be LARGE):")
for (label, a, b) in [
    ("whitePawn vs blackPawn", (6, 0), (1, 0)),
    ("whiteRook vs blackRook", (7, 0), (0, 0)),
    ("empty vs whitePawn", (4, 0), (6, 0)),
] as [(String, (Int, Int), (Int, Int))] {
    let (sh, cd) = d(a, b)
    print(String(format: "  %@  shape=%3d  colour=%.3f", label.padding(toLength: 24, withPad: " ", startingAt: 0), sh, cd))
}

do {
    let (book, _, read) = try BoardReader.calibrate(image: image, rect: rect)
    print("\ntemplates: \(book.entries.count)")
    for e in book.entries {
        print(String(format: "  %@  support=%d  shapeTol=%d  colorTol=%.2f",
                     "\(e.piece)".padding(toLength: 3, withPad: " ", startingAt: 0),
                     e.support, book.maxShapeDistance, book.maxColorDistance))
    }
    print("\nfen:        \(read.fen)")
    print("expected:   \(FEN.encode(TemplateBook.standardStartPlacement))")
    print(String(format: "exactRate=%.3f worstShape=%d minColorMargin=%.3f trustworthy=%@",
                 read.exactRate, read.worstShapeDistance, read.minColorMargin,
                 read.isTrustworthy ? "yes" : "no"))
} catch {
    print("\nERROR: \(error)")
    exit(1)
}
