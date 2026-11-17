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
        guard let jpeg = FramePublisher.jpeg(from: buffer, quality: 0.5) else { return }
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

    /// Native scale. Half scale was tried first to save bytes, but a 55 px square after
    /// downscale plus JPEG artefacts pushes the piece signature close to its tolerance;
    /// fidelity of the thing being measured matters more than payload size.
    private static let scale: CGFloat = 1.0

    private static func jpeg(from buffer: CVPixelBuffer, quality: CGFloat) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let scaled = scale == 1.0
            ? ciImage
            : ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: quality)
    }
}
