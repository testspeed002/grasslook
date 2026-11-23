#!/usr/bin/env bash
set -euo pipefail

echo "========================================"
echo "  Grasslook Release Packaging Pipeline  "
echo "========================================"

echo "==> [1/4] Generating Xcode Project..."
xcodegen generate

echo "==> [2/4] Building Grasslook in Release Configuration..."
xcodebuild -project "Grasslook.xcodeproj" -scheme Grasslook -configuration Release -derivedDataPath .derivedData build

echo "==> [3/4] Running Unit Tests..."
xcodebuild -project "Grasslook.xcodeproj" -scheme Grasslook -derivedDataPath .derivedData test

echo "==> [4/4] Creating Custom DMG Installer..."
mkdir -p dist/dmg_staging
rm -rf dist/dmg_staging/*
cp -R .derivedData/Build/Products/Release/Grasslook.app dist/dmg_staging/
ln -sf /Applications dist/dmg_staging/Applications

DMG_PATH="dist/Grasslook.dmg"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "Grasslook" \
  -srcfolder dist/dmg_staging \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf dist/dmg_staging

echo "==> [5/5] Packaging NPM Distribution Bundle..."
mkdir -p npm/app
tar -czf npm/app/Grasslook.app.tar.gz -C .derivedData/Build/Products/Release Grasslook.app

echo "========================================"
echo "  🎉 Release Packages Created!"
echo "  DMG Artifact: $DMG_PATH ($(ls -lh "$DMG_PATH" | awk '{print $5}'))"
echo "  NPM Artifact: npm/app/Grasslook.app.tar.gz ($(ls -lh npm/app/Grasslook.app.tar.gz | awk '{print $5}'))"
echo "========================================"
