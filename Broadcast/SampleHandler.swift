import CoreImage
import ReplayKit
import UIKit

/// Receives the screen stream while the user is broadcasting.
///
/// It does no chess work: ReplayKit extensions get ~50 MB and no ActivityKit, so the job here
/// is to publish a decimated stream of frames into the shared App Group container and let the
/// app do the reading, the engine query and the Island.
final class SampleHandler: RPBroadcastSampleHandler {
    private var sequence = 0
    private var lastPublishedTime: TimeInterval = 0
    /// ~4 frames per second is plenty for a board that changes a few times a minute.
    private let minInterval: TimeInterval = 0.25

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        sequence = 0
        lastPublishedTime = 0
        let meta = AppGroup.Meta(sequence: 0, capturedAt: Date().timeIntervalSince1970, width: 0, height: 0,
                                 broadcasting: true)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: AppGroup.metaURL, options: .atomic)
        }
    }

    override func broadcastPaused() {}

    override func broadcastResumed() {}

    override func broadcastFinished() {
        // Mark the mailbox as no longer live so the app can notice quickly.
        let meta = AppGroup.Meta(sequence: sequence, capturedAt: Date().timeIntervalSince1970, width: 0, height: 0,
                                 broadcasting: false)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: AppGroup.metaURL, options: .atomic)
        }
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        guard sampleBufferType == .video else { return }
        let now = Date().timeIntervalSince1970
        // Throttle to ~4 fps, but always publish the very first frame immediately.
        if lastPublishedTime > 0 && (now - lastPublishedTime) < minInterval {
            return
        }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastPublishedTime = now
        sequence += 1
        FramePublisher.publish(buffer, sequence: sequence)
    }
}
