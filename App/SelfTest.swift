import Foundation

/// In-app end-to-end check, runnable without a single tap.
///
/// Launch with `-chesssense-selftest` (Xcode scheme argument, or
/// `simctl launch --console <udid> <bundle-id> -chesssense-selftest`) and the app reads the
/// bundled TakeTakeTake screenshot, calibrates, analyses it against the live engine, tries
/// the Live Activity, prints a report to stdout and shows it on screen.
///
/// This exercises the real binary on real iOS — the reader, the rules, the network engine
/// and ActivityKit — which unit tests on macOS cannot. It uses its own UserDefaults suite
/// so it never disturbs a real calibration.
enum SelfTest {
    static let argument = "-chesssense-selftest"

    static var requested: Bool {
        CommandLine.arguments.contains(argument)
    }

    struct Report {
        let text: String
        let passed: Bool
    }

    static func run() async -> Report {
        var lines: [String] = []
        var passed = true

        func check(_ name: String, _ body: () async throws -> String) async {
            do {
                let result = try await body()
                lines.append("PASS  \(name): \(result)")
            } catch {
                passed = false
                lines.append("FAIL  \(name): \(error)")
            }
        }

        let defaults = UserDefaults(suiteName: "chesssense.selftest") ?? .standard
        defaults.removePersistentDomain(forName: "chesssense.selftest")
        let store = CalibrationStore(defaults: defaults)

        await check("bundle fixture") {
            guard let url = Bundle.main.url(
                forResource: "taketaketake-start", withExtension: "png"
            ) else { throw BoardError.unreadableImage }
            let size = (try? FileManager.default
                .attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            return "\(url.lastPathComponent), \(size ?? 0) bytes"
        }

        guard let url = Bundle.main.url(forResource: "taketaketake-start", withExtension: "png"),
              let data = try? Data(contentsOf: url)
        else {
            let text = (lines + ["FATAL fixture missing"]).joined(separator: "\n")
            return Report(text: text, passed: false)
        }

        await check("calibrate (13 templates, self-verifying)") {
            let read = try AnalysisPipeline.calibrate(imageData: data, store: store)
            guard read.fen.hasPrefix("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR") else {
                throw BoardError.verificationFailed(
                    expected: "start position", got: String(read.fen.prefix(56))
                )
            }
            return String(
                format: "worst shape %d, colour margin %.2f, trusted %@",
                read.worstShapeDistance,
                read.minColorMargin,
                read.isTrustworthy ? "yes" : "no"
            )
        }

        await check("tracker bootstrap") {
            let book = store.loadBook()
            let rect = store.loadRect()
            guard book != nil, rect != nil else { throw BoardError.notCalibrated }
            return "book + rect persisted (\(rect.map { "\($0.width)x\($0.height)" } ?? "?"))"
        }

        await check("analyse + live engine + SAN") {
            let outcome = try await AnalysisPipeline.analyze(imageData: data, store: store)
            if let failure = outcome.failure, outcome.move == nil {
                throw BoardError.verificationFailed(expected: "a move", got: failure)
            }
            guard let move = outcome.move else {
                throw BoardError.verificationFailed(expected: "a move", got: "none")
            }
            return "\(move.displayMove) \(move.evalText) · \(move.provenance) · "
                + "pv \(move.principalVariation) · \(outcome.trackingNote)"
        }

        await check("tracked position advanced") {
            guard let fen = store.trackedFEN, ChessPosition(fen: fen) != nil else {
                throw BoardError.verificationFailed(expected: "valid FEN", got: "none")
            }
            return fen
        }

        var liveActivity = "not attempted"
        do {
            try LiveActivityController.start()
            await LiveActivityController.update(
                EngineMove(uci: "g1f3", san: "Nf3", principalVariation: "g1f3",
                           evalText: "+0.25", provenance: "selftest"),
                why: "Your knight comes out towards the middle.",
                trusted: true
            )
            liveActivity = LiveActivityController.isRunning
                ? "started and updated"
                : "request did not produce an activity (expected on simulator)"
        } catch {
            liveActivity = "unavailable: \(error)"
        }
        lines.append("INFO  live activity: \(liveActivity)")

        let text = lines.joined(separator: "\n")
        print("---- SELFTEST BEGIN ----")
        for line in lines { print("SELFTEST \(line)") }
        print("SELFTEST RESULT \(passed ? "PASSED" : "FAILED")")
        print("---- SELFTEST END ----")

        // Also written to Documents: `simctl launch --console` needs a pty, which is not
        // available in every environment, and a file survives the app being relaunched.
        let dump = (["SELFTEST RESULT \(passed ? "PASSED" : "FAILED")"] + lines.map { "SELFTEST \($0)" })
            .joined(separator: "\n")
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? dump.write(to: dir.appendingPathComponent("selftest-report.txt"),
                            atomically: true, encoding: .utf8)
        }
        return Report(text: text, passed: passed)
    }
}
