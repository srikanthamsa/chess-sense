import Foundation

/// Stockfish 11, running inside the app process.
///
/// iOS forbids spawning helpers, so the unmodified UCI loop is booted on a background thread
/// with its stdin/stdout redirected onto a socketpair (see `CSBridge.cpp`), and this type
/// speaks UCI over that pair. No network, no licence, no per-position cache miss: a
/// middlegame position is answered in a couple of hundred milliseconds at depth 14.
final class LocalStockfishBackend: EngineBackend, @unchecked Sendable {
    /// One engine for the whole app. Booting is expensive and the search state is not
    /// per-caller, so a fresh instance per query would pay the boot cost every time.
    static let shared = LocalStockfishBackend(depth: 12)

    let name = "stockfish 11 · on device"

    private let depth: Int
    private let queue = DispatchQueue(label: "chesssense.stockfish", qos: .userInitiated)
    private var started = false
    private let lock = NSLock()

    init(depth: Int = 14) {
        self.depth = depth
    }

    // MARK: - EngineBackend

    func evaluate(
        fen: String,
        transport: any EngineTransport = URLSessionTransport()
    ) async throws -> EngineMove {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try self.search(fen: fen)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// Boots the engine off the caller's thread.
    ///
    /// Called when the app launches and again when an intent starts, so the UCI handshake
    /// (its own thread, ~50 ms, plus Stockfish's init) is already paid for by the time a
    /// screenshot arrives. The shutter-to-answer delay is dominated by things like this that
    /// happen once, not by the search.
    func warmUp() {
        queue.async {
            try? withUnsafeMutablePointer(to: &self.started) { _ in _ = self.tryBoot() }
        }
    }

    private func tryBoot() -> Bool {
        do { try boot(); return true } catch { return false }
    }

    /// True once the engine has answered `uci`. Used by the status pane.
    var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return started && cs_engine_is_running() == 1
    }

    // MARK: - UCI

    private func search(fen: String) throws -> EngineMove {
        try boot()

        try send("position fen \(fen)")
        try send("go depth \(depth)")

        var evalText = "+0.00"
        var principalVariation = ""
        let deadline = Date().addingTimeInterval(12)

        while Date() < deadline {
            let line = try readLine(timeout: 240, until: deadline)
            if line.hasPrefix("bestmove") {
                let parts = line.split(separator: " ").map(String.init)
                guard let best = parts.dropFirst().first, best != "(none)" else {
                    throw EngineError.noMove
                }
                return EngineMove(
                    uci: best,
                    principalVariation: principalVariation,
                    evalText: evalText,
                    provenance: name
                )
            }
            if line.hasPrefix("info"), line.contains(" pv ") {
                if let parsed = Self.parseInfo(line) {
                    evalText = parsed.eval
                    principalVariation = parsed.pv
                }
            }
        }
        throw EngineError.transport
    }

    private func boot() throws {
        lock.lock()
        defer { lock.unlock() }
        if started { return }

        guard cs_engine_start() == 0 else { throw EngineError.transport }
        try send("uci")
        while true {
            let line = try readLine(timeout: 2000, until: Date().addingTimeInterval(20))
            if line == "uciok" { break }
        }
        // One search thread is plenty at this depth, and it keeps the phone cool.
        try send("setoption name Threads value 1")
        try send("setoption name Hash value 16")
        try send("isready")
        while true {
            let line = try readLine(timeout: 2000, until: Date().addingTimeInterval(20))
            if line == "readyok" { break }
        }
        started = true
    }

    private func send(_ command: String) throws {
        let status = command.withCString { cs_engine_send($0) }
        guard status == 0 else { throw EngineError.transport }
    }

    private func readLine(timeout: Int32, until deadline: Date) throws -> String {
        var buffer = [CChar](repeating: 0, count: 8192)
        while Date() < deadline {
            let status = cs_engine_read_line(&buffer, Int32(buffer.count), timeout)
            if status == 1 { return String(cString: buffer) }
            if status < 0 { throw EngineError.transport }
        }
        throw EngineError.transport
    }

    /// `info depth 14 seldepth 20 score cp 24 nodes ... pv e2e4 e7e5 ...`
    static func parseInfo(_ line: String) -> (eval: String, pv: String)? {
        let tokens = line.split(separator: " ").map(String.init)
        var evalText: String?
        var pv = ""

        for (index, token) in tokens.enumerated() {
            if token == "cp", index + 1 < tokens.count, let value = Int(tokens[index + 1]) {
                let pawns = Double(value) / 100
                evalText = String(format: "%+.2f", pawns)
            }
            if token == "mate", index + 1 < tokens.count, let value = Int(tokens[index + 1]) {
                evalText = value >= 0 ? "#\(value)" : "-#\(abs(value))"
            }
            if token == "pv" {
                pv = tokens[(index + 1)...].joined(separator: " ")
                break
            }
        }
        guard let evalText else { return nil }
        return (evalText, pv)
    }
}
