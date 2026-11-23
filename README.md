# Grasslook

Grasslook is a macOS menu bar app for scheduled eye breaks, movement reminders, and mindful delays on distracting apps and websites. It runs locally on your Mac with zero telemetry or remote accounts.

## Contents

Use these links to jump directly to a section.

- [Features](#features)
- [Requirements](#requirements)
- [Install and run](#install-and-run)
- [Grant macOS permissions](#grant-macos-permissions)
- [Accessibility and keyboard support](#accessibility-and-keyboard-support)
- [Development and testing](#development-and-testing)
- [Privacy and local storage](#privacy-and-local-storage)
- [License](#license)

## Features

Grasslook combines proactive rest timers with intentional friction before distracting habits start.

- **Scheduled rest breaks.** Micro-breaks run for `20` seconds every `20` minutes (`20-20-20` rule). Movement breaks run for `5` minutes every `60` minutes.
- **Automatic smart pause.** Timers pause when your Mac is idle for more than `3` minutes, during active presentations or calls, and across system sleep.
- **Pre-break notifications.** Alerts appear `30` seconds before a break starts with **Snooze 5m** and **Start Now** actions.
- **App and browser delays.** Breathing overlays pause switches to blocked apps. Active browser tabs are checked every `1.25` seconds while a browser is frontmost.
- **Seven-engine browser discovery.** Grasslook detects installed browsers across `WebKit`, `Chromium`, `Electron`, `Dual CEF / WebKit`, `CEF Native`, `Gecko`, and `Ladybird` engines while excluding media players such as `VLC`.
- **Non-destructive tab shield.** Scriptable browsers (`Safari`, `Google Chrome`, `Arc`, `Dia`, `Helium`, `yab`, `Brave`, `Microsoft Edge`, `Vivaldi`, `Opera`, and `Orion`) redirect blocked tabs in-place to the [local shield page](Resources/shield.html). That page uses an offline blurred background with zero runtime CSS blur filters.
- **Non-scriptable browser fallback.** Browsers without AppleScript tab control (`Firefox`, `Zen`, and `Electron` browsers) hide the window by default. You can opt in to **Send Cmd+W to close tab in non-scriptable browsers** in **Delays**.
- **Bedtime wind-down.** A `30` minute wind-down (`11:00 PM` to `11:30 PM`) enforces at least a `20` second breathing delay.
- **Strict curfew.** During curfew (`11:30 PM` to `6:00 AM`), overlays hide skip controls, lock manual quit without blocking macOS shutdown, and show a clock after `10:00 PM`.
- **Nightly Break-Glass pass.** You get `1` emergency pass per rolling night, resetting at `6:00 AM`. Each pass requires a `30` second wait and a typed note of at least `4` characters.
- **Native macOS settings.** Five panes (**Breaks**, **Delays**, **Sound**, **Stats**, and **Permissions**) live in a standard preferences window with **Launch at Login** and App Nap protection (`NSAppSleepDisabled`).

## Requirements

Verify that your Mac meets these requirements before building or installing Grasslook.

- **Operating system.** macOS `14.0` or later.
- **Build tools (from source).** Xcode with Swift `6.0` and XcodeGen (`project.yml`).
- **Node.js (optional).** Required only when running the `npm` scripts or the [Grasslook CLI wrapper](npm/bin/grasslook.js).

## Install and run

Choose source builds for local development or the CLI wrapper for terminal startup.

### Build and run from source

Run these commands from the repository root to generate the Xcode project, compile a Release build, and launch Grasslook.

```bash
xcodegen generate
make build
open ".derivedData/Build/Products/Release/Grasslook.app"
```

Pass `--open-settings` and an optional `--settings-tab` flag (`breaks`, `delays`, `sound`, `stats`, or `permissions`) when launching from Terminal to open a specific preferences tab immediately.

```bash
".derivedData/Build/Products/Release/Grasslook.app/Contents/MacOS/Grasslook" --open-settings --settings-tab=permissions
```

### Run with the CLI wrapper

Use the scripts in the [npm package manifest](package.json) and the [Grasslook CLI wrapper](npm/bin/grasslook.js) to launch, check, or stop Grasslook from Terminal.

```bash
npm install
npm start
node ./npm/bin/grasslook.js status
node ./npm/bin/grasslook.js stop
```

### Create release packages

Run the [release packaging script](build_and_package.sh) to build Release, run unit tests, and output `dist/Grasslook.dmg` and `npm/app/Grasslook.app.tar.gz`.

```bash
./build_and_package.sh
```

## Grant macOS permissions

macOS blocks browser URL checks and cross-app Automation events until you approve permissions for Grasslook. Complete these steps on first launch.

1. Open **Grasslook** from the menu bar, choose **Settings**, and select **Permissions**.
2. Select **Prompt Access** or **Open Accessibility**, then enable **Grasslook** under **System Settings > Privacy & Security > Accessibility**.
3. Select **Relaunch App** so macOS activates Accessibility access for the running binary.
4. Check **Detected browsers**, select **Open Automation** if a scriptable browser shows **Denied**, and allow **Grasslook** to control that browser.
5. Open **Breaks** and enable **Show 30s pre-break warning** or **Launch at Login** if you want pre-break alerts or automatic login startup.

## Accessibility and keyboard support

Grasslook uses native macOS AppKit and SwiftUI controls so assistive technologies work cleanly without custom overlays blocking navigation. The table below lists supported assistive features and where each applies.

| Feature | Supported behavior | Scope |
| --- | --- | --- |
| VoiceOver labels | Exposes native control titles, hides decorative icons, and labels icon-only rule delete buttons | Settings window and overlays |
| Voice Control | Matches visible button labels and registers alternate **Delete** and **Remove** names on rule actions | Settings **Delays** pane |
| Dynamic Type | Uses semantic `.body` and `.caption` text styles without hardcoded font pixel sizes | Settings panes |
| Full keyboard access | Supports `Command + ,` to open Settings, `Escape` to skip non-curfew breaks, and keyable overlay focus for Break-Glass notes | Settings and full-screen overlays |
| Reduce Motion | Disables overlay fade, ring, breathing bubble scaling, and tab-switch window resize animations while keeping countdown timers accurate | Overlays and Settings window |
| Differentiate Without Color | Pairs icons with text labels (`Granted`, `Denied`, `Prompt`, `AX Only`, `Unknown`) on every status indicator | Settings **Permissions** pane |

## Development and testing

Never edit `Grasslook.xcodeproj` by hand. Update the [XcodeGen project manifest](project.yml), regenerate the Xcode project, and run the build and `XCTest` targets through the [project Makefile](Makefile).

```bash
xcodegen generate
make build
make test
```

## Privacy and local storage

Grasslook runs offline with zero analytics telemetry and zero network calls. Settings, rules, bedtime schedule, Break-Glass history, and active cooldowns save atomically to `~/Library/Application Support/Grasslook/config.json`. Break and avoidance counters save locally in `UserDefaults`.

## License

Grasslook is open-source software released under the MIT License. See the [Grasslook repository on GitHub](https://github.com/testspeed002/Grasslook) for project details.
