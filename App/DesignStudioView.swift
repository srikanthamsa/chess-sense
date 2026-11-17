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
                return .init(uci: "----", san: "", evalText: "---",
                             principalVariation: "", provenance: "waiting for a screenshot",
                             trusted: true, why: "", playerEval: "0.00", pieceSymbol: "")
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
                return .init(uci: "--", san: "", evalText: "!",
                             principalVariation: "board read was not confident",
                             provenance: "rejected", trusted: false, why: "")
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
            VStack(spacing: 26) {
                Picker("Sample", selection: $sample) {
                    ForEach(Sample.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Group {
                    caption("Compact · live activity")
                    compact

                    caption("Minimal")
                    minimalRow

                    caption("Evaluation chip and bar")
                    evalRow

                    caption("Expanded")
                    expanded
                }

                caption("Lock screen · over a photo")
                ZStack {
                    wallpaper
                    VStack(spacing: 18) {
                        LockScreenCard(state: sample.state)
                            .padding(14)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
                .padding(20)
            }
        }
        .environment(\.colorScheme, .dark)
        .navigationTitle("Island studio")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A warm, bright backdrop so the glass has something to refract, as in the reference.
    private var wallpaper: some View {
        LinearGradient(
            colors: [
                Color(red: 0.93, green: 0.82, blue: 0.66),
                Color(red: 0.74, green: 0.60, blue: 0.46),
                Color(red: 0.28, green: 0.24, blue: 0.22),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Circle()
                .fill(.white.opacity(0.35))
                .blur(radius: 60)
                .offset(x: 90, y: -140)
        )
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compact: some View {
        HStack(spacing: 26) {
            HStack(spacing: 8) {
                IslandCompactLeading(trusted: sample.state.trusted,
                                     accent: IslandAccent.resolve(sample.state))
                IslandCompactTrailing(move: sample.state.displayMove,
                                      trusted: sample.state.trusted,
                                      accent: IslandAccent.resolve(sample.state),
                                      evalText: sample.state.youEval)
            }
            .padding(.horizontal, 14)
            .frame(height: 37)
            .background(Capsule().fill(.black))
            .overlay(Capsule().strokeBorder(.white.opacity(0.06)))

            HStack {
                IslandMinimal(move: sample.state.displayMove, presentation: IslandPresentation(sample.state), symbol: sample.state.pieceSymbol, accent: IslandAccent.resolve(sample.state))
                    .foregroundStyle(.white)
            }
            .padding(10)
            .frame(height: 37)
            .background(Capsule().fill(.black))
            .overlay(Capsule().strokeBorder(.white.opacity(0.06)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var minimalRow: some View {
        HStack(spacing: 12) {
            HStack { IslandMinimal(move: sample.state.displayMove, presentation: IslandPresentation(sample.state), symbol: sample.state.pieceSymbol, accent: IslandAccent.resolve(sample.state)) }
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(Capsule().fill(.black))
                .overlay(Capsule().strokeBorder(.white.opacity(0.06)))
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var evalRow: some View {
        HStack(spacing: 14) {
            EvalPill(evalText: sample.state.youEval, trusted: sample.state.trusted)
            AdvantageBar(evalText: sample.state.youEval).frame(width: 200)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                IslandExpandedLeading(state: sample.state, thinking: sample == .thinking)
                IslandExpandedMove(state: sample.state)
                Spacer(minLength: 4)
                EvalPill(evalText: sample.state.youEval, trusted: sample.state.trusted)
            }
            IslandExpandedBottom(state: sample.state)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .strokeBorder(.white.opacity(0.07))
                )
        )
    }
}
