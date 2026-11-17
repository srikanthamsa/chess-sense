import CoreImage
import ReplayKit
import UIKit

/// Receives the screen stream while the user is broadcasting.
///
/// It does no chess work: ReplayKit extensions get ~50 MB and no ActivityKit, so the job here
/// is to publish a decimated stream of frames into the shared App Group container and let the
/// app do the reading, the engine query and the Island.
final class SampleHandler: RPBroadcastSampleHandler {
    private var frameCount = 0
    private var sequence = 0
    /// ~4 frames per second is plenty for a board that changes a few times a minute.
    private let decimation = 15

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        frameCount = 0
        sequence = 0
    }

    override func broadcastPaused() {}

    override func broadcastResumed() {}

    override func broadcastFinished() {
        // Mark the mailbox as no longer live so the app can notice quickly.
        let meta = AppGroup.Meta(sequence: sequence, capturedAt: 0, width: 0, height: 0,
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
        frameCount += 1
        guard frameCount % decimation == 0,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        sequence += 1
        FramePublisher.publish(buffer, sequence: sequence)
    }
}
