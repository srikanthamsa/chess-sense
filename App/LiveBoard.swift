import SwiftUI

/// The line the user has played on top of the read position.
///
/// Kept outside `LiveBoard` so the undo/redo/reset controls can sit in the pinned bar where a
/// thumb reaches them, while the board stays a pure view of the state.
@MainActor
final class BoardSession: ObservableObject {
    @Published var history: [String] = []
    @Published var redoStack: [String] = []
    @Published var selected: Int?
    @Published var rejected: Bool = false
    @Published var flipped: Bool = false

    var current: String? { history.last }
    var canUndo: Bool { !history.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isModified: Bool { !history.isEmpty }

    func reset() {
        history = []
        redoStack = []
        selected = nil
        rejected = false
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        redoStack.append(previous)
        selected = nil
        rejected = false
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        history.append(next)
        selected = nil
        rejected = false
    }

    func play(_ fen: String) {
        history.append(fen)
        redoStack.removeAll()
        selected = nil
        rejected = false
    }
}

/// The board, playable.
///
/// Tap a piece, then tap its destination. Only legal moves are accepted — the same move
/// generator the analyser trusts decides legality, so the board cannot invent a move the
/// position does not contain. Undo and redo are stacks of whole positions, which stays exact
/// through castles, captures and promotions.
struct LiveBoard: View {
    let fen: String
    var highlight: [Int] = []
    var isPlaceholder: Bool = false
    @ObservedObject var session: BoardSession


    private let accent = Color(red: 0.831, green: 0.659, blue: 0.353)
    private var flipped: Bool { session.flipped }

    private var currentFEN: String { session.current ?? fen }

    private var position: ChessPosition? {
        // Failable on purpose: a malformed FEN must not take the board down.
        ChessPosition(fen: currentFEN)
    }

    private var cells: [(asset: String, light: Bool)] {
        let board = currentFEN.split(separator: " ").first.map(String.init) ?? currentFEN
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
            let light = (index / 8 + index % 8) % 2 == 0
            return (Self.assetName(symbol), light)
        }
    }

    private var legalTargets: [Int] {
        guard let selected = session.selected, let position else { return [] }
        return MoveGenerator.legalMoves(in: position)
            .filter { $0.from == selected }
            .map(\.to)
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

    var body: some View {
        GeometryReader { geo in
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .opacity(isPlaceholder && !session.isModified ? 0.5 : 1)
        .animation(.snappy(duration: 0.3), value: isPlaceholder)
        .onChange(of: fen) { _, _ in session.reset() }
    }

    private func tap(_ index: Int) {
        guard let position else { return }

        if let from = session.selected, from != index {
            let candidates = MoveGenerator.legalMoves(in: position)
                .filter { $0.from == from && $0.to == index }
            if let move = candidates.first {
                let next = position.applying(move)
                withAnimation(.snappy(duration: 0.24)) { session.play(next.fen) }
                return
            }
            if case let .piece(_, colour) = position.board[index], colour == position.sideToMove {
                withAnimation(.snappy(duration: 0.2)) {
                    session.selected = index
                    session.rejected = false
                }
                return
            }
            withAnimation(.easeOut(duration: 0.15)) {
                session.rejected = true
                session.selected = nil
            }
            return
        }

        guard case let .piece(_, colour) = position.board[index], colour == position.sideToMove else {
            withAnimation(.snappy(duration: 0.2)) { session.selected = nil }
            return
        }
        withAnimation(.snappy(duration: 0.2)) {
            session.selected = session.selected == index ? nil : index
            session.rejected = false
        }
    }

    @ViewBuilder
    private func cellView(index: Int, square: CGFloat) -> some View {
        let cell = cells.indices.contains(index) ? cells[index] : nil
        let marked = highlight.contains(index)
        let isSelected = session.selected == index
        let isTarget = legalTargets.contains(index)

        ZStack {
            Rectangle()
                .fill(cell?.light == true
                      ? Color(red: 0.941, green: 0.851, blue: 0.710)
                      : Color(red: 0.710, green: 0.533, blue: 0.388))
            if marked {
                Rectangle().fill(accent.opacity(0.30))
            }
            if isSelected {
                Rectangle().fill(accent.opacity(0.24))
            }
            if let cell, !cell.asset.isEmpty {
                Image(cell.asset)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(square * 0.07)
            }
            if isTarget {
                Circle()
                    .fill(Color.black.opacity(0.20))
                    .frame(width: square * 0.22, height: square * 0.22)
            }
        }
        .frame(width: square, height: square)
        .contentShape(Rectangle())
        .onTapGesture { tap(index) }
    }
}
