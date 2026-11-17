import PhotosUI
import SwiftUI

struct ContentView: View {
    private let store = CalibrationStore()

    /// What a picked screenshot is for. Two pickers used to share one `pickerItem`, so the
    /// handler guessed from calibration state and the button label could lie.
    private enum PickIntent { case calibrate, analyse }

    @State private var calibrationItem: PhotosPickerItem?
    @State private var analysisItem: PhotosPickerItem?
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 40

    @State private var busy = false
    @State private var tracking = false
    @State private var calibrationDate: Date?
    @State private var trackedFEN: String?

    @State private var headline = "Ready"
    @State private var subline = "Screenshot a fresh game to calibrate."
    @State private var detail = ""
    @State private var lastMove: String?
    @State private var lastEval: String?
    @State private var lastWhy: String?

    @State private var keyDraft = ""
    @State private var keySaved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                bento
                    .padding(.horizontal, 14)
                    .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("chess-sense")
            .navigationBarTitleDisplayMode(.large)
            .overlay {
                if busy {
                    ZStack {
                        Color.black.opacity(0.08).ignoresSafeArea()
                        ProgressView().controlSize(.large)
                            .padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
            .onAppear(perform: refresh)
            .task {
                guard SelfTest.requested else { return }
                busy = true
                let report = await SelfTest.run()
                busy = false
                headline = report.passed ? "Self test passed" : "Self test failed"
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
    }

    // MARK: - Bento

    /// A three-band bento: one statement, a pair of actions, a pair of settings, then the
    /// wide detail strip. Tiles in a band share a height, which is what makes the grid read as
    /// a composition rather than a list of cards.
    private var bento: some View {
        VStack(spacing: 12) {
            resultTile

            HStack(alignment: .top, spacing: 12) {
                analyseTile.frame(maxWidth: .infinity)
                islandTile.frame(maxWidth: .infinity)
            }
            .frame(height: 138)

            HStack(alignment: .top, spacing: 12) {
                calibrationTile.frame(maxWidth: .infinity)
                coachingTile.frame(maxWidth: .infinity)
            }
            .frame(height: 152)

            positionTile

            if !detail.isEmpty { detailTile }
        }
        .padding(.top, 4)
    }

    // MARK: - Tiles

    /// The statement. One number, one sentence, nothing competing with it.
    private var resultTile: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(headline)
                    .font(.brandHero(headlineSize * 1.18))
                    .tracking(-0.5)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: headline)
                if let lastEval {
                    Text(lastEval)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(evalTint.opacity(0.16), in: Capsule())
                        .foregroundStyle(evalTint)
                }
                Spacer(minLength: 0)
            }

            Text(subline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let lastWhy, !lastWhy.isEmpty {
                Text(lastWhy)
                    .font(.footnote)
                    .foregroundStyle(.primary.opacity(0.72))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tileFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var evalTint: Color {
        guard let lastEval else { return .secondary }
        if lastEval.hasPrefix("#") { return .green }
        if lastEval.hasPrefix("-#") { return .red }
        guard let v = Double(lastEval.replacingOccurrences(of: "+", with: "")) else { return .secondary }
        if v > 0.6 { return .green }
        if v < -0.6 { return .red }
        return .secondary
    }

    private var analyseTile: some View {
        tile("Analyse", systemImage: "sparkle.magnifyingglass", tint: .blue) {
            Text("Screenshot the board, pick it here, get the move.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            PhotosPicker(selection: $analysisItem, matching: .images) {
                Label("Screenshot", systemImage: "photo")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }

    private var islandTile: some View {
        tile("Island", systemImage: "capsule.portrait.fill", tint: .pink) {
            Text(tracking ? "Live Activity running." : "Shows the move above the game.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button {
                do {
                    if LiveActivityController.isRunning {
                        Task { await LiveActivityController.end() }
                    } else {
                        _ = try LiveActivityController.start()
                    }
                    tracking = LiveActivityController.isRunning
                } catch {
                    headline = "Island failed"
                    subline = "Live Activities are unavailable for this app."
                    detail = "\(error)"
                }
            } label: {
                Label(tracking ? "Stop" : "Start",
                      systemImage: tracking ? "stop.circle.fill" : "play.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(tracking ? .red : .accentColor)
        }
    }

    private var calibrationTile: some View {
        tile("Calibration", systemImage: "square.grid.3x3.fill", tint: .orange) {
            Text("Learn this board once, from the start.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            PhotosPicker(selection: $calibrationItem, matching: .images) {
                Label("Pick start", systemImage: "photo.badge.plus")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Spacer(minLength: 0)

            if let calibrationDate {
                Label(calibrationDate.formatted(date: .abbreviated, time: .omitted),
                      systemImage: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            } else {
                Label("not calibrated", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }

            Button("Reset") {
                store.reset()
                refresh()
                headline = "Reset"
                subline = "Calibration and move history cleared."
                lastMove = nil; lastEval = nil; lastWhy = nil
            }
            .font(.caption2)
            .foregroundStyle(.red)
            .buttonStyle(.plain)
        }
    }

    private var coachingTile: some View {
        tile("Coach", systemImage: "text.bubble.fill", tint: .green) {
            Text("Optional: warmer wording.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                SecureField("sk-…", text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    keySaved = APIKeyStore.save(keyDraft)
                    keyDraft = ""
                    headline = keySaved ? "Key saved" : "Key failed"
                    subline = keySaved
                        ? "DeepSeek will refine each explanation."
                        : "Could not write to the keychain."
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Label(APIKeyStore.isConfigured ? "connected" : "on device",
                      systemImage: APIKeyStore.isConfigured ? "bolt.horizontal.circle.fill" : "cpu")
                    .font(.caption2)
                    .foregroundStyle(APIKeyStore.isConfigured ? .green : .secondary)
                Spacer(minLength: 0)
                if APIKeyStore.isConfigured {
                    Button("Remove") {
                        APIKeyStore.clear()
                        refresh()
                        headline = "Key removed"
                        subline = "Falling back to on-device explanations."
                    }
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Wide strip: the position being tracked, and the way into the design studio.
    private var positionTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "number")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.teal)
                    .frame(width: 22, height: 22)
                    .background(Color.teal.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text("Position")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                Spacer()
                NavigationLink("Studio") { DesignStudioView() }
                    .font(.caption2)
            }
            Text(trackedFEN ?? "No position tracked yet. Calibrate, then analyse a move.")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(tileFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var detailTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Details")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(detail)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(tileFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - Tile chrome

    private var tileFill: some ShapeStyle {
        .regularMaterial
    }

    /// One bento tile: a tinted glyph, a small title, then content that fills the band.
    private func tile<Content: View>(
        _ title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                Spacer(minLength: 0)
            }
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(tileFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func refresh() {
        calibrationDate = store.calibrationDate
        trackedFEN = store.trackedFEN
        keySaved = APIKeyStore.isConfigured
    }

    /// The picker's own intent decides what happens. Deciding from `store.isCalibrated`
    /// meant "Pick starting-position screenshot" analysed on a calibrated device, and
    /// "Pick current-position screenshot" calibrated on a fresh one.
    private func handle(_ item: PhotosPickerItem, intent: PickIntent) async {
        busy = true
        defer {
            busy = false
            calibrationItem = nil
            analysisItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                headline = "No image"
                subline = "That screenshot could not be loaded. Pick it again."
                return
            }

            switch intent {
            case .calibrate:
                let read = try await AnalysisPipeline.calibrateOffMain(imageData: data)
                refresh()
                headline = "Calibrated"
                subline = "This board is now recognised. Screenshot a move to get one."
                // Measurements belong in Details, not in the sentence a player reads.
                detail = [
                    "reading verified: worst shape distance \(read.worstShapeDistance) bits, "
                        + "colour margin \(String(format: "%.2f", read.minColorMargin))",
                    read.fen,
                ].joined(separator: "\n")

            case .analyse:
                guard store.isCalibrated else {
                    headline = "Not calibrated"
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
            headline = "Couldn't read"
            subline = Self.recovery(for: error)
            detail = "\(error)"
        }
    }

    /// What the player should do next, in their words. The raw error stays in Details.
    private static func recovery(for error: Error) -> String {
        if let boardError = error as? BoardError {
            return boardError.userFacingDescription
        }
        return "Something went wrong. Screenshot the board again and pick it."
    }

    private func present(_ outcome: AnalysisPipeline.Outcome) {
        if let move = outcome.move {
            headline = move.displayMove
            lastEval = move.evalText
            lastMove = move.displayMove
            lastWhy = outcome.why.isEmpty ? nil : outcome.why
            subline = outcome.trackingNote.isEmpty ? "analysed" : outcome.trackingNote
        } else if !outcome.trusted {
            headline = "Unclear"
            lastEval = nil
            lastWhy = nil
            subline = "I could not read the board confidently, so I am not guessing."
        } else {
            headline = "No move"
            lastEval = nil
            lastWhy = nil
            // `outcome.failure` is diagnostic ("engine: no engine available
            // (lichess cloud: …, stockfish.online: …)"). Say something usable here and
            // leave the reason in Details.
            subline = outcome.failure == nil
                ? "The engine had nothing for this position."
                : "I couldn't get an engine answer. Check your connection and try again."
        }

        detail = [
            outcome.trackingNote,
            outcome.move.map { "pv: \($0.principalVariation)" },
            outcome.move.map { "via \($0.provenance)" },
            outcome.failure.map { "note: \($0)" },
            outcome.fen,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }
}

#Preview {
    ContentView()
}
