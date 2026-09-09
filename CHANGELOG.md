# Changelog

## [4.1] — 2026-09-10 (Phases 5–7: Production Hardening, CI & Input Coverage)

### Added
- **Notification App Icon (Phase 5)**: macOS notification banners now display the real
  Android app icon (cached PNG from `AppIconExtractor`) as a thumbnail via
  `UNNotificationAttachment`, replacing the generic Macrodroid icon.
- **True Independent Multi-Window (Phase 5)**: `openAppWindow` now uses
  `activeAppWindows[pkg]` as the primary lookup. Each unique Android package
  receives its own independent `MainWindowController`; re-opening an already-
  running package focuses its existing window instead of reusing another.
- **Dynamic Test Discovery (Phase 6)**: `automate-test-all.command` dynamically
  parses native unit test count via grep instead of relying on hardcoded counts.
- **Input Pipeline & Telemetry Coverage (Phase 7)**: Expanded test suite to 59
  tests (+4 tests) covering primary touch sequence contact/release pressures,
  pinch span clamp boundaries, multi-subscriber mailbox telemetry, and modern
  Android 12+ root task format parsing.

### Changed
- **CI Modernization (Phase 6)**: Updated GitHub Actions checkout to `actions/checkout@v7.0.1`
  and added SwiftLint version assertion.
- **Release Documentation (Phase 6)**: Realigned release procedures and verification
  commands with `verify-macrodroid.command` and documented SSOT freeze boundaries.

### Fixed
- `openAppWindow` would incorrectly call `updateTitle(appName:)` on an
  unrelated window when a second app was launched while a first was open.

---

## [4.0] — 2026-09-08 (Phase 4: Multi-Instance, App Gallery & Vietnamese IME)

### Added
- **Per-App Independent Windows (Multi-Instance)**: `LatestFrameMailbox` gains
  `latestFrame(after:)` allowing multiple `MainWindowController` subscribers to
  read frames non-destructively without starvation. `FreeformTaskManager` added
  for Android Freeform windowing orchestration (`WINDOWING_MODE_FREEFORM = 5`).
- **App Gallery & Automatic Icon Extraction**: `AppIconExtractor` pulls APK
  files from the Android guest via ADB, extracts the highest-density launcher
  icon using `aapt2` (with `unzip` fallback), caches to
  `~/Library/Application Support/Macrodroid/Icons/`, and automatically creates
  macOS `.app` shortcuts in `~/Applications/Macrodroid Apps/`.
- **Vietnamese IME Direct Forwarding**: `EmbeddedEmulatorView` now conforms to
  `@MainActor @preconcurrency NSTextInputClient`. Telex/VNI composition is
  handled natively by macOS; composed text is delivered to the Android guest as
  `adb shell input text`. Toggle via `⌘I` or the HUD `VN` button.
- **Task Switcher HUD** (`⌘T`): Shows a menu of running Android tasks with real
  app icons and 1-click switching. Backed by `FreeformTaskManager.parseTasks`.

### Tests
- Added 4 native unit tests (51 total): multi-window mailbox subscription,
  Vietnamese IME NFC/NFD normalization, Freeform task dumpsys parsing, and APK
  package line parsing.

---

## [3.0] — Phase 3: Deep Platform Features

### Added
- **Trackpad Gestures**: 2-finger scroll → Android scroll event; pinch-to-zoom
  → Android pinch gesture via `NSMagnificationGestureRecognizer`.
- **Microphone Input**: Virtual microphone support for voice chat in games
  (`-audiodev coreaudio,id=in,...`). Toggle via Settings.
- **Class Rename**: All `TFTMAC`-prefixed classes renamed to `Macrodroid`
  (`MacrodroidRuntimeController`, `MacrodroidRuntimeProfile`, etc.).

---

## [2.0] — Phase 2: Desktop Interactivity

### Added
- **Two-Way Clipboard Sync**: `NSPasteboard` ↔ Android `ClipboardManager` via
  gRPC stream with ADB fallback.
- **Drag & Drop File Sharing**: Drop files onto the game window → `adb push`
  to `/sdcard/Download/` + MediaScanner broadcast.
- **Smart Idle Suspend**: Auto-pause vCPU after configurable idle timeout;
  resume in < 50 ms on window focus.
- **Persistent Menu Bar Daemon**: Quick Launch, Sleep/Resume, Toggle Dock Icon.
- **Shared Folder**: `~/Macrodroid/Shared` bidirectional sync with ADB.
- **Android Freeform Multi-Window** (`⌘M`): Toggle `enable_freeform_support`.
- **Google Ecosystem**: Aurora Store + microG GmsCore + FakeStore one-click.
- **In-Game HUD Controls**: Rotate (`⌘R`), Screenshot (`⌘S`), Keymap Overlay
  (`⌘K`), Mouse Aim Lock (`⌥`).

---

## [1.0] — Phase 1: Foundation

### Added
- **Headless QEMU Engine**: `-qt-hide-window` background mode; `alwaysBackground`
  and `onDemand` launch policies.
- **Notification Mirroring**: ADB polling → `UNUserNotificationCenter`; click
  banner to focus or launch the corresponding Android app window.
- **macOS App Shortcuts**: Auto-generated `.app` bundles in
  `~/Applications/Macrodroid Apps/` for Spotlight & Dock integration.

---

## Legacy (pre-v1.0)

### Changed
- Split repository/CI verification from the local-only installed-runtime and
  signing audit; CI no longer depends on `/Applications`, an external runtime,
  a private signing identity, credentials, or captures.
- Updated GitHub checkout to `actions/checkout@v7.0.1` while retaining Node 24.
- Established TFTMAC as the sole product and repository identity.
- Replaced legacy validation with the native TFTMAC build/test verifier.
- Removed obsolete launcher, hosted update/feed, helper-host, and branding layers.
- Moved runtime authority to the stock Google Android Emulator and official
  Google Play TFT lifecycle.
- Retired source-built emulator work from the normal product path.

### Current target

- Native macOS application bundle: `com.macrodroid`.
- Stock Android Emulator 37.1.11.
- Official Google Play package `com.riotgames.league.teamfighttactics`.
- 1920x1080 / 60 Hz target on Apple Silicon.
