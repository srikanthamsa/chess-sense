import SwiftUI

/// The board, live and draggable.
///
/// Not a picture of the position: pieces can be picked up and dropped on another square, which
/// is the fastest way to ask "what about this move instead". The drag is local preview only —
/// the app never treats a hand-moved piece as a read from the screen.
struct LiveBoard: View {
    let fen: String
    var highlight: [Int] = []
    var isPlaceholder: Bool = false

    @State private var selected: Int?
    @State private var flipped = false
    /// Set when the player drags a piece, so the diagram answers immediately.
    @State private var edited: [Character]?
    @State private var dragFrom: Int?
    @State private var dragOffset: CGSize = .zero
    @State private var moving: Character?

    private struct Cell: Identifiable {
        let id: Int
        let asset: String
        let light: Bool
    }

    // MARK: Position

    private var symbols: [Character] {
        if let edited { return edited }
        let board = fen.split(separator: " ").first.map(String.init) ?? fen
        var out: [Character] = []
        for character in board {
            if character == "/" { continue }
            if let digit = character.wholeNumberValue {
                out.append(contentsOf: Array(repeating: ".", count: digit))
            } else {
                out.append(character)
            }
        }
        return out.count == 64 ? out : Array(repeating: ".", count: 64)
    }

    private var cells: [Cell] {
        let list = symbols
        return list.enumerated().map { index, symbol in
            let rank = index / 8, file = index % 8
            return Cell(id: index,
                        asset: Self.assetName(symbol),
                        light: (rank + file) % 2 == 0)
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

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let square = side / 8
                ZStack(alignment: .topLeading) {
                    grid(square: square, side: side)

                    if let moving, dragFrom != nil {
                        Image(Self.assetName(moving))
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: square * 0.94, height: square * 0.94)
                            .offset(dragOffset)
                            .allowsHitTesting(false)
                            .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
                    }
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(square: square, side: side))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 0.5)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .opacity(isPlaceholder ? 0.5 : 1)
            .animation(.snappy(duration: 0.3), value: isPlaceholder)

            footer
        }
        .onChange(of: fen) { _, _ in edited = nil; selected = nil }
    }

    private func grid(square: CGFloat, side: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { column in
                        cellView(index: displayIndex(row: row, column: column), square: square)
                    }
                }
            }
        }
        .frame(width: side, height: side)
    }

    private func displayIndex(row: Int, column: Int) -> Int {
        flipped ? 63 - (row * 8 + column) : row * 8 + column
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(footerText)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(selected == nil ? Color.white.opacity(0.38)
                                                 : Theme.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if edited != nil {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { edited = nil; selected = nil }
                } label: {
                    Text("UNDO")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
            Button {
                withAnimation(.snappy(duration: 0.35)) { flipped.toggle() }
            } label: {
                Text(flipped ? "BLACK VIEW" : "WHITE VIEW")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
    }

    private var footerText: String {
        if isPlaceholder { return "START POSITION · WAITING FOR A FRAME" }
        if let selected { return "SELECTED " + squareName }
        return edited == nil ? "DRAG A PIECE OR TAP A SQUARE" : "EDITED LOCAL PREVIEW · UNDO TO RESET"
    }

    // MARK: Gestures

    private func dragGesture(square: CGFloat, side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !isPlaceholder else { return }
                if dragFrom == nil {
                    let index = index(at: value.startLocation, square: square, side: side)
                    let list = symbols
                    guard list.indices.contains(index), list[index] != "." else { return }
                    dragFrom = index
                    moving = list[index]
                    selected = index
                }
                dragOffset = CGSize(
                    width: CGFloat(indexedColumn(dragFrom ?? 0)) * square + value.translation.width,
                    height: CGFloat(indexedRow(dragFrom ?? 0)) * square + value.translation.height
                )
            }
            .onEnded { value in
                defer {
                    withAnimation(.snappy(duration: 0.2)) {
                        dragFrom = nil
                        moving = nil
                        dragOffset = .zero
                    }
                }
                guard let from = dragFrom, !isPlaceholder else { return }
                let target = index(at: value.location, square: square, side: side)
                guard target != from else { return }
                var list = symbols
                list[target] = list[from]
                list[from] = "."
                withAnimation(.snappy(duration: 0.22)) {
                    edited = list
                    selected = target
                }
            }
    }

    /// Board index for a point, honouring the flip.
    private func index(at point: CGPoint, square: CGFloat, side: CGFloat) -> Int {
        let column = min(7, max(0, Int(point.x / square)))
        let row = min(7, max(0, Int(point.y / square)))
        return displayIndex(row: row, column: column)
    }

    private func indexedRow(_ index: Int) -> Int { flipped ? 7 - index / 8 : index / 8 }
    private func indexedColumn(_ index: Int) -> Int { flipped ? 7 - index % 8 : index % 8 }

    // MARK: Cells

    @ViewBuilder
    private func cellView(index: Int, square: CGFloat) -> some View {
        let cell = cells.indices.contains(index) ? cells[index] : nil
        let marked = highlight.contains(index)
        let isSelected = selected == index
        ZStack {
            Rectangle()
                .fill(cell?.light == true ? Theme.squareLight : Theme.squareDark)
            if marked {
                Rectangle().fill(Theme.gold.opacity(0.45))
            }
            if isSelected {
                Rectangle().strokeBorder(Theme.gold, lineWidth: 2.5)
            }
            if let cell, !cell.asset.isEmpty, dragFrom != index {
                Image(cell.asset)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(square * 0.07)
            }
        }
        .frame(width: square, height: square)
        .onTapGesture {
            withAnimation(.snappy(duration: 0.18)) {
                selected = selected == index ? nil : index
            }
        }
    }
}
