# Building & Testing Macrodroid

This guide documents the prerequisites, build workflows, testing procedures, and local verification gates for **Macrodroid 5.4**.

---

## 1. System Requirements

- **Hardware**: Apple Silicon Mac (M1, M2, M3, M4 series, including Pro, Max, and Ultra variants).
- **Operating System**: macOS 15.0 (Sequoia) or later.
- **Toolchain**:
  - **Xcode**: 16.0 or later (with macOS SDK 15+).
  - **Swift**: 6.0 toolchain with strict concurrency support.
  - **Shell / Utilities**: `zsh`, `jq`, `ripgrep` (installed via Homebrew or Xcode command line tools).
  - **Protocol Buffers**: (Optional for gRPC regeneration) `protoc` + `protoc-gen-swift` 1.28+.

---

## 2. Building from Command Line

### Debug Build
```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project Macrodroid.xcodeproj \
  -scheme Macrodroid \
  -configuration Debug \
  -destination 'platform=macOS' \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO
```

### Release Build
```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project Macrodroid.xcodeproj \
  -scheme Macrodroid \
  -configuration Release \
  -destination 'platform=macOS' \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO
```

The compiled application bundle will be located at:
`build/Release/Macrodroid.app` (or your configured Xcode DerivedData directory).

---

## 3. Running the Test Suite

Macrodroid features an extensive automated test suite consisting of **99 unit and integration tests** covering all subsystems:
- `ViewportMapperTests` (Coordinate normalization, aspect-ratio letterboxing)
- `KeybindingOverlayTests` (Visual HUD, hit-testing, active preset switching)
- `SmartAimTests` (Pointer lock, cursor sensitivity, edge wrapping)
- `GamepadMapperTests` (Apple GameController framework mapping)
- `MacroEngineTests` (Macro recording, playback timing, serialization)
- `MultiInstanceCoordinatorTests` (Window tiling, port allocation, instance focus)
- `GooglePlayGamesParityTests` (Overlay HUD, shortcut parity, achievement toasts)
- `GraphicsPipelineTests` (Metal 3 triple buffer presentation pool, vsync sync)
- `AudioStreamerTests` (CoreAudio ring buffer, loopback latency)
- `TelemetryCollectorTests` (SQLite session persistence, frame rate calculation)

### Run All 99 Tests:
```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Macrodroid.xcodeproj \
  -scheme Macrodroid \
  -configuration Debug \
  -destination 'platform=macOS' \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO
```

*Expected result:* **`** TEST SUCCEEDED **`** (99 tests passed, 0 failures).

---

## 4. Code Signing & Entitlements

Macrodroid accesses native macOS capabilities including Metal 3 graphics, loopback networking, and optional Game Controller inputs:

### Local Development Signing
For local testing, standard ad-hoc code signing or a local self-signed certificate is sufficient:
```sh
/bin/zsh scripts/ensure-local-signing-identity.command
```
This generates the `TFTMAC Local Code Signing` certificate in your macOS login keychain.

### Hardened Runtime & Distribution
For public distribution, builds require Apple Developer ID signing, hardened runtime flags, and Apple Notarization:
```sh
codesign --deep --force --options runtime \
  --sign "Developer ID Application: YOUR_TEAM_NAME (TEAM_ID)" \
  --entitlements Macrodroid/Macrodroid.entitlements \
  dist/Macrodroid.app
```

---

## 5. Cleaning Build Artifacts

To clear all cached build products and test logs:
```sh
rm -rf build/
rm -rf ~/Library/Developer/Xcode/DerivedData/Macrodroid-*
```
