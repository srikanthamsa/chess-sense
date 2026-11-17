import Foundation

struct EngineMove: Sendable {
    /// UCI, e.g. "e2e4".
    let uci: String
    /// Principal variation, space separated.
    let principalVariation: String
    let evalText: String
    let provenance: String
}

enum EngineError: Error, CustomStringConvertible {
    case notCached
    case badResponse(Int)
    case noMove

    var description: String {
        switch self {
        case .notCached: return "position not in cloud cache"
        case let .badResponse(code): return "engine responded \(code)"
        case .noMove: return "engine returned no move"
        }
    }
}

/// Lichess runs a public cloud evaluation service: no key, no rate limit at this volume,
/// depth 30+ for common positions. A 404 simply means the position isn't cached, which is
/// the cue to fall back (local Stockfish, or just report "no engine" for now).
enum EngineClient {
    static let endpoint = URL(string: "https://lichess.org/api/cloud-eval")!

    static func bestMove(fen: String) async throws -> EngineMove {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "fen", value: fen),
            URLQueryItem(name: "multiPv", value: "1"),
        ]
        guard let url = components.url else { throw EngineError.badResponse(-1) }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 6

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EngineError.badResponse(-1)
        }
        if http.statusCode == 404 { throw EngineError.notCached }
        guard http.statusCode == 200 else { throw EngineError.badResponse(http.statusCode) }
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> EngineMove {
        struct Payload: Decodable {
            struct PV: Decodable {
                let moves: String
                let cp: Int?
                let mate: Int?
            }
            let depth: Int
            let pvs: [PV]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let first = payload.pvs.first else { throw EngineError.noMove }
        let moves = first.moves.split(separator: " ").map(String.init)
        guard let uci = moves.first else { throw EngineError.noMove }

        let evalText: String
        if let mate = first.mate {
            evalText = mate > 0 ? "#\(mate)" : "-#\(-mate)"
        } else if let cp = first.cp {
            evalText = String(format: "%+.2f", Double(cp) / 100.0)
        } else {
            evalText = "?"
        }

        return EngineMove(
            uci: uci,
            principalVariation: moves.prefix(6).joined(separator: " "),
            evalText: evalText,
            provenance: "lichess cloud · d\(payload.depth)"
        )
    }
}
