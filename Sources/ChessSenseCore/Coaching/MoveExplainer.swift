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

    // MARK: - Facts

    static func capturedPiece(for move: Move, in position: ChessPosition) -> Piece? {
        if move.isEnPassant {
            return .piece(.pawn, position.sideToMove == .white ? .black : .white)
        }
        let target = position.board[move.to]
        return target.isEmpty ? nil : target
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
