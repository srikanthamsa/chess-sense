import PhotosUI
import SwiftUI

/// Everything that is not the answer: calibration, coaching key, the studio, the engine, and
/// the notes that used to sit on the page as an accordion.
struct SettingsSheet: View {
    let store: CalibrationStore
    @Binding var tracking: Bool
    var onRefresh: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var calibrationItem: PhotosPickerItem?
    @State private var keyDraft = ""
    @State private var keySaved = false
    @State private var calibrationDate: Date?
    @State private var busy = false
    @State private var message: String?
    @State private var openNote: Int?

    private let hairline = Color(red: 0.10, green: 0.10, blue: 0.11)
    private let ink = Color(red: 0.957, green: 0.957, blue: 0.949)
    private let mute = Color(red: 0.467, green: 0.455, blue: 0.467)
    private let magenta = Color(red: 0.886, green: 0.102, blue: 0.635)

    private var notes: [(String, String)] {
        [
            ("How is the board read?",
             "It finds a rectangle of alternating squares, learns the pieces from one "
                + "calibration frame, then matches every square. Anything ambiguous is refused "
                + "rather than guessed."),
            ("Does it need a network?",
             "No. Stockfish is compiled into this app and runs in-process. The optional "
                + "coaching key is the only outbound call."),
            ("Will it read other chess apps?",
             "The recogniser learns a theme, but the board finder currently expects "
                + "TakeTakeTake's layout. Another app needs its own calibration."),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    row(
                        title: calibrationDate == nil ? "Not calibrated" : "Calibrated",
                        detail: calibrationDate.map { SettingsSheet.dateText($0) }
                            ?? "One start-position screenshot",
                        live: calibrationDate != nil
                    ) {
                        PhotosPicker(selection: $calibrationItem, matching: .images) {
                            pill("PICK", filled: false)
                        }
                        .buttonStyle(.plain)
                    }

                    row(
                        title: keySaved ? "Coaching connected" : "Coaching offline",
                        detail: keySaved ? "Warmer wording from your key" : "On-device wording only",
                        live: keySaved
                    ) {
                        if keySaved {
                            Button {
                                APIKeyStore.clear()
                                refresh()
                            } label: { pill("REMOVE", filled: false) }
                            .buttonStyle(.plain)
                        } else {
                            HStack(spacing: 8) {
                                TextField("sk-…", text: $keyDraft)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(ink)
                                    .frame(width: 104)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(.white.opacity(0.05))
                                    )
                                Button {
                                    _ = APIKeyStore.save(keyDraft)
                                    keyDraft = ""
                                    refresh()
                                } label: { pill("SAVE", filled: true) }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    NavigationLink {
                        DesignStudioView()
                    } label: {
                        linkRow("Design studio", "Island, lock screen, previews")
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        EngineProbeView()
                    } label: {
                        linkRow("Engine", "Timings and best moves per position")
                    }
                    .buttonStyle(.plain)

                    if let message {
                        Text(message)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(mute)
                            .padding(.top, 12)
                    }

                    Text("NOTES")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(mute)
                        .padding(.top, 28)

                    ForEach(Array(notes.enumerated()), id: \.offset) { index, note in
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                withAnimation(.snappy(duration: 0.26)) {
                                    openNote = openNote == index ? nil : index
                                }
                            } label: {
                                HStack {
                                    Text(note.0)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(ink)
                                    Spacer(minLength: 10)
                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(mute)
                                        .rotationEffect(.degrees(openNote == index ? 45 : 0))
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 15)
                            }
                            .buttonStyle(.plain)

                            if openNote == index {
                                Text(note.1)
                                    .font(.system(size: 13))
                                    .lineSpacing(2)
                                    .foregroundStyle(mute)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.bottom, 14)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(hairline).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Color(red: 0.02, green: 0.02, blue: 0.02).ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
            }
            .onAppear(perform: refresh)
            .onChange(of: calibrationItem) { _, item in
                guard let item else { return }
                Task { await calibrate(item) }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pieces

    private func row<Right: View>(
        title: String,
        detail: String,
        live: Bool,
        @ViewBuilder trailing: () -> Right
    ) -> some View {
        HStack(alignment: .center) {
            Circle()
                .fill(live ? magenta : hairline)
                .frame(width: 5, height: 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(ink)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(mute)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) { Rectangle().fill(hairline).frame(height: 1) }
    }

    private func linkRow(_ title: String, _ detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(ink)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(mute)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(mute)
        }
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) { Rectangle().fill(hairline).frame(height: 1) }
    }

    private func pill(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(filled ? Color.black : ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(filled ? Capsule().fill(ink) : nil)
            .overlay(filled ? nil : Capsule().strokeBorder(hairline, lineWidth: 1))
    }

    private func refresh() {
        calibrationDate = store.calibrationDate
        keySaved = APIKeyStore.isConfigured
    }

    private func calibrate(_ item: PhotosPickerItem) async {
        busy = true
        message = "Reading that frame…"
        defer { busy = false; calibrationItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                message = "That screenshot could not be loaded."
                return
            }
            let read = try await AnalysisPipeline.calibrateOffMain(imageData: data)
            refresh()
            onRefresh()
            message = "Calibrated · worst shape distance \(read.worstShapeDistance)"
        } catch {
            message = ContentView.recovery(for: error)
        }
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM · HH:mm"
        return formatter.string(from: date)
    }
}
