import SwiftUI

/// Diagnostics screen for the on-device engine: how fast is it, really, on this phone.
/// Reached with `-snse-engine YES` (or the Diagnostics row in the app).
struct EngineProbeView: View {
    @State private var lines: [String] = []
    @State private var running = true

    private static let positions: [(String, String)] = [
        ("start", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"),
        ("middlegame", "r3kbnr/pp3ppp/1qn1p3/3pNbB1/3P4/1B6/PPP2PPP/RN1QK2R w KQkq - 0 1"),
        ("endgame", "8/5pk1/6p1/8/3K4/5P2/6P1/8 w - - 0 1"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(line.hasPrefix("✓") ? .green : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if running { ProgressView() }
            }
            .padding(16)
        }
        .navigationTitle("Engine")
        .task { await run() }
    }

    private func run() async {
        guard let backend = EngineRegistry.localBackend else {
            lines = ["✗ no local engine registered"]
            running = false
            return
        }
        lines.append("backend: \(backend.name)")
        for (label, fen) in Self.positions {
            let started = Date()
            do {
                let move = try await backend.evaluate(fen: fen, transport: URLSessionTransport())
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                lines.append("✓ \(label) \(ms) ms → \(move.uci) \(move.evalText)")
                if !move.principalVariation.isEmpty {
                    lines.append("   pv \(move.principalVariation.prefix(60))")
                }
            } catch {
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                lines.append("✗ \(label) \(ms) ms → \(error)")
            }
        }
        running = false
    }
}
