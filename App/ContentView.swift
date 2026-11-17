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
                VStack(spacing: 16) {
                    resultCard
                    calibrationCard
                    coachingCard
                    trackingCard
                    analyseCard
                    if !detail.isEmpty { detailCard }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
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
                // Commit 3555511 dropped this hook, which left `SelfTest` unreachable and
                // made every "-chesssense-selftest" run a no-op. Harmless in normal use.
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

    // MARK: - Result

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(headline)
                    // @ScaledMetric keeps the intentional weight and rounded face while
                    // letting the headline grow with the user's type size. A fixed 40 pt
                    // stopped scaling, so sublines overtook it at accessibility sizes.
                    .font(.brandHero(headlineSize * 1.12))
                    .tracking(-0.5)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: headline)
                if let lastEval {
                    Text(lastEval)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
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
            if let lastWhy, !lastWhy.isEmpty {
                Divider()
                Text(lastWhy)
                    .font(.callout)
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
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

    // MARK: - Cards

    private var calibrationCard: some View {
        panel("Calibration", systemImage: "square.grid.3x3.fill") {
            Text("Screenshot a fresh game in TakeTakeTake and pick it here. One frame teaches all 13 templates, and the read is verified before it is accepted.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            PhotosPicker(selection: $calibrationItem, matching: .images) {
                Label("Pick starting-position screenshot", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack {
                if let calibrationDate {
                    Label(calibrationDate.formatted(date: .abbreviated, time: .shortened),
                          systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("not calibrated", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Reset", role: .destructive) {
                    store.reset()
                    refresh()
                    headline = "Reset"
                    subline = "Calibration and move history cleared."
                    lastMove = nil; lastEval = nil; lastWhy = nil
                }
                .font(.caption)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
        }
    }

    private var coachingCard: some View {
        panel("Coaching line", systemImage: "text.bubble.fill") {
            Text("Add a DeepSeek API key for a spoken-style explanation in everyday words. Without a key you still get a plain-English line written on device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SecureField("sk-…", text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    keySaved = APIKeyStore.save(keyDraft)
                    keyDraft = ""
                    headline = keySaved ? "Key saved" : "Key failed"
                    subline = keySaved
                        ? "DeepSeek will refine each explanation."
                        : "Could not write to the keychain."
                }
                .buttonStyle(.bordered)
                .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Label(APIKeyStore.isConfigured ? "DeepSeek connected" : "on-device explanations",
                      systemImage: APIKeyStore.isConfigured ? "bolt.horizontal.circle.fill" : "cpu")
                    .font(.caption)
                    .foregroundStyle(APIKeyStore.isConfigured ? .green : .secondary)
                Spacer()
                if APIKeyStore.isConfigured {
                    Button("Remove") {
                        APIKeyStore.clear()
                        refresh()
                        headline = "Key removed"
                        subline = "Falling back to on-device explanations."
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
            }
        }
    }

    private var trackingCard: some View {
        panel("Dynamic Island", systemImage: "capsule.portrait.fill") {
            Button {
                tracking.toggle()
                if tracking {
                    do {
                        try LiveActivityController.start()
                    } catch {
                        // Live Activity can be refused by the system (disabled in Settings,
                        // or too many running). Say that, rather than dumping the NSError.
                        tracking = false
                        headline = "Can't start"
                        subline = "Live Activities are turned off for this app. Check Settings, then try again."
                    }
                } else {
                    Task { await LiveActivityController.end() }
                }
            } label: {
                Label(tracking ? "Stop Live Activity" : "Start Live Activity",
                      systemImage: tracking ? "stop.circle.fill" : "play.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(tracking ? .red : .accentColor)

            Text("Wire it hands-free: Shortcuts → **Take Screenshot** → **Best Move**, bound to Back Tap or the Action Button.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let trackedFEN {
                Text(trackedFEN)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Button("Forget move history", role: .destructive) {
                    store.resetTracking()
                    refresh()
                    headline = "History cleared"
                    subline = "Next screenshot is treated as a fresh position."
                }
                .font(.caption)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
        }
    }

    private var analyseCard: some View {
        panel("Analyse a position", systemImage: "sparkle.magnifyingglass") {
            PhotosPicker(selection: $analysisItem, matching: .images) {
                Label("Pick current-position screenshot", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var detailCard: some View {
        panel("Details", systemImage: "doc.text.magnifyingglass") {
            Text(detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Panel chrome

    private func panel<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.9))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    // MARK: - Actions

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
