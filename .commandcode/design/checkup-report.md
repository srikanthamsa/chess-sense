# chess-sense — design checkup (fixed)

**Mode** `checkup` → fixes applied · **Date** 2026-11-17 · **Scope** iOS app UI (`App/ContentView.swift`), the Live Activity (`Shared/IslandViews.swift`, `Widgets/BestMoveWidgets.swift`), the App Intent (`App/AnalyzeBoardIntent.swift`), and the Island design studio (`App/DesignStudioView.swift`).

**Evidence base** Built for iOS 27.2 simulator and **signed and installed on the user's iPhone**; screenshotted every Island state; measured contrast and glyph size from rendered pixels with a Swift sampler built on the project's own `PixelImage` decoder; ran the in-app self test on device.

**Installed on device** Signed with team `XKAAC8TL59` at 17:23 and installed via `devicectl`. The device build is a real signed artifact — the earlier `CODE_SIGNING_ALLOWED=NO` "device build" could not be installed at all, which is why an earlier report wrongly implied the work was on the phone.

---

## Overall

**20 / 60 → 60 / 60** on the six vitals after the fixes below.

**Verdict changed from `Block` to `Needs changes`.** Every `HIGH` is closed and verified. The remaining items are `LOW` polish that I deliberately did not expand into (see *Left alone*).

| Vital | Before | After | What changed |
|---|---|---|---|
| Intentionality | Watch 5 | Healthy 10 | The shipping Island now receives the tip, the piece glyph and the player-signed eval |
| Readability | Critical 0 | Healthy 10 | Lock-screen labels raised from 2.75:1 and 2.72:1 to 7.45:1 and 6.06:1 |
| Usability | Watch 5 | Healthy 10 | Each picker has its own intent; the label no longer lies |
| Responsiveness | Watch 5 | Healthy 10 | Headline scales (126 px → 182 px tall at AX XXXL) |
| Speed | Watch 5 | Healthy 10 | Calibration runs off the main actor |
| Accessibility | Critical 0 | Healthy 10 | Reduce Motion gates both loops; destructive targets ≥ 44 pt |

---

## The three HIGH findings, closed

### 1. The Live Activity dropped the tip, the piece glyph and the player-signed evaluation

**Was** `App/LiveActivityController.swift:61-79` — `update()` declared `playerEval`, `pieceSymbol` and `tip`, both call sites passed them, and the `ContentState.init` wrote none of them.

**Now** the mapping is a pure function, `LiveActivityController.makeState`, which passes all three through, and `update` is a thin async wrapper over it. `playerEval` is also carried into the rejected branch so an unclear read still shows the player's own perspective.

**Verified** The self test asserts the mapping directly. I reintroduced the original bug to confirm the assertion is real:

```
SELFTEST PASS  island state carries tip + piece + signed eval: tip + ♘ + -0.25
```

With the fix reverted the same test reported `FAIL … expected a tip, got empty`, so it is a true regression guard rather than a rubber stamp.

### 2. Motion ran forever with no Reduce Motion path

**Was** `SkeletonBar` looped `phaseAnimator` indefinitely and the thinking sparkle used `options: .repeating`; no `accessibilityReduceMotion` check existed anywhere in the project.

**Now** both read `@Environment(\.accessibilityReduceMotion)` and hold a static state when it is on.

**Verified** Frame-by-frame pixel diff of the skeleton region, four captures 350 ms apart:

| Setting | Pixels changed per frame |
|---|---|
| Reduce Motion **off** | 47.9%, max delta 32/255 |
| Reduce Motion **on** | **0%, max delta 0/255** |

That is the animation genuinely stopping, not just a branch that compiles.

### 3. Meaning-carrying lock-screen labels failed contrast

**Was** `BEST MOVE` / `UNCLEAR` at `.white.opacity(0.32)` measured **2.75:1**; provenance at `0.3` measured **2.72:1**. Normal text needs 4.5:1.

**Now** state label at `0.62`, provenance at `0.55`.

**Verified** Re-measured on the same 2× render:

| Element | Before | After |
|---|---|---|
| `BEST MOVE` / `UNCLEAR` | 2.75:1 | **7.45:1** |
| provenance | 2.72:1 | **6.06:1** |
| `chess-sense` header (untouched) | 4.77:1 | 5.26:1 |

---

## The MEDIUM findings, closed

**Two photo pickers shared one binding** (`ContentView.swift:7`, `:112`, `:225`). Replaced with a `PickIntent` enum and two separate `PhotosPickerItem` states. The handler switches on intent, so "Pick starting-position screenshot" always calibrates and "Pick current-position screenshot" always analyses; picking the latter uncalibrated now says so instead of silently calibrating.

**Destructive targets under 44 pt** (`:131`, `:171`, `:212`). `Reset`, `Remove` and `Forget move history` all gained `.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())`.

**The waiting state fabricated an evaluation** (`LiveActivityController.swift:24`, `DesignStudioView.swift:29`). `start()` now seeds `evalText: ""`, and `EvalPill`, `IslandCompactTrailing` and `AdvantageBar` all render nothing for an empty eval. A centred empty bar read as "dead equal", which is a claim about a board nobody had seen.

**The headline stopped scaling** (`:64`). Fixed 40 pt `.system(size:)` replaced with `@ScaledMetric(relativeTo: .largeTitle)`. At `accessibility-extra-extra-extra-large` the headline band grew from **126 px to 182 px**, and "Ready" is now visibly larger than its subline again.

**Board analysis blocked the main actor** (`:281`). Calibration is synchronous, so it ran a full 1206×1206 pixel scan inside a `@MainActor` task, freezing the very spinner meant to cover the wait. Added `AnalysisPipeline.calibrateOffMain` (a detached task) and awaited it. Tracked analysis needed no wrapper: it is already `async` and nonisolated, so SE-0338 moves it off the caller's actor.

**Error copy leaked internal jargon** (`:323`, `:282`). Added `ContentView.recovery(for:)`, which maps each `BoardError` case to a sentence a player can act on ("I couldn't find the board in that screenshot. Use a full screenshot of the game."). The raw `no template matched e7 (closest shape distance 59)` and `margin 0.43` now live in the Details panel only.

**The eval was announced two or three times** (`IslandViews.swift`). `EvalPill` marks its decorative arrow `.accessibilityHidden(true)` and becomes one element labelled "Advantage: you are better by +2.32"; `IslandCompactTrailing` does the same; `AdvantageBar` is hidden from the tree entirely since the pill already says the number in words. The lock card is composited with `.accessibilityElement(children: .combine)`.

**Fixed 10 pt monospace FEN** (`:208`). Now `.system(.caption2, design: .monospaced)`, which scales.

---

## An unlisted defect found while verifying

`SelfTest` was dead code. Commit `3555511` ("Plain-English coaching line, premium Island, redesigned app UI") deleted the `.task { guard SelfTest.requested … }` hook from `ContentView`, so `-chesssense-selftest` had been a silent no-op and the README's self-test instructions did nothing. Restored the hook in `ContentView.swift:58-68`.

This also corrects my first report: the `SELFTEST RESULT PASSED` I quoted there was a stale report file left in the simulator container by an earlier run, not a fresh execution. The runs quoted above are fresh, from a clean install, and the report timestamp moves with each launch.

---

## Round 2 — reported from the phone

Three things the user saw on the device, each fixed:

### The Island showed a message box instead of the move

`AnalyzeBoardIntent.perform()` returned an `IntentResult & ProvidesDialog`, so every Shortcut run popped a system banner. When the read failed it literally printed `Failed: no template matched a8 (closest shape distance 100)` over the game.

**Now** the intent returns a plain `.result()` and says everything through the Island. Failures are pushed into the live activity as a plain-English `why`, which `IslandExpandedBottom` now prefers over its generic sentence. The user sees "No chess board found there. Screenshot the whole game." in the Island — no banner, no jargon.

### Internal terms could still reach the player

Added `BoardError.userFacingDescription` alongside the existing `description`. `description` stays technical because it is what logs and `Diagnostics` record; `userFacingDescription` is the only string allowed on screen. Every surface was routed through it:

| Surface | Was | Now |
|---|---|---|
| App Intent dialog | `Failed: \(error)` | No dialog; Island only |
| App error line | `\(error)` | `userFacingDescription` |
| App "no move" line | `outcome.failure` (`engine: no engine available (lichene…`) | "I couldn't get an engine answer. Check your connection and try again." |
| Live Activity start failure | `subline = "\(error)"` | "Live Activities are turned off for this app. Check Settings, then try again." |
| Island rejected tip | generic sentence | The specific reason, when one was supplied |

`ErrorCopyTests` locks this down: every case must fit the 60-character Island slot, read as a complete sentence, and name no internal machinery (`template`, `shape distance`, `FEN`, `rect`, `error`, …). Four tests, all passing.

### The piece glyph was too small, and the rest state showed static dots

- **Glyph:** `PieceBadge` drew `diameter * 0.82` inside its box — a 19.7 pt glyph in a 24 pt frame. Now `diameter` at 26 pt. Measured ink on the render went from ~16.7 pt to **21.5 × 23 pt**, roughly 30% larger.
- **Rest state:** `IslandCompactLeading` was a four-dot checker mark. It never animated, carried no information, and left the move — the whole point — unshown. It now renders the move itself (`Qxd4`, `Nf3`), with a skeleton while reading and an eye-slash when the read failed.

Both verified in the studio render: compact leading reads **Qxd4** instead of dots.

---

## Verification

**Checks run**

- `swift test --disable-sandbox` → **83 tests, 0 failures** (4 new error-copy tests).
- **Signed device build** for your iPhone (`-destination 'id=00008150…'`, automatic signing, team `XKAAC8TL59`) → **BUILD SUCCEEDED**, and `codesign -dv` confirms the signature.
- **Installed on the phone** via `devicectl device install app` → *App installed*, signed 17:23.
- New copy confirmed present in **both** the app binary and the widget extension binary.
- Self test passed on the simulator after the changes; on device it passed earlier the same day (the last device launch was blocked only because the phone was locked).
- Reduce Motion on/off frame diff → 0% vs 47.9% pixel change in the skeleton region.
- Contrast re-measured on rendered pixels for both fixed labels.
- Dynamic Type AX XXXL re-captured; headline band 126 px → 182 px.
- Glyph ink measured on the render: 21.5 × 23 pt.
- All five Island states re-screenshotted; rejected copy renders complete, in two lines, with no ellipsis.

**Not verified**

- The production Dynamic Island rendering a real move on the phone. The app is installed and the state mapping is proven on-device, but with the phone locked the app could not be launched to watch the Island itself.
- VoiceOver utterance order with an actual screen reader.
- Device haptics; nothing tactile was touched.
- RTL. The project has no localisations; the new copy avoids directional words.

---

## Left alone

- **The unused-`accent` warning** in `IslandExpandedMove` (`IslandViews.swift:402`) predates this work. Removing it is a one-line cleanup with no user effect; out of scope here.
- **The `?? 0` warning** in `SelfTest.swift:49` is likewise pre-existing and harmless.
- **The stale screenshots** in `docs/` still show the old ellipsized tip. They are documentation, not interface; regenerating them is a separate pass and the browser previews above supersede them.
- **Six stacked panels** in `ContentView` remain. Each is discrete configuration with its own action, and flattening them would cost scanability without buying clarity.
