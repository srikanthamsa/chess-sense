import Foundation

/// Captures a frame that the reader could not handle, plus everything needed to reproduce
/// it offline: the pixels, the failure reason, the board rect, the palette and every
/// square's distance from its nearest template.
///
/// This exists because "no template matched f6 (closest shape distance 59)" is not enough
/// information to fix anything — 59 bits means the whole square was masked as ink, but not
/// *why*. With the frame on disk the exact case becomes a unit test instead of a guess.
enum Diagnostics {
    private static let keep = 6

    static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("chesssense-frames", isDirectory: true)
    }

    @discardableResult
    static func record(
        image: PixelImage,
        reason: String,
        book: TemplateBook?,
        rectOverride: BoardRect? = nil
    ) -> URL? {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let slug = reason.replacingOccurrences(of: " ", with: "_")
            .prefix(40)
        let stem = "\(stamp)_\(slug)"

        let pngURL = directory.appendingPathComponent("\(stem).png")
        guard let png = image.pngData(), (try? png.write(to: pngURL)) != nil else {
            return nil
        }

        // Everything the classifier saw, so the offline reproduction matches exactly.
        var report: [String: Any] = [
            "reason": reason,
            "image": pngURL.lastPathComponent,
            "size": ["\(image.width)x\(image.height)"],
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            "recordedAt": stamp,
        ]
        if let rect = rectOverride ?? BoardLocator.locate(image) {
            report["boardRect"] = [rect.x, rect.y, rect.width, rect.height]
            let palette = BoardPalette.estimate(image: image, rect: rect)
            report["palette"] = [
                "light": [palette.light.r, palette.light.g, palette.light.b],
                "dark": [palette.dark.r, palette.dark.g, palette.dark.b],
                "lightIsEvenParity": palette.lightIsEvenParity,
            ]
            let sigs = SquareExtractor.extract(image: image, rect: rect, palette: palette)
            var squares: [[String: Any]] = []
            for rank in 0..<8 {
                for file in 0..<8 {
                    let sig = sigs[rank * 8 + file]
                    var entry: [String: Any] = [
                        "square": BoardRect.squareName(rank: rank, file: file),
                        "ink": (sig.ink * 1000).rounded() / 1000,
                        "bright": (sig.brightFraction * 1000).rounded() / 1000,
                        "background": (sig.backgroundLuma * 1000).rounded() / 1000,
                        "ring": { () -> [Int] in
                            let c = SquareExtractor.ringMode(image: image, rect: rect,
                                                             rank: rank, file: file)
                            return [c.r, c.g, c.b]
                        }(),
                    ]
                    if let book {
                        entry["nearestShape"] = book.bestShapeDistance(sig)
                        if let match = book.classify(sig) {
                            entry["match"] = "\(match.piece)"
                            entry["matchShape"] = match.shapeDistance
                            entry["matchColour"] = (match.colorDistance * 1000).rounded() / 1000
                        }
                    }
                    squares.append(entry)
                }
            }
            report["squares"] = squares
        }

        let jsonURL = directory.appendingPathComponent("\(stem).json")
        if let data = try? JSONSerialization.data(withJSONObject: report,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: jsonURL)
        }

        prune()
        return jsonURL
    }

    private static func prune() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        let jsons = names.filter { $0.hasSuffix(".json") }.sorted()
        guard jsons.count > keep else { return }
        for name in jsons.dropLast(keep) {
            let stem = (name as NSString).deletingPathExtension
            try? fm.removeItem(at: directory.appendingPathComponent("\(stem).png"))
            try? fm.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
