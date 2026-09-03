# Macrodroid

> **Native Apple Silicon Android Client & High-Performance Gaming Runtime**

Macrodroid is a high-performance native macOS application built in Swift and MetalKit, designed to run official Android applications and mobile games—deeply optimized for Teamfight Tactics (TFT)—on Apple Silicon (M1/M2/M3/M4) Macs through a headless, fully embedded Google Android Emulator.

---

## 🌟 Highlights

- **100% Native Mac Experience**: No third-party emulator windows or Qt toolbars. Macrodroid embeds the Android display directly inside a native AppKit window backed by MetalKit with full macOS Spaces and Fullscreen support.
- **Ultra-Low Latency Input**: Native macOS mouse clicks, drags, and keyboard strokes map directly to authenticated gRPC `EmulatorController.sendTouch` calls—bypassing `adb shell` execution overhead.
- **Metal Presentation Pipeline**: 1080p RGBA presentation rendered with a triple-buffered Metal texture pipeline, hardware-accelerated on Apple Silicon GPUs.
- **Engineering Performance Lab**: Built-in SQLite telemetry engine tracking continuous frame times, GPU render latencies (p95/p99), frame drops, and combat degradation incidents in real time.
- **Clean Ownership & Security**: Zero binary tampering with game APKs. Preserves official Google Play and Riot Games authentication and update lifecycles.

---

## 🏗 Architecture

```text
Macrodroid.app
  ├── AppKit Window & Menu Bar (Native macOS controls, fullscreen Space)
  ├── MetalKit Presentation Layer (MTKView, custom Metal pipeline, triple-buffering)
  ├── Authenticated gRPC Protocol (EmulatorController loopback over port 5582)
  │     ├── Native Touch & Mouse Mapping (ViewportMapper -> sendTouch)
  │     └── Native Frame Streaming (RGBA8888 1920×1080 -> LatestFrameMailbox)
  └── Headless Android Emulator (-no-window via Macrodroid Emulator Host.app)
        ├── Official ARM64 Guest Image (API 36 / Android 16)
        ├── Guest ANGLE (OpenGL ES → Vulkan translator)
        ├── VirtIO-GPU ASG Transport (Address Space Graphics)
        └── MoltenVK (Vulkan → Metal on macOS)
```

---

## 📋 Requirements

- **Hardware**: Apple Silicon Mac (M1, M2, M3, M4 or later).
- **Operating System**: macOS 15.0 (Sequoia) or later.
- **Development Tools**: Xcode 16+ or Apple Command Line Tools.
- **Runtime Dependencies**:
  - Android Emulator 37.1.11+ (ARM64).
  - Android SDK (Platform Tools 36+, System Image API 36 Google APIs / Play Store).
  - Node.js 24 (for repository validation tooling).
  - `jq`, `ripgrep` (`rg`), and `zsh`.

---

## 🚀 Quick Start

### 1. Build the Native App

Build the release application bundle:

```sh
/bin/zsh scripts/build-macrodroid-app.command
```

The compiled application will be generated at:
```text
dist/Macrodroid.app
```

### 2. Run Tests

Execute the native test suite (covering FrameContract, ViewportMapper, AVD guards, and telemetry stores):

```sh
/bin/zsh scripts/test-native-app.command
```

### 3. Verify Repository Integrity

Run the automated consistency and SSOT checks:

```sh
/bin/zsh scripts/verify-tftmac.command
```

---

## 🎮 Playing Games & Running Apps

Macrodroid connects to an AVD configured for high-performance graphics:

1. **First Launch**: Open `Macrodroid.app`. The headless emulator process will start in the background via the isolated host helper.
2. **Account Sign-in**: If Google Play or Riot Games requires authentication, PIN, or MFA, the official interface appears directly inside the Metal window for you to complete.
3. **Gameplay**:
   - Left-click / Drag: Native touchscreen interaction mapped seamlessly to Android touch events.
   - Hotkeys: In-game actions map directly via the gRPC input bridge.
   - Fullscreen: Press `Command + Control + F` or use the native green macOS window button to enter fullscreen.

---

## 🔬 Performance Lab & Telemetry

Macrodroid includes a continuous graphics and combat performance logger:

- **Local Storage**: Captures and session records are stored locally under `~/Library/Application Support/Macrodroid`.
- **SQL Analytics**: High-frequency metrics (monotonic frame timestamps, Metal command buffer latencies, and SurfaceFlinger presentation markers) are recorded into a local SQLite database schema.
- **Automatic Incident Detection**: Any sequence drops or frame pacing anomalies exceeding threshold intervals are tagged and analyzed automatically.

---

## 📁 Project Structure

```text
├── tftmac/               # Core native macOS Swift application
│   ├── App/             # App lifecycle, coordinators, settings window
│   ├── Presentation/    # EmbeddedEmulatorView (MetalKit), FrameContract, ViewportMapper
│   ├── Runtime/         # gRPC client, AVD transaction guard, telemetry store, input
│   └── Assets/          # Application icons and branding assets
├── RuntimeHost/         # Minimal C helper application (Macrodroid Emulator Host.app)
├── Vendor/              # Google Android Emulator gRPC Protobuf definitions
├── ssot/                # Single Source of Truth: hardware facts, SQL schemas, locks
├── scripts/             # Build, testing, benchmarking, and verification automation
├── docs/                # Architecture specifications, benchmarks, and research logs
├── facts.md             # Locked facts and observed runtime boundaries
├── project.md           # Project chronology, architectural pivots, and development state
└── benchmark.md         # Detailed benchmarking methodology and continuous FPS metrics
```

---

## 📄 License & Attribution

- **License**: MIT License (see [LICENSE](LICENSE)).
- **Heritage**: Macrodroid builds upon the foundational research and donor contracts pioneered by Mactician and the TFTMAC native client project.
- **Disclaimer**: Teamfight Tactics, League of Legends, and Riot Games are trademarks or registered trademarks of Riot Games, Inc. Android is a trademark of Google LLC. Macrodroid is an independent open-source project and is not affiliated with or endorsed by Riot Games or Google.
