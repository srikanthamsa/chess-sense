import PhotosUI
import SwiftUI

/// One idea: a scoreboard. Dense, high-contrast, single accent, no decoration that is not
/// carrying information.
///
/// The language is borrowed from sports apps: a compressed heavy display face for the number
/// that matters, uppercase micro-labels with wide tracking, hairline dividers instead of
/// cards-in-cards, and exactly one saturated colour doing all the pointing.
struct ContentView: View {
    private let store = CalibrationStore()

    private enum PickIntent { case calibrate, analyse }

    // MARK: Colours

    private let ink = Color(red: 0.96, green: 0.97, blue: 0.98)
    private let mute = Color.white.opacity(0.55)
    private let accent = Color(red: 0.89, green: 0.12, blue: 0.19)
    private let surface = Color(red: 0.075, green: 0.078, blue: 0.086)
    private let hairline = Color.white.opacity(0.08)

    // MARK: State

    @State private var calibrationItem: PhotosPickerItem?
    @State private var analysisItem: PhotosPickerItem?

    @State private var busy = false
    @State private var tracking = false
    @State private var calibrationDate: Date?
    @State private var trackedFEN: String?

    @State private var headline = "READY"
    @State private var subline = "Screenshot a fresh game to calibrate."
    @State private var detail = ""
    @State private var lastMove: String?
    @State private var lastMoveUCI: String?
    @State private var lastEval: String?
    @State private var lastWhy: String?

    @State private var keyDraft = ""
    @State private var keySaved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    wordmark
                    scoreboard
                    statStrip
                    actions
                    positionSection
                    setupSection
                    if !detail.isEmpty { diagnostics }
                }
                .padding(.bottom, 40)
            }
            .background(Color(red: 0.043, green: 0.043, blue: 0.047).ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationBarHidden(true)
            .overlay {
                if busy {
                    ZStack {
                        Color.black.opacity(0.55).ignoresSafeArea()
                        ProgressView()
                            .controlSize(.large)
                            .tint(ink)
                    }
                }
            }
            .onAppear {
                refresh()
                applyDemoIfRequested()
            }
            .task {
                guard SelfTest.requested else { return }
                busy = true
                let report = await SelfTest.run()
                busy = false
                headline = report.passed ? "SELF TEST PASSED" : "SELF TEST FAILED"
                subline = report.passed ? "The whole pipeline ran on this device." : "See Details."
                detail = report.text
            }
            .onChange(of: calibrationItem) { _, item in
                guard let item else { return }
                Task { await handle(item, intent: .calibrate) }
            }
            .onChange(of: analysisItem) { _, item in
                guard let item else { return }
                Task { await handle(item, intent: .analyse) }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Wordmark

    private var wordmark: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("CHESS")
                .foregroundStyle(ink)
            + Text("SENSE")
                .foregroundStyle(accent)
            Spacer()
            Text(calibrationDate == nil ? "UNCALIBRATED" : "LIVE")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(calibrationDate == nil ? mute : accent)
        }
        .font(.system(size: 15, weight: .black).width(.compressed))
        .tracking(2.4)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    // MARK: - Scoreboard

    private var scoreboard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(headline)
                    .font(.system(size: 74, weight: .black).width(.compressed))
                    .tracking(-2)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.34)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.35), value: headline)
                if let lastEval {
                    evalChip(lastEval)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }

            Text(subline)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(mute)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            if let lastWhy, !lastWhy.isEmpty {
                Text(lastWhy)
                    .font(.system(size: 17, weight: .regular))
                    .lineSpacing(3)
                    .foregroundStyle(ink.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let fen = trackedFEN, fen.contains("/") {
                BoardThumbnail(fen: fen, highlight: highlightSquares)
                    // Full bleed inside the margins: the board is the one element worth the
                    // width, and a capped square left a dead gap down the right edge.
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.4), value: lastWhy)
        .animation(.snappy(duration: 0.4), value: trackedFEN)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
    }

    /// Squares of the last detected move, so the diagram marks what changed.
    private var highlightSquares: [Int] {
        guard let uci = lastMoveUCI, uci.count >= 4 else { return [] }
        func index(_ square: Substring) -> Int? {
            let characters = Array(square)
            guard characters.count == 2,
                  let file = characters[0].asciiValue.map({ Int($0) - 97 }),
                  let rank = characters[1].wholeNumberValue
            else { return nil }
            return (8 - rank) * 8 + file
        }
        let from = uci.prefix(2), to = uci.dropFirst(2).prefix(2)
        return [index(from), index(to)].compactMap { $0 }
    }

    /// The scorebox: three facts, evenly spaced, separated by hairlines. Empty values are an
    /// em dash rather than a blank, so the structure is visible before any analysis exists.
    private var statStrip: some View {
        HStack(spacing: 0) {
            stat("MOVE", lastMove ?? "—")
            Rectangle().fill(hairline).frame(width: 1, height: 34)
            stat("TURN", turnText)
            Rectangle().fill(hairline).frame(width: 1, height: 34)
            stat("ENGINE", engineText)
        }
        .padding(.vertical, 12)
        .background(
            Rectangle().fill(hairline).frame(height: 1),
            alignment: .top
        )
        .background(
            Rectangle().fill(hairline).frame(height: 1),
            alignment: .bottom
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8.5, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(mute)
            Text(value)
                .font(.system(size: 17, weight: .black).width(.compressed))
                .tracking(0.4)
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var turnText: String {
        guard let fen = trackedFEN,
              let field = fen.split(separator: " ").dropFirst().first
        else { return "—" }
        return field == "w" ? "WHITE" : "BLACK"
    }

    /// The engine that answered. On-device always, so it is a constant fact, not a status.
    private var engineText: String { "STOCKFISH 11" }

    private func evalChip(_ text: String) -> some View {
        let tint = advantageTint(text)
        return Text(text)
            .font(.system(size: 11, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $analysisItem, matching: .images) {
                Text("SCREENSHOT")
                    .font(.system(size: 12, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button {
                tracking.toggle()
                Task { await setTracking(tracking) }
            } label: {
                Text(tracking ? "STOP" : "ISLAND")
                    .font(.system(size: 12, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(tracking ? accent : ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(tracking ? accent : hairline, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 26)
    }

    // MARK: - Position

    private var positionSection: some View {
        section("POSITION") {
            HStack(alignment: .top, spacing: 12) {
                Text(trackedFEN ?? "No position tracked. Calibrate, then analyse a move.")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(trackedFEN == nil ? mute : ink.opacity(0.8))
                    .lineLimit(3)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                NavigationLink {
                    DesignStudioView()
                } label: {
                    Text("STUDIO")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(accent)
                }
            }
        }
    }

    // MARK: - Setup

    private var setupSection: some View {
        section("SETUP") {
            VStack(spacing: 0) {
                row {
                    HStack(spacing: 10) {
                        statusDot(on: calibrationDate != nil)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(calibrationDate == nil ? "Not calibrated" : "Calibrated")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ink)
                            Text(calibrationDate.map(Self.dateText) ?? "One start-position screenshot")
                                .font(.system(size: 11))
                                .foregroundStyle(mute)
                        }
                        Spacer()
                        PhotosPicker(selection: $calibrationItem, matching: .images) {
                            Text("PICK")
                                .font(.system(size: 11, weight: .black))
                                .tracking(1.2)
                                .foregroundStyle(ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(hairline, lineWidth: 1)
                                )
                        }
                        if calibrationDate != nil {
                            Button {
                                store.reset()
                                refresh()
                                headline = "READY"
                                subline = "Calibration cleared."
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(mute)
                            }
                        }
                    }
                }

                divider

                row {
                    HStack(spacing: 10) {
                        statusDot(on: keySaved)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(keySaved ? "DeepSeek connected" : "Coaching offline")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ink)
                            Text(keySaved ? "Warmer explanations" : "Uses the on-device line")
                                .font(.system(size: 11))
                                .foregroundStyle(mute)
                        }
                        Spacer()
                        if keySaved {
                            Button {
                                APIKeyStore.clear()
                                refresh()
                            } label: {
                                Text("REMOVE")
                                    .font(.system(size: 10, weight: .black))
                                    .tracking(1.1)
                                    .foregroundStyle(accent)
                            }
                        } else {
                            TextField("sk-…", text: $keyDraft)
                                .font(.system(size: 11, design: .monospaced))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .frame(width: 96)
                            Button {
                                APIKeyStore.save(keyDraft)
                                keyDraft = ""
                                refresh()
                            } label: {
                                Text("SAVE")
                                    .font(.system(size: 10, weight: .black))
                                    .tracking(1.1)
                                    .foregroundStyle(ink)
                            }
                        }
                    }
                }
            }
        }
    }

    private func statusDot(on: Bool) -> some View {
        Circle()
            .fill(on ? accent : Color.white.opacity(0.22))
            .frame(width: 6, height: 6)
    }

    // MARK: - Diagnostics

    private var diagnostics: some View {
        section("DIAGNOSTICS") {
            Text(detail)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(mute)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Chrome

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 9.5, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(mute)
            content()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.vertical, 11)
    }

    private var divider: some View {
        Rectangle().fill(hairline).frame(height: 1)
    }

    // MARK: - Actions

    /// -chesssense-demo YES fills the screen with a real analysis so the populated layout can
    /// be inspected without a calibrated device and a game.
    private func applyDemoIfRequested() {
        guard UserDefaults.standard.bool(forKey: "chesssense-demo") else { return }
        headline = "Nxe4"
        subline = "Your turn · black"
        lastMove = "Nxe4"
        lastMoveUCI = "f6e4"
        lastEval = "+3.37"
        lastWhy = "You take a knight with your knight. That puts it in the middle of the "
            + "board, where it controls the most squares."
        trackedFEN = "r3k2r/1p3ppp/p3pn2/8/P1pPN3/5NP1/1q3P1P/R2QR1K1 b kq - 1 4"
        detail = "read 363 · track 8 · engine 21 · total 392 ms\nwall 498 ms"
        tracking = true
    }

    private func refresh() {
        calibrationDate = store.calibrationDate
        trackedFEN = store.trackedFEN
        keySaved = APIKeyStore.isConfigured
        tracking = LiveActivityController.isRunning
    }

    private func setTracking(_ on: Bool) async {
        if on {
            do {
                _ = try LiveActivityController.start()
                headline = "ISLAND ON"
                subline = "Screenshot a move; the answer appears above the game."
            } catch {
                tracking = false
                headline = "ISLAND OFF"
                subline = "Live Activities are not available right now."
            }
        } else {
            await LiveActivityController.end()
            headline = "ISLAND OFF"
            subline = "Stopped."
        }
    }

    private func handle(_ item: PhotosPickerItem, intent: PickIntent) async {
        busy = true
        defer {
            busy = false
            calibrationItem = nil
            analysisItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                headline = "NO IMAGE"
                subline = "That screenshot could not be loaded. Pick it again."
                return
            }

            switch intent {
            case .calibrate:
                let read = try await AnalysisPipeline.calibrateOffMain(imageData: data)
                refresh()
                headline = "CALIBRATED"
                subline = "This board is recognised. Screenshot a move to get one."
                detail = [
                    "reading verified: worst shape distance \(read.worstShapeDistance) bits, "
                        + "colour margin \(String(format: "%.2f", read.minColorMargin))",
                    read.fen,
                ].joined(separator: "\n")

            case .analyse:
                guard store.isCalibrated else {
                    headline = "NOT CALIBRATED"
                    subline = "Pick a starting-position screenshot first, so I know this board."
                    return
                }
                let started = Date()
                let outcome = try await AnalysisPipeline.analyzeAndPublish(imageData: data)
                let wall = Int(Date().timeIntervalSince(started) * 1000)
                refresh()
                present(outcome)
                if !outcome.timings.isEmpty {
                    detail = [outcome.timings, "wall \(wall) ms"].joined(separator: "\n")
                }
            }
        } catch {
            headline = "COULDN'T READ"
            subline = Self.recovery(for: error)
            detail = "\(error)"
        }
    }

    private func present(_ outcome: AnalysisPipeline.Outcome) {
        lastMove = outcome.move?.displayMove
        lastMoveUCI = outcome.move?.uci
        lastEval = outcome.move.map { outcome.playerEval.isEmpty ? $0.evalText : outcome.playerEval }
        lastWhy = outcome.why.isEmpty ? nil : outcome.why

        if let move = outcome.move {
            headline = move.displayMove
            subline = outcome.trackingNote.isEmpty
                ? "Best move in this position."
                : outcome.trackingNote
        } else {
            headline = "NO MOVE"
            subline = outcome.failure ?? "The engine had nothing to say."
        }
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM · HH:mm"
        return formatter.string(from: date)
    }

    private static func recovery(for error: Error) -> String {
        switch error {
        case BoardError.notCalibrated:
            return "Pick a starting-position screenshot first."
        case BoardError.boardNotFound:
            return "No board in that image. Frame the whole board."
        case BoardError.verificationFailed:
            return "That is not a starting position. Use a fresh game."
        case let BoardError.unknownSquare(rank, file, _):
            return "Square \(file + 1)/\(8 - rank) was unreadable. Try another frame."
        default:
            return "\(error)"
        }
    }
}
