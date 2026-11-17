import Foundation

public enum EngineError: Error, CustomStringConvertible, Equatable {
    case transport
    case notCached
    case badResponse(Int)
    case noMove
    case allBackendsFailed([String])

    public var description: String {
        switch self {
        case .transport: return "network error"
        case .notCached: return "position not in this backend's cache"
        case let .badResponse(code): return "backend responded \(code)"
        case .noMove: return "backend returned no move"
        case let .allBackendsFailed(reasons):
            return "no engine available (" + reasons.joined(separator: "; ") + ")"
        }
    }
}

/// Seam for testing: the real one is `URLSession`, the test one is a dictionary.
public protocol EngineTransport: Sendable {
    func get(_ url: URL) async throws -> (Data, Int)
}

public struct URLSessionTransport: EngineTransport {
    public init() {}

    public func get(_ url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 6
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (data, code)
    }
}

public protocol EngineBackend: Sendable {
    var name: String { get }
    func evaluate(fen: String, transport: any EngineTransport) async throws -> EngineMove
}

/// Ordered fallbacks. Lichess's cloud evaluation is instant and keyless but only covers
/// positions someone has already asked it about (~85% of real games); the public
/// Stockfish endpoint fills the rest.
public struct EngineChain: Sendable {
    public let backends: [any EngineBackend]

    public init(backends: [any EngineBackend]) {
        self.backends = backends
    }

    public static var `default`: EngineChain {
        EngineChain(backends: [LichessCloudBackend(), StockfishOnlineBackend()])
    }

    public func bestMove(
        fen: String,
        transport: any EngineTransport = URLSessionTransport()
    ) async throws -> EngineMove {
        var reasons: [String] = []
        for backend in backends {
            do {
                return try await backend.evaluate(fen: fen, transport: transport)
            } catch {
                reasons.append("\(backend.name): \(error)")
            }
        }
        throw EngineError.allBackendsFailed(reasons)
    }
}
