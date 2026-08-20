# Grasslook — Comprehensive Code Audit Report

**Auditor:** Antigravity (AGY)  
**Date:** 2026-08-18  
**Revision:** 2 (full checklist pass)  
**Build:** `xcodegen generate` ✅  `xcodebuild test` ❌ (sandbox launch restriction — see §7)

---

## §1 · Swift 6 Strict Concurrency & Thread Safety

### 1.1 Actor Isolation

| Class | Isolation | Assessment |
|---|---|---|
| `GrasslookCoordinator` | `@MainActor` | ✅ Correct |
| `BreakScheduler` | `@MainActor` | ✅ Correct |
| `OverlayWindowController` | `@MainActor` | ✅ Correct |
| `AnalyticsManager` | `@MainActor` | ✅ Correct |

All four root objects are confined to the main actor. The ticker `Task` in `BreakScheduler` is explicitly annotated `Task { @MainActor [weak self] in … }`, so `tick()` never hops off the main thread. `@Published` property mutations and all UI callbacks are therefore data-race-free under Swift 6 strict concurrency rules.

`GrasslookCoordinator.setupBindings()` wires callback closures that all run on the main actor. The `[weak self]` capture list is used consistently on every closure. No strong reference cycles were found.

> **Finding 1.1-A (Minor):** `GrasslookCoordinator` stores `AppInterceptionEngine`. If that type's `onInterventionTriggered` callback is not `@MainActor`-isolated, it could deliver cross-thread invocations into coordinator code. Verify `AppInterceptionEngine` is also `@MainActor` or dispatches onto `DispatchQueue.main`.

### 1.2 Lock Management — `CooldownManager` & `BrowserMonitor`

**`CooldownManager`** uses a single `NSLock` guarding `cooldowns: [String: Date]`. The `lock.lock() / defer { lock.unlock() }` pattern is consistent across all four public methods. `cacheKey(for:)` is called inside the lock but has no internal locking of its own, so no reentrance risk exists. `NSLock` is non-reentrant; no method calls another locked method internally, so no deadlock is possible.

> **Finding 1.2-A (Recommendation):** `CooldownManager` is marked `@unchecked Sendable` with a manual lock. Migrating to a Swift `actor` would give compiler-verified isolation, eliminate the lock entirely, and make Swift 6 strict-mode compliance automatic.

**`BrowserMonitor`** also uses `@unchecked Sendable` + `NSLock` guarding `customBrowserBundleIds`. Crucially, the lock is released *before* any blocking AX or AppleScript call — long operations never hold the lock. No deadlock risk.

> **Finding 1.2-B ✅ (Correct):** Lock is never held during blocking system calls.

### 1.3 Task Cancellation — `BreakScheduler.tickerTask`

The ticker loop checks `Task.isCancelled` before *and* after the 1-second sleep. `stop()` cancels and nils the task; `deinit` also cancels. The `[weak self]` capture prevents the Task from retaining the scheduler past deallocation.

> **Finding 1.3-A ✅ (Clean):** No leaked background loops.

> **Finding 1.3-B (Minor):** `try? await Task.sleep` silently discards `CancellationError` and falls through to the subsequent guard. The code is correct but it would be more idiomatic Swift 6 to let the thrown `CancellationError` exit the loop naturally by removing `try?`.

---

## §2 · AppKit Multi-Display Overlay Lifecycle & Memory Management

### 2.1 Panel Configuration

| Setting | Value | Purpose |
|---|---|---|
| `panel.level` | `.screenSaver` | Above fullscreen apps ✅ |
| `styleMask` | `[.borderless, .nonactivatingPanel]` | No focus steal ✅ |
| `collectionBehavior` | `[.canJoinAllSpaces, .fullScreenAuxiliary]` | All spaces/fullscreen ✅ |
| `panel.ignoresMouseEvents` | `false` | Buttons remain interactive ✅ |
| `panel.isOpaque` | `false` | Liquid Glass compositing ✅ |

> **Finding 2.1-A ✅ (Correct):** Panel configuration is production-quality and matches the design intent.

### 2.2 View Hierarchy Teardown

`dismissOverlays()` calls `panel.orderOut(nil)` then `overlayPanels.removeAll()`. When the array is cleared, ARC releases each `NSPanel`, which releases its `contentView` (`NSHostingView`), which releases the SwiftUI view graph. `displayViewOnAllScreens` calls `dismissOverlays()` before creating new panels, ensuring stale panels are always torn down first.

> **Finding 2.2-A ✅ (Clean):** No memory accumulation over repeated break cycles.

### 2.3 Multi-Monitor Resizing — `repositionPanels()`

> **Finding 2.3-A 🔴 (Bug — New Display Plugged In During Overlay):**  
> If a display is plugged in while an overlay is active, `NSScreen.screens.count` grows but `overlayPanels.count` stays the same. The `if index < overlayPanels.count` guard silently skips the new screen — that display will show **no overlay**, allowing free interaction during a mandatory break.  
> **Fix:** Store the current active `AnyView` as a property and call `displayViewOnAllScreens(rootView: currentRootView)` instead of just repositioning.

> **Finding 2.3-B ⚠️ (Minor — Display Removed During Overlay):**  
> If a display is removed, the orphaned panel is never explicitly removed from `overlayPanels`. It is memory-safe (AppKit handles the orphaned window) but slightly wasteful; cleaned up on the next `dismissOverlays()` call.

---

## §3 · Universal Browser Inspection & Permissions Hygiene

### 3.1 AXUIElement Traversal — CPU Risk

The traversal is depth-limited to 4 levels but the branching factor at each level is unbounded. The fast path (`AXDocument` / `AXURL` on the window element) short-circuits for Safari and most Chromium browsers. For niche browsers relying purely on tree traversal, a very wide toolbar could cause a CPU spike.

> **Finding 3.1-A ⚠️ (Performance):** Add a total-node-visited cap (e.g. 50 nodes) alongside the depth cap to bound worst-case CPU cost for complex browser chrome (e.g. Firefox's XUL tree).

> **Finding 3.1-B ✅ (Correct):** `AXUIElementCopyAttributeValue` returns quickly if the target is unresponsive — the system times out the Mach port call. No indefinite block.

### 3.2 AppleScript Execution — Frozen Browser Risk

`NSAppleScript.executeAndReturnError` is **synchronous** and can block the calling thread for up to ~30 seconds if the target application is frozen or terminating.

> **Finding 3.2-A 🔴 (Serious — Potential Main-Thread Hang):**  
> If `extractActiveURL` is called on the main thread and the browser is frozen, Grasslook's UI will be completely unresponsive for up to 30 seconds.  
> **Fix:** Dispatch `extractURLViaAppleScript` to a background task and deliver the result back to the main actor:
> ```swift
> Task.detached {
>     let url = self.extractURLViaAppleScript(bundleIdentifier: bundleId)
>     await MainActor.run { completion(url) }
> }
> ```

### 3.3 Permissions Priming — `SettingsView`

`AXIsProcessTrusted()` is called inline during body evaluation. It is lightweight but returns a cached value — if the user grants permission in System Settings and returns to Grasslook, the pane may still show "not granted" until the next render cycle.

> **Finding 3.3-A ⚠️ (UX):** Add a 1-second polling `Timer` or a "Re-check" button to re-evaluate `AXIsProcessTrusted()` after the user may have granted access.

> **Finding 3.3-B ✅ (No Crash):** The `AXIsProcessTrustedWithOptions` button is safe.

---

## §4 · State Machine & Timer Logic

### 4.1 Break Precedence

In `tick()`, the `secondsUntilNextLong <= 0` check fires before `secondsUntilNextMicro <= 0`. When both hit zero simultaneously, the long break wins. `resetTimers(after: .long)` resets **both** counters. The `testLongBreakPrecedenceOverMicro` unit test directly exercises this path.

> **Finding 4.1-A ✅ (Correct):** Long break always takes precedence. Counter reset is clean.

### 4.2 Postpone / Skip Edge Cases

> **Finding 4.2-A ⚠️ (Logic Bug — Postpone from `.inBreak`):**  
> `postponeBreak` from `.inBreak` calls `resetTimers(after: type)` first (setting `secondsUntilNextMicro = microInterval`, e.g. 1200s), then adds `seconds` (300s) on top → `secondsUntilNextMicro = 1500s`. The intent appears to be "fire again in 5 minutes", not "microInterval + 5 minutes". The `.breakDue` path correctly sets `secondsUntilNextMicro = seconds` (300s) without the double-add.  
> **Fix:** Remove the `resetTimers(after: type)` call from the `.inBreak` postpone path; set `secondsUntilNextMicro = seconds` directly.

> **Finding 4.2-B ✅ (Correct):** Skip fires `onBreakSkipped`, resets to the full interval, and transitions to `.countingDown`. The `Esc` keyboard shortcut binding in `BreakOverlayView` is correct.

### 4.3 Inactivity Sensor

`CGEventSource.secondsSinceLastEventType(.combinedSessionState, anyEvent)` is the correct API. It resets to 0 on any HID event and also on system wake — appropriately resuming the countdown fresh after sleep.

> **Finding 4.3-A ✅ (Correct):** Reliable across sleep/wake cycles. No known regressions.

---

## §5 · Privacy, Sandboxing & Zero Telemetry

### 5.1 `AnalyticsManager` — Local-Only

Only `import Foundation` is present. All persistence is via `UserDefaults.standard` with `grasslook.stats.*` keys. No `URLSession`, `Network`, or third-party analytics framework is used anywhere in the project.

> **Finding 5.1-A ✅ (Clean):** Zero network telemetry confirmed.

### 5.2 `project.yml` — Dependency Audit

No `dependencies:` key exists under any target. Zero SPM packages, CocoaPods, or Carthage dependencies. All capabilities are fulfilled via Apple system frameworks only.

> **Finding 5.2-A ✅ (Clean):** Full supply-chain trust. Zero external dependencies.

### 5.3 Entitlements

```xml
<!-- Entitlements/Grasslook.entitlements -->
<key>com.apple.security.automation.apple-events</key><true/>
```

> **Finding 5.3-A ⚠️ (Info — No App Sandbox):** App Sandbox (`com.apple.security.app-sandbox`) is absent. Acceptable for direct distribution; blocks Mac App Store submission. Document this as an intentional architectural decision.

> **Finding 5.3-B ⚠️ (Build):** `GrasslookTests` has no `CODE_SIGN_ENTITLEMENTS` in `project.yml`. This causes `OSStatus -54` ("sandbox profile missing `(allow lsopen)`") at test launch. Fix: create `Tests/GrasslookTests.entitlements` and reference it in the test target's `project.yml` settings.

---

## §6 · Accessibility & Human Interface Guidelines

### 6.1 Reduce Motion — `BreathingBubbleView`

```swift
private func startBreathingCycle() {
    guard !reduceMotion else {
        isBreathingComplete = true  // Skip all animation
        return
    }
    …
}
```

> **Finding 6.1-A ✅ (Excellent):** Reduce Motion is handled at the function entry point, completely suppressing animations. Fully HIG-compliant.

### 6.2 Reduce Motion — `BreakOverlayView`

`@Environment(\.accessibilityReduceMotion) private var reduceMotion` is declared but **never used**. The ring animation runs unconditionally:

```swift
// Current (incorrect):
.animation(.linear(duration: 1.0), value: progress)

// Required fix:
.animation(reduceMotion ? .none : .linear(duration: 1.0), value: progress)
```

> **Finding 6.2-A 🔴 (Bug):** Ring progress animation fires regardless of Reduce Motion, which can cause discomfort for users with vestibular disorders. One-line fix required.

### 6.3 VoiceOver Labels

| Button | `accessibilityLabel` | Assessment |
|---|---|---|
| Skip break | "Skip break" | ✅ |
| Postpone 5m | "Postpone break by 5 minutes" | ✅ |
| Step Away & Close | "Step away and close application" | ✅ |
| Continue for 15m | "Continue to application for fifteen minutes" | ✅ |
| Countdown ring | *(none)* | ⚠️ |

> **Finding 6.3-A ✅ (Excellent):** All four action buttons have explicit, descriptive VoiceOver labels that spell out abbreviations and provide meaningful context beyond the visible text.

> **Finding 6.3-B (Minor):** The countdown ring has no `accessibilityLabel`. Add:
> ```swift
> .accessibilityLabel("Time remaining: \(formattedTime(secondsRemaining))")
> ```

---

## §7 · Build & Test Suite Results

| Command | Result |
|---|---|
| `xcodegen generate` | ✅ Pass |
| `xcodebuild … build` | ✅ Pass (inferred from test build phase) |
| `xcodebuild … test` | ❌ Fail — OSStatus -54 (sandbox environment restriction, not a logic error) |

Test logic was reviewed manually. 11 test cases across 3 suites cover the core state machine, pattern matching, and cooldown logic.

**Missing test coverage:**
- `postponeBreak` from `.breakDue` state  
- `triggerBreakNow` starting a break mid-countdown  
- `CooldownManager.clearAll`  
- `BrowserMonitor.normalizeURLString` edge cases (bare domain, http vs https, search queries)  
- `AnalyticsManager` `breakComplianceRate` / `focusSuccessRate` division-by-zero guards  

---

## §8 · Consolidated Findings

| # | Severity | File | Finding |
|---|---|---|---|
| 1.1-A | ⚠️ | `GrasslookCoordinator` | Verify `AppInterceptionEngine` is `@MainActor` |
| 1.2-A | 💡 | `CooldownManager` | Migrate from `NSLock + @unchecked Sendable` to `actor` |
| 1.3-B | 💡 | `BreakScheduler` | Use `try await Task.sleep` without `try?` |
| 2.3-A | 🔴 | `OverlayWindowController` | New display gets no overlay panel during active break |
| 2.3-B | ⚠️ | `OverlayWindowController` | Removed-display panel not cleaned from array |
| 3.1-A | ⚠️ | `BrowserMonitor` | Add node-count cap to `findAddressBarURL` |
| 3.2-A | 🔴 | `BrowserMonitor` | AppleScript is synchronous — can block main thread ~30s |
| 3.3-A | ⚠️ | `SettingsView` | Permissions pane may show stale trusted state |
| 4.2-A | ⚠️ | `BreakScheduler` | `postponeBreak` from `.inBreak` applies double interval |
| 5.3-A | ⚠️ | `Grasslook.entitlements` | No App Sandbox — blocks MAS; acceptable for direct dist |
| 5.3-B | ⚠️ | `project.yml` | Test target missing entitlements → OSStatus -54 |
| 6.2-A | 🔴 | `BreakOverlayView` | Ring animation ignores `accessibilityReduceMotion` |
| 6.3-B | 💡 | `BreakOverlayView` | Countdown ring lacks `accessibilityLabel` |

**Legend:** 🔴 Must fix before beta · ⚠️ Should fix before release · 💡 Nice-to-have

---

## §9 · Priority Remediation Plan

### Priority 1 — Fix Before First Beta

1. **`BreakOverlayView` Reduce Motion** (6.2-A) — one-line fix  
2. **`extractURLViaAppleScript` main-thread block** (3.2-A) — move to `Task.detached`  
3. **Multi-monitor overlay gap** (2.3-A) — store active root view, call `displayViewOnAllScreens` in `repositionPanels`  
4. **Postpone double-add** (4.2-A) — remove `resetTimers` call in `.inBreak` postpone path  

### Priority 2 — Fix Before Public Release

5. **Test entitlements** (5.3-B) — add `GrasslookTests.entitlements`  
6. **AX tree node cap** (3.1-A) — add 50-node visitor limit  
7. **Permissions pane re-check** (3.3-A) — add `Timer` or "Re-check" button  

### Priority 3 — Technical Debt

8. Migrate `CooldownManager` to `actor` (1.2-A)  
9. Fill missing unit test coverage (§7)  
10. Add countdown ring `accessibilityLabel` (6.3-B)  
11. Verify `AppInterceptionEngine` actor isolation (1.1-A)  

---

*Prepared by Antigravity (AGY) — Independent Code Auditor*  
*Next review recommended after Priority 1 items are addressed.*
