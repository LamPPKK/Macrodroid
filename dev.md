# Macrodroid Developer Handbook

**Development Baseline:** Macrodroid 5.4.0 (Installed and verified on Apple Silicon macOS)  
**Swift Toolchain:** Swift 6.0 with Strict Concurrency Checking (`-strict-concurrency=complete`)  
**Target Platform:** macOS 15.0+ (Sequoia)  
**Authoritative Test Suite:** 99 native unit tests passing (`MacrodroidGate1Tests.swift`)

This handbook is the operational guide for developers contributing to Macrodroid. It outlines code ownership, architectural invariants, concurrency rules, debugging procedures, and testing commands.

---

## 1. Code Ownership & Subsystem Map

```text
Macrodroid/
├── App/
│   ├── MacrodroidApp.swift                 # Application entry point (@main)
│   ├── AppCoordinator.swift               # Window routing, lifecycle, playtime accumulation, audio mute
│   ├── MainWindowController.swift         # Window chrome, titlebar accessories, toast notifications
│   └── RuntimeSettingsWindowController.swift # Settings sheet: hardware resources, refresh rate, mic
├── Launcher/
│   ├── MacrodroidLauncherView.swift       # SwiftUI library UI (Grid/List, playtime badges)
│   ├── LauncherWindowController.swift     # Host window for SwiftUI launcher
│   └── AppIconExtractor.swift             # ADB badging dump parser, cached icon retrieval
├── Presentation/
│   ├── EmbeddedEmulatorView.swift         # MTKView, input capture, session timer, gesture router
│   ├── GooglePlayGamesOverlayView.swift    # In-Game Dashboard HUD (Shift+Tab glassmorphism card)
│   ├── KeymappingOverlayView.swift        # On-screen key badge renderer & visual drag editor
│   ├── FrameContract.swift                # 1080p/4K RGBA buffer validation
│   └── ViewportMapper.swift               # Aspect-ratio preserving coordinate translator
├── Runtime/
│   ├── MacrodroidRuntime.swift            # gRPC client service, process manager, ADB channels
│   ├── AppProfileModel.swift              # AppProfile, resolution, FPS, totalPlayTimeSeconds
│   ├── KeymappingModel.swift              # KeymapProfile, button bindings, KeymapProfileStore
│   ├── CommunityHubModel.swift            # Curated official game presets & regional matching
│   ├── GamepadManager.swift               # GameController framework bridge & virtual stick math
│   ├── MacroAutomationModel.swift         # Action recorder, pacing timeline, jitter variance
│   └── CombatBenchmarkAnalysis.swift      # SurfaceFlinger frame pacing & stutter detection
└── Tests/MacrodroidTests/
    ├── MacrodroidGate1Tests.swift         # Comprehensive unit tests (Playtime, Keymaps, Inputs)
    ├── GameFrameTelemetryTests.swift     # Framebuffer telemetry tests
    └── CombatBenchmarkAnalysisTests.swift # Stutter and frame pacing analysis tests
```

---

## 2. Developer Invariants & Coding Standards

### A. Swift 6 Strict Concurrency
1. **`@MainActor` Isolation**: All UI classes (`EmbeddedEmulatorView`, `GooglePlayGamesOverlayView`, `MainWindowController`, `PlayApp`) are isolated to `@MainActor`.
2. **`nonisolated deinit` Safety**: In Swift 6, `deinit` is `nonisolated`. Never access non-Sendable stored properties (such as `Timer`) inside `deinit`. Use `Task<Void, Never>?` for background timers, which can safely be cancelled in `deinit`.
3. **Sendable Models**: Value models (`AppProfile`, `KeymapProfile`, `TouchInput`, `GamepadState`) must conform to `Sendable`.

### B. Input Isolation & Leak Prevention
1. **Overlay Shielding**: When `isGPGOverlayVisible == true`, all mouse clicks (`mouseDown`, `mouseDragged`, `mouseUp`, `rightMouseDown`), keyboard presses (`keyDown`, `keyUp`), scroll gestures (`scrollWheel`), and magnification (`magnify`) must be absorbed and **NEVER** dispatched to the guest game.
2. **Cursor Trap Prevention**: Whenever the game window resigns key focus (`windowDidResignKey`), minimizes (`windowDidMiniaturize`), or closes (`windowWillClose`), mouse aim lock must automatically disengage and unhide the macOS cursor.
3. **Modifier Key Isolation**: Pressing `Option` in combinations such as `⌥⌘K` (Keymap Editor) or `⌥⌘R` (Macro Record) must not accidentally trigger Mouse Aim Lock.

### C. Clean Binary Ownership
1. **Zero Tampering**: Never patch, unpack, or re-sign official game APKs.
2. **Standard Protocols**: Communicate with the Android guest runtime solely via authenticated loopback gRPC (`EmulatorController`) and ADB.

---

## 3. Build & Test Commands

### 🔨 Build Release Application Bundle
```sh
/bin/zsh scripts/build-macrodroid-app.command
```
Outputs: `dist/Macrodroid.app`.

### 🧪 Run Native Unit Test Suite
Execute the 99 unit tests:
```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project Macrodroid.xcodeproj \
  -scheme Macrodroid \
  -configuration Debug \
  -destination 'platform=macOS' \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO
```

### 🔬 Run Comprehensive 6-Phase Repository Verification
Executes toolchain check, SwiftLint, shell syntax, SQL schema self-tests, and unit tests:
```sh
/bin/zsh scripts/test-all.command
```

---

## 4. Debugging & Telemetry Inspection

### A. Inspect Local Telemetry Database
Macrodroid records continuous graphics receipts and SurfaceFlinger samples in SQLite:
```sh
sqlite3 "$HOME/Library/Application Support/Macrodroid/telemetry.sqlite"
```
Useful diagnostic queries:
```sql
-- View recent game sessions
SELECT session_id, app_package, target_fps, started_utc, ended_utc FROM session_runs ORDER BY id DESC LIMIT 5;

-- Check frame pacing and stutter incidents
SELECT observed_utc, display_fps, dropped_frames, choreographer_skips 
FROM frame_telemetry_samples 
WHERE choreographer_skips > 0 
ORDER BY id DESC LIMIT 10;
```

### B. Guest ADB Shell & Logcat Diagnostics
To interact directly with the running guest emulator:
```sh
adb -s emulator-5582 shell dumpsys SurfaceFlinger --latency
adb -s emulator-5582 logcat -d | grep -E "Vulkan|ANGLE|Choreographer|AudioFlinger"
```

### C. Checking Audio Keycode Routing
Audio mute is routed via Android keycode 164 (`KEYCODE_VOLUME_MUTE`). You can verify guest volume stream status:
```sh
adb -s emulator-5582 shell media volume --stream 3 --get
```

---

## 5. Adding New Game Community Presets

To add a new pre-tuned game preset to the Community Hub:
1. Open [`CommunityHubModel.swift`](file:///Users/lamndt/mactician/Macrodroid/Runtime/CommunityHubModel.swift).
2. Add a new `CommunityPreset` entry in `defaultPresets`:
   ```swift
   CommunityPreset(
       packageIdentifier: "com.example.game",
       title: "Example Game",
       developer: "Developer Name",
       category: .action,
       keymapProfile: KeymapProfile(
           packageName: "com.example.game",
           appName: "Example Game",
           dpad: KeymapDPad(normalizedCenterX: 0.18, normalizedCenterY: 0.72, radius: 80),
           buttons: [
               KeymapButton(keyLabel: "Space", keyCode: 49, normalizedX: 0.88, normalizedY: 0.80, actionName: "Attack"),
               KeymapButton(keyLabel: "Q", keyCode: 12, normalizedX: 0.78, normalizedY: 0.82, actionName: "Skill 1")
           ]
       ),
       recommendedFPS: .fps120,
       recommendedResolution: .p1080,
       recommendedOrientation: .landscape
   )
   ```
3. Run the test suite to verify matching and persistence:
   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Macrodroid.xcodeproj -scheme Macrodroid -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO
   ```
