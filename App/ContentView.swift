import PhotosUI
import SwiftUI

struct ContentView: View {
    private let store = CalibrationStore()

    @State private var pickerItem: PhotosPickerItem?
    @State private var busy = false
    @State private var status: String = ""
    @State private var details: String = ""
    @State private var tracking = false

    var body: some View {
        NavigationStack {
            List {
                Section("1 · Calibrate") {
                    Text("Screenshot a **fresh game** (starting position) in TakeTakeTake, then pick it here. One frame teaches all 13 templates.")
                        .font(.footnote)
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Pick starting-position screenshot", systemImage: "square.grid.3x3")
                    }
                    if let date = store.calibrationDate {
                        LabeledContent("Calibrated", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button("Reset calibration", role: .destructive) {
                        store.reset()
                        status = "Calibration cleared."
                        details = ""
                    }
                }

                Section("2 · Track") {
                    Button {
                        tracking.toggle()
                        if tracking {
                            do { try LiveActivityController.start() } catch { status = "\(error)" }
                        } else {
                            Task { await LiveActivityController.end() }
                        }
                    } label: {
                        Label(
                            tracking ? "Stop Live Activity" : "Start Live Activity",
                            systemImage: tracking ? "stop.circle" : "play.circle"
                        )
                    }
                    Text("With it running, the Island shows the move after each analyse.")
                        .font(.footnote)
                }

                Section("3 · Analyse a position") {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Pick current-position screenshot", systemImage: "photo")
                    }
                    Text("For hands-free: bind **Best Move** to the Action Button in Shortcuts (Take Screenshot → Best Move).")
                        .font(.footnote)
                }

                if !status.isEmpty {
                    Section("Result") {
                        Text(status).font(.body.monospaced())
                        if !details.isEmpty {
                            Text(details).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("chess-sense")
            .overlay { if busy { ProgressView() } }
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
                status = "Could not load that image."
                return
            }
            if store.isCalibrated {
                let result = try await AnalysisPipeline.analyzeAndPublish(imageData: data)
                status = result.move.map { "\($0.uci)   \($0.evalText)" } ?? "no move"
                details = [
                    result.fen,
                    result.failure.map { "note: \($0)" },
                    result.move?.principalVariation,
                ].compactMap { $0 }.joined(separator: "\n")
            } else {
                let read = try AnalysisPipeline.calibrate(imageData: data)
                status = "Calibrated ✓"
                details = read.fen + "\nworst shape distance \(read.worstShapeDistance)"
            }
        } catch {
            status = "Failed"
            details = "\(error)"
        }
    }
}
