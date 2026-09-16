# Macrodroid Project Record

**Status:** Authoritative for the active repository state.  
**Current Development Line:** `codex/native-macrodroid-5.4.0`  
**Current Release Version:** Macrodroid 5.4.0 (Google Play Games on PC Parity, In-Game HUD, Playtime Tracking, Gamepad & Audio Integration).  
**Test Suite Verification:** 99 / 99 tests passing (100% pass rate).

---

## 1. Goal & Product Vision

Deliver a premium, 100% native macOS application that brings the **Google Play Games on PC** experience to Apple Silicon Macs. Macrodroid enables users to install, launch, play, and automate any official Android game or application with PC-grade desktop ergonomics:
- Native fullscreen Spaces and multi-window multitasking.
- High-refresh gaming up to 144 Hz.
- Low-latency mouse, keyboard, and gamepad input.
- Real-time playtime and session duration tracking.
- In-game dashboard overlay accessible via `Shift+Tab`.
- Community Hub presets for instant, zero-configuration keymapping.

The Android emulator is treated strictly as an isolated, headless graphics runtime (`-no-window`) and is never exposed as the user interface.

---

## 2. Architectural Evolution

```text
┌────────────────────────────────────────────────────────────────────────────┐
│                              Macrodroid.app                                │
│                                                                            │
│  ┌─────────────────────────┐ ┌───────────────────────────────────────────┐ │
│  │     AppCoordinator      │ │       MacrodroidLauncherView (SwiftUI)    │ │
│  │   (Session Playtime,    │ │     • App Library (Grid / List view)      │ │
│  │    Multi-Window Router) │ │     • Drag & Drop APK / Bundle Installer  │ │
│  └────────────┬────────────┘ └───────────────────────────────────────────┘ │
│               │                                                            │
│  ┌────────────▼──────────────────────────────────────────────────────────┐ │
│  │                    MainWindowController (AppKit)                      │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │ │
│  │  │                     EmbeddedEmulatorView                        │  │ │
│  │  │  • MetalKit Triple-Buffered Presenter (Host Metal 3 GPU)        │  │ │
│  │  │  • Real-Time Session Duration Task (every 5s async sync)        │  │ │
│  │  │  • ViewportMapper (Letterbox protection & dynamic resolution)   │  │ │
│  │  │                                                                 │  │ │
│  │  │  ┌───────────────────────────────────────────────────────────┐  │  │ │
│  │  │  │     GooglePlayGamesOverlayView (Shift+Tab Dashboard HUD)  │  │  │ │
│  │  │  │  • Session & Playtime Badge   • Gamepad Detection Pill    │  │  │ │
│  │  │  │  • Reset Keymap to Defaults   • Audio Mute Toggle (164)   │  │  │ │
│  │  │  │  • Refresh Rate (60-144Hz)    • Mouse Aim Lock (F10 / ⌥)  │  │  │ │
│  │  │  └───────────────────────────────────────────────────────────┘  │  │ │
│  │  │                                                                 │  │ │
│  │  │  ┌───────────────────────────────────────────────────────────┐  │  │ │
│  │  │  │        KeymappingOverlayView (On-Screen Key Badges)       │  │  │ │
│  │  │  │  • D-Pad Joystick (WASD)       • Click / Aim / Fire       │  │  │ │
│  │  │  └───────────────────────────────────────────────────────────┘  │  │ │
│  │  └─────────────────────────────────────────────────────────────────┘  │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────┬───────────────────────────────────────┘
                                     │
                     Loopback gRPC (Port 5582) / ADB (5038)
                                     │
┌────────────────────────────────────▼───────────────────────────────────────┐
│              Headless Google Android Emulator (-no-window)                 │
│  • Official ARM64 Guest Image (API 36 / Android 16)                        │
│  • VirtIO-GPU Address Space Graphics (ASG) Transport                       │
│  • Guest ANGLE (OpenGL ES → Vulkan)                                        │
│  • Host MoltenVK (Vulkan → Metal 3 Translator)                             │
│  • SurfaceFlinger Display Pipeline & Hardware AudioFlinger                 │
└────────────────────────────────────────────────────────────────────────────┘
```

### Chronology of Milestones:
1. **Phase 1 (Mactician / TFT Prototype)**:
   - Proved official ARM64 Android emulation and Riot Games Unreal Engine compatibility on M4 Apple Silicon.
   - Identified and solved ADB authorization regressions by using isolated host launcher with loopback gRPC (`port 5582`).
2. **Phase 2 (Macrodroid 2.0 - 3.0 Native App Transition)**:
   - Replaced Qt emulator window with native `EmbeddedEmulatorView` backed by MetalKit.
   - Built dynamic `ViewportMapper` for aspect-ratio preservation and letterbox rejection.
   - Implemented native Vietnamese IME (`⌘I`), trackpad 2-finger scroll, and pinch zoom.
3. **Phase 3 (Macrodroid 4.0 Gaming Platform)**:
   - Added `GamepadManager` with full support for DualSense, DualShock 4, Xbox, and Switch Pro controllers.
   - Built `MacroAutomationModel` for recording and replaying touch sequences with human jitter variance.
   - Launched `CommunityHubModel` with pre-tuned profiles for Wild Rift, Free Fire, PUBG, Genshin, and TFT.
4. **Phase 4 (Macrodroid 5.0 - 5.4 Google Play Games on PC Parity)**:
   - Implemented glassmorphism In-Game Dashboard HUD (`GooglePlayGamesOverlayView`, `Shift+Tab`).
   - Integrated real-time Session and Cumulative Playtime tracking (`AppProfile.totalPlayTimeSeconds`).
   - Added dynamic gamepad connection status badge and one-touch audio mute toggle (`KEYCODE_VOLUME_MUTE` 164).
   - Added one-touch preset reset restoring official community configurations.
   - Expanded high-refresh eSports targets to 90 Hz, 120 Hz, and 144 Hz.
   - Reached 99/99 automated native unit tests passing with 0 failures.

---

## 3. Core Architectural Tenets

1. **Clean Ownership & Zero Tampering**:
   - Never modify, patch, unpack, or re-sign official APK binaries.
   - Maintain untouched Google Play Services and Riot Games anti-tamper update channels.
2. **Authenticated Loopback gRPC (`EmulatorController`)**:
   - Route mouse, touch, keyboard, and frame streaming through high-speed authenticated loopback gRPC (`port 5582`).
   - Completely bypass `adb shell` execution latency for user input.
3. **Swift 6 Strict Concurrency**:
   - Enforce `@MainActor` isolation on all UI controllers, overlay views, and state models.
   - Ensure thread-safe background presentation callbacks and lock-protected telemetry snapshots.
4. **Observable Performance Lab**:
   - Continuously record frame presentation timestamps, Metal latencies, and SurfaceFlinger markers into local SQLite databases under `~/Library/Application Support/Macrodroid`.
   - Never rely on lobby averages; evaluate 1% lows and frame pacing degradation based on evidence.

---

## 4. Component Mapping

| Subsystem | Primary Files | Responsibility |
|---|---|---|
| **App Lifecycle & Coordination** | `AppCoordinator.swift`<br>`MainWindowController.swift`<br>`RuntimeSettingsWindowController.swift` | Coordinates game window creation, session duration accumulation, audio mute routing, and system settings. |
| **Launcher Experience** | `MacrodroidLauncherView.swift`<br>`LauncherWindowController.swift`<br>`AppIconExtractor.swift` | Modern library UI, APK drag-and-drop installer, bundle sharing, and Dock shortcut creator. |
| **Metal Presenter & Input** | `EmbeddedEmulatorView.swift`<br>`FrameContract.swift`<br>`ViewportMapper.swift`<br>`TouchInput.swift` | Triple-buffered Metal renderer, coordinate normalization, mouse aim lock, gesture dispatcher, and session timer. |
| **In-Game Dashboard HUD** | `GooglePlayGamesOverlayView.swift` | Glassmorphism card overlay (`Shift+Tab`), playtime badge, gamepad pill, mute and reset buttons. |
| **Keymapping Engine** | `KeymappingModel.swift`<br>`KeymappingOverlayView.swift`<br>`CommunityHubModel.swift` | On-screen key badge editing, virtual D-Pad stick calculations, official preset management. |
| **Gamepad Integration** | `GamepadManager.swift` | Apple `GameController` framework bridge, thumbstick-to-touch math, button dispatch. |
| **Automation Engine** | `MacroAutomationModel.swift` | Macro recording, replay scheduling, timeline pacing, and human variance jitter. |
| **Telemetry & Diagnostics** | `CombatBenchmarkAnalysis.swift`<br>`MacrodroidRuntime.swift` | SQLite telemetry storage, SurfaceFlinger metric parser, stutter classifier. |

---

## 5. Verification & Acceptance Gates

All changes to the Macrodroid codebase must satisfy:
1. **Automated Unit Tests**: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test` must pass 99/99 tests with 0 failures.
2. **Swift Concurrency Audit**: No unsafe non-Sendable access from `nonisolated deinit` or worker threads.
3. **Input Boundary Audit**: When `isGPGOverlayVisible == true`, no user input, mouse clicks, or gestures may leak into the guest game.
4. **Cursor Trap Audit**: When a game window loses key focus, miniaturizes, or closes, mouse aim lock must automatically disengage and unhide the macOS cursor.
5. **Playtime Persistence**: Closing a game session must accurately increment `totalPlayTimeSeconds` and update `lastPlayedDate` in `AppProfileStore`.
