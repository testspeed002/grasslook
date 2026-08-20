# Grasslook

## How the repo works
- `Sources/GrasslookApp/`: Application entry point (`@main`), `MenuBarExtra` lifecycle, and App Delegate.
- `Sources/Core/Breaks/`: `BreakScheduler`, timer state machine (Micro-breaks: 20s/20m; Long breaks: 5m/60m), idle/meeting smart-pause sensors.
- `Sources/Core/Friction/`: `AppInterceptionEngine`, `BrowserMonitor` (universal AX + AppleScript URL extractor), `CooldownManager`, target app/domain matchers.
- `Sources/Core/Analytics/`: Local privacy-safe metrics (breaks taken vs skipped, distractions avoided, mindful minutes).
- `Sources/UI/Overlays/`: Multi-display full-screen `NSPanel` overlay controllers, calming Liquid Glass blur, animated breathing bubble (`BreathingView`), countdown timer HUD.
- `Sources/UI/Settings/`: Settings window (NavigationSplitView / Liquid Glass) for configuring break intervals, targeted apps/websites, audio preferences, and viewing stats.
- `Tests/`: Unit tests and snapshot test suites for timing models, pattern matchers, and view states.

## Build / test / run

\# Generate the Xcode project after editing project.yml

`xcodegen generate`

\# Build (open in Xcode or use xcodebuild)

`xcodebuild -project "Grasslook.xcodeproj" -scheme Grasslook build`

\# Test

`xcodebuild -project "Grasslook.xcodeproj" -scheme Grasslook test`

\# Package / sign / notarize

`./build_and_package.sh`

- Run tests (including snapshot tests) before declaring a task complete.  
- If snapshot tests fail, inspect the diff before re-recording — don't blindly re-record baselines.  
- Fix root causes; never disable a failing test or bypass a check to make it pass.
