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
    public func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }

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
