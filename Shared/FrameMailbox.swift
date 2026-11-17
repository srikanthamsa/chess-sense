import Foundation
import UIKit

/// Reads what the broadcast extension last wrote. Owned by the app.
public struct FrameMailbox {
    public init() {}
    /// Latest frame, or nil when the extension has not published one.
    public func latest() -> (image: Data, meta: AppGroup.Meta)? {
        guard let metaData = try? Data(contentsOf: AppGroup.metaURL),
              let meta = try? JSONDecoder().decode(AppGroup.Meta.self, from: metaData),
              meta.broadcasting,
              let image = try? Data(contentsOf: AppGroup.frameURL),
              !image.isEmpty
        else { return nil }
        return (image, meta)
    }

    /// True when the extension is currently actively broadcasting.
    public var isBroadcasting: Bool {
        guard let metaData = try? Data(contentsOf: AppGroup.metaURL),
              let meta = try? JSONDecoder().decode(AppGroup.Meta.self, from: metaData)
        else { return false }
        return meta.broadcasting && (Date().timeIntervalSince1970 - meta.capturedAt < 60)
    }

    /// True when the extension has stopped publishing (user stopped the broadcast).
    public var isStale: Bool {
        guard let metaData = try? Data(contentsOf: AppGroup.metaURL),
              let meta = try? JSONDecoder().decode(AppGroup.Meta.self, from: metaData)
        else { return true }
        if !meta.broadcasting { return true }
        return Date().timeIntervalSince1970 - meta.capturedAt > 300
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: AppGroup.frameURL)
        try? FileManager.default.removeItem(at: AppGroup.metaURL)
    }
}

/// Writes frames from inside the broadcast extension.
public enum FramePublisher {
    public static func publish(_ buffer: CVPixelBuffer, sequence: Int) {
        guard let jpeg = FramePublisher.jpeg(from: buffer, quality: 0.6) else { return }
        let meta = AppGroup.Meta(
            sequence: sequence,
            capturedAt: Date().timeIntervalSince1970,
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            broadcasting: true
        )
        // Write the image first, then the manifest: a reader that sees a matching sequence
        // always finds complete bytes, never a half-written JPEG.
        try? jpeg.write(to: AppGroup.frameURL, options: .atomic)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: AppGroup.metaURL, options: .atomic)
        }
    }

    private static func jpeg(from buffer: CVPixelBuffer, quality: CGFloat) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        // The board is drawn at full resolution; half scale keeps the signature channel
        // stable (it is a proportion, not a pixel count) while cutting the payload ~4x.
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: quality)
    }
}
