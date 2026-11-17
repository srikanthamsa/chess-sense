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
| Clean-room engine + tests | 13 tests green |
| iOS app, Live Activity, App Intent | in progress |
| Engine client (Lichess cloud eval) | in progress |

## Quick start

```bash
swift test                                   # 13 tests
swift run chesssense-diag <screenshot.png>   # dump board rect, palette, templates, FEN
```

The test fixture is a real TakeTakeTake screenshot (`Tests/ChessSenseCoreTests/Fixtures/`).

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

## Layout

```
Sources/ChessSenseCore/
  PixelImage.swift      RGBA raster decode + RGB type
  BoardLocator.swift    board rect + square geometry
  BoardPalette.swift    checkerboard palette, per-square background
  SquareSignature.swift shape bits + bright fraction
  TemplateBook.swift    calibration, clustering, two-stage classify
  BoardReader.swift     image -> FEN, self-verifying calibration
  Piece.swift           pieces, errors
Sources/chesssense-diag/  CLI diagnostics: rect, palette, per-square stats, FEN
Tests/ChessSenseCoreTests/
```

## Roadmap

- [ ] iOS app target + Calibration screen (one screenshot, tap to confirm board rect)
- [ ] Live Activity / Dynamic Island rendering of the best move
- [ ] App Intent so the Action Button (or a Shortcut) triggers a background analyze
- [ ] Engine: Lichess cloud eval, fallback to local Stockfish
- [ ] Move diffing + castling/en-passant tracking so only the FEN's board part comes from pixels
- [ ] Optional: raw ReplayKit frames for continuous updates
- [ ] Optional: DeepSeek for a one-line "why" in the expanded Island view

## Notes

- Side to move, castling rights and en-passant are *not* read from pixels. A single frame
  cannot contain them; tracking them from move history is strictly more reliable, which is
  also why chessvision.ai exposes `--orientation` / `--castling` / `--turn` overrides.
- `chessvision` on PyPI is a different, unrelated project (GPL-3.0) that happens to share
  the name.
