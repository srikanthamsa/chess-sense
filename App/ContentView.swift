import PhotosUI
import SwiftUI

struct ContentView: View {
    private let store = CalibrationStore()

    @State private var pickerItem: PhotosPickerItem?
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
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await handle(item) }
            }
        }
    }

    // MARK: - Result

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(headline)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
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
            PhotosPicker(selection: $pickerItem, matching: .images) {
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
                }
            }
        }
    }

    private var trackingCard: some View {
        panel("Dynamic Island", systemImage: "capsule.portrait.fill") {
            Button {
                tracking.toggle()
                if tracking {
                    do { try LiveActivityController.start() } catch { headline = "Error"; subline = "\(error)" }
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
                    .font(.system(size: 10, design: .monospaced))
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
            }
        }
    }

    private var analyseCard: some View {
        panel("Analyse a position", systemImage: "sparkle.magnifyingglass") {
            PhotosPicker(selection: $pickerItem, matching: .images) {
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

    private func handle(_ item: PhotosPickerItem) async {
        busy = true
        defer { busy = false; pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                headline = "No image"
                subline = "Could not load that image."
                return
            }

            if !store.isCalibrated {
                let read = try AnalysisPipeline.calibrate(imageData: data)
                refresh()
                headline = "Calibrated"
                subline = "Reading verified: \(read.worstShapeDistance) bits worst case, "
                    + "margin \(String(format: "%.2f", read.minColorMargin))."
                detail = read.fen
                return
            }

            let outcome = try await AnalysisPipeline.analyzeAndPublish(imageData: data)
            refresh()

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
                subline = outcome.failure ?? "The engine had nothing."
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
        } catch {
            headline = "Failed"
            subline = "\(error)"
            detail = ""
        }
    }
}

#Preview {
    ContentView()
}
