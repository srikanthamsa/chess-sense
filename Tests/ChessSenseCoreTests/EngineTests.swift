import XCTest
@testable import ChessSenseCore

/// Backends are tested against payloads captured from the live services, and the
/// fallback chain is tested against a mock transport so no test needs the network.
final class EngineTests: XCTestCase {

    // Captured: GET lichess.org/api/cloud-eval?fen=<start>&multiPv=1
    static let lichessStart = #"""
    {"fen":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","knodes":695524,"depth":75,"pvs":[{"moves":"e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 d2d3 f8c5 e1h1 d7d6","cp":19}]}
    """#

    // Captured: GET stockfish.online/api/s/v2.php?fen=<start>&depth=10
    static let stockfishStart = #"""
    {"success":true,"evaluation":0.4,"mate":null,"bestmove":"bestmove e2e4 ponder c7c5","continuation":"e2e4 c7c5 g1f3 b8c6 b1c3 g8f6 d2d4 c5d4 f3d4 e7e6 d4c6 b7c6"}
    """#

    enum MockError: Error { case unexpectedHost }

    actor MockTransport: EngineTransport {
        struct Response: Sendable {
            let data: Data
            let code: Int
        }
        private var responses: [String: Response]
        private(set) var calls = 0
        private(set) var hosts: [String] = []

        init(_ responses: [String: Response] = [:]) {
            self.responses = responses
        }

        func get(_ url: URL) async throws -> (Data, Int) {
            calls += 1
            let host = url.host ?? "<none>"
            hosts.append(host)
            guard let response = responses[host] else { throw MockError.unexpectedHost }
            return (response.data, response.code)
        }

        func callCount() -> Int { calls }
    }

    // MARK: - Lichess

    func testLichessDecodesCloudEval() async throws {
        let transport = MockTransport([
            "lichess.org": .init(data: Data(Self.lichessStart.utf8), code: 200),
        ])
        let move = try await LichessCloudBackend().evaluate(
            fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            transport: transport
        )
        XCTAssertEqual(move.uci, "e2e4")
        XCTAssertEqual(move.evalText, "+0.19")
        XCTAssertEqual(move.principalVariation.split(separator: " ").count, 6)
        XCTAssertTrue(move.provenance.contains("d75"))
    }

    func testLichess404MeansNotCached() async {
        let transport = MockTransport([
            "lichess.org": .init(data: Data("{}".utf8), code: 404),
        ])
        do {
            _ = try await LichessCloudBackend().evaluate(fen: "8/8/8/8/8/8/8/8 w - - 0 1",
                                                         transport: transport)
            XCTFail("expected notCached")
        } catch {
            XCTAssertEqual(error as? EngineError, .notCached)
        }
    }

    // MARK: - Stockfish.online

    func testStockfishStripsTheBestmovePrefix() async throws {
        let transport = MockTransport([
            "stockfish.online": .init(data: Data(Self.stockfishStart.utf8), code: 200),
        ])
        let move = try await StockfishOnlineBackend(depth: 10).evaluate(
            fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            transport: transport
        )
        XCTAssertEqual(move.uci, "e2e4")
        XCTAssertEqual(move.evalText, "+0.40")
        XCTAssertTrue(move.principalVariation.hasPrefix("e2e4 c7c5"))
    }

    func testStockfishReportsMate() async throws {
        let payload = #"{"success":true,"evaluation":null,"mate":3,"bestmove":"bestmove a1a8","continuation":"a1a8"}"#
        let transport = MockTransport([
            "stockfish.online": .init(data: Data(payload.utf8), code: 200),
        ])
        let move = try await StockfishOnlineBackend(depth: 8).evaluate(fen: "", transport: transport)
        XCTAssertEqual(move.evalText, "#3")
    }

    // MARK: - Chain

    func testChainFallsThroughWhenLichessMisses() async throws {
        let transport = MockTransport([
            "lichess.org": .init(data: Data("{}".utf8), code: 404),
            "stockfish.online": .init(data: Data(Self.stockfishStart.utf8), code: 200),
        ])
        let move = try await EngineChain.default.bestMove(fen: "fen", transport: transport)
        XCTAssertEqual(move.uci, "e2e4")
        XCTAssertTrue(move.provenance.contains("stockfish.online"))
        let hosts = await transport.hosts
        XCTAssertEqual(hosts, ["lichess.org", "stockfish.online"], "backend order matters")
    }

    func testChainPrefersLichessWhenItHasThePosition() async throws {
        let transport = MockTransport([
            "lichess.org": .init(data: Data(Self.lichessStart.utf8), code: 200),
        ])
        let move = try await EngineChain.default.bestMove(fen: "fen", transport: transport)
        XCTAssertTrue(move.provenance.contains("lichess"))
        let count = await transport.callCount()
        XCTAssertEqual(count, 1, "the fallback must not be called when the first works")
    }

    func testChainReportsEveryFailure() async {
        let transport = MockTransport([
            "lichess.org": .init(data: Data("{}".utf8), code: 404),
            "stockfish.online": .init(data: Data("{}".utf8), code: 500),
        ])
        do {
            _ = try await EngineChain.default.bestMove(fen: "fen", transport: transport)
            XCTFail("expected failure")
        } catch let error as EngineError {
            guard case let .allBackendsFailed(reasons) = error else {
                return XCTFail("got \(error)")
            }
            XCTAssertEqual(reasons.count, 2)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: - Cache

    func testCacheAvoidsASecondRequest() async throws {
        let transport = MockTransport([
            "lichess.org": .init(data: Data(Self.lichessStart.utf8), code: 200),
        ])
        let cache = EngineCache()
        let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        _ = try await cache.value(for: fen, chain: .default, transport: transport)
        _ = try await cache.value(for: fen, chain: .default, transport: transport)
        let count = await transport.callCount()
        XCTAssertEqual(count, 1)
    }

    // MARK: - Presentation

    func testDisplayPrefersSAN() {
        let withSAN = EngineMove(uci: "g1f3", san: "Nf3",
                                 principalVariation: "g1f3", evalText: "+0.30",
                                 provenance: "test")
        XCTAssertEqual(withSAN.displayMove, "Nf3")

        let withoutSAN = EngineMove(uci: "g1f3", principalVariation: "", evalText: "0.00",
                                    provenance: "test")
        XCTAssertEqual(withoutSAN.displayMove, "g1\u{2013}f3")
    }

    func testPrincipalVariationRendersAsSAN() throws {
        let position = try XCTUnwrap(ChessPosition(
            fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        ))
        let move = EngineMove(uci: "e2e4",
                              principalVariation: "e2e4 e7e5 g1f3 b8c6",
                              evalText: "+0.19", provenance: "test")
        XCTAssertEqual(move.principalVariationSAN(from: position), "e4 e5 Nf3 Nc6")
    }
}
