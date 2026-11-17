import AVFoundation
import Foundation
import SwiftUI

/// Continuous mode: the broadcast extension publishes frames, this polls them and only
/// analyses what actually changed.
///
/// The app has to be running to do this — the extension cannot touch ActivityKit, so the
/// Island belongs to the app. A silent audio session keeps the app alive in the background,
/// which is the same mechanism a music player uses. It is honest to say what that is: a
/// keep-alive, not a supported way to run a background camera, so it is offered as a toggle
/// rather than being on by default.
@MainActor
final class ContinuousMode: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var isBroadcasting = false
    @Published private(set) var status = "Not running"
    @Published private(set) var analyses = 0
    @Published private(set) var lastMove: String?
    /// Why the broadcast sheet could not open, if it could not.
    @Published var broadcastNote: String?
    /// Step-by-step trace of the last attempt, newest last.
    @Published var broadcastLog: [String] = []
    @Published private(set) var taps = 0
    @Published private(set) var frames = 0
    @Published private(set) var lastAttempt: Date?
    /// What this build actually embeds, shown so a missing extension is obvious.
    var embedded: String { BroadcastInfo.diagnostics }

    /// Always visible: which build is running, how many taps landed, what is embedded.
    /// Without this the only evidence was a blank card, which hid the difference between
    /// "not the build you think" and "the tap never arrived".
    var buildLine: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let live = mailbox.isBroadcasting ? "live" : "idle"
        return "build \(version)(\(build)) · frames \(frames) · taps \(taps) · \(live)"
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var timer: Timer?
    private var keepAlive: AVAudioPlayer?
    private var lastSequence = -1
    private var lastAnalysedFEN: String?
    private var inFlight = false

    private let mailbox = FrameMailbox()
    private let store = CalibrationStore()

    /// Polling faster than this wastes CPU; slower feels laggy after a move.
    private let interval: TimeInterval = 0.5
    /// The board has to settle before it is worth an engine query.
    private let settleTime: TimeInterval = 0.45
    private var pendingSince: Date?

    func presentBroadcastSheet() {
        taps += 1
        lastAttempt = Date()
        start()
    }

    func toggle() {
        if active {
            stop()
        } else {
            presentBroadcastSheet()
        }
    }

    func start() {
        guard !active else { return }
        FrameMailbox.clear()
        lastSequence = -1
        lastAnalysedFEN = nil
        analyses = 0
        isBroadcasting = false
        startKeepAlive()
        active = true
        status = "Waiting for broadcast — tap icon above"
        if !LiveActivityController.isRunning {
            _ = try? LiveActivityController.start()
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        keepAlive?.stop()
        keepAlive = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        active = false
        isBroadcasting = false
        status = "Stopped"
        FrameMailbox.clear()
    }

    // MARK: - Polling

    /// Engages by itself as soon as the extension starts publishing.
    ///
    /// Requiring a toggle after starting a broadcast made a working pipeline look dead: the
    /// frames were there, nothing consumed them. Watching now begins on its own.
    func autoEngage() async {
        guard !active, mailbox.isBroadcasting, mailbox.latest() != nil else { return }
        start()
    }

    private func tick() async {
        guard active, !inFlight else { return }

        let broadcastingNow = mailbox.isBroadcasting
        if isBroadcasting != broadcastingNow {
            isBroadcasting = broadcastingNow
        }

        if !broadcastingNow && lastSequence >= 0 {
            status = "Broadcast ended"
            return
        }

        guard let frame = mailbox.latest() else {
            if lastSequence < 0 {
                status = broadcastingNow
                    ? "Broadcasting · Waiting for board"
                    : "Waiting for broadcast — tap icon above"
            }
            return
        }
        guard frame.meta.sequence != lastSequence else { return }
        lastSequence = frame.meta.sequence
        frames += 1

        // Wait for the board to stop moving: consecutive frames differ while an animation
        // runs, and analysing those yields rejected reads.
        if pendingSince == nil {
            pendingSince = Date()
            status = "Board changed"
            return
        }
        guard let since = pendingSince, Date().timeIntervalSince(since) >= settleTime else { return }
        pendingSince = nil

        inFlight = true
        defer { inFlight = false }
        do {
            let outcome = try await AnalysisPipeline.analyzeAndPublish(imageData: frame.image)
            analyses += 1
            if let move = outcome.move {
                lastMove = move.displayMove
                status = "Watching · \(move.displayMove)"
            } else if let failure = outcome.failure {
                status = "Watching · \(failure)"
            } else {
                status = "Watching"
            }
            lastAnalysedFEN = outcome.fen
        } catch {
            status = "Read failed · \(error)"
        }
    }

    // MARK: - Keep alive

    /// A one second silent, looping WAV. The audio session is what keeps the process
    /// scheduled; nothing is audible.
    private func startKeepAlive() {
        Task.detached(priority: .utility) {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true)
            guard let url = SilentAudio.writeIfNeeded() else { return }
            let player = try? AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.volume = 0
            player?.play()
            await MainActor.run { [weak self] in
                self?.keepAlive = player
            }
        }
    }
}

enum SilentAudio {
    /// Builds a valid 1-second silent mono WAV once, in the caches directory.
    static func writeIfNeeded() -> URL? {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("silence.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let sampleRate = 8_000
        let samples = sampleRate
        var data = Data()
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8))
        append32(UInt32(36 + samples * 2))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append32(16)
        append16(1)                        // PCM
        append16(1)                        // mono
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))   // byte rate
        append16(2)                        // block align
        append16(16)                       // bits
        data.append(contentsOf: Array("data".utf8))
        append32(UInt32(samples * 2))
        data.append(Data(repeating: 0, count: samples * 2))

        do { try data.write(to: url); return url } catch { return nil }
    }
}
