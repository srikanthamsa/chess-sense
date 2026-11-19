import CoreGraphics
import Foundation
import ImageIO

/// A decoded, tightly packed RGBA8 raster. Everything downstream works on this,
/// so the recognizer has no dependency on UIKit/SwiftUI.
public struct PixelImage: Sendable {
    public let width: Int
    public let height: Int
    /// `width * height * 4` bytes, R,G,B,A order.
    public let rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        precondition(rgba.count == width * height * 4, "rgba buffer size mismatch")
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    public init?(cgImage: CGImage) {
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue

        let ok: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(
                    data: base,
                    width: w,
                    height: h,
                    bitsPerComponent: 8,
                    bytesPerRow: w * 4,
                    space: space,
                    bitmapInfo: bitmapInfo
                  )
            else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }

        self.width = w
        self.height = h
        self.rgba = buffer
    }

    public init?(contentsOf url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { return nil }
        self.init(cgImage: cg)
    }

    public init?(data: Data) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { return nil }
        self.init(cgImage: cg)
    }

    @inline(__always)
    /// Nearest-neighbour downscale, used to simulate a broadcast frame arriving at a lower
    /// resolution than the screenshot the board rectangle was learned from.
    public func scaled(by factor: Double) -> PixelImage {
        let newWidth = max(1, Int(Double(width) * factor))
        let newHeight = max(1, Int(Double(height) * factor))
        var out = [UInt8](repeating: 255, count: newWidth * newHeight * 4)
        for y in 0..<newHeight {
            let sy = min(height - 1, Int(Double(y) / factor))
            for x in 0..<newWidth {
                let sx = min(width - 1, Int(Double(x) / factor))
                let src = offset(sx, sy)
                let dst = (y * newWidth + x) * 4
                out[dst] = rgba[src]
                out[dst + 1] = rgba[src + 1]
                out[dst + 2] = rgba[src + 2]
                out[dst + 3] = rgba[src + 3]
            }
        }
        return PixelImage(width: newWidth, height: newHeight, rgba: out)
    }

    /// Nearest-neighbour scale-down, used by tests to mimic the broadcast extension's
    /// half-resolution frames without a CoreGraphics dependency in the core module.
    public func downscaledForTest(by factor: Double) -> PixelImage? {
        guard factor > 0, factor < 1 else { return nil }
        let w = Int(Double(width) * factor)
        let h = Int(Double(height) * factor)
        guard w > 0, h > 0 else { return nil }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let sy = min(height - 1, Int(Double(y) / factor))
            for x in 0..<w {
                let sx = min(width - 1, Int(Double(x) / factor))
                let src = offset(sx, sy)
                let dst = (y * w + x) * 4
                out[dst] = rgba[src]
                out[dst + 1] = rgba[src + 1]
                out[dst + 2] = rgba[src + 2]
                out[dst + 3] = rgba[src + 3]
            }
        }
        return PixelImage(width: w, height: h, rgba: out)
    }

    public func offset(_ x: Int, _ y: Int) -> Int {
        // Clamped on purpose. Callers work inside a validated rectangle, but a stale
        // rectangle against a smaller image (a broadcast frame at half resolution) used to
        // index past the buffer and take the whole app down. A repeated edge pixel is a
        // wrong answer; a crash is not an answer.
        let cx = min(max(0, x), max(0, width - 1))
        let cy = min(max(0, y), max(0, height - 1))
        return (cy * width + cx) * 4
    }

    /// PNG encoding, so a failing frame can be captured on device and reproduced offline.
    public func pngData() -> Data? {
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        )
        guard let cg = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: info,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, "public.png" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    @inline(__always)
    public func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let o = offset(x, y)
        return (Int(rgba[o]), Int(rgba[o + 1]), Int(rgba[o + 2]))
    }
}

/// A plain RGB triple. A struct rather than a tuple so it can be Equatable,
/// Hashable and printable — board colours are compared in the API and in tests.
public struct RGB: Sendable, Hashable, CustomStringConvertible {
    public var r: Int
    public var g: Int
    public var b: Int

    public init(_ r: Int, _ g: Int, _ b: Int) {
        self.r = r
        self.g = g
        self.b = b
    }

    public var luminance: Double { luma(r, g, b) }

    public var description: String { "RGB(\(r), \(g), \(b))" }
}

@inline(__always)
func luma(_ c: RGB) -> Double { luma(c.r, c.g, c.b) }

@inline(__always)
func rgbDistance(_ a: RGB, _ b: RGB) -> Double {
    rgbDistance((a.r, a.g, a.b), (b.r, b.g, b.b))
}

@inline(__always)
func luma(_ r: Int, _ g: Int, _ b: Int) -> Double {
    (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)) / 255.0
}

/// Euclidean RGB distance, 0...441.7
@inline(__always)
func rgbDistance(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Double {
    let dr = Double(a.0 - b.0)
    let dg = Double(a.1 - b.1)
    let db = Double(a.2 - b.2)
    return (dr * dr + dg * dg + db * db).squareRoot()
}
