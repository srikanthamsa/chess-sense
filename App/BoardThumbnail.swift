import SwiftUI

/// A diagram of the tracked position, drawn from the FEN.
///
/// The app had no visual of the board it was talking about, so the lower half of the screen was
/// empty and the user had to trust a string of letters. This renders the position with its own
/// glyphs, marks the squares of the last move, and animates pieces in as they change -- the one
/// place a static screenshot can't go.
struct BoardThumbnail: View {
    let fen: String
    /// Squares of the last move, as FEN indices (rank 8 first).
    var highlight: [Int] = []

    private struct Cell: Identifiable {
        let id: Int
        let piece: String
        let isWhite: Bool
        let light: Bool
    }

    private var cells: [Cell] {
        let board = fen.split(separator: " ").first.map(String.init) ?? fen
        var pieces: [Character] = []
        for character in board {
            if character == "/" { continue }
            if let digit = character.wholeNumberValue {
                pieces.append(contentsOf: Array(repeating: ".", count: digit))
            } else {
                pieces.append(character)
            }
        }
        guard pieces.count == 64 else { return [] }

        return pieces.enumerated().map { index, symbol in
            let rank = index / 8, file = index % 8
            // a8 is light on this board, verified from the pixels long ago.
            let light = (rank + file) % 2 == 0
            return Cell(id: index,
                        piece: Self.glyph(symbol),
                        isWhite: symbol.isUppercase,
                        light: light)
        }
    }

    private static func glyph(_ symbol: Character) -> String {
        switch symbol.lowercased() {
        case "p": return "\u{265F}"
        case "n": return "\u{265E}"
        case "b": return "\u{265D}"
        case "r": return "\u{265C}"
        case "q": return "\u{265B}"
        case "k": return "\u{265A}"
        default: return ""
        }
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let square = side / 8
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { rank in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { file in
                            cellView(index: rank * 8 + file,
                                     square: square,
                                     light: (rank + file) % 2 == 0)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.snappy(duration: 0.35), value: fen)
    }

    @ViewBuilder
    private func cellView(index: Int, square: CGFloat, light: Bool) -> some View {
        let cell = cells.indices.contains(index) ? cells[index] : nil
        let marked = highlight.contains(index)
        ZStack {
            Rectangle()
                .fill(light ? Color(red: 0.78, green: 0.76, blue: 0.86)
                            : Color(red: 0.47, green: 0.42, blue: 0.63))
            if marked {
                Rectangle().fill(Color.red.opacity(0.38))
            }
            if let cell, !cell.piece.isEmpty {
                Text(cell.piece)
                    .font(.system(size: square * 0.78))
                    .foregroundStyle(cell.isWhite ? Color.white : Color(red: 0.11, green: 0.10, blue: 0.14))
                    .shadow(color: cell.isWhite ? .black.opacity(0.35) : .clear, radius: 1, y: 0.5)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: square, height: square)
    }
}
