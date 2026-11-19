import SwiftUI

/// The board, live and touchable.
///
/// Not a picture of the position: every square is a target. Tap one to inspect it, tap the
/// same square again to clear, hold the flip button to see it from Black's side. The pieces are
/// drawn from the same asset set the reader matches against, so a wrong read is visible here
/// rather than hidden behind a FEN string.
struct LiveBoard: View {
    let fen: String
    var highlight: [Int] = []
    /// Shows the starting position when the app has nothing tracked yet.
    var isPlaceholder: Bool = false

    @State private var selected: Int?
    @State private var flipped = false

    private struct Cell: Identifiable {
        let id: Int
        let asset: String
        let light: Bool
    }

    private var cells: [Cell] {
        let board = fen.split(separator: " ").first.map(String.init) ?? fen
        var symbols: [Character] = []
        for character in board {
            if character == "/" { continue }
            if let digit = character.wholeNumberValue {
                symbols.append(contentsOf: Array(repeating: ".", count: digit))
            } else {
                symbols.append(character)
            }
        }
        guard symbols.count == 64 else { return [] }
        return symbols.enumerated().map { index, symbol in
            let rank = index / 8, file = index % 8
            // a8 is light on this board, verified from the pixels.
            let light = (rank + file) % 2 == 0
            return Cell(id: index, asset: Self.assetName(symbol), light: light)
        }
    }

    private static func assetName(_ symbol: Character) -> String {
        let kind: String
        switch symbol.lowercased() {
        case "p": kind = "P"
        case "n": kind = "N"
        case "b": kind = "B"
        case "r": kind = "R"
        case "q": kind = "Q"
        case "k": kind = "K"
        default: return ""
        }
        return (symbol.isUppercase ? "w" : "b") + kind
    }

    private var squareName: String {
        guard let selected else { return "" }
        let rank = selected / 8, file = selected % 8
        let letter = Character(UnicodeScalar(UInt8(97 + file)))
        return "\(letter)\(8 - rank)".uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                // The parent gives this an explicit square. Letting a GeometryReader negotiate
                // its height inside a ScrollView stalls layout, and the window renders black.
                let side = min(geo.size.width, geo.size.height)
                let square = side / 8
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { column in
                                cellView(
                                    index: flipped ? 63 - (row * 8 + column) : row * 8 + column,
                                    square: square
                                )
                            }
                        }
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .opacity(isPlaceholder ? 0.55 : 1)
            .animation(.snappy(duration: 0.3), value: isPlaceholder)

            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(isPlaceholder ? "START POSITION · WAITING FOR A FRAME"
                               : (selected == nil ? "TAP A SQUARE TO INSPECT" : "SELECTED " + squareName))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(selected == nil ? Color.white.opacity(0.4) : Color(red: 0.886, green: 0.102, blue: 0.635))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Button {
                withAnimation(.snappy(duration: 0.35)) { flipped.toggle() }
            } label: {
                Text(flipped ? "BLACK VIEW" : "WHITE VIEW")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private func cellView(index: Int, square: CGFloat) -> some View {
        let cell = cells.indices.contains(index) ? cells[index] : nil
        let marked = highlight.contains(index)
        let isSelected = selected == index
        ZStack {
            Rectangle()
                .fill(cell?.light == true
                      ? Color(red: 0.78, green: 0.76, blue: 0.86)
                      : Color(red: 0.47, green: 0.42, blue: 0.63))
            if marked {
                Rectangle().fill(Color(red: 0.886, green: 0.102, blue: 0.635).opacity(0.35))
            }
            if isSelected {
                Rectangle().strokeBorder(Color(red: 0.886, green: 0.102, blue: 0.635), lineWidth: 2)
            }
            if let cell, !cell.asset.isEmpty {
                Image(cell.asset)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(square * 0.06)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: square, height: square)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.18)) {
                selected = selected == index ? nil : index
            }
        }
    }
}
