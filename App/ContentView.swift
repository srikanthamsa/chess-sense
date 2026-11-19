import PhotosUI
import SwiftUI

/// SNSE — an app, not a page.
///
/// Everything that was page furniture (numbered anchors, taglines, footer badges, an FAQ) is
/// gone or moved into a settings sheet. What remains is the three things an app has: a brand
/// statement, the current answer, and the board it came from — with the actions pinned where a
/// thumb can reach them.
struct ContentView: View {
    private let store = CalibrationStore()

    private enum PickIntent { case calibrate, analyse }

    // MARK: Palette

    private let canvas = Color(red: 0.02, green: 0.02, blue: 0.02)
    private let panel = Color(red: 0.035, green: 0.035, blue: 0.04)
    private let hairline = Color(red: 0.10, green: 0.10, blue: 0.11)
    private let ink = Color(red: 0.957, green: 0.957, blue: 0.949)
    private let mute = Color(red: 0.467, green: 0.455, blue: 0.467)
    private let magenta = Color(red: 0.886, green: 0.102, blue: 0.635)

    private let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"

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

    @State private var showSettings = false

    // MARK: Body

    var body: some View {
        ZStack(alignment: .top) {
            canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    brand
                    answerCard
                    boardSection
                    if !detail.isEmpty { detailLine }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .overlay(alignment: .topTrailing) { settingsButton }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(store: store, tracking: $tracking, onRefresh: refresh)
        }
        .onAppear(perform: refresh)
        .onAppear(perform: applyDemoIfRequested)
        .task {
            guard SelfTest.requested else { return }
            busy = true
            let report = await SelfTest.run()
            busy = false
            headline = report.passed ? "SELF TEST PASSED" : "SELF TEST FAILED"
            subline = report.passed ? "The whole pipeline ran on this device." : "See settings."
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

    // MARK: - Brand

    private var brand: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("SN").foregroundStyle(ink)
                Text("SE").foregroundStyle(magenta)
            }
            .font(.system(size: 76, weight: .black).width(.compressed))
            .tracking(-2.5)
            .lineLimit(1)
            .minimumScaleFactor(0.5)

            HStack(spacing: 8) {
                Circle()
                    .fill(tracking ? magenta : mute)
                    .frame(width: 5, height: 5)
                Text(statusLabel)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(tracking ? magenta : mute)
                Spacer()
                Text("STOCKFISH 11 · d12")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(mute)
            }
            .padding(.top, 6)
        }
        .padding(.top, 8)
    }

    private var statusLabel: String {
        if store.isCalibrated { return tracking ? "LIVE" : "CALIBRATED" }
        return "UNCALIBRATED"
    }

    // MARK: - Answer

    private var answerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text(headline)
                    .font(.system(size: 54, weight: .black).width(.compressed))
                    .tracking(-1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .foregroundStyle(lastMove == nil ? ink.opacity(0.9) : ink)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.35), value: headline)

                if let eval = lastEval, lastMove != nil {
                    Text(eval)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(eval.hasPrefix("-") ? Color(red: 0.97, green: 0.44, blue: 0.44)
                                                             : Color(red: 0.36, green: 0.85, blue: 0.58))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.06)))
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }

            Text(lastWhy ?? subline)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(ink.opacity(lastWhy == nil ? 0.55 : 0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .intelligenceOverlay(
            in: RoundedRectangle(cornerRadius: 22, style: .continuous),
            lineWidths: lastMove == nil ? [1.5, 3, 5] : [1.5, 4, 7],
            blurs: [0, 2, 7],
            updateInterval: 0.6
        )
        .padding(.top, 22)
    }

    // MARK: - Board

    private var boardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("POSITION")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(mute)
                Spacer()
                if let fen = trackedFEN, fen.contains("/") {
                    Text(fen)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(mute.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 200, alignment: .trailing)
                }
            }

            LiveBoard(
                fen: trackedFEN ?? startFEN,
                highlight: highlightSquares,
                isPlaceholder: trackedFEN == nil
            )
            .frame(width: boardSide, height: boardSide)
        }
        .padding(.top, 26)
    }

    private var boardSide: CGFloat {
        // The board *plus* the footer line, so the square stays square.
        UIScreen.main.bounds.width - 40
    }

    private var detailLine: some View {
        Text(detail)
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(mute.opacity(0.85))
            .padding(.top, 16)
            .textSelection(.enabled)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(hairline).frame(height: 1)
            HStack(spacing: 10) {
                PhotosPicker(selection: $analysisItem, matching: .images) {
                    HStack(spacing: 8) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 13, weight: .semibold))
                        Text("SCREENSHOT")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.4)
                    }
                    .foregroundStyle(canvas)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(ink))
                }
                .buttonStyle(.plain)

                Button {
                    Task { await setTracking(!tracking) }
                } label: {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(tracking ? magenta : ink.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Text(tracking ? "LIVE" : "GO LIVE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.4)
                    }
                    .foregroundStyle(ink)
                    .frame(width: 128)
                    .padding(.vertical, 15)
                    .overlay(Capsule().strokeBorder(hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
        }
        .overlay(alignment: .top) {
            if busy {
                Rectangle().fill(magenta).frame(height: 2)
            }
        }
        .animation(.easeOut(duration: 0.2), value: busy)
    }

    // MARK: - Settings

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ink.opacity(0.75))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.05), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.top, 6)
    }

    // MARK: - Derived

    private var highlightSquares: [Int] {
        guard let uci = lastMoveUCI, uci.count >= 4 else { return [] }
        func index(_ square: Substring) -> Int? {
            guard square.count == 2,
                  let file = square.first.map({ Int($0.asciiValue ?? 0) - 97 }),
                  let rank = Int(String(square.last ?? "1"))
            else { return nil }
            return (8 - rank) * 8 + file
        }
        let parts = Array(uci)
        return [index(Substring(String(parts[0...1]))), index(Substring(String(parts[2...3])))]
            .compactMap { $0 }
    }

    // MARK: - Behaviour

    private func applyDemoIfRequested() {
        guard UserDefaults.standard.bool(forKey: "snse-demo") else { return }
        headline = "Nxe4"
        lastMove = "Nxe4"
        lastMoveUCI = "f6e4"
        lastEval = "+3.37"
        lastWhy = "You take a knight with your knight. That puts it in the middle of the "
            + "board, where it controls the most squares."
        trackedFEN = "r3k2r/1p3ppp/p3pn2/8/P1pPN3/5NP1/1q3P1P/R2QR1K1 b kq - 1 4"
        detail = "read 363 · track 8 · engine 21 · total 392 ms"
        tracking = true
    }

    private func refresh() {
        calibrationDate = store.calibrationDate
        trackedFEN = store.trackedFEN
        tracking = LiveActivityController.isRunning
    }

    private func setTracking(_ on: Bool) async {
        if on {
            do {
                _ = try LiveActivityController.start()
                headline = "ISLAND ON"
                subline = "Screenshot a move; the answer appears above the game."
                tracking = true
            } catch {
                tracking = false
                headline = "ISLAND OFF"
                subline = "Live Activities are not available right now."
            }
        } else {
            await LiveActivityController.end()
            headline = "ISLAND OFF"
            subline = "Stopped."
            tracking = false
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
                detail = "verified · worst shape distance \(read.worstShapeDistance) · "
                    + "colour margin \(String(format: "%.2f", read.minColorMargin))"

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
                    detail = [outcome.timings, "wall \(wall) ms"].joined(separator: " · ")
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
            subline = outcome.trackingNote.isEmpty ? "Best move in this position."
                                                   : outcome.trackingNote
        } else {
            headline = "NO MOVE"
            subline = outcome.failure ?? "The engine had nothing to say."
        }
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM · HH:mm"
        return formatter.string(from: date)
    }

    static func recovery(for error: Error) -> String {
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
