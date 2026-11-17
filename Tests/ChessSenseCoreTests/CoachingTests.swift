import XCTest
@testable import ChessSenseCore

/// The "why" line must be understandable with zero chess knowledge, so the tests assert
/// the absence of notation, not just the presence of words.
final class CoachingTests: XCTestCase {

    private func position(_ fen: String) throws -> ChessPosition {
        try XCTUnwrap(ChessPosition(fen: fen))
    }

    private func explain(_ uci: String, _ fen: String, eval: String? = "+0.20") throws -> String {
        let pos = try position(fen)
        let move = try XCTUnwrap(pos.move(uci: uci), "\(uci) illegal")
        return MoveExplainer.explain(move: move, in: pos, evalText: eval)
    }

    private static let start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    /// No square names, no piece letters, no x / + / #.
    private func assertNoNotation(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(text.range(of: "\\b[a-h][1-8]\\b", options: .regularExpression),
                     "square name leaked: \(text)", file: file, line: line)
        XCTAssertNil(text.range(of: "\\b[NBRQK][a-h]?[1-8]?\\b", options: .regularExpression),
                     "piece letter leaked: \(text)", file: file, line: line)
        XCTAssertFalse(text.contains("x"), "capture mark leaked: \(text)", file: file, line: line)
        XCTAssertFalse(text.contains("#"), "mate mark leaked: \(text)", file: file, line: line)
        XCTAssertFalse(text.contains("O-O"), "castling notation leaked: \(text)", file: file, line: line)
    }

    func testPawnAdvance() throws {
        let text = try explain("e2e4", Self.start)
        assertNoNotation(text)
        XCTAssertTrue(text.lowercased().contains("pawn"))
    }

    func testKnightDevelopment() throws {
        let text = try explain("g1f3", Self.start)
        assertNoNotation(text)
        XCTAssertTrue(text.lowercased().contains("knight"))
        XCTAssertTrue(text.lowercased().contains("centre") || text.lowercased().contains("center"))
    }

    func testCaptureNamesThePieceNotTheSquare() throws {
        let text = try explain("e4d5", "4k3/8/8/3p4/4Q3/8/8/4K3 w - - 0 1")
        assertNoNotation(text)
        XCTAssertTrue(text.lowercased().contains("take"), text)
        XCTAssertTrue(text.lowercased().contains("pawn"), text)
    }

    func testCastlingIsDescribedInWords() throws {
        let text = try explain("e1g1", "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        assertNoNotation(text)
        XCTAssertTrue(text.lowercased().contains("castle") || text.lowercased().contains("king"), text)
    }

    func testCheckMateIsStatedPlainly() throws {
        let text = try explain("a1a8", "6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1", eval: "#1")
        assertNoNotation(text)
        XCTAssertTrue(text.lowercased().contains("checkmate"), text)
    }

    func testEvaluationVerdict() {
        XCTAssertEqual(MoveExplainer.verdict(for: "+0.10"), "The position is roughly balanced.")
        XCTAssertEqual(MoveExplainer.verdict(for: "+0.90"), "You are a little better.")
        XCTAssertEqual(MoveExplainer.verdict(for: "-1.80"), "You are clearly worse.")
        XCTAssertEqual(MoveExplainer.verdict(for: "+4.00"), "You are winning comfortably.")
        XCTAssertNil(MoveExplainer.verdict(for: nil))
    }

    // MARK: - DeepSeek

    actor MockPost: EngineTransport {
        var lastBody: Data?
        var lastHeaders: [String: String] = [:]
        let payload: String
        let code: Int

        init(payload: String, code: Int = 200) {
            self.payload = payload
            self.code = code
        }

        func get(_ url: URL) async throws -> (Data, Int) { (Data(), 404) }

        func post(_ url: URL, body: Data?, headers: [String: String]) async throws -> (Data, Int) {
            lastBody = body
            lastHeaders = headers
            return (Data(payload.utf8), code)
        }
    }

    func testCoachSendsTheNoNotationInstructionAndReturnsProse() async throws {
        let reply = #"{"choices":[{"message":{"content":"Your knight comes out towards the middle, where it controls the most squares."}}]}"#
        let transport = MockPost(payload: reply)
        let coach = DeepSeekCoach(apiKey: "sk-test")
        let pos = try position(Self.start)
        let move = try XCTUnwrap(pos.move(uci: "g1f3"))

        let text = try await coach.explain(
            move: move, in: pos, evalText: "+0.20", san: "Nf3",
            principalVariation: "g1f3 e7e5", transport: transport
        )

        XCTAssertEqual(text, "Your knight comes out towards the middle, where it controls the most squares.")
        let capturedBody = await transport.lastBody
        let body = try XCTUnwrap(capturedBody)
        let json = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(json.contains("Never use chess notation"), json)
        XCTAssertTrue(json.contains("deepseek-chat"), json)
        let headers = await transport.lastHeaders
        XCTAssertEqual(headers["Authorization"], "Bearer sk-test")
    }

    func testUnconfiguredCoachDoesNothing() async throws {
        let coach = DeepSeekCoach(apiKey: "  ")
        XCTAssertFalse(coach.isConfigured)
        let pos = try position(Self.start)
        let move = try XCTUnwrap(pos.move(uci: "e2e4"))
        let text = try await coach.explain(
            move: move, in: pos, evalText: "0.00", san: "e4", principalVariation: "e2e4"
        )
        XCTAssertNil(text)
    }

    func testSanitizerRemovesNotationThatSlipsThrough() {
        let cleaned = DeepSeekCoach.sanitize("Your knight hops to f3 and eyes e5, developing nicely.")
        let text = cleaned ?? ""
        XCTAssertFalse(text.isEmpty)
        XCTAssertNil(text.range(of: "\\b[a-h][1-8]\\b", options: .regularExpression), text)
        XCTAssertTrue(text.contains("developing"), text)
    }
}

/// The Island tip is bounded at the source, so the view never truncates.
final class IslandTipTests: XCTestCase {

    private func position(_ fen: String) throws -> ChessPosition {
        try XCTUnwrap(ChessPosition(fen: fen))
    }

    private func tip(_ uci: String, _ fen: String, eval: String? = "+0.30") throws -> String {
        let pos = try position(fen)
        let move = try XCTUnwrap(pos.move(uci: uci), "\(uci) illegal")
        return MoveExplainer.islandTip(move: move, in: pos, evalText: eval)
    }

    /// Every realistic move type must produce a tip that fits two lines at subheadline size.
    func testEveryTipFitsTheLimit() throws {
        let cases: [(String, String)] = [
            ("e2e4", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"),
            ("g1f3", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"),
            ("e4d5", "4k3/8/8/3p4/4Q3/8/8/4K3 w - - 0 1"),
            ("e1g1", "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"),
            ("a7a8q", "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"),
            ("a1a8", "6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1"),
            ("e5c6", "r3kbnr/pp3ppp/1qn1p3/3pNbB1/3P4/1B6/PPP2PPP/RN1QK2R w - - 0 1"),
        ]
        for (uci, fen) in cases {
            let text = try tip(uci, fen)
            XCTAssertLessThanOrEqual(text.count, MoveExplainer.islandTipLimit, "\(uci): \(text)")
            XCTAssertFalse(text.contains("…"), "no ellipsis allowed: \(text)")
            XCTAssertFalse(text.contains("..."), "no ellipsis allowed: \(text)")
            XCTAssertFalse(text.isEmpty, uci)
            // Sentence-shaped: starts with a capital, no dangling punctuation.
            XCTAssertTrue(text.first?.isUppercase ?? false, text)
            XCTAssertFalse([",", "-", ":", ";"].contains(String(text.last ?? " ")), text)
        }
    }

    /// The worst case the UI must survive: a long model answer.
    func testOverlongCopyIsCutWithoutAnEllipsis() {
        let long = "Your rook slides all the way across the back row to join its partner and double the attack on the open file"
        let clamped = MoveExplainer.clamped(long)
        XCTAssertLessThanOrEqual(clamped.count, MoveExplainer.islandTipLimit)
        XCTAssertFalse(clamped.contains("…"))
        XCTAssertFalse(clamped.contains("..."))
        XCTAssertFalse(clamped.hasSuffix(" "), "no trailing space")
        // Never sliced mid-word.
        XCTAssertFalse(clamped.hasSuffix("do"), clamped)
        XCTAssertEqual(MoveExplainer.clamped("Short."), "Short.")
    }

    func testNoTipContainsNotation() throws {
        let text = try tip("g1f3", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        XCTAssertNil(text.range(of: "\\b[a-h][1-8]\\b", options: .regularExpression), text)
        XCTAssertFalse(text.contains("x"), text)
        XCTAssertFalse(text.contains("+"), text)
    }
}

final class TipClampingTests: XCTestCase {
    func testCompleteSentenceWins() {
        let raw = "Your queen moves left. It puts his king in check, so he must"
        XCTAssertEqual(MoveExplainer.clamped(raw), "Your queen moves left.")
    }

    func testWordBoundaryWhenNoSentenceFits() {
        let clamped = MoveExplainer.clamped(
            "Your rook slides all the way across the back row to join its partner"
        )
        XCTAssertLessThanOrEqual(clamped.count, MoveExplainer.islandTipLimit)
        XCTAssertFalse(clamped.hasSuffix(" "), clamped)
        XCTAssertFalse(clamped.contains("…"), clamped)
    }

    func testShortCopyIsUntouched() {
        XCTAssertEqual(MoveExplainer.clamped("Your pawn takes the centre."),
                       "Your pawn takes the centre.")
    }
}
