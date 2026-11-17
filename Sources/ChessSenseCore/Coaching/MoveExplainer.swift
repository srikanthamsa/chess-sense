import Foundation

/// Turns a move into plain English with no chess notation at all.
///
/// This is the offline fallback for the "why" line, and the source of the facts handed to
/// the language model when one is configured. Everything here is derived from the rules
/// module, so it can never describe a move that did not happen.
public enum MoveExplainer {
    /// One or two sentences a beginner can act on. No square names, no `Nf3`, no `x`, `+`, `#`.
    public static func explain(
        move: Move,
        in position: ChessPosition,
        evalText: String?
    ) -> String {
        let mover = position.board[move.from]
        var kind: PieceKind = .pawn
        var color: PieceColor = .white
        if case let .piece(k, c) = mover { kind = k; color = c }

        var sentences: [String] = []

        // --- what happened -------------------------------------------------------
        if move.isCastle {
            sentences.append(move.isKingsideCastle
                ? "You tuck your king into the corner and bring a rook towards the middle."
                : "You castle long: king to safety and a rook onto a central file.")
        } else if let capturedPiece = capturedPiece(for: move, in: position) {
            sentences.append("You take \(article(capturedPiece, of: color)) with your "
                + "\(pieceName(kind)).")
        } else if let promotion = move.promotion {
            sentences.append("Your pawn reaches the far end and becomes a \(pieceName(promotion)).")
        } else {
            sentences.append("Your \(pieceName(kind)) moves \(plainDirection(from: move.from, to: move.to)).")
        }

        // --- what it gains -------------------------------------------------------
        let after = position.applying(move)
        if after.isInCheck {
            let replies = MoveGenerator.legalMoves(in: after)
            sentences.append(replies.isEmpty
                ? "That is checkmate — the game is over."
                : "It puts his king in check, so he must respond before doing anything else.")
        }

        if !after.isInCheck, let gain = positionalGain(kind: kind, move: move, after: after) {
            sentences.append(gain)
        }

        // --- what it means for the result ---------------------------------------
        if let verdict = verdict(for: evalText), !sentences.contains(where: { $0.contains("checkmate") }) {
            sentences.append(verdict)
        }

        return sentences.prefix(2).joined(separator: " ")
    }

    // MARK: - Island tip

    /// One sentence, one idea, guaranteed to fit two lines in the Dynamic Island.
    ///
    /// The Island has no room for a paragraph and must never end in an ellipsis, so the copy
    /// is constrained *here*, at the source, rather than clipped in the view. The full
    /// explanation stays in the app and on the lock screen.
    public static let islandTipLimit = 60

    public static func islandTip(
        move: Move,
        in position: ChessPosition,
        evalText: String?
    ) -> String {
        let mover = position.board[move.from]
        var kind: PieceKind = .pawn
        var color: PieceColor = .white
        if case let .piece(k, c) = mover { kind = k; color = c }

        let after = position.applying(move)
        let isMate = after.isInCheck && MoveGenerator.legalMoves(in: after).isEmpty
        let isCheck = after.isInCheck
        let captured = capturedPiece(for: move, in: position)
        var capturedKind: PieceKind?
        if case let .piece(k, _) = captured ?? .empty { capturedKind = k }

        // Ordered by how much the fact changes the player's understanding.
        let candidate: String
        if isMate {
            candidate = "Checkmate — his king has nowhere to run."
        } else if let promo = move.promotion {
            candidate = "Your pawn promotes to a \(pieceName(promo))."
        } else if move.isCastle {
            candidate = "You castle, tucking the king away and waking a rook."
        } else if let taken = capturedKind, isCheck {
            candidate = "Your \(pieceName(kind)) takes the \(pieceName(taken)) with check."
        } else if let taken = capturedKind {
            candidate = "Your \(pieceName(kind)) takes the \(pieceName(taken))."
        } else if isCheck {
            candidate = "Your \(pieceName(kind)) lands with check."
        } else if [27, 28, 35, 36].contains(move.to) {
            candidate = "Your \(pieceName(kind)) takes the centre."
        } else if kind != .pawn, move.to / 8 >= 2, move.to / 8 <= 5 {
            candidate = "Your \(pieceName(kind)) joins the play in the middle."
        } else if kind == .pawn {
            candidate = "Your pawn gains space and opens a lane."
        } else {
            candidate = "Your \(pieceName(kind)) moves to a better square."
        }
        return clamped(candidate)
    }

    /// Hard guarantee, independent of the wording above or of a model's output: never longer
    /// than the limit and never containing an ellipsis.
    public static func clamped(_ text: String) -> String {
        var trimmed = text.replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.count > islandTipLimit {
            guard let space = trimmed.lastIndex(of: " ") else {
                trimmed = String(trimmed.prefix(islandTipLimit))
                break
            }
            trimmed = String(trimmed[..<space])
        }
        // Tidy a dangling comma or dash left by the cut.
        while let last = trimmed.last, ",;:—- ".contains(last) {
            trimmed.removeLast()
        }
        return trimmed
    }

    // MARK: - Facts

    static func capturedPiece(for move: Move, in position: ChessPosition) -> Piece? {
        if move.isEnPassant {
            return .piece(.pawn, position.sideToMove == .white ? .black : .white)
        }
        let target = position.board[move.to]
        return target.isEmpty ? nil : target
    }

    /// Unicode chess glyph for a piece, as the Island shows it.
    public static func symbol(for kind: PieceKind, color: PieceColor) -> String {
        let white: [PieceKind: String] = [
            .king: "\u{2654}", .queen: "\u{2655}", .rook: "\u{2656}",
            .bishop: "\u{2657}", .knight: "\u{2658}", .pawn: "\u{2659}",
        ]
        let black: [PieceKind: String] = [
            .king: "\u{265A}", .queen: "\u{265B}", .rook: "\u{265C}",
            .bishop: "\u{265D}", .knight: "\u{265E}", .pawn: "\u{265F}",
        ]
        return color == .white ? (white[kind] ?? "") : (black[kind] ?? "")
    }

    static func pieceName(_ kind: PieceKind) -> String {
        switch kind {
        case .pawn: return "pawn"
        case .knight: return "knight"
        case .bishop: return "bishop"
        case .rook: return "rook"
        case .queen: return "queen"
        case .king: return "king"
        }
    }

    static func article(_ piece: Piece, of mover: PieceColor) -> String {
        guard case let .piece(kind, _) = piece else { return "piece" }
        let name = pieceName(kind)
        return (name.first.map { "aeiou".contains($0) } ?? false ? "an " : "a ") + name
    }

    /// Direction in words, avoiding square names entirely.
    static func plainDirection(from: Int, to: Int) -> String {
        let df = fileIndex(to) - fileIndex(from)
        let dr = rankIndex(to) - rankIndex(from)
        let forward = dr < 0 ? "forward" : dr > 0 ? "backward" : ""
        let side = df < 0 ? "left" : df > 0 ? "right" : ""

        if abs(dr) <= 1, abs(df) <= 1, !(dr == 0 && df == 0) {
            if dr == 0 { return side }
            if df == 0 { return forward }
            return "diagonally \(forward)"
        }
        if dr == 0 { return "\(side), along the same row" }
        if df == 0 { return "straight \(forward)" }
        return "\(forward) and \(side)"
    }

    /// Why the move is good, in one clause, when it clearly is.
    static func positionalGain(kind: PieceKind, move: Move, after: ChessPosition) -> String? {
        let centre = [27, 28, 35, 36]           // d4, e4, d5, e5
        if centre.contains(move.to) {
            return "That puts it in the middle of the board, where it controls the most squares."
        }
        let nearCentre = [18, 19, 20, 21, 26, 29, 34, 37, 42, 43, 44, 45]
        if nearCentre.contains(move.to), kind != .pawn {
            return "It heads for the centre, which is where pieces do the most work."
        }
        if kind == .pawn, move.to / 8 == 3 || move.to / 8 == 4 {
            return "The pawn grabs space and opens a path for your pieces."
        }
        if kind == .king, after.isInCheck == false {
            return nil
        }
        return nil
    }

    static func verdict(for evalText: String?) -> String? {
        guard let evalText else { return nil }
        if evalText.hasPrefix("#") {
            return "There is a forced mate from here — the win is certain with correct play."
        }
        if evalText.hasPrefix("-#") {
            return "You are about to be mated unless something changes."
        }
        guard let value = Double(evalText.replacingOccurrences(of: "+", with: "")) else { return nil }
        switch abs(value) {
        case ..<0.4: return "The position is roughly balanced."
        case ..<1.2: return value > 0 ? "You are a little better." : "You are a little worse."
        case ..<2.5: return value > 0 ? "You have a clear advantage." : "You are clearly worse."
        default: return value > 0 ? "You are winning comfortably." : "You are in real trouble."
        }
    }
}
