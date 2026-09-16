# Releasing Macrodroid

This document defines the release lifecycle, packaging pipeline, signing contracts, and release gate checklist for **Macrodroid 5.4**.

---

## 1. Application Identity

```text
Application Name:  Macrodroid
Bundle Identifier: com.macrodroid
Architecture:      arm64 (Apple Silicon native: M1 / M2 / M3 / M4)
Minimum macOS:     macOS 15.0 (Sequoia)
Current Version:   5.4.0
Build Number:      99
```

---

## 2. Release Verification Gate

Every release candidate must pass all criteria before distribution:

### 1. Test Suite Acceptance
All 99 unit and integration tests must pass cleanly without warnings:
```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Macrodroid.xcodeproj \
  -scheme Macrodroid \
  -configuration Release \
  -destination 'platform=macOS' \
  ONLY_ACTIVE_ARCH=YES
```

### 2. Workspace Cleanliness
Ensure no untracked binaries, AVD state, private session logs, or credentials exist in the git tree:
```sh
git status --porcelain
```

### 3. Protocol & Schema Integrity
Confirm that `Vendor/AndroidEmulator/emulator_controller.proto` matches the frozen authority checksum in `Vendor/AndroidEmulator/SOURCE.json`.

---

## 3. Code Signing & Notarization

### Apple Developer ID Signing
Production releases must be signed using a valid Apple Developer ID certificate with Hardened Runtime enabled:
```sh
codesign --deep --force --options runtime \
  --sign "Developer ID Application: Macrodroid Project (TEAM_ID)" \
  --entitlements Macrodroid/Macrodroid.entitlements \
  dist/Macrodroid.app
```

### Apple Notarization
Submit the signed `.app` or `.dmg` for Apple notarization:
```sh
xcrun notarytool submit dist/Macrodroid.dmg \
  --keychain-profile "macrodroid-notary-profile" \
  --wait
```

### Ticket Stapling
Staple the notarization ticket to the distributed artifact:
```sh
xcrun stapler staple dist/Macrodroid.dmg
```

---

## 4. Packaging & Distribution

### DMG Packaging
Distributable disk images are packaged with an aesthetic volume icon, Applications folder symlink, and default window geometry:
```sh
hdiutil create -volname "Macrodroid" \
  -srcfolder dist/Macrodroid.app \
  -ov -format UDZO \
  dist/Macrodroid-5.4.0.dmg
```

### Sparkle Update Feed (Optional)
If distributed via Sparkle automatic updates, generate the `appcast.xml` item with EdDSA signature:
```sh
./bin/generate_appcast dist/
```

---

## 5. Security & Legal Boundaries

- **No Redistribution of Game APKs**: Macrodroid does NOT bundle, distribute, or modify game APKs (Riot Games, HoYoverse, Tencent, etc.). All game packages are acquired by the end user via the official Google Play Store.
- **Privacy Assurance**: Telemetry data is stored locally in SQLite (`~/Library/Application Support/Macrodroid/Captures/`) and is never exfiltrated to external analytics servers.
