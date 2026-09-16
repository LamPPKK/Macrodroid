# Macrodroid Architecture Specification

**Product Line:** Macrodroid 5.4.0  
**Target Architecture:** Apple Silicon (ARM64)  
**Host Frameworks:** AppKit, SwiftUI, MetalKit, Metal 3, GameController, CoreGraphics  
**Runtime Engine:** Headless Google Android Emulator (`-no-window`) with VirtIO-GPU ASG and MoltenVK

---

## 1. Architectural Overview

Macrodroid replaces the traditional emulator experience with an integrated native macOS client. It couples a headless Android guest runtime to a native MetalKit presentation shell via an authenticated, ultra-low-latency loopback gRPC transport.

```text
┌────────────────────────────────────────────────────────────────────────────┐
│ macOS Application Layer (AppKit + SwiftUI)                                 │
│                                                                            │
│  [MacrodroidLauncher] ────> [AppCoordinator] ────> [MainWindowController] │
│                                                          │                 │
│                                                          ▼                 │
│                                              [EmbeddedEmulatorView]        │
│                                              • Metal MTKView Presenter     │
│                                              • ViewportMapper Coordinate   │
│                                              • Session Duration Tracker    │
│                                              • Input Dispatcher            │
│                                                          │                 │
│                 ┌────────────────────────────────────────┼──────────────┐  │
│                 ▼                                        ▼              ▼  │
│    [GooglePlayGamesOverlayView]               [KeymappingOverlay] [Gamepad]│
│    • Glassmorphism HUD (Shift+Tab)            • On-screen badges • Stick   │
│    • Session time, Gamepad pill, Mute, Reset  • WASD D-Pad       • Buttons │
└──────────────────────────────────────────────────────────┬─────────────────┘
                                                           │
                                   Local Loopback IPC      │
                    ┌──────────────────────────────────────┴──────────────┐
                    │  Authenticated EmulatorController gRPC (Port 5582)  │
                    │  • sendTouch(TouchInput)                            │
                    │  • sendMouse(MouseInput)                            │
                    │  • sendKeyboard(KeyboardInput)                      │
                    │  • sendClipboard(String)                            │
                    │  • streamScreenshot(RGBA8888 1920x1080)             │
                    └──────────────────────────────────────┬──────────────┘
                                                           │
┌──────────────────────────────────────────────────────────▼─────────────────┐
│ Headless Guest Runtime (Google Android Emulator ARM64, -no-window)         │
│                                                                            │
│  [Guest Android Application (e.g. TFT, Wild Rift, Free Fire, Genshin)]     │
│                             │                                              │
│                             ▼                                              │
│               [SurfaceFlinger Compositor]                                  │
│                             │                                              │
│                             ▼                                              │
│         [ANGLE (OpenGL ES 3.2 → Vulkan 1.3 Translator)]                    │
│                             │                                              │
│                             ▼                                              │
│      [VirtIO-GPU ASG (Address Space Graphics Transport)]                   │
│                             │                                              │
│                             ▼                                              │
│         [MoltenVK (Vulkan 1.3 → Apple Metal 3 Driver)]                     │
│                             │                                              │
│                             ▼                                              │
│         [Hardware CoreAudio & AudioFlinger Subsystem]                      │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Host Presentation Pipeline (MetalKit & Metal 3)

The display presentation is owned by `EmbeddedEmulatorView` (an `MTKView` subclass):

1. **Triple-Buffered Texture Pool**: A thread-safe `PresenterGPUState` manages a pool of 3 Metal texture buffers (`MTLTexture`). While buffer 0 is scanned out by the display, buffer 1 is written with new guest frame data, and buffer 2 remains queued to eliminate frame tearing.
2. **Dynamic Resolution Handling**: When the game orientation or resolution changes (e.g., from 1080p landscape to 1080×1920 portrait), the Metal texture cache is automatically reallocated, avoiding GPU memory assertion faults.
3. **Pacing & Refresh Rates**: Supports selectable framerate targets up to 144 FPS (`.fps30`, `.fps60`, `.fps90`, `.fps120`, `.fps144`). When throttled to the background, the view dynamically drops to 15 FPS to conserve battery and CPU resources.

---

## 3. Viewport Mapping & Coordinate Normalization

Touch and mouse interactions on macOS are normalized through `ViewportMapper`:

- **Aspect Ratio Preservation**: Games are letterboxed or pillarboxed to maintain their native aspect ratio (e.g. 16:9 or 9:16) regardless of macOS window dimensions.
- **Letterbox Guard**: Coordinates falling outside the active game content rect are rejected immediately, preventing unintentional off-screen touches.
- **Dynamic Resolution Normalization**: Translates normalized coordinates `(0.0...1.0, 0.0...1.0)` into guest pixel coordinates `(0...width, 0...height)` using the runtime resolution rather than hardcoded dimensions.

---

## 4. In-Game Dashboard HUD (`GooglePlayGamesOverlayView`)

Inspired by the Google Play Games on PC HUD overlay:

1. **Summon / Dismiss Mechanism**: Triggered globally via `Shift + Tab` or `Escape`.
2. **Event Shielding**: When active, all keyboard presses, mouse clicks, drags, scroll events, and trackpad gestures are consumed by the overlay, preventing leakage into the underlying guest game.
3. **Smart Mouse Aim Lock Preservation**: If Mouse Aim Lock is active when the overlay opens, it is automatically suspended and the macOS cursor is revealed. Resuming the game automatically re-engages Mouse Aim Lock.
4. **Real-Time Telemetry & Controller Monitoring**:
   - Session duration is measured via a monotonic timer and displayed alongside total cumulative playtime.
   - Controller status listens directly to `GamepadManager` notifications, showing connected models (DualSense, Xbox, etc.).
   - Audio mute sends keycode 164 (`KEYCODE_VOLUME_MUTE`) through ADB/gRPC with visual toast confirmation.

---

## 5. Storage Hierarchy & State Management

All persistent user data is isolated cleanly under macOS `Application Support`:

```text
~/Library/Application Support/Macrodroid/
├── Profiles/                     # Per-app settings (JSON)
│   ├── com.riotgames.league.wildrift.json
│   └── com.dts.freefireth.json
├── Keymaps/                      # Custom user keymappings (JSON)
│   ├── com.riotgames.league.wildrift.json
│   └── com.dts.freefireth.json
├── Icons/                        # High-resolution application icons extracted via ADB
│   ├── com.riotgames.league.wildrift.png
│   └── com.dts.freefireth.png
├── Macros/                       # Recorded automated macro sequences (JSON)
│   └── AutoFarm_com.dts.freefireth.json
├── Shared/                       # Bidirectional host-guest file sharing folder
├── Screenshots/                  # Lossless PNG game screenshots (⌘S)
└── telemetry.sqlite              # Continuous graphics and combat performance metrics database
```

---

## 6. Failure Boundaries & Recovery

- **AVD Transaction Safety**: Handled by `AVDTransactionGuard` to prevent corrupted guest state during abrupt host restarts.
- **Lease Lock Enforcement**: Only one active Macrodroid process may hold the runtime lease for an AVD instance.
- **Graceful Window Teardown**: Closing a game window automatically disengages mouse locks, saves playtime increments, invalidates timers safely under Swift 6 strict concurrency, and returns the guest to the home state.
