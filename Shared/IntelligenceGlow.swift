import SwiftUI

/// Apple Intelligence–style glowing stroke, vendored from
/// [Livsy90/IntelligenceGlow](https://github.com/Livsy90/IntelligenceGlow) (MIT).
///
/// The library rotates an angular gradient through a few blurred strokes, which is what gives
/// Siri's current treatment its living rim. Vendored rather than pulled in as a package because
/// the app is built from `project.yml` and has no package graph.
extension Array where Element == Color {
    static var intelligenceColors: [Color] {
        [
            Color(red: 188 / 255, green: 130 / 255, blue: 243 / 255),
            Color(red: 245 / 255, green: 185 / 255, blue: 234 / 255),
            Color(red: 141 / 255, green: 159 / 255, blue: 255 / 255),
            Color(red: 255 / 255, green: 103 / 255, blue: 120 / 255),
            Color(red: 255 / 255, green: 186 / 255, blue: 113 / 255),
            Color(red: 198 / 255, green: 134 / 255, blue: 255 / 255),
        ]
    }
}

extension Array where Element == Gradient.Stop {
    static var intelligenceStyle: [Gradient.Stop] {
        [Color].intelligenceColors
            .map { Gradient.Stop(color: $0, location: Double.random(in: 0...1)) }
            .sorted { $0.location < $1.location }
    }
}

extension View {
    /// A glowing rim around any insettable shape.
    @MainActor
    func intelligenceOverlay<S: InsettableShape>(
        in shape: S,
        lineWidths: [CGFloat] = [3, 6, 9, 13],
        blurs: [CGFloat] = [0, 3, 8, 14],
        updateInterval: TimeInterval = 0.5,
        animationDurations: [TimeInterval] = [0.5, 0.7, 0.9, 1.1]
    ) -> some View {
        overlay(
            shape.intelligenceStroke(
                lineWidths: lineWidths,
                blurs: blurs,
                updateInterval: updateInterval,
                animationDurations: animationDurations
            )
        )
    }
}

extension InsettableShape {
    @MainActor
    func intelligenceStroke(
        lineWidths: [CGFloat] = [3, 6, 9, 13],
        blurs: [CGFloat] = [0, 3, 8, 14],
        updateInterval: TimeInterval = 0.5,
        animationDurations: [TimeInterval] = [0.5, 0.7, 0.9, 1.1]
    ) -> some View {
        IntelligenceGlowStroke(
            shape: self,
            lineWidths: lineWidths,
            blurs: blurs,
            updateInterval: updateInterval,
            animationDurations: animationDurations
        )
        .allowsHitTesting(false)
    }
}

private struct IntelligenceGlowStroke<S: InsettableShape>: View {
    let shape: S
    let lineWidths: [CGFloat]
    let blurs: [CGFloat]
    let updateInterval: TimeInterval
    let animationDurations: [TimeInterval]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stops: [Gradient.Stop] = .intelligenceStyle

    var body: some View {
        let layers = min(lineWidths.count, blurs.count, animationDurations.count)
        let gradient = AngularGradient(gradient: Gradient(stops: stops), center: .center)
        ZStack {
            ForEach(0..<layers, id: \.self) { index in
                shape
                    .strokeBorder(gradient, lineWidth: lineWidths[index])
                    .blur(radius: blurs[index])
                    .animation(
                        reduceMotion ? .linear(duration: 0)
                                     : .easeInOut(duration: animationDurations[index]),
                        value: stops
                    )
            }
        }
        .task(id: updateInterval) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                stops = .intelligenceStyle
                try? await Task.sleep(nanoseconds: UInt64(updateInterval * 1_000_000_000))
            }
        }
    }
}
