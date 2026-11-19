import Foundation

/// Asks a language model to rephrase the move in beginner language, with chess notation
/// banned explicitly. Used only for the "why" line: the move itself always comes from the
/// engine, never from the model.
public struct DeepSeekCoach: Sendable {
    public static let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    public let apiKey: String
    public let model: String

    public init(apiKey: String, model: String = "deepseek-chat") {
        self.apiKey = apiKey
        self.model = model
    }

    public var isConfigured: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    struct Request: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let messages: [Message]
        let temperature: Double
        let max_tokens: Int
    }

    struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }

    public static func prompt(
        move: Move,
        in position: ChessPosition,
        evalText: String,
        san: String,
        principalVariation: String
    ) -> String {
        let mover = position.board[move.from]
        var kind = "piece"
        if case let .piece(k, _) = mover { kind = MoveExplainer.pieceName(k) }
        return """
        You are a friendly chess coach for a total beginner.

        Explain the move in ONE or TWO short sentences of plain English.

        Hard rules:
        - Never use chess notation of any kind. No square names (e2, f6), no piece letters \
        (Nf3, Qxd5), no symbols (x, +, #, O-O), no evaluation numbers.
        - Describe squares and pieces in ordinary words instead: "the centre", "towards your king", \
        "the left side of the board", "his knight".
        - Say what the move achieves for a beginner: safety, space, development, attacking a piece, \
        trading, defending.
        - Do not repeat the notation. Do not use lists. Do not open with "This move".

        Move being played: a \(kind). (Internal reference only, never quote: \(san))
        Evaluation after the move: \(evalText).
        Engine's suggested continuation (internal only): \(principalVariation)
        """
    }

    /// Returns the explanation, or nil if the service did not give a usable sentence.
    public func explain(
        move: Move,
        in position: ChessPosition,
        evalText: String,
        san: String,
        principalVariation: String,
        transport: any EngineTransport = URLSessionTransport()
    ) async throws -> String? {
        guard isConfigured else { return nil }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8

        let body = Request(
            model: model,
            messages: [
                .init(role: "user", content: Self.prompt(
                    move: move,
                    in: position,
                    evalText: evalText,
                    san: san,
                    principalVariation: principalVariation
                ))
            ],
            temperature: 0.4,
            max_tokens: 90
        )
        request.httpBody = try JSONEncoder().encode(body)

        guard let url = request.url else { return nil }
        let (data, code) = try await transport.post(url, body: request.httpBody, headers: [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json",
        ])
        guard code == 200 else { throw EngineError.badResponse(code) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return Self.sanitize(decoded.choices.first?.message.content)
    }

    /// Strips notation that slipped through, so a model that ignores the instruction cannot
    /// put "Nf3" on the Dynamic Island.
    public static func sanitize(_ text: String?) -> String? {
        guard var text else { return nil }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "\"", with: "")
        // Remove square references like e4, d5.
        for pattern in [
            "\\b[a-h][1-8]\\b",
            "\\b[NBRQK][a-h]?[1-8]?[x-]?[a-h]?[1-8]?[+#]?\\b",
            "O-O(-O)?",
        ] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "  ", with: " ")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 12 else { return nil }
        return text
    }

    // MARK: - Island tip

    /// A version constrained for the Dynamic Island: one sentence, one idea, hard length cap.
    /// The length is enforced in the prompt *and* validated afterwards, so the view never has
    /// to ellipsize. An unusable answer returns nil and the caller keeps the local tip.
    public static func tipPrompt(move: Move, in position: ChessPosition, san: String) -> String {
        let mover = position.board[move.from]
        var kind = "piece"
        if case let .piece(k, _) = mover { kind = MoveExplainer.pieceName(k) }
        return """
        Write ONE sentence of at most 55 characters for a small wrist-sized widget.
        A \(kind) moves. (Internal reference, never quote: \(san))

        Hard rules:
        - At most 55 characters. Shorter is better. Never use an ellipsis.
        - One idea only: what the move achieves.
        - No chess notation of any kind: no square names, no piece letters, no x, +, #, O-O.
        - Plain English. No lists, no quotes, no opening like "This move".
        """
    }

    public func tip(
        move: Move,
        in position: ChessPosition,
        san: String,
        transport: any EngineTransport = URLSessionTransport()
    ) async throws -> String? {
        guard isConfigured else { return nil }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 6

        let body = Request(
            model: model,
            messages: [.init(role: "user",
                             content: Self.tipPrompt(move: move, in: position, san: san))],
            temperature: 0.3,
            max_tokens: 40
        )
        request.httpBody = try JSONEncoder().encode(body)
        guard let url = request.url else { return nil }
        let (data, code) = try await transport.post(url, body: request.httpBody, headers: [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json",
        ])
        guard code == 200 else { throw EngineError.badResponse(code) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let text = Self.sanitize(decoded.choices.first?.message.content) else { return nil }
        let clamped = MoveExplainer.clamped(text)
        return clamped.count >= 12 ? clamped : nil
    }
}
