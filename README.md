# 🌱 Grasslook
> **Rest your eyes. Reset your posture. Reclaim your focus.**  
> A native, privacy-first macOS digital wellness companion combining proactive eye rest with mindful distraction delays.
---
## ⚡ Quick Start
### Install Command
```bash
npm install
```
*(or `./build_and_package.sh` to build the native macOS `.app` and `.dmg`)*
### Run Command
```bash
npm start
```
*(or `open .derivedData/Build/Products/Debug/Grasslook.app`)*
### Build Command
```bash
npm run build
```
### Test Command
```bash
npm test
```
---
## 📦 Distribution Packages
- **DMG Installer:** `dist/Grasslook.dmg`
- **NPM Package:** `npm/app/Grasslook.app.tar.gz` (`npx grasslook`)
---
## 🛠️ Stack & Requirements
- **Platform:** macOS 14.0+ (Sonoma) / macOS 15.0+ (Sequoia) / macOS 26.0+ (Tahoe)
- **Language:** Swift 6+, SwiftUI, AppKit
- **Project Generator:** XcodeGen (`project.yml`)
- **Zero Telemetry:** 100% local persistence with SwiftData / UserDefaults
---
