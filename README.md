# chess-sense

Read the chess board off a screen, find the best move, show it in the Dynamic Island.

Built for one game and one board: **TakeTakeTake** on iPhone. It is deliberately *not*
a general chess-OCR engine — see [Why not a general recognizer](#why-not-a-general-recognizer).

```
screenshot ──▶ locate board ──▶ classify 64 squares ──▶ FEN ──▶ engine ──▶ Dynamic Island
              (pixel scan)      (template match)              (cloud eval)     (Live Activity)
```

## Status

| Piece | State |
|---|---|
| Board locator | works on TakeTakeTake screenshots |
| Square classifier | reads the starting position exactly, 13/13 templates learned from one frame |
| Template calibration | self-verifying; rejects frames that disagree with the expected position |
| Chess rules module (move gen, legality, castling, ep, promotion) | done, anchored by perft |
| Move diffing + castling / en passant / turn tracking | done, 9 tracker tests |
| SAN generation | done, 10 notation tests |
| Engine: Lichess cloud eval + Stockfish fallback + cache | done, payload-captured tests |
| iOS app, Live Activity, App Intent | scaffolded, compiles in Xcode |
| 43 unit tests | green |

## Quick start

```bash
swift test                                   # 13 tests, no Xcode session needed
swift run chesssense-diag <screenshot.png>   # dump board rect, palette, per-square stats, FEN
./scripts/verify.sh                          # tests + iOS-SDK typecheck of the app layer
```

The test fixture is a real TakeTakeTake screenshot (`Tests/ChessSenseCoreTests/Fixtures/`).

## Running it on a phone

```bash
xcodegen generate          # project.yml -> ChessSense.xcodeproj
open ChessSense.xcodeproj
```

1. Set your team on both targets, run on the device.
2. Screenshot a **fresh game** in TakeTakeTake, tap *Pick starting-position screenshot*.
   It calibrates and verifies in one step; you should see `Calibrated ✓`.
3. *Start Live Activity* — the Island shows `----` waiting state.
4. In **Shortcuts**, build: `Take Screenshot` → `Best Move` (the app's intent).
   Bind it to the Action Button or Back Tap. Screenshot mid-game, the move appears.

The Dynamic Island shows **SAN** (`Nf3`, `Qxd5+`, `O-O`), falling back to `from–to` if the
engine's move somehow isn't legal in the tracked position.

## How it works

### 1. Find the board — no detector needed

`BoardLocator` scans row and column density for board-coloured pixels
(neither near-black UI chrome nor near-white pieces; blue-dominant) and takes the longest
contiguous run. The board is the only element that produces a long run of mostly
board-coloured rows, so avatars and lavender buttons can't corrupt the result.

On the fixture this returns `(x: 0, y: 684, w: 1206, h: 1206)` — full-bleed width,
square, `150.75 px` per square. No perspective, no scaling, no lighting.

### 2. Call it a checkerboard

`BoardPalette` estimates the light and dark square colours from the medoid of each
checkerboard parity, then assigns each square's background **by `(rank + file) % 2`**.

This is the single most important design decision. Inferring a square's background from
its own contents fails: a detail-heavy glyph can own the largest flat area inside its
square and hijack the colour mode. Measured, that inverts the white/black signal for
knights, queens and kings (bright fraction 0.00 where it should be ~0.70 and vice versa).

Pinning background to the checkerboard structure also makes last-move and check tints a
non-issue: a tint moves a square a few tens of RGB units, so it is still closer to its
palette colour than to the other one, and the tinted value is used as the background.

### 3. Two channels, in order of discriminative power

Per square, relative to that square's background:

| Channel | Representation | Separates |
|---|---|---|
| **shape** | 16×16 coverage bitmap → 256 bits | piece type |
| **bright fraction** | share of ink pixels lighter than bg + 0.15 | piece colour |

Both are needed, and the measurements say why:

- White rook vs black rook: `shapeDistance = 0`, `colorDistance = 0.49`.
  **Identical silhouettes.** Shape alone cannot tell them apart — a shape-only classifier
  reports a black rook as a white rook.
- Same piece on a light vs a dark square: `shapeDistance ≤ 4`, `colorDistance ≤ 0.03`.
  The signal survives the square's colour.

Colour is measured as "how much of this glyph is brighter than the board", which is what
a human reads. Mean, mode and percentile luma of the whole ink mask all fail here because
the anti-aliasing band where the glyph meets the board drifts by up to 0.19 between square
colours and dominates the pixel count.

Classification narrows by shape (within a tolerance band), then discriminates by bright
fraction. A square that matches nothing is **rejected**, never guessed.

### 4. Calibration is one screenshot

`BoardReader.calibrate` learns 13 templates (6 pieces × 2 colours + empty) from a single
frame of a **known** position — the starting position, which conveniently contains all 13
classes. Squares sharing a piece are sub-clustered, so a piece that renders differently on
light vs dark squares gets two templates instead of one smeared average.

It then **re-reads the frame and requires the expected position back**. Wrong theme,
mid-animation frame, or a finished game fails loudly instead of baking a broken book:

```swift
let (book, rect, verification) = try BoardReader.calibrate(image: shot)
// verification.fen == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
// book.entries.count == 13, supports 32/8/8/2/2/2/2/1/1/1/1...
```

Measured on the fixture: worst shape distance 5, minimum colour margin 0.43.

## Why not a general recognizer

[chessvision.ai](https://chessvision.ai/) is the reference implementation and worth
studying. Its author splits the problem into board detection (custom skeleton + graph
algorithm, the hard part, paper-worthy) and per-square classification (transformer-free
CNNs, type then colour), and states the accuracy floor plainly: 0.99 per square still means
`0.99^64 ≈ 0.52` per board, so you need better than 0.999.

That floor applies to *arbitrary* input — book photos, tilted magazine shots, YouTube
frames with arrows drawn on them. This app's input is one app's canvas at one fixed rect,
with no compression and no perspective, so the piece renders are byte-identical frame to
frame. Substituting a structural prior and a locked theme buys accuracy that a general
model has to earn with a dataset, and skips the detector entirely.

The discipline worth copying is the reject path: never emit a move from a low-confidence
read.

## Rules, tracking and notation

### The rules module

Finding the best move is worthless if the FEN is wrong, so the core owns a complete chess
rules implementation: move generation, legality (pins and checks), castling, en passant,
promotion, castling-right bookkeeping, FEN round-trip and SAN.

It is anchored to published **perft** counts, which is the cheapest honest proof a move
generator is correct:

| Position | Depth 1 | 2 | 3 |
|---|---|---|---|
| start | 20 | 400 | 8,902 |
| Kiwipete `r3k2r/p1ppqpb1/...` | 48 | 2,039 | — |
| P3 `8/2p5/3p4/KP5r/...` | 14 | 191 | 2,812 |

**Why not ChessKit:** SAN needs full legal-move generation for disambiguation, check and
mate — the same machinery move diffing needs. A package dependency can't resolve in this
project's Xcode targets here either (SwiftPM's manifest cache is outside the writable
sandbox), so one self-contained module that serves both jobs beats a dependency that
serves one.

### Tracking is how a FEN gets its other five fields

A screenshot is 64 piece placements. A FEN needs six fields. The other five come from
**history**, which is strictly more reliable than inferring them from pixels:

```
observed 64 squares ──▶ find the legal move(s) that reach them
                        ├─ exactly one 1-ply move      → apply, advance turn
                        ├─ exactly one 2-ply sequence  → a frame was missed; apply both
                        └─ nothing explains it         → resync: adopt the board,
                                                         rebuild castling from piece
                                                         placement, drop ep
```

Every special case falls out of move generation instead of being special-cased by hand:
castling arrives as one ply because the rook leg is in the diff, en passant because the
captured pawn is not on the destination square, promotion because a pawn disappears and a
queen appears. `Side to move` is never read from pixels at all.

### Engine

`EngineChain` tries backends in order and reports every reason if all fail:

1. **Lichess cloud eval** — keyless, instant, depth 30–75 for positions someone has already
   analysed. ~85% of real games.
2. **stockfish.online** — covers the rest.

Responses are cached per FEN, so recognising the same frame twice costs nothing.

## Layout

```
Sources/ChessSenseCore/
  PixelImage.swift      RGBA raster decode + RGB type
  BoardLocator.swift    board rect + square geometry
  BoardPalette.swift    checkerboard palette, per-square background
  SquareSignature.swift shape bits + bright fraction
  TemplateBook.swift    calibration, clustering, two-stage classify
  BoardReader.swift     image -> 64 squares -> FEN, self-verifying calibration
  Piece.swift           pieces, errors
  Chess/                squares, moves, position, move generation, SAN, tracker
  Engine/               backends, fallback chain, cache
App/                    pipeline, Live Activity, App Intent, calibration UI
Widgets/                Dynamic Island / lock-screen activity
Shared/                 activity attributes (compiled into app + extension)
Sources/chesssense-diag/  CLI diagnostics: rect, palette, per-square stats, FEN
Tests/ChessSenseCoreTests/  reader, rules, tracker, engine
```

## Roadmap

- [x] iOS app target + calibration from one screenshot
- [x] Live Activity / Dynamic Island rendering of the best move
- [x] App Intent so the Action Button (or a Shortcut) triggers a background analyze
- [x] Engine: Lichess cloud eval (no key)
- [x] Fallback engine: stockfish.online
- [x] SAN via an in-house rules module, anchored by perft
- [x] Move diffing + castling / en-passant / turn tracking
- [ ] On-device fallback engine (Stockfish binary) for fully offline operation
- [ ] Optional: raw ReplayKit frames for continuous updates
- [ ] Optional: DeepSeek for a one-line "why" in the expanded Island view

## Verification status

Green and repeatable: `swift test` (43 tests — reader, perft-anchored rules, tracker,
engine payloads) and an iOS-17-simulator typecheck of the core plus every non-SwiftUI app
file (`CalibrationStore`, `LiveActivityController`, `AnalysisPipeline`).

Not yet verified: the SwiftUI surface (`ContentView`, the app entry point, the App Intent,
the widget). Those expand macros through `swift-plugin-server`, which cannot start in a
headless sandboxed build — open the project in Xcode to compile them. Nothing on this list
has been run on a physical device yet, so the Island rendering, App Intent background
execution and the real end-to-end latency are still unmeasured.

## Notes

- If a frame can't be explained by legal play the tracker resyncs rather than guessing. A
  board that turns out to be the starting position is treated as a fresh game (White to
  move, all castling rights); any other resync keeps the previous turn, and the result is
  reported as an assumption rather than a certainty.
- Side to move, castling rights and en-passant are *not* read from pixels. A single frame
  cannot contain them; tracking them from move history is strictly more reliable, which is
  also why chessvision.ai exposes `--orientation` / `--castling` / `--turn` overrides.
- `chessvision` on PyPI is a different, unrelated project (GPL-3.0) that happens to share
  the name.
