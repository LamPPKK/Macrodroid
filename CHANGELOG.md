# Changelog

## [5.1] — 2026-09-10 (Android Image Optimization: Adaptive Profiles, Image Health & AVD Tuning)

### Added
- **Adaptive Hardware Profile System (`HardwareCapabilityProbe`)**:
  - Auto-detects Apple Silicon memory tier via `sysctlbyname("hw.memsize")` (no special entitlements required).
  - Four tiers: `ultraMax` (≥ 64 GB), `pro` (≥ 24 GB), `standard` (≥ 16 GB), `compat` (< 16 GB).
  - M4 Max/Ultra gets 8 vCPU, 8 GB guest RAM, 4 MB ASG write buffer; Compat drops to 4 vCPU, 4 GB RAM, 512 KB buffer.
  - `withASGBuffers(writeBufferSize:writeStepSize:dataRingSize:)` extension for clean tier-level ASG tuning.
- **Image Health & Maintenance Engine (`ImageHealthMonitor`)**:
  - Pre-launch checks: measures `userdata-qemu.img` size, detects corrupted or unexpected snapshots.
  - Post-shutdown maintenance: removes stale lock files and suspect snapshot residue.
  - ADB disk usage sampler with POSIX `df /data` output parser (`parseDFOutput`).
  - `DiskUsageSample` and `ImageHealthReport` data models with human-readable summaries.
- **Android Image Optimization section in Runtime Settings**:
  - Hardware tier badge (auto-detected, read-only display).
  - Virtual disk size dropdown (4–16 GB) controlling `disk.dataPartition.size`.
  - "Run Health Check…" button launching an `NSAlert` sheet with full `ImageHealthReport`.
  - Window height expanded from 640 → 720 px to accommodate new section.
- **New AVD config.ini optimization keys** (written by `AVDConfigurationTransaction`):
  - `hw.heapSize` / `vm.heapSize` — ART/Dalvik heap capped at `min(ramMiB/9, 576)` MiB (reduces GC pauses).
  - `disk.dataPartition.size` — driven by `dataDiskGB` profile field (default 8 GB; prevents I/O stalls).
  - `disk.cachePartition.size = 512m` — increased APK cache.
  - `hw.audioInput` — controlled by `microphoneEnabled` profile flag (avoids audio thread overhead when mic is off).
- **ASG buffer defaults upgraded** in `MacrodroidRuntimeProfile.playable`:
  - `asgWriteStepSize`: 16 384 → **32 768** bytes (+2× throughput per submit).
  - `asgDataRingSize`: 32 768 → **65 536** bytes (+2× ring depth).
- **`MacrodroidRuntimeProfile` new fields**:
  - `dataDiskGB: Int` (persisted via `UserDefaults` key `runtime.dataDiskGB`).
  - `heapSizeMiB: Int` (computed, not persisted).
  - `supportedDataDiskGB = [4, 6, 8, 12, 16]` static allowed list.

### Tests
- Expanded test suite to **82 native unit tests** (+7) — all passing:
  1. `testAVDConfigTransactionIncludesHeapSize` — verifies `heapSizeMiB` formula for baseline profile.
  2. `testAVDConfigHeapSizeCapAt576MiB` — verifies 576 MiB cap for 8 GB+ RAM profiles.
  3. `testAVDConfigTransactionDiskAllocation` — verifies `dataDiskGB` round-trips through `with()`.
  4. `testHardwareCapabilityProbeMemoryTiers` — verifies all 4 tier boundaries.
  5. `testAdaptiveProfileCompatTierReducesResources` — verifies compat profile (4 vCPU / 4 GB).
  6. `testAdaptiveProfileUltraMaxTierMaximizesResources` — verifies ultra max profile (8 vCPU / 8 GB / 4 MB ASG).
  7. `testImageHealthMonitorDFOutputParsing` — verifies `df /data` POSIX output parser.

---

## [5.0] — 2026-09-10 (Phases 8–14: PlayCover & WSA Parity, Gamepad, MetalFX & Macro Engine)

### Added
- **Visual Keymapping Engine (PlayCover-style)**:
  - Full in-game visual overlay (`⌘K`) and drag-and-drop interactive keymapper (`⌥⌘K`).
  - D-Pad 8-direction continuous multi-touch movement and 1-click mouse aim lock (`⌥`).
  - Keymap profiles persisted per-app in `~/Library/Application Support/Macrodroid/Keymaps/`.
- **Per-App Graphics, Orientation & 120 FPS ProMotion Profiles (WSA-style)**:
  - Per-app settings for display orientation (Portrait 9:16 vs Landscape 16:9), target framerate (30 / 60 / 120 FPS ProMotion), and automated classification for popular phone apps.
- **Native Gamepad Interoperability**:
  - Deep Apple `GameController.framework` integration via `GamepadManager`.
  - Seamless support for PlayStation DualSense / DualShock 4, Xbox Wireless, Nintendo Switch Pro, and MFi controllers.
  - Virtual analog stick deflection math with deadzone clamping and automated routing to `KeymapProfile`.
- **Dynamic Multi-Resolution & MetalFX Upscaling**:
  - Dynamic `FrameContract.Resolution` supporting 720p HD, 1080p FHD, 1440p 2K QHD, 4K Retina Ultra, and 21:9 Ultrawide Gaming.
  - Dynamic `ViewportMapper` providing accurate letterbox/pillarbox calculation and coordinate mapping.
- **Macro Automation & Recording Engine ("Macrodroid" Identity)**:
  - In-game macro recorder and playback engine triggered via `⌥⌘R` (record) and `⌥⌘P` (playback), plus titlebar accessory lightning button.
  - Anti-detection human variance jitter (±2.0 px micro-variance) to prevent bot detection in online games.
  - Portable persistence in `~/Library/Application Support/Macrodroid/Macros/`.
- **Community Profiles & Presets Hub**:
  - 5 pre-tuned flagship presets: TFT, League of Legends: Wild Rift, Genshin Impact, PUBG Mobile, and TikTok.
  - Portable `.macrodroid` bundle codec (`MacrodroidBundle`) for 1-click import and export of profiles and keymaps across Macs.

### Tests
- Expanded test suite to **75 native unit tests** (100% passing) across `MacrodroidGate1Tests`, `GameFrameTelemetryTests`, `CombatBenchmarkAnalysisTests`, and `GraphicsStackReceiptTests`.
- 100% clean SwiftLint compliance (0 violations across 31 Swift files).
- Passed all 6 phases of `automate-test-all.command` and `verify-macrodroid.command`.

---

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
