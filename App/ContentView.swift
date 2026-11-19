import PhotosUI
import SwiftUI

/// SNSE — an editorial, technical page rather than a dashboard.
///
/// Near-black canvas, one magenta doing all the pointing, hairlines instead of boxes, and
/// hierarchy built from scale and long vertical intervals. Labels are monospaced and tracked;
/// the move is a single oversized word, because it is the only thing anyone opens this for.
struct ContentView: View {
    private let store = CalibrationStore()

    private enum PickIntent { case calibrate, analyse }

    // MARK: Palette

    private let canvas = Color(red: 0.02, green: 0.02, blue: 0.02)      // #050505
    private let panel = Color(red: 0.031, green: 0.031, blue: 0.035)    // #080809
    private let hairline = Color(red: 0.10, green: 0.10, blue: 0.11)    // #1A1A1D
    private let ink = Color(red: 0.957, green: 0.957, blue: 0.949)      // #F4F4F2
    private let mute = Color(red: 0.467, green: 0.455, blue: 0.467)     // #777477
    private let magenta = Color(red: 0.886, green: 0.102, blue: 0.635)  // #E21AA2

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
    @State private var lastTimings = ""

    @State private var keyDraft = ""
    @State private var keySaved = false
    @State private var openNote: Int?

    // MARK: Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    utilityHeader(proxy)
                    taglineStrip
                    hero
                    statusRow
                    positionSection.id("01")
                    analysisSection.id("02")
                    setupSection.id("03")
                    notesSection
                    footer
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 56)
            }
            .background(canvas.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .overlay(alignment: .top) {
                if busy {
                    Rectangle()
                        .fill(magenta)
                        .frame(height: 2)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: busy)
            .onAppear(perform: refresh)
            .task {
                guard SelfTest.requested else { return }
                busy = true
                let report = await SelfTest.run()
                busy = false
                headline = report.passed ? "SELF TEST PASSED" : "SELF TEST FAILED"
                subline = report.passed ? "The whole pipeline ran on this device." : "See notes."
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
            .onAppear(perform: applyDemoIfRequested)
        }
    }

    // MARK: - 1 · Utility header

    private func utilityHeader(_ proxy: ScrollViewProxy) -> some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 0) {
                Text("SN").foregroundStyle(ink)
                Text("SE").foregroundStyle(magenta)
            }
            .font(.system(size: 17, weight: .black))
            .tracking(1.2)

            Spacer(minLength: 8)

            HStack(spacing: 14) {
                ForEach([("01", "01"), ("02", "02"), ("03", "03")], id: \.0) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            proxy.scrollTo(item.1, anchor: .top)
                        }
                    } label: {
                        Text(item.0)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(mute)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

            NavigationLink {
                EngineProbeView()
            } label: {
                Text("ENGINE")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .overlay(Capsule().strokeBorder(hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                Task { await setTracking(!tracking) }
            } label: {
                Text(tracking ? "LIVE" : "GO LIVE")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(canvas)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(ink))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    // MARK: - 2 · Micro-tagline strip

    private var taglineStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(hairline).frame(height: 1)
            Text("ON-DEVICE STOCKFISH  ·  NO NETWORK  ·  PIXEL READ")
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(magenta)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 9)
                .padding(.bottom, 9)
        }
    }

    // MARK: - 3 · Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(headline)
                .font(.system(size: heroSize, weight: .black).width(.compressed))
                .tracking(-1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(ink)
                .padding(.top, 26)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.35), value: headline)

            Text(subline)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(ink.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
                .frame(maxWidth: 420, alignment: .leading)

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    PhotosPicker(selection: $analysisItem, matching: .images) {
                        Text("SCREENSHOT  →")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(canvas)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(ink))
                    }
                    .buttonStyle(.plain)

                    PhotosPicker(selection: $calibrationItem, matching: .images) {
                        Text("CALIBRATE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(ink)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .overlay(Capsule().strokeBorder(hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 10) {
                    featureRow("01", "PIXELS", "board found and read")
                    featureRow("02", "SEARCH", "stockfish, in-process")
                    featureRow("03", "ISLAND", "answer above the game")
                }
                .frame(maxWidth: 190, alignment: .trailing)
            }
            .padding(.top, 26)
        }
    }

    private var heroSize: CGFloat {
        headline.count <= 4 ? 86 : headline.count <= 6 ? 64 : 44
    }

    private func featureRow(_ index: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(index)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(magenta)
            VStack(alignment: .trailing, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(ink)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(mute)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - 4 · Status row

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(hairline).frame(height: 1)
            HStack {
                HStack(spacing: 7) {
                    Circle()
                        .fill(tracking ? magenta : mute)
                        .frame(width: 5, height: 5)
                    Text(statusLabel)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(magenta)
                }
                Spacer()
                Text("SNSE · STOCKFISH 11 · d12")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(mute)
            }
            .padding(.vertical, 12)
        }
    }

    private var boardSide: CGFloat {
        UIScreen.main.bounds.width - 44
    }

    private var statusLabel: String {
        if !lastTimings.isEmpty { return "ANALYSIS · " + lastTimings }
        if store.isCalibrated { return "CALIBRATED · READY" }
        return "UNCALIBRATED"
    }

    // MARK: - 5 · 01 Position

    private var positionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("01", "POSITION")
            Text("The board, as the app read it.")
                .font(.system(size: 34, weight: .semibold))
                .tracking(-1)
                .foregroundStyle(ink)
                .padding(.top, 10)
                .padding(.bottom, 18)

            if let fen = trackedFEN, fen.contains("/") {
                // An explicit square. `.frame(maxWidth: .infinity)` around the thumbnail's
                // GeometryReader left the scroll view with an unbounded height to solve, and
                // the window rendered black with the app still running.
                BoardThumbnail(fen: fen, highlight: highlightSquares)
                    .frame(width: boardSide, height: boardSide)
                    .transition(.opacity)
                Text(fen)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(mute)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .padding(.top, 12)
            } else {
                HStack {
                    Text("NO POSITION YET")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(mute)
                    Spacer()
                    Text("CALIBRATE, THEN SCREENSHOT")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(mute.opacity(0.7))
                }
                .padding(.vertical, 30)
                .overlay(alignment: .top) { Rectangle().fill(hairline).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(hairline).frame(height: 1) }
            }
        }
        .padding(.top, 84)
    }

    // MARK: - 6 · 02 Analysis

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("02", "MOVE")
            Text("What Stockfish would play, and why.")
                .font(.system(size: 34, weight: .semibold))
                .tracking(-1)
                .foregroundStyle(ink)
                .padding(.top, 10)
                .padding(.bottom, 22)

            VStack(spacing: 0) {
                analysisRow("MOVE", lastMove ?? "—")
                analysisRow("EVAL", lastEval ?? "—", emphasis: true)
                analysisRow("TURN", turnText)
                analysisRow("ENGINE", "STOCKFISH 11")
            }

            if let why = lastWhy, !why.isEmpty {
                Text(why)
                    .font(.system(size: 17, weight: .regular))
                    .lineSpacing(4)
                    .foregroundStyle(ink.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
            }

            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(mute)
                    .padding(.top, 18)
                    .textSelection(.enabled)
            }
        }
        .padding(.top, 84)
    }

    private func analysisRow(_ label: String, _ value: String, emphasis: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(mute)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(emphasis ? magenta : ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Rectangle().fill(hairline).frame(height: 1) }
    }

    // MARK: - 7 · 03 Setup

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("03", "SETUP")
            Text("Two things to be useful.")
                .font(.system(size: 34, weight: .semibold))
                .tracking(-1)
                .foregroundStyle(ink)
                .padding(.top, 10)
                .padding(.bottom, 22)

            setupRow(
                title: calibrationDate == nil ? "Not calibrated" : "Calibrated",
                detail: calibrationDate.map { "One frame, " + Self.dateText($0) }
                    ?? "One start-position screenshot",
                trailing: AnyView(
                    HStack(spacing: 12) {
                        PhotosPicker(selection: $calibrationItem, matching: .images) {
                            Text("PICK")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1.4)
                                .foregroundStyle(ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .overlay(Capsule().strokeBorder(hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        if calibrationDate != nil {
                            Button {
                                store.reset()
                                refresh()
                            } label: {
                                Text("RESET")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(1.4)
                                    .foregroundStyle(magenta)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                ),
                live: calibrationDate != nil
            )

            setupRow(
                title: keySaved ? "Coaching connected" : "Coaching offline",
                detail: keySaved ? "Warmer wording from your key" : "On-device wording only",
                trailing: AnyView(
                    HStack(spacing: 10) {
                        if keySaved {
                            Button {
                                APIKeyStore.clear()
                                refresh()
                            } label: {
                                Text("REMOVE")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(1.4)
                                    .foregroundStyle(magenta)
                            }
                            .buttonStyle(.plain)
                        } else {
                            TextField("sk-…", text: $keyDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(ink)
                                .frame(width: 108)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(hairline, lineWidth: 1)
                                )
                            Button {
                                _ = APIKeyStore.save(keyDraft)
                                keyDraft = ""
                                refresh()
                            } label: {
                                Text("SAVE")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(1.4)
                                    .foregroundStyle(canvas)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(ink))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                ),
                live: keySaved
            )

            HStack {
                NavigationLink {
                    DesignStudioView()
                } label: {
                    Text("DESIGN STUDIO  →")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(ink)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("ISLAND, LOCK SCREEN, PREVIEWS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(mute)
            }
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) { Rectangle().fill(hairline).frame(height: 1) }
        }
        .padding(.top, 84)
    }

    private func setupRow(
        title: String,
        detail: String,
        trailing: AnyView,
        live: Bool
    ) -> some View {
        HStack(alignment: .center) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(live ? magenta : hairline)
                    .frame(width: 5, height: 5)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ink)
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(mute)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(hairline).frame(height: 1) }
    }

    // MARK: - 8 · Notes

    private var notes: [(String, String)] {
        [
            ("How is the board read?",
             "It looks for a rectangle of alternating squares, learns the pieces from one "
                + "calibration frame, then matches each square. Anything ambiguous is refused "
                + "rather than guessed."),
            ("Does it need a network?",
             "No. Stockfish is compiled into the app and runs in-process, so the answer never "
                + "waits on a server. The optional coaching key is the only outbound call."),
            ("Will it read other chess apps?",
             "The recogniser learns a theme, but the board finder currently expects "
                + "TakeTakeTake's layout. Another app needs its own one-time calibration."),
        ]
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("04", "NOTES")
            VStack(spacing: 0) {
                ForEach(Array(notes.enumerated()), id: \.offset) { index, note in
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.snappy(duration: 0.28)) {
                                openNote = openNote == index ? nil : index
                            }
                        } label: {
                            HStack(alignment: .center) {
                                Text(note.0)
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(ink)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 12)
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(mute)
                                    .rotationEffect(.degrees(openNote == index ? 45 : 0))
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 18)
                        }
                        .buttonStyle(.plain)

                        if openNote == index {
                            Text(note.1)
                                .font(.system(size: 14))
                                .lineSpacing(3)
                                .foregroundStyle(mute)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 18)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .overlay(alignment: .bottom) { Rectangle().fill(hairline).frame(height: 1) }
                }
            }
            .padding(.top, 14)
        }
        .padding(.top, 84)
    }

    // MARK: - 9 · Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(hairline).frame(height: 1)
                .padding(.top, 96)

            HStack(alignment: .top) {
                HStack(spacing: 8) {
                    footerBadge("ON DEVICE")
                    footerBadge("NO ACCOUNT")
                }
                Spacer()
                HStack(spacing: 16) {
                    Text("PRIVACY").footerLink()
                    Text("TERMS").footerLink()
                    Text("NOTICES").footerLink()
                }
            }
            .padding(.top, 20)

            Text("© 2026 SNSE · BUILD " + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                 + " · " + (calibrationDate.map { "CALIBRATED " + Self.dateText($0).uppercased() } ?? "UNCALIBRATED"))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(mute.opacity(0.75))
                .padding(.top, 14)
        }
        .padding(.bottom, 40)
    }

    private func footerBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .tracking(1.3)
            .foregroundStyle(mute)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(Capsule().strokeBorder(hairline, lineWidth: 1))
    }

    // MARK: - Section chrome

    private func sectionLabel(_ index: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Text(index)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(magenta)
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(mute)
            Rectangle().fill(hairline).frame(height: 1)
        }
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
        let from = String(parts[0...1]), to = String(parts[2...3])
        return [index(Substring(from)), index(Substring(to))].compactMap { $0 }
    }

    private var turnText: String {
        guard let fen = trackedFEN,
              let field = fen.split(separator: " ").dropFirst().first
        else { return "—" }
        return field == "w" ? "WHITE" : "BLACK"
    }

    // MARK: - Behaviour

    private func applyDemoIfRequested() {
        guard UserDefaults.standard.bool(forKey: "snse-demo") else { return }
        headline = "Nxe4"
        subline = "Your turn · black"
        lastMove = "Nxe4"
        lastMoveUCI = "f6e4"
        lastEval = "+3.37"
        lastWhy = "You take a knight with your knight. That puts it in the middle of the "
            + "board, where it controls the most squares."
        trackedFEN = "r3k2r/1p3ppp/p3pn2/8/P1pPN3/5NP1/1q3P1P/R2QR1K1 b kq - 1 4"
        detail = "read 363 · track 8 · engine 21 · total 392 ms\nwall 498 ms"
        lastTimings = "392 MS"
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
                    lastTimings = outcome.timings
                        .split(separator: " ")
                        .first(where: { $0.hasSuffix("ms") })
                        .map { $0.uppercased() } ?? ""
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

private extension Text {
    func footerLink() -> some View {
        self
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1.3)
            .foregroundStyle(Color(red: 0.467, green: 0.455, blue: 0.467))
    }
}
