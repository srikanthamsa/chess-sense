import SwiftUI

/// Renders the Island's real subviews inside mock hardware shells so the layout can be
/// inspected and screenshotted without a device or a live game.
struct DesignStudioView: View {
    @State private var sample: Sample = {
        if let raw = UserDefaults.standard.string(forKey: "studioSample"),
           let match = Sample(rawValue: raw) {
            return match
        }
        return .coaching
    }()

    enum Sample: String, CaseIterable, Identifiable {
        case waiting, thinking, coaching, unclear, mate
        var id: String { rawValue }
        var label: String {
            switch self {
            case .waiting: return "Waiting"
            case .thinking: return "Thinking"
            case .coaching: return "Move"
            case .unclear: return "Unclear"
            case .mate: return "Mate"
            }
        }
        var state: BestMoveAttributes.ContentState {
            switch self {
            case .waiting:
                // Mirrors `LiveActivityController.start()`. Nothing has been read, so there
                // is no evaluation to show.
                return .init(uci: "----", san: "", evalText: "",
                             principalVariation: "", provenance: "waiting for a screenshot",
                             trusted: true, why: "Play a move, then screenshot the board.",
                             playerEval: "", pieceSymbol: "")
            case .thinking:
                return .init(uci: "----", san: "", evalText: "+0.20",
                             principalVariation: "", provenance: "reading the board",
                             trusted: true, why: "", playerEval: "+0.20", pieceSymbol: "")
            case .coaching:
                return .init(uci: "b6d4", san: "Qxd4", evalText: "-2.32",
                             principalVariation: "Qxd4 Nxc6 Qd1+ Rxd1 bxc6",
                             provenance: "lichess cloud · d31",
                             trusted: true,
                             why: "Your queen slides onto the open diagonal and takes that pawn, so you are simply a piece up here.",
                             playerEval: "+2.32", pieceSymbol: "\u{265B}", tip: "Your queen takes the bishop and hits the king.")
            case .unclear:
                // What production actually sends for a failed read: a plain-English reason
                // the player can act on. The studio previews it so this copy is reviewed.
                return .init(uci: "--", san: "", evalText: "!",
                             principalVariation: "",
                             provenance: "rejected", trusted: false,
                             why: "No chess board found there. Screenshot the whole game.")
            case .mate:
                return .init(uci: "a1a8", san: "Ra8#", evalText: "#1",
                             principalVariation: "Ra8#",
                             provenance: "stockfish.online · d14", trusted: true,
                             why: "Your rook drops onto the back row. His king has nowhere to go — that is checkmate.",
                             playerEval: "#1", pieceSymbol: "\u{2656}", tip: "Checkmate — his king has nowhere to run.")
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
            VStack(spacing: 24) {
                Picker("Sample", selection: $sample) {
                    ForEach(Sample.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Group {
                    caption("Compact live activity")
                    compact

                    caption("Minimal")
                    minimalRow

                    caption("Evaluation readout")
                    evalRow

                    caption("Expanded")
                    expanded
                }

                caption("Lock screen")
                LockScreenCard(state: sample.state)
                    .background(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Color(white: 0.09))
                    )
            }
                .padding(20)
            }
        }
        .environment(\.colorScheme, .dark)
        .navigationTitle("Island studio")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compact: some View {
        HStack(spacing: 24) {
            HStack(spacing: 8) {
                IslandCompactLeading(move: sample.state.displayMove,
                                     trusted: sample.state.trusted,
                                     accent: IslandAccent.resolve(sample.state),
                                     presentation: IslandPresentation(sample.state),
                                     symbol: sample.state.pieceSymbol)
                IslandCompactTrailing(move: sample.state.displayMove,
                                      trusted: sample.state.trusted,
                                      accent: IslandAccent.resolve(sample.state),
                                      evalText: sample.state.youEval,
                                      presentation: IslandPresentation(sample.state))
            }
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Capsule().fill(.black))
            .overlay(Capsule().strokeBorder(.white.opacity(0.06)))

            HStack {
                IslandMinimal(move: sample.state.displayMove, presentation: IslandPresentation(sample.state), symbol: sample.state.pieceSymbol, accent: IslandAccent.resolve(sample.state))
                    .foregroundStyle(.white)
            }
            .padding(10)
            .frame(height: 36)
            .background(Capsule().fill(.black))
            .overlay(Capsule().strokeBorder(.white.opacity(0.06)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var minimalRow: some View {
        HStack(spacing: 12) {
            HStack { IslandMinimal(move: sample.state.displayMove, presentation: IslandPresentation(sample.state), symbol: sample.state.pieceSymbol, accent: IslandAccent.resolve(sample.state)) }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Capsule().fill(.black))
                .overlay(Capsule().strokeBorder(.white.opacity(0.06)))
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var evalRow: some View {
        HStack(spacing: 16) {
            EvalPill(evalText: sample.state.youEval, trusted: sample.state.trusted)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var expanded: some View {
        IslandExpandedCard(state: sample.state)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 42, style: .continuous)
                    .fill(.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 42, style: .continuous)
                            .strokeBorder(.white.opacity(0.07))
                    )
            )
    }
}
