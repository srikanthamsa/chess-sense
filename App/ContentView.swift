import PhotosUI
import SwiftUI

struct ContentView: View {
    private let store = CalibrationStore()

    @State private var pickerItem: PhotosPickerItem?
    @State private var busy = false
    @State private var headline = ""
    @State private var detail = ""
    @State private var tracking = false
    @State private var calibrationDate: Date?
    @State private var trackedFEN: String?

    var body: some View {
        NavigationStack {
            List {
                Section("1 · Calibrate") {
                    Text("Screenshot a **fresh game** (starting position) in TakeTakeTake and pick it here. One frame teaches all 13 templates, and the app verifies the read before accepting it.")
                        .font(.footnote)
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Pick starting-position screenshot", systemImage: "square.grid.3x3")
                    }
                    if let calibrationDate {
                        LabeledContent("Calibrated",
                                       value: calibrationDate.formatted(date: .abbreviated,
                                                                        time: .shortened))
                    }
                    Button("Reset calibration", role: .destructive) {
                        store.reset()
                        calibrationDate = nil
                        trackedFEN = nil
                        headline = "Calibration cleared."
                        detail = ""
                    }
                }

                Section("2 · Track") {
                    Button {
                        tracking.toggle()
                        if tracking {
                            do { try LiveActivityController.start() } catch { headline = "\(error)" }
                        } else {
                            Task { await LiveActivityController.end() }
                        }
                    } label: {
                        Label(tracking ? "Stop Live Activity" : "Start Live Activity",
                              systemImage: tracking ? "stop.circle" : "play.circle")
                    }
                    Text("The Island shows the move after each analysis. Wire it hands-free with **One Screenshot → Best Move** — see the README.")
                        .font(.footnote)
                    if let trackedFEN {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tracked position").font(.caption).foregroundStyle(.secondary)
                            Text(trackedFEN).font(.caption2.monospaced()).textSelection(.enabled)
                        }
                    }
                    Button("Forget move history", role: .destructive) {
                        store.resetTracking()
                        trackedFEN = nil
                        headline = "Move history cleared."
                        detail = ""
                    }
                }

                Section("3 · Analyse a position") {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Pick current-position screenshot", systemImage: "photo")
                    }
                }

                if !headline.isEmpty {
                    Section("Result") {
                        Text(headline).font(.title3.monospaced().weight(.semibold))
                        if !detail.isEmpty {
                            Text(detail).font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("chess-sense")
            .overlay { if busy { ProgressView() } }
            .onAppear {
                calibrationDate = store.calibrationDate
                trackedFEN = store.trackedFEN
            }
            .task {
                guard SelfTest.requested else { return }
                busy = true
                let report = await SelfTest.run()
                busy = false
                headline = report.passed ? "SELF TEST PASSED" : "SELF TEST FAILED"
                detail = report.text
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await handle(item) }
            }
        }
    }

    private func handle(_ item: PhotosPickerItem) async {
        busy = true
        defer { busy = false; pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                headline = "Could not load that image."
                return
            }

            if !store.isCalibrated {
                let read = try AnalysisPipeline.calibrate(imageData: data)
                calibrationDate = store.calibrationDate
                trackedFEN = store.trackedFEN
                headline = "Calibrated ✓"
                detail = "\(read.fen)\nworst shape distance \(read.worstShapeDistance), "
                    + "colour margin \(String(format: "%.2f", read.minColorMargin))"
                return
            }

            let outcome = try await AnalysisPipeline.analyzeAndPublish(imageData: data)
            trackedFEN = store.trackedFEN

            if let move = outcome.move {
                headline = "\(move.displayMove)    \(move.evalText)"
            } else if !outcome.trusted {
                headline = "Read rejected"
            } else {
                headline = "No move"
            }

            detail = [
                outcome.trackingNote,
                outcome.move.map { "pv: \($0.principalVariation)" },
                outcome.move.map { "via \($0.provenance)" },
                outcome.failure.map { "note: \($0)" },
                "\(outcome.fen)",
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        } catch {
            headline = "Failed"
            detail = "\(error)"
        }
    }
}

#Preview {
    ContentView()
}
