import Foundation

/// `GET https://lichess.org/api/cloud-eval?fen=...&multiPv=1`
/// → `{"depth":75,"pvs":[{"moves":"e2e4 e7e5 ...","cp":19}]}`
/// A 404 means "this position isn't cached", which is the cue to fall through.
public struct LichessCloudBackend: EngineBackend {
    public let name = "lichess cloud"

    public init() {}

    public func evaluate(fen: String, transport: any EngineTransport) async throws -> EngineMove {
        var components = URLComponents(
            string: "https://lichess.org/api/cloud-eval"
        )!
        components.queryItems = [
            URLQueryItem(name: "fen", value: fen),
            URLQueryItem(name: "multiPv", value: "1"),
        ]
        guard let url = components.url else { throw EngineError.badResponse(-1) }

        let (data, code) = try await transport.get(url)
        if code == 404 { throw EngineError.notCached }
        guard code == 200 else { throw EngineError.badResponse(code) }

        struct Payload: Decodable {
            struct PV: Decodable {
                let moves: String
                let cp: Int?
                let mate: Int?
            }
            let depth: Int
            let pvs: [PV]?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let first = payload.pvs?.first
        else { throw EngineError.noMove }

        let moves = first.moves.split(separator: " ").map(String.init)
        guard let uci = moves.first else { throw EngineError.noMove }

        let eval: String
        if let mate = first.mate {
            eval = mate > 0 ? "#\(mate)" : "-#\(-mate)"
        } else if let cp = first.cp {
            eval = String(format: "%+.2f", Double(cp) / 100.0)
        } else {
            eval = "?"
        }

        return EngineMove(
            uci: uci,
            principalVariation: moves.prefix(6).joined(separator: " "),
            evalText: eval,
            provenance: "lichess cloud · d\(payload.depth)"
        )
    }
}

/// `GET https://stockfish.online/api/s/v2.php?fen=...&depth=N`
/// → `{"success":true,"evaluation":0.4,"mate":null,
///     "bestmove":"bestmove e2e4 ponder c7c5","continuation":"e2e4 c7c5 ..."}`
public struct StockfishOnlineBackend: EngineBackend {
    public let name = "stockfish.online"
    public let depth: Int

    public init(depth: Int = 12) {
        self.depth = depth
    }

    public func evaluate(fen: String, transport: any EngineTransport) async throws -> EngineMove {
        var components = URLComponents(string: "https://stockfish.online/api/s/v2.php")!
        components.queryItems = [
            URLQueryItem(name: "fen", value: fen),
            URLQueryItem(name: "depth", value: String(depth)),
        ]
        guard let url = components.url else { throw EngineError.badResponse(-1) }

        let (data, code) = try await transport.get(url)
        guard code == 200 else { throw EngineError.badResponse(code) }

        struct Payload: Decodable {
            let success: Bool
            let evaluation: Double?
            let mate: Int?
            let bestmove: String?
            let continuation: String?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.success
        else { throw EngineError.noMove }

        // "bestmove e2e4 ponder c7c5"
        let tokens = (payload.bestmove ?? "").split(separator: " ").map(String.init)
        guard let bestIndex = tokens.firstIndex(of: "bestmove"),
              tokens.index(after: bestIndex) < tokens.endIndex
        else { throw EngineError.noMove }
        let uci = tokens[tokens.index(after: bestIndex)]

        let eval: String
        if let mate = payload.mate {
            eval = mate > 0 ? "#\(mate)" : "-#\(-mate)"
        } else if let value = payload.evaluation {
            eval = String(format: "%+.2f", value)
        } else {
            eval = "?"
        }

        return EngineMove(
            uci: uci,
            principalVariation: payload.continuation ?? uci,
            evalText: eval,
            provenance: "stockfish.online · d\(depth)"
        )
    }
}

/// Serialises engine calls per position so repeated screenshots of the same frame cost
/// nothing. Actor because the pipeline may be hit from an intent while the app is open.
public actor EngineCache {
    private var storage: [String: EngineMove] = [:]
    private let capacity: Int

    public init(capacity: Int = 64) {
        self.capacity = capacity
    }

    public func cached(_ fen: String) -> EngineMove? { storage[fen] }

    public func store(_ move: EngineMove, for fen: String) {
        if storage.count >= capacity, let first = storage.keys.first {
            storage.removeValue(forKey: first)
        }
        storage[fen] = move
    }

    public func value(
        for fen: String,
        chain: EngineChain,
        transport: any EngineTransport = URLSessionTransport()
    ) async throws -> EngineMove {
        if let hit = storage[fen] { return hit }
        let move = try await chain.bestMove(fen: fen, transport: transport)
        store(move, for: fen)
        return move
    }
}
