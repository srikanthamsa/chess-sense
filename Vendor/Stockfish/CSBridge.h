#ifndef CS_ENGINE_BRIDGE_H
#define CS_ENGINE_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

/// Boots Stockfish's UCI loop on a background thread.
///
/// iOS forbids spawning a helper process, so the engine runs in-process. Its stdin/stdout are
/// redirected onto a socketpair that this file owns, which means the unmodified UCI loop in
/// uci.cpp can be used as-is: nothing in Stockfish has to know it is inside an app.
int cs_engine_start(void);

/// Sends one UCI command. A newline is appended. Returns 0 on success.
int cs_engine_send(const char *command);

/// Reads one line, newline stripped and NUL-terminated.
/// Returns 1 when a line was read, 0 on timeout, -1 on a closed pipe.
int cs_engine_read_line(char *buffer, int capacity, int timeout_ms);

/// True once cs_engine_start has completed.
int cs_engine_is_running(void);

#ifdef __cplusplus
}
#endif

#endif
