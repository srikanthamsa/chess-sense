import SwiftUI

/// The house palette: a warm, quiet chess set rather than a neon dashboard.
///
/// Charcoal canvas, cream ink, one gold. The board itself is walnut and cream, which is the
/// scheme every serious chess app has converged on — the pieces were drawn for those two
/// squares, and a saturated accent beside them reads as a toy.
public enum Theme {
    // Surfaces
    public static let canvas = Color(red: 0.043, green: 0.043, blue: 0.047)   // #0B0B0C
    public static let panel = Color(red: 0.071, green: 0.071, blue: 0.078)    // #121214
    public static let line = Color(red: 0.125, green: 0.125, blue: 0.137)     // #202023

    // Ink
    public static let ink = Color(red: 0.953, green: 0.937, blue: 0.902)      // #F3EFE6
    public static let mute = Color(red: 0.541, green: 0.522, blue: 0.482)     // #8A857B

    // One accent, and its two semantic partners
    public static let gold = Color(red: 0.831, green: 0.659, blue: 0.353)     // #D4A85A
    public static let good = Color(red: 0.353, green: 0.612, blue: 0.475)     // #5A9C79
    public static let bad = Color(red: 0.760, green: 0.412, blue: 0.361)      // #C2695C

    // Board
    public static let squareLight = Color(red: 0.941, green: 0.851, blue: 0.710)  // #F0D9B5
    public static let squareDark = Color(red: 0.710, green: 0.533, blue: 0.388)   // #B58863
}

/// Spring presets, fitted by feel rather than formula: these are the two the island lives on.
public enum Spring {
    /// Tight, crisp, no visible wobble. State changes and reveals.
    public static let snappy = Animation.spring(response: 0.35, dampingFraction: 0.72)
    /// A little bounce. Something appearing or landing.
    public static let pop = Animation.spring(response: 0.32, dampingFraction: 0.58)
    /// Long, slow settle. Layout changes that must not feel mechanical.
    public static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.82)
}

// MARK: - Parts

/// A ring that fills. Used for engine thinking and for how the position stands, because a
/// number in a pill says less than a ring you can read at a glance.
public struct ProgressRing: View {
    let value: Double          // 0...1
    var lineWidth: CGFloat = 2.5
    var tint: Color = Theme.gold
    var track: Color = Theme.line

    public init(value: Double, lineWidth: CGFloat = 2.5,
                tint: Color = Theme.gold, track: Color = Theme.line) {
        self.value = value
        self.lineWidth = lineWidth
        self.tint = tint
        self.track = track
    }

    public var body: some View {
        ZStack {
            Circle().strokeBorder(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Spring.snappy, value: value)
        }
    }
}

/// Five ticks that light up left to right. A level meter reads faster than a percentage.
public struct LevelMeter: View {
    let value: Double
    var tint: Color = Theme.gold

    public init(value: Double, tint: Color = Theme.gold) {
        self.value = value
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(Double(index) < value * 5 ? tint : Theme.line)
                    .frame(width: 3, height: CGFloat(4 + index * 2))
            }
        }
        .animation(Spring.snappy, value: value)
    }
}

/// Text that counts rather than cuts, for anything numeric that changes in place.
public struct SteadyText: View {
    let text: String
    var size: CGFloat
    var weight: Font.Weight = .semibold
    var tint: Color = Theme.ink

    public init(_ text: String, size: CGFloat, weight: Font.Weight = .semibold,
                tint: Color = Theme.ink) {
        self.text = text
        self.size = size
        self.weight = weight
        self.tint = tint
    }

    public var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .contentTransition(.numericText())
    }
}

/// A slow highlight travelling across the letters, for waiting states.
public struct ShimmerText: View {
    let text: String
    var size: CGFloat = 12
    var tint: Color = Theme.ink

    @State private var phase: CGFloat = -1

    public init(_ text: String, size: CGFloat = 12, tint: Color = Theme.ink) {
        self.text = text
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(tint.opacity(0.55))
            .overlay(
                LinearGradient(
                    colors: [.clear, tint.opacity(0.95), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .scaleEffect(x: 0.35, anchor: .center)
                .offset(x: phase * 220)
                .blendMode(.plusLighter)
                .mask(Text(text).font(.system(size: size, weight: .medium)))
            )
            .onAppear {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
    }
}
