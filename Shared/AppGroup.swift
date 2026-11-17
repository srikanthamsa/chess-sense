import Foundation

/// The shared mailbox between the broadcast extension and the app.
///
/// ReplayKit runs the extension in its own process with its own container, so an App Group is
/// the only channel between it and the app that owns the Live Activity. The extension uploads
/// frames; the app polls them, analyses only what changed, and pushes the Island.
public enum AppGroup {
    public static let identifier = "group.ai.chesssense.app"

    /// Falls back to the app's own caches directory so simulator runs without the
    /// entitlement still work end to end.
    public static var container: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        let fallback = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mailbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    public static var frameURL: URL { container.appendingPathComponent("latest.jpg") }
    public static var metaURL: URL { container.appendingPathComponent("latest.json") }

    public struct Meta: Codable, Sendable {
        public var sequence: Int
        public var capturedAt: TimeInterval
        public var width: Int
        public var height: Int
        public var broadcasting: Bool

        public init(sequence: Int, capturedAt: TimeInterval, width: Int, height: Int,
                    broadcasting: Bool) {
            self.sequence = sequence
            self.capturedAt = capturedAt
            self.width = width
            self.height = height
            self.broadcasting = broadcasting
        }
    }
}
