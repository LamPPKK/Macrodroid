# Macrodroid Troubleshooting & Diagnostics Manual

This manual provides verified diagnostic procedures, recovery workflows, and troubleshooting steps for **Macrodroid 5.4**.

---

## Quick Diagnostic Checklist

| Symptom | Primary Cause | Immediate Fix |
|---|---|---|
| **Build fails in Xcode/CLI** | Swift 6 concurrency or signing | Check Xcode 16+, run with `CODE_SIGNING_ALLOWED=NO` |
| **Emulator window black/stuck** | gRPC port 5582 collision or AVD freeze | Kill lingering emulator processes (`killall qemu-system-aarch64`) |
| **No touch/click response** | Viewport aspect ratio or overlay shielding | Press `Cmd+Shift+M` to ensure game controls are active |
| **Keys not registering** | Keybinding mode disabled or key conflict | Press `Cmd+K` to inspect bindings; confirm profile matches active game |
| **Audio stutter / desync** | CoreAudio buffer exhaustion / underrun | Toggle Audio Stream in `Window > Runtime Settings` |
| **FPS drops / thermal throttling** | Host GPU saturation / background instances | Switch profile to *Standard 60 FPS* or *Eco Profile* |
| **Multi-instance port collision** | Duplicate port binding | Ensure each instance uses isolated gRPC (`5582 + 2*i`) |

---

## 1. Native Build & Toolchain Issues

### Symptom: `xcodebuild` or Xcode compilation failure
Macrodroid requires **macOS 15.0+ Sequoia**, **Xcode 16.0+**, and the **Swift 6 toolchain**.

#### Verification Command:
```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Macrodroid.xcodeproj \
  -scheme Macrodroid \
  -configuration Debug \
  -destination 'platform=macOS' \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO
```

#### Common Solutions:
- **Swift 6 Strict Concurrency warnings/errors**: Ensure all UI interactions are marked `@MainActor`. Non-isolated tasks (e.g., background tickers in `EmbeddedEmulatorView`) must use `Task<Void, Never>?` to allow cancellation from `nonisolated deinit`.
- **Code Signing block**: Local development builds do not require paid Apple Developer accounts. Set `CODE_SIGNING_ALLOWED=NO` or configure `TFTMAC Local Code Signing` via:
  ```sh
  /bin/zsh scripts/ensure-local-signing-identity.command
  ```

---

## 2. Emulator & Runtime Startup Failures

### Symptom: Emulator fails to boot or gRPC connection drops
Macrodroid communicates with the Android stock emulator runtime over loopback gRPC on port **5582** (console) and **5038** (ADB).

#### Step-by-Step Resolution:
1. **Check for Zombie Emulator Processes**:
   ```sh
   pgrep -fl "qemu-system-aarch64|emulator"
   ```
   If stale processes exist, kill them gracefully:
   ```sh
   killall qemu-system-aarch64
   ```

2. **Verify Port Availability**:
   ```sh
   lsof -i :5582 -i :5038
   ```
   If another application is occupying port 5582, terminate it or assign a custom port offset in `RuntimeSettingsWindowController`.

3. **Verify AVD Integrity**:
   Verify the guest disk images and configuration exist:
   ```sh
   ls -la ~/.android/avd/
   ```
   If using an external runtime volume (e.g. `/Volumes/MAC MINI M4/TFTMAC/Runtime`), confirm the external disk is mounted before starting Macrodroid.

---

## 3. Google Play Games & Authentication Gateways

### Symptom: Play Games Services sign-in fails or prompts CAPTCHA
- **Google Play Games Cloud Sync**: Macrodroid delegates all Google Sign-in and Riot ID authentications directly to official Android UI components (`com.android.vending` / `com.google.android.gms`).
- **Never Automate Login Screens**: Do not attempt key-macros or simulated clicks on MFA, CAPTCHA, or password inputs. Use the mouse to interact directly with the embedded Metal window.
- **Play Integrity / SafetyNet**: Use official Google Play system images (with Play Store included) to satisfy Play Integrity API hardware-backed attestations.

---

## 4. Input Mapping & Keybinding Troubleshooting

### Symptom: Keystrokes or clicks do not translate to touch coordinates
Macrodroid uses `ViewportMapper` to convert AppKit window points into normalized Android touchscreen coordinates `(0...1, 0...1)`.

#### Resolution Steps:
1. **Toggle Control Overlay**:
   Press `Cmd+Shift+M` (or `F10`) to toggle the visual keybinding HUD. If overlays are hidden, the mapping engine is still active.
2. **Inspect Active Preset**:
   Press `Cmd+K` to open the **Visual Keybinding Editor**. Check if the preset matches the currently running title (e.g., MOBA preset vs FPS preset).
3. **Cursor Free / Aim Lock Desync**:
   In shooter games (PUBG / CoD), press **`Alt`** (Option) to release the locked cursor for inventory interaction. Press **`Alt`** again to re-lock Smart Aim.
4. **Gamepad Controller Disconnected**:
   Macrodroid hooks into Apple's `GameController.framework`. Verify controller connection in macOS System Settings > Game Controllers. Once connected, Macrodroid automatically maps analog sticks to virtual D-pads.

---

## 5. Graphics, Frame Drops & Metal 3 Presentation

### Symptom: Stuttering, frame drops, or high thermal load
Macrodroid renders Android framebuffers via a **Metal 3 triple-buffered presentation pool** with CVDisplayLink synchronization.

#### Resolution Steps:
1. **Check Display Refresh Rate (ProMotion)**:
   Ensure your Mac's built-in ProMotion display or external 120Hz/144Hz monitor is set to variable or fixed high refresh rate in macOS System Settings > Displays.
2. **Adjust Launch Profile**:
   Navigate to `Window > Runtime Settings` (`Cmd+,`):
   - For lower temperatures on MacBook laptops: Select **Battery Saver (Eco 60)**.
   - For maximum responsiveness: Select **Competitive E-Sports (120 FPS)**.
3. **GPU Host Driver State**:
   Verify that ANGLE / Metal Vulkan pass-through is active. Check `~/Library/Application Support/Macrodroid/Captures/<session-id>/Macrodroid_RUNTIME.sqlite` to review SurfaceFlinger missed frame counters.

---

## 6. Multi-Instance & Tiling Issues

### Symptom: Secondary instance window fails to spawn or input bleeds
- **Port Allocation**: Each secondary instance automatically increments gRPC and ADB port numbers:
  - Instance 1: `5582` / `5038`
  - Instance 2: `5584` / `5040`
  - Instance 3: `5586` / `5042`
- **Input Isolation**: Macrodroid ensures window-level isolation. Key events are dispatched strictly to the `NSWindow` that holds key window focus. Check `Window > Tile All Windows` (`Cmd+Option+T`) for synchronized multi-window layouts.

---

## 7. Telemetry & SQLite Diagnostics Extraction

When filing an issue or analyzing a performance regression:

1. Open the local SQLite session:
   ```sh
   sqlite3 ~/Library/Application\ Support/Macrodroid/Captures/latest/Macrodroid_RUNTIME.sqlite
   ```
2. Query frame statistics:
   ```sql
   SELECT 
     AVG(ingress_fps) AS avg_fps, 
     MAX(latency_p99_ms) AS peak_latency_ms,
     SUM(missed_frames) AS total_drops 
   FROM frame_windows;
   ```
3. **Sanitization Requirement**:
   **NEVER** share complete memory dumps, cookies, Google tokens, or raw unredacted logcat files. All diagnostic exports from Macrodroid are locally stored and strictly sanitized.
