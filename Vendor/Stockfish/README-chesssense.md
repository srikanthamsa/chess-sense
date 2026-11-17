# Stockfish 11, running in-process

Vendored from Stockfish 11 (`sf_11`, GPLv3). Classical evaluation only — no NNUE, so no
network file, no 40 MB binary.

## Why in-process

iOS forbids `fork`/`exec`, so the engine cannot be a helper binary. Its sources are compiled
into the app target and `UCI::loop` is booted on a background thread. Stockfish is unmodified:
the only glue is `CSBridge.cpp`, which

1. redirects `std::cin`/`std::cout` onto a socketpair using a file-descriptor `std::streambuf`
   (libc++ has no `stdio_filebuf`), and
2. performs the initialisation Stockfish's own `main.cpp` would have done, in the same order.

Two details cost real debugging time and are worth not rediscovering:

- `UCI::loop` only enters its interactive read loop when `argc == 1`. Called with `argc == 0`
  it returns immediately, so the engine looks alive but never answers.
- `Threads.set(...)` is required before the first search: `ThreadPool::main()` calls
  `threads.front()` on the first search, which aborts on an empty vector.

## Cost

Compiled at `-O2` even in Debug (`GCC_OPTIMIZATION_LEVEL: 2`); at `-Onone` a single search
takes minutes, which reads as a hang. Measured at depth 14 with one thread:

| position | time |
|---|---|
| opening | ~180 ms |
| middlegame | ~110 ms |
| endgame | ~15 ms |

Roughly 2.4 Mnps with the release build.
