# TFTMACAPP.md — Native macOS TFTMAC Full Implementation Plan

**Status:** AUTHORITATIVE NATIVE-APP IMPLEMENTATION PLAN
**Project:** TFTMAC
**Target:** Apple Silicon / Mac mini M4
**Product:** One native macOS application containing the complete Android/TFT user experience
**Primary workload:** Current official Google Play Teamfight Tactics client
**Presentation target:** Full 1920×1080 Android framebuffer, native Mac window and native macOS fullscreen
**Performance target:** Stable 60-Hz-class presentation with truthful FPS/frame telemetry
**Architecture rule:** Preserve the proven stock Android Emulator graphics/runtime path; replace only the user-facing wrapper/presentation/control layer unless measurement proves a deeper runtime blocker.

---

## 0. Executive implementation directive

Build **one real native Mac application, `TFTMAC.app`**, that launches the proven Android runtime invisibly, embeds the full Android display directly inside its own AppKit window, accepts normal Mac mouse/keyboard input, provides all normal emulator/device controls natively, manages Google Play/TFT lifecycle, exposes approved runtime settings, displays and records truthful FPS, keeps the continuous raw logger alive from before emulator launch through stop, seals raw data immediately at shutdown, and can optionally connect to legitimate Riot League Voice through the official League Client if Riot permits concurrent authentication.

This file supersedes the old production direction based on:

- a visible QEMU/Qt Android Emulator window;
- window repositioning, cropping, overlays, or Accessibility automation;
- `-scale` tricks to make the emulator fit the Mac screen;
- source-built AEMU as the normal critical path;
- API 37 as the required production guest;
- custom ANGLE as normal production work;
- scrcpy, video encoding, screenshots, or software streaming as the gameplay display path;
- the retired donor's hosted TFT feed/updater/orchestration;
- third-party Riot APK distribution;
- per-match telemetry as the primary performance model.

The current working stock runtime is the control. The native app must first reproduce it unchanged, then prove that embedding does not materially degrade it.

---

# 1. Product definition

The shipping user experience is:

```text
Finder / Dock
    -> TFTMAC.app
        -> one normal native macOS window
        -> full Android/TFT display inside the window
        -> native toolbar / menus / optional Device Controls inspector
        -> native Settings
        -> live FPS overlay
        -> official Google Play / Riot sign-in surfaces inside the embedded Android display
        -> native macOS fullscreen
```

The user must never need to interact with a separate Android Emulator window in normal operation.

The final product is not a skin around QEMU. QEMU remains the VM process, but TFTMAC owns the presentation, lifecycle, controls, telemetry, state, recovery, and native Mac UX.

---

# 2. Current known-good runtime authority

The native app begins from the runtime that has already completed real official TFT games on this machine.

## 2.1 Host

```text
Machine: Mac mini Mac16,10
Chip: Apple M4
Architecture: arm64
Unified memory: 16 GB
macOS: 26.6.2
Build: 25G83
Authoritative Xcode: /Users/flash/Downloads/Xcode.app
Xcode: 26.6 / 17F113
```

Do not allow a stale `/Applications/Xcode.app` selection to control production builds. Native build scripts set:

```text
DEVELOPER_DIR=/Users/flash/Downloads/Xcode.app/Contents/Developer
```

unless machine-state discovery proves that this exact installation has intentionally changed.

## 2.2 Android runtime

```text
Bulk runtime root: /Volumes/MAC MINI M4/TFTMAC/Runtime
Android Emulator: 37.1.11.0
Emulator build: 15917651
ADB protocol: 1.0.41
AVD: TFT_Ultra_Tablet
Guest family: official Google Play ARM64 API 36
Guest display: 1920x1080
Density: 320 dpi
Refresh target: 60 Hz
CPU baseline: 6 cores
Guest RAM baseline: 5120 MB / 5.0 GB
GPU mode: host
Audio backend: CoreAudio
Graphics transport: virtio-gpu-asg / gfxstream
ASG write buffer: 1 MiB
ASG write step: 16 KiB
ASG data ring: 32 KiB
ASG draw flush baseline: 800
```

Current graphics execution path:

```text
TFT / Unreal GameActivity
 -> ANGLE
 -> guest Vulkan/ranchu
 -> virtio-gpu-asg / gfxstream
 -> host Vulkan
 -> MoltenVK
 -> Metal
 -> Apple M4
```

Current compatibility adapter required by the proven build:

```text
ANGLE_FEATURE_OVERRIDES_ENABLED=
  exposeNonConformantExtensionsAndVersions:exposeES32ForTesting
```

This is recorded truthfully as a compatibility adapter. The native-app project does **not** reopen source-AEMU/custom-ANGLE work merely to remove it. A future conformance project may replace it only after the native product is stable and measurement proves that work is necessary.

## 2.3 Current official TFT package

Observed working package:

```text
applicationId/package: com.riotgames.league.teamfighttactics
versionName observed: 18.1-5392842
versionCode observed: 8392842
installer observed: com.android.vending
launch activity: com.epicgames.unreal.GameActivity
```

The observed version is not permanently pinned. Google Play remains package/update authority. Every launch re-queries package state.

The signing certificate digest has not yet been promoted as verified project authority. Native-app implementation must capture and record the Google-delivered signer digest before release rather than inventing or assuming it.

## 2.4 Current performance decisions

```text
Guest RAM 5.0 GB: KEEP as current development baseline
Guest RAM 4.0 GB: not the default; do not force a further RAM cut
CPU: 6 cores baseline
TFT graphics: High baseline
TFT FPS cap: 60 baseline
TFT Performance Mode (Beta): OFF baseline
Ultra High graphics: REJECTED on current stack for usability; user observed unplayable lag
ASG draw flush 800: baseline
ASG draw flush 400: experimental until controlled evidence promotes it
```

Do not silently default the app to Ultra High or Riot Performance Mode Beta. High/60/OFF is the current user-confirmed playable in-game reference until better measured evidence exists.

---

# 3. Non-negotiable architecture rules

1. **Stock Google Android Emulator remains the normal runtime.** No mandatory source-built AEMU tree.
2. **Retired donor evidence remains untouched as donor/control evidence.** Do not make the shipping app depend on retired donor servers, feed, updater, or orchestration.
3. **Official Google Play/Riot package only.** Do not mirror, repack, patch, or re-sign Riot binaries.
4. **The Android source framebuffer stays 1920×1080.** Native window resizing changes presentation size, not guest resolution.
5. **No visible Qt/QEMU UI in production.** The emulator runs hidden.
6. **No scrcpy/video encode path.** Use EmulatorController raw frame transport and Metal.
7. **No fake fullscreen.** Use ordinary AppKit fullscreen/Spaces.
8. **No Accessibility permission for normal operation.** Input goes through EmulatorController/ADB fallbacks.
9. **Logger starts before emulator.** TFT does not launch if the critical logger gate cannot initialize.
10. **Continuous run is the performance source of truth.** Matches and setting changes are timestamped annotations.
11. **Raw telemetry is sealed before SQL/post-processing.** Analysis can fail without losing the run.
12. **One-variable experimentation.** No combinatorial tuning runs unless evidence requires them.
13. **No source-level zero-copy presentation bridge unless the simple MMAP/Metal path fails the measured performance gate.**
14. **League Voice cannot bypass Riot authentication or entitlement.** It is a separate conditional module and cannot block the core app release.

---

# 4. Production build system

The current ad-hoc `swiftc` wrapper build is not sufficient for the final embedded app.

Create a normal Xcode project:

```text
TFTMAC.xcodeproj
Product: TFTMAC.app
Architecture: arm64
Minimum macOS: 15.0
Swift language mode: Swift 6.x
Primary UI: AppKit
Optional hosted UI: SwiftUI where it reduces code, not for window control
Renderer: Metal / MetalKit
Distribution: Developer ID direct distribution
```

Why macOS 15.0: the maintained gRPC Swift 2 ecosystem is the intended client stack and currently targets modern macOS. The actual target machine is much newer, so lowering deployment compatibility is not worth complicating the embedded-control build.

## 4.1 Dependencies

Use maintained Swift packages only:

```text
gRPC Swift 2.x
gRPC Swift NIO transport 2.x
gRPC Swift Protobuf 2.x
SwiftProtobuf 1.x
```

Implementation procedure:

1. Resolve versions compatible with Xcode 26.6 and the vendored emulator proto.
2. Pin exact versions and checksums in `Package.resolved`.
3. Never ship floating `main`/branch dependencies.
4. Commit `Package.resolved`.
5. Treat dependency update as an explicit maintenance change, not an automatic build-time upgrade.

## 4.2 Emulator protocol source

Vendor the exact compatible EmulatorController protocol source:

```text
Vendor/AndroidEmulator/emulator_controller.proto
Vendor/AndroidEmulator/SOURCE.json
Generated/EmulatorController/*.swift
```

`SOURCE.json` records:

```text
installed emulator version/build
upstream source URL/revision
proto SHA-256
generator versions
generated-source SHA-256
```

Generate the Swift protobuf/gRPC client once through a reproducible script and commit the generated code. Normal end-user builds must not depend on downloading Android Emulator source or running an uncontrolled code generator.

Required RPC capability set to prove against Emulator 37.1.11:

```text
status / getStatus
raw screenshot/frame streaming
single screenshot
keyboard input
mouse/touch input
wheel input if supported
VM state / restart / shutdown
microphone state where exposed
optional notifications/device-control RPCs needed by Advanced Controls
```

Exact RPC names follow the vendored proto, not remembered examples.

---

# 5. Repository structure

Keep the app modular without creating a forest of frameworks.

Use one production app target plus tests, one small developer probe target, and generated protocol code.

```text
TFTMAC.xcodeproj
TFTMAC/
  App/
    TFTMACApplication.swift
    AppCoordinator.swift
    AppState.swift
    MenuBuilder.swift
    MainWindowController.swift
  Runtime/
    RuntimeLocation.swift
    RuntimeProfile.swift
    RuntimeSettingDefinition.swift
    RuntimeProfileStore.swift
    RuntimeController.swift
    EmulatorProcessController.swift
    AndroidBootVerifier.swift
  Emulator/
    EmulatorDiscoveryService.swift
    EmulatorControllerClient.swift
    EmulatorConnectionState.swift
    FrameStreamSession.swift
  Presentation/
    EmbeddedEmulatorView.swift
    MetalFramePresenter.swift
    FrameRing.swift
    ViewportMapper.swift
    FPSOverlayView.swift
  Input/
    AndroidInputRouter.swift
    KeyboardMapper.swift
    PointerMapper.swift
  DeviceControls/
    DeviceActionService.swift
    DeviceControlsInspector.swift
    AdvancedControlsController.swift
  Package/
    PackageStateManager.swift
    TFTPackageState.swift
    PlayStoreCoordinator.swift
  Telemetry/
    CaptureManager.swift
    CaptureSeal.swift
    FPSAccumulator.swift
    HostSampler.swift
    AndroidSampler.swift
    SurfaceFlingerSampler.swift
    TelemetryNormalizer.swift
  Voice/
    LeagueVoiceProvider.swift
    LeagueClientVoiceProvider.swift
    LeagueVoiceState.swift
  Resources/
Generated/
  EmulatorController/
Vendor/
  AndroidEmulator/
Probes/
  EmbeddedControlProbe/
Tests/
  TFTMACTests/
  TFTMACUITests/
scripts/
  generate-emulator-proto.command
  build-native-app.command
  test-native-app.command
  notarize-native-app.command
ssot/
  native-app-probe-results.json
  native-app-release-checklist.md
```

Do not recreate a monolithic `TFTMACWindowCoordinator` that owns every responsibility.

Existing Node tools remain diagnostic/control oracles during migration, but the final user-facing runtime must not require Node for display, input, normal lifecycle, settings, or telemetry capture.

---

# 6. Native application state machine

The app state must describe what the user can actually do.

```text
BOOTSTRAPPING
  -> EXTERNAL_RUNTIME_MISSING
  -> RUNTIME_NEEDS_REPAIR
  -> READY_TO_START

READY_TO_START
  -> STARTING_CAPTURE
  -> STARTING_EMULATOR
  -> ANDROID_BOOTING
  -> ANDROID_LOCKED_OR_SETUP_REQUIRED
  -> GOOGLE_PLAY_SIGNIN_REQUIRED
  -> TFT_INSTALL_REQUIRED
  -> TFT_UPDATE_REQUIRED
  -> TFT_PATCHING_OR_INITIALIZING
  -> READY_TO_PLAY

READY_TO_PLAY
  -> LAUNCHING_TFT
  -> PLAYING

PLAYING
  -> RESTARTING_TFT
  -> APPLYING_ANDROID_PROFILE
  -> STOPPING
  -> LOGGER_FAULT

STOPPING
  -> SEALING_CAPTURE
  -> READY_TO_START
```

Error states expose one specific recovery action. Do not terminate with a generic failure when the package is missing, Play sign-in is needed, Android is locked, or Riot is patching.

---

# 7. Runtime root and storage behavior

Bulk runtime authority remains:

```text
/Volumes/MAC MINI M4/TFTMAC/Runtime
```

Small native state remains:

```text
~/Library/Application Support/TFTMAC/
  Profiles/
  State/
  Captures/
  Diagnostics/
  Logs/
  Rollback/
```

Large capture traces may be stored on the external volume with an index under Application Support.

Rules:

- if `/Volumes/MAC MINI M4` is not mounted, do not start the emulator;
- never silently build a second SDK/AVD on the internal disk;
- verify the runtime root and AVD before launch;
- preserve the existing runtime instead of reinstalling it on every app build;
- first-run bootstrap only installs/repairs missing official components;
- Android SDK licenses are accepted through the normal Google tooling/user agreement path;
- Riot APKs and private AVD userdata never enter Git or the app bundle.

---

# 8. Hidden Android Emulator launch

Normal production launch is the current proven runtime plus embedded-control flags.

Required additional flags/direction:

```text
-qt-hide-window
-grpc-use-token
-idle-grpc-timeout 300
```

Use isolated ADB:

```text
ANDROID_ADB_SERVER_PORT=5038
```

Preserve the current renderer/audio/CPU/RAM/display/compatibility arguments from the active RuntimeProfile.

Do not rely on:

```text
-scale
emulator-user.ini window placement
Finder desktop dimensions
Accessibility window APIs
off-screen QEMU positioning
cover windows / fake chrome
```

The app tracks the emulator process directly by PID and owns its lifecycle.

## 8.1 gRPC discovery and authentication

On each launch:

1. Locate the registration/discovery record belonging to the new emulator process.
2. Read the actual local gRPC endpoint.
3. Read the token into memory only.
4. Determine the exact authentication-header form required by the installed emulator.
5. Call status/getStatus.
6. Verify the endpoint belongs to the expected emulator PID/AVD.
7. Store neither token nor auth header in logs, SQL, crash metadata, or profiles.
8. Discard credentials when the emulator terminates.

A hidden emulator with no authenticated controller connection is a hard architecture failure. Do not continue building product UI around it.

---

# 9. Android boot and Google Play preflight

After process start, native TFTMAC verifies:

```text
ADB serial present
boot_completed=1
user 0 unlocked or actionable lock/setup state shown
1920x1080 display
320 dpi
expected CPU count
expected guest memory range
Google Play Store package present
Google Play Services present
network active
host/guest clock reasonably synchronized
automatic time enabled
automatic timezone enabled
```

Date/time is a first-class Play preflight because Play installation/auth failures can be caused by clock drift.

Before opening Play installation/sign-in:

- enable Android automatic time/time-zone settings when permitted;
- compare host UTC with guest UTC;
- if the guest is materially wrong, repair through the normal emulator/Android time path or restart the guest;
- do not proceed with Play account flow while the clock is obviously wrong.

Do not automate Google credentials, CAPTCHA, consent, MFA, or Riot credentials.

---

# 10. Official TFT package lifecycle

`PackageStateManager` is a required native service.

States:

```text
MISSING
PLAY_AVAILABLE
INSTALLING
INSTALLED_UNKNOWN_VERSION
INSTALLED_VERIFIED
UPDATE_AVAILABLE
PATCHING_OR_INITIALIZING
READY_FOR_LAUNCH
PACKAGE_DAMAGED_OR_INCOMPLETE
```

Every package observation captures:

```text
package/applicationId
versionName
versionCode
installer package
base APK path
split APK paths
first install time
last update time
launch activity
base/split SHA-256 when readable
signing certificate digest(s)
```

Verification rules:

- package name must be `com.riotgames.league.teamfighttactics`;
- installer must be `com.android.vending` for the production authority path;
- versionName/versionCode are observed from the installed package, not hardcoded forever;
- signing digest is extracted from the actual Google-delivered APK set and stored as package evidence;
- on every update, re-record signer and hashes;
- a signer mismatch is a hard package-integrity warning requiring review;
- never re-sign or modify the package.

If TFT is missing or out of date, TFTMAC opens the official Google Play surface **inside the embedded Android display**. The user signs into Play normally there.

Once TFT is installed, TFTMAC launches the official activities and allows Riot's own patch/init flow to complete. Riot login remains inside the official game surface.

---

# 11. Full embedded display architecture

The user-facing Android display is a native `MTKView` or equivalent Metal-backed AppKit view.

```text
Android Emulator hidden Qt UI
 -> EmulatorController raw frame stream
 -> MMAP/shared-memory source
 -> bounded host copy
 -> 2/3-frame Metal texture ring
 -> MTKView
 -> TFTMAC NSWindow
```

Initial stream request:

```text
display: 0
width: native / 0 where proto means native
height: native / 0 where proto means native
format: raw RGBA8888 or exact native raw format exposed by proto
transport: MMAP/shared memory
```

The app verifies the received source is 1920×1080 landscape.

Do not use PNG, H.264, VP8, scrcpy, periodic screenshots, or Android software encoding as the primary display.

## 11.1 Why the first implementation uses one copy

A 1920×1080 RGBA frame is about 8.3 MB. Shared-memory producers can overwrite their region while a client is rendering. The safe first implementation copies each new complete frame into a bounded Metal presentation ring.

This gives deterministic ownership and prevents half-written frames/tearing.

Only if measured embedded-vs-direct A/B proves this single copy materially harms performance may the project activate a source-level IOSurface/zero-copy adapter. Do not build that preemptively.

## 11.2 Metal presenter

`MetalFramePresenter` must:

- detect each new source sequence number;
- copy/swap into an available presentation buffer without blocking the frame-receive loop;
- use a bounded 2- or 3-buffer ring;
- present only complete new frames;
- retain source sequence/timestamp metadata with the presented frame;
- record receive, submit, and present/completion monotonic timestamps;
- avoid unnecessary color conversions;
- preserve normal sRGB-looking output unless measured source metadata requires another color space;
- never perform heavy telemetry/SQL work on the render thread.

---

# 12. Full-size window, fit, 100%, and fullscreen behavior

The source Android display always stays 1920×1080.

Main `NSWindow` style:

```text
.titled
.closable
.miniaturizable
.resizable
.fullSizeContentView
```

Required behavior:

- real macOS red/yellow/green traffic lights;
- title `TFTMAC`;
- normal Dock identity;
- normal menu-bar identity;
- native unified/compact toolbar;
- `.fullScreenPrimary` collection behavior;
- green traffic-light fullscreen works;
- `View > Enter Full Screen` works;
- `Control-Command-F` works;
- no fake fullscreen or menu-bar/Dock hiding code.

Display modes:

```text
FIT
  Aspect-fit the entire 1920x1080 source into available content.
  Never crop or stretch.

100%
  One source pixel equals one view pixel.
  If the window is smaller than 1920x1080, use a native scroll container rather than scaling/cropping silently.

FULLSCREEN
  Keep source at 1920x1080.
  Aspect-fit into the native fullscreen content area.
  On a 16:9 display, fill the complete content area without Qt/QEMU chrome.
```

Letterboxing is allowed only when the Mac content region is not 16:9.

---

# 13. Native input system

Normal gameplay input must not depend on fixed Android screen coordinates.

Input mapping:

```text
Mac event point
 -> EmbeddedEmulatorView local point
 -> actual displayed-image rectangle
 -> normalized source coordinates
 -> Android 1920x1080 coordinates
 -> EmulatorController input RPC
```

Required input:

```text
left click / touch down-up
drag / touch move
mouse movement where useful
wheel/scroll
keyboard keys
text entry
Back
Home
Overview
```

Rules:

- ignore letterbox regions for Android touch;
- preserve Mac command shortcuts (`Command-*`) for TFTMAC menus;
- send normal unhandled gameplay keys to Android;
- keep input ordering deterministic;
- do not block input while telemetry writes;
- gRPC is primary for pointer/key transport where supported;
- isolated ADB is allowed as a service-control fallback, not as brittle coordinate automation.

---

# 14. Native toolbar, menus, and Device Controls inspector

The game gets the full content width by default. All emulator functionality remains available through native controls.

Primary toolbar:

```text
Back
Home
Overview
Device Controls toggle
Volume/Mute
Screenshot
Restart TFT
FPS indicator
League Voice
```

The Device Controls inspector opens on the right when requested and may contain:

```text
Power / Wake
Back
Home
Overview
Rotate Left
Rotate Right
Volume Up
Volume Down
Mute
Screenshot
Fit
100%
Restart TFT
Restart Android
Pause/Resume VM where supported
Advanced Emulator Controls
```

When the inspector is visible, the Android view aspect-fits into the remaining content. It is never stretched.

Application menus:

```text
TFTMAC
  About TFTMAC
  Settings...
  Quit TFTMAC

File
  Screenshot
  Open Capture Folder

View
  Fit
  100%
  Enter Full Screen
  Show FPS Overlay
  Show Device Controls

Device
  Power / Wake
  Back
  Home
  Overview
  Volume Up
  Volume Down
  Mute
  Rotate Left
  Rotate Right
  Restart TFT
  Restart Android
  Advanced Emulator Controls...

Voice
  League Voice
  Disconnect Voice

Help
```

Every visible control receives an explicit release test. No button may silently do nothing.

---

# 15. Advanced emulator controls

Do not recreate Google's Qt Extended Controls UI pixel-for-pixel. Recreate the **functional capabilities** the native app may need.

`AdvancedControlsController` capability-discovers the current EmulatorController and exposes supported controls such as:

```text
location/GPS
battery state
cellular/network simulation
microphone state
clipboard
camera/sensor status where exposed
VM pause/resume/restart
additional display/device state available in the exact installed proto
```

For each action:

1. Prefer the supported EmulatorController RPC.
2. Use a deterministic ADB fallback only if it is safer and already proven.
3. Hide/disable capabilities not exposed by the installed emulator rather than presenting dead controls.
4. Never require the hidden Qt toolbar.

---

# 16. Runtime profile system

Runtime tuning is a product feature, not a source-edit workflow.

Persistent profiles live in:

```text
~/Library/Application Support/TFTMAC/Profiles/
```

Each `RuntimeProfile` is canonical JSON with a deterministic SHA-256 config hash.

Minimum fields:

```text
profileVersion
name
cpuCores
ramMB
guestWidth
guestHeight
densityDpi
refreshHz
gpuMode
audioBackend
graphicsTransport
asgWriteBuffer
asgWriteStep
asgDataRing
asgDrawFlushInterval
angleCompatibilityFeatures
configHash
```

Each session writes an immutable copy as `runtime-profile.json`.

## 16.1 Declarative settings registry

Each `RuntimeSettingDefinition` contains:

```text
id
label
group
value type
allowed values/range
default
unit
apply mode
restart requirement
runtime mapping
validation rule
safety class
log key
help text
```

Apply modes:

```text
LIVE
RESTART_TFT
RESTART_ANDROID
NEXT_SESSION
```

Safety badges:

```text
BASELINE
VALIDATED
EXPERIMENTAL
UNSUPPORTED
```

## 16.2 CPU cores

Expose exactly the values implemented by the current native profile:

```text
4, 6, 8
```

Default: `6`
Apply: `RESTART_ANDROID`

Pre-release validation tests the CPU dimension one value at a time against the baseline profile. Do not test the Cartesian product of every CPU/RAM combination.

## 16.3 Guest RAM

Expose exactly the values implemented by the current native profile:

```text
4.0
5.0
6.0
GB
```

Default: `5.0 GB / 5120 MB`
Apply: `RESTART_ANDROID`

The UI is a validated dropdown; unsupported intermediate values are not silently accepted.

Pre-release validation smoke-tests each value independently against the baseline CPU/graphics configuration. This proves launch compatibility without requiring nine full TFT matches.

5.0 GB remains the performance baseline until evidence changes it.

## 16.4 ASG draw flush interval

Expose:

```text
800 — BASELINE
400 — EXPERIMENTAL until promoted
```

Apply: `RESTART_ANDROID`

Do not expose arbitrary ASG values in v1.

## 16.5 Locked baseline values

Show but do not make editable in the first release:

```text
1920x1080
320 dpi
60 Hz target
host GPU
virtio-gpu-asg
1 MiB ASG write buffer
16 KiB ASG write step
32 KiB ASG ring
CoreAudio
ANGLE compatibility feature set
MoltenVK configuration
```

New knobs are added only when measurement names a causal variable.

## 16.6 Apply & Restart workflow

When a restart-required value changes:

1. Save the pending profile.
2. Mark `Restart required`.
3. User selects `Apply & Restart Android`.
4. Record `CONFIG_CHANGE_REQUESTED`.
5. Seal the current raw capture using the bounded shutdown protocol.
6. Stop Android cleanly.
7. Persist new profile and config hash.
8. Start a new logger/capture **before** the new emulator process.
9. Start hidden emulator with the new profile.
10. Verify requested vs observed CPU/RAM/config.
11. Record `CONFIG_CHANGE_APPLIED`.
12. Relaunch TFT when Android/package state is ready.

One runtime configuration never silently mixes into another capture.

---

# 17. TFT in-game graphics settings

Known user-facing values:

```text
Graphics: Low / Medium / High / Ultra High
FPS cap: 30 / 60 / None
Performance Mode (Beta): On / Off
```

Current baseline:

```text
High / 60 / OFF
```

Current Ultra High verdict:

```text
REJECTED for current usability because it produced unplayable lag.
```

Do not automate these with blind screen-coordinate taps.

Implementation sequence:

1. Inspect logcat and Riot/Unreal runtime output for deterministic setting-change events.
2. Inspect any stable local configuration/preferences interface legally and non-invasively accessible from the Play guest.
3. If a deterministic interface exists, expose the setting through TFTMAC and timestamp every apply automatically.
4. If no stable write interface exists but logcat exposes changes, observe and timestamp them automatically.
5. If neither exists, provide an explicit native `Game Settings Observation` control that records the user's declared current values without pretending TFTMAC applied them.

Manual in-game setting changes may never be assigned a fabricated timestamp or value.

---

# 18. FPS and presentation telemetry — required product feature

`gfxinfo` is not the primary FPS source because TFT renders through a native Unreal/Vulkan SurfaceView path.

The embedded frame stream supplies always-on presentation metrics. SurfaceFlinger/Perfetto calibrates and deepens them.

Track separately:

```text
emulator/source frame rate
frame stream delivery rate
Metal presented FPS
sequence gaps / stream drops
source frame intervals
source-to-receive latency
receive-to-submit latency
submit-to-present latency
source-to-present latency
Mac display refresh rate
```

## 18.1 User-visible FPS

Default HUD:

```text
FPS 59.8
```

Default user number = distinct **Metal presented FPS**, because this is what the user actually sees in TFTMAC.

Expanded diagnostic HUD:

```text
FPS 59.8
SRC 60.0
DROP 0.0%
P95 17.4 ms
```

The overlay:

- is native AppKit/Metal overlay content;
- is not rendered inside Android;
- does not alter guest resolution;
- does not intercept normal gameplay outside its own small bounds;
- is toggleable from `View > Show FPS Overlay`;
- persists the user's preference.

## 18.2 FPS accumulator

Every source frame captures:

```text
source sequence
source timestampUs
host receive monotonic time
Metal submit monotonic time
Metal present/completion monotonic time when available
```

Maintain rolling windows:

```text
1 second
5 seconds
30 seconds
```

Do not write one database row per rendered frame during gameplay.

## 18.3 Raw `fps.jsonl`

Append one compact record per second:

```text
utc
host_mono_ns
source_fps_1s
source_fps_5s
presented_fps_1s
presented_fps_5s
source_frame_count
delivered_frame_count
presented_frame_count
stream_dropped_frame_count
stream_dropped_percent
source_frame_interval_mean_ms
source_frame_interval_p95_ms
source_to_present_mean_ms
source_to_present_p95_ms
display_refresh_hz
emulator_seq_first
emulator_seq_last
runtime_config_hash
```

## 18.4 Calibration gate

Before calling emulator stream timestamps the authoritative **game/display source FPS**:

1. Capture a stable TFT animation interval.
2. Record gRPC source seq/timestamps.
3. Simultaneously capture bounded SurfaceFlinger/FrameTimeline Perfetto evidence.
4. Compare frame count/timing.
5. Repeat during known heavy/stutter gameplay.

If the streams track closely, source FPS is promoted. If not, SurfaceFlinger remains source/display-production authority and the gRPC source number is labeled transport/source-stream FPS.

Do not lie with labels.

---

# 19. Continuous raw telemetry architecture

One emulator/logger start-to-stop interval is one authoritative continuous performance run.

Matches, wins, placements, TFT restarts, quality reports, graphics changes, FPS-cap changes, Performance Mode changes, and traces are annotations inside that continuous timeline.

No match-start marker is required for the run to be useful.

Required capture root:

```text
~/Library/Application Support/TFTMAC/Captures/<session-id>/
```

Required or attempted raw artifacts:

```text
session.json
runtime-profile.json
runtime-state.json
package-state.json
renderer-state.json
clock-sync.jsonl
host-events.jsonl
markers.jsonl
fps.jsonl
embed-present.jsonl
host-process.jsonl
host-memory.jsonl
surfaceflinger/counters.jsonl
logcat.raw.txt
logcat.filtered.txt
emulator.stdout.log
emulator.stderr.log
perfetto/            # bounded traces when requested/needed
capture.seal.json
manifest.sha256      # post-seal integrity pass
```

Critical always-on streams:

```text
FPS/presentation
host process/CPU/RSS
host memory/compression/swap/pageouts
Android/logcat
SurfaceFlinger miss counters
clock sync
runtime events
```

The native app owns enough telemetry directly that a played session cannot become totally valueless because a separate analysis command failed.

---

# 20. Logger gate and fault behavior

Before TFT launch, `CaptureManager` must prove:

```text
session created
runtime profile frozen
host sampler advancing
host memory sampler advancing
frame/FPS telemetry ready once display stream starts
logcat collector available once Android is ready
capture directory writable
```

If the critical gate fails before gameplay, do not launch TFT.

During gameplay:

- restart a failed non-render sampler automatically once;
- record `LOGGER_STREAM_RESTARTED`;
- keep native FPS/presentation recording independent of logcat/process samplers;
- surface `LOGGER DEGRADED` if a critical stream cannot recover;
- never destroy the game merely because post-processing is unavailable.

---

# 21. Bounded raw-first stop/seal protocol

Shutdown must be fast and deterministic. It must never recursively inventory the Android SDK/AVD before protecting gameplay data.

When Stop/Quit/Apply-Restart is requested:

1. Record `STOP_REQUESTED` and final monotonic timestamp.
2. Stop accepting new experiment annotations.
3. Stop/flush critical telemetry producers.
4. `fsync`/close raw files where practical.
5. Write `session.json` final raw state.
6. Atomically write `capture.seal.json` containing:
   - session id;
   - start/end timestamps;
   - exact runtime config hash;
   - package identity;
   - immutable raw file list;
   - final byte counts;
   - capture state `RAW_SEALED`;
   - integrity state `PENDING`.
7. Once `capture.seal.json` exists, the raw run is protected and may not be rewritten.
8. Stop/terminate the emulator if the requested action requires it.
9. Compute SHA-256 integrity manifest **after** raw seal at background priority.
10. Normalize/ingest SQLite **after** raw seal.
11. Storage/BOM inventory, compression, long analysis, and report generation are post-processing only.

A full SDK/AVD recursive size walk is explicitly forbidden on the critical stop path.

If SHA/SQL/post-processing fails, raw capture remains `RAW_SEALED` and the app writes a secondary error artifact.

If the app or Mac dies before normal seal, next launch recovers the abandoned `CAPTURING` directory as `RECOVERED_PARTIAL` without modifying existing raw bytes.

For macOS application termination, use `applicationShouldTerminate` / terminate-later semantics so the app gets a short bounded seal opportunity rather than exiting mid-write.

---

# 22. SQL performance laboratory integration

Use SQLite as post-session normalized evidence, not as the high-rate capture transport.

Add/maintain a time-series FPS table logically equivalent to:

```sql
fps_samples(
    session_id,
    observed_utc,
    host_mono_ns,
    source_fps_1s,
    source_fps_5s,
    presented_fps_1s,
    presented_fps_5s,
    stream_dropped_frames,
    stream_dropped_percent,
    source_interval_mean_ms,
    source_interval_p95_ms,
    source_to_present_mean_ms,
    source_to_present_p95_ms,
    display_refresh_hz,
    config_hash
)
```

Index:

```text
(session_id, host_mono_ns)
```

Post-session rollups include:

```text
source_fps_mean
source_fps_p5
source_fps_p50
source_fps_p95
source_fps_min
presented_fps_mean
presented_fps_p5
presented_fps_min
percent_time_below_60
percent_time_below_50
percent_time_below_30
stream_drop_percent
source_to_present_p95_ms
longest_sub_30fps_interval_seconds
CPU mean/p95/max
RSS mean/p95/max
host available/compressed/swap
pageout delta/rate
SurfaceFlinger/HWC/GPU miss deltas
ANR/fatal/OOM/restart counts
```

Schema migrations are idempotent and tested against the current live performance DB. A normalization/migration failure must never invalidate raw capture sealing.

---

# 23. Deep graphics diagnostics

Always-on FPS tells us **that** a frame problem exists. It does not always tell us **why**.

Keep bounded deep diagnostics separate:

```text
SurfaceFlinger frame/frametimeline/layers
GPU memory
Perfetto process/system stats where needed
host CPU/memory
ASG/gfxstream instrumentation when needed
MoltenVK instrumentation when needed
```

Native trace actions remain developer diagnostics, not something every player session must run at maximum intensity.

No source-built AEMU or custom renderer work is activated until these measurements identify that layer as the first causal blocker.

---

# 24. Audio and microphone

Core TFT audio remains the current proven explicit backend:

```text
CoreAudio
```

Native app launch must preserve it and record the observed backend.

Acceptance:

```text
TFT audible through selected Mac output
no recurring emulator PCM I/O error
no recurring mixer underrun problem
audio survives native display embedding
audio survives fullscreen
audio survives TFT restart
```

Android volume controls alter Android audio state; native Mac system volume remains user-controlled by macOS.

Microphone passthrough is implemented only where required by an Android feature or diagnostics. League Voice uses native/official League Client audio rather than routing voice through the Android guest.

---

# 25. League Voice integration — separate conditional module

Include a native `League Voice` toolbar/menu location from the beginning, but do not allow it to delay the core TFTMAC app.

## 25.1 Allowed architecture

Preferred path:

```text
TFTMAC League Voice button
 -> detect official Riot/League Client on Mac
 -> user signs in through Riot's own UI
 -> discover local League Client API endpoint
 -> keep local credentials only in memory
 -> dynamically verify current premade-voice capability
 -> ask official League Client/plugin to join the account's legitimate party voice session
 -> Riot/Vivox auth/media remains owned by Riot's client
```

Never:

- fake Riot/Vivox tokens;
- hardcode private voice endpoints as permanent authority;
- persist LCU credentials;
- capture League passwords;
- bypass party entitlement;
- work around a Riot same-account concurrent-session restriction.

## 25.2 Provider isolation

Define:

```swift
protocol LeagueVoiceProvider {
    func probe() async -> LeagueVoiceCapability
    func connect() async throws
    func disconnect() async
    func setSelfMuted(_ muted: Bool) async throws
    func setParticipantVolume(id: String, value: Double) async throws
}
```

The rest of TFTMAC depends only on this interface.

## 25.3 Mandatory feasibility gate

Prove on the target Mac:

```text
official League Client available
user authenticates only in Riot UI
local client API discoverable
premade voice endpoints currently exist
same user can remain authenticated in League Client while Android TFT is active
joining voice does not log TFT out
TFT activity does not tear down voice
Mac mic/output work
self mute works
participant mute/volume works
son/other party member on PC can hear user and user can hear them
```

The decisive gate is same-account concurrency.

If Riot rejects concurrent session use:

```text
League Voice = UNAVAILABLE — RIOT SESSION LIMIT
```

Ship TFTMAC without an authentication bypass.

---

# 26. Security, privacy, and credential handling

TFTMAC may handle local ephemeral control credentials but must not become a credential store.

Rules:

```text
Google credentials: only inside official Google Play Android UI
Riot credentials: only inside official Riot/TFT/League Client UI
emulator gRPC token: memory only, never logged
League Client local API token: memory only, never logged
Riot/Vivox voice token: never persist/log
Riot APKs: never commit/bundle/redistribute
AVD userdata: never commit
capture logs: redact obvious auth headers/tokens before filtered diagnostics
```

Bind emulator control to local loopback only.

The native app should use Hardened Runtime and least required entitlements. Do not enable the App Sandbox if it prevents required child-process, external-volume, local gRPC, ADB, or runtime behavior; this is a direct Developer ID application, not a Mac App Store-first product.

---

# 27. Repair and rollback model

Keep repair simple and targeted.

User-facing repair actions:

```text
Repair Runtime
Restart Display Connection
Restart TFT
Restart Android
Open Google Play
Reset Runtime Profile to Baseline
Open Diagnostics
```

Runtime repair verifies:

```text
external root mounted
emulator binary/version present
platform-tools present
AVD exists
Google Play image metadata matches expected family
AVD config is readable
TFT package state
```

Do not delete/recreate the AVD automatically because one probe failed.

Profile rollback:

- keep `Baseline` immutable;
- keep last-known-good profile;
- if a new restart configuration fails boot/readiness, automatically revert the pending profile and offer `Restart with Last Known Good`;
- unsupported values never silently clamp to a different value.

Application rollback:

- retain the last notarized release artifact;
- keep the current direct-window control build available for engineering A/B until native embedding passes release gates;
- the direct-window control is not a second shipping UX after native acceptance.

---

# 28. Native build/sign/notarize/release

Production output:

```text
dist/TFTMAC.app
dist/TFTMAC.dmg
```

Build script:

```text
scripts/build-native-app.command
```

Requirements:

- use authoritative Xcode path;
- build arm64 Release;
- preserve/discover the existing TFTMAC bundle identifier rather than inventing a second app identity;
- set semantic app version/build number;
- sign all app executables/frameworks with Developer ID Application;
- Hardened Runtime enabled;
- notarize with Apple notary service;
- staple notarization ticket;
- validate with `codesign`, `spctl`, and launch smoke test;
- install test copy to `/Applications/TFTMAC.app`;
- verify Dock/Finder identity is TFTMAC.

Do not bundle Google Play system images or Riot game binaries into the DMG. The app uses/bootstraps the user's licensed official Android runtime installation on the external runtime root.

---

# 29. Test strategy

Avoid a combinatorial test explosion. Test each independent variable against the known-good baseline and reserve full real matches for release-critical paths.

## 29.1 Unit tests

Required deterministic tests:

```text
runtime profile canonicalization/hash
setting allowed values
CPU/RAM conversion
viewport/letterbox coordinate mapping
1920x1080 touch mapping
FPS rolling-window math
sequence-gap detection
latency math
state-machine transitions
capture seal atomicity
abandoned-capture recovery
package metadata parsing
redaction
gRPC discovery parsing
```

## 29.2 Integration tests

```text
hidden emulator boot
controller authentication
status/getStatus
1920x1080 raw stream
10-minute animated frame stream
Metal presentation
mouse/touch round trip
keyboard round trip
Back/Home/Overview
Power/Wake
rotate both directions
volume/mute
screenshot
TFT restart
Android restart
CoreAudio
logger start-before-emulator
raw seal
post-seal SQL
```

## 29.3 Runtime settings smoke matrix

Do not test all combinations.

RAM dimension:

```text
4.0 / 5.0 / 6.0 GB
```

For each, hold CPU=6 and all other baseline values. Verify Android boots and TFT reaches a stable ready/lobby state without OOM/ANR.

CPU dimension:

```text
4 / 6 / 8
```

For each, hold RAM=5.0 GB and all other baseline values. Verify boot/readiness.

ASG dimension:

```text
800 / 400
```

Hold CPU=6, RAM=5.0 GB, High/60/OFF.

Full-match performance validation is required only for the baseline and any candidate being promoted, not every valid dropdown choice.

## 29.4 Real user acceptance

At least one complete official TFT match must be played entirely through `TFTMAC.app` with:

```text
embedded display only
native input
CoreAudio
logger healthy
FPS visible/logging
no visible Qt/QEMU
native fullscreen tested
normal window mode tested
restart controls tested outside active match
raw capture sealed correctly
```

---

# 30. Performance acceptance contract

The native embed layer must not become the reason TFT is slower.

For a stable gameplay measurement:

```text
warm-up exclusion: first 120 seconds
measurement: next 600 continuous seconds
Average presented FPS >= 58.0
P95 frame interval <= 20.0 ms
P99 frame interval <= 33.334 ms
janky frame = interval > 33.334 ms
janky frames <= 1.0%
severe stall = interval > 100 ms
severe stalls <= 3 in 600 seconds
no renderer crash
no Vulkan device loss
no recurring graphics error storm
```

Embedded-vs-direct control regression gate under equivalent runtime/workload:

```text
Average/source FPS regression <= 1.0 FPS
P99 frame interval regression <= 3%
jank regression <= 0.25 percentage points
median synthetic input-to-present <= direct control + 5 ms
P95 synthetic input-to-present <= direct control + 8.334 ms
absolute median input-to-present <= 50 ms
absolute P95 input-to-present <= 83.334 ms
```

If the simple MMAP/Metal presentation cannot pass this gate, investigate the embed transport first. Do not randomly tune guest RAM, renderer, and graphics settings simultaneously.

---

# 31. Strict implementation gates

## Gate 0 — preserve the control

Deliverables:

```text
record exact current runtime config
retain current direct-window control build for engineering A/B
preserve current telemetry/performance evidence
mark old window-hack production path superseded
```

Exit: known-good control remains launchable and recoverable.

## Gate 1 — Xcode/native project and protocol lock

Implement:

```text
TFTMAC.xcodeproj
SwiftPM locks
vendored compatible emulator proto
generated Swift client
basic native NSWindow
unit-test target
EmbeddedControlProbe target
```

Exit: clean Release build on authoritative Xcode.

## Gate 2 — hidden emulator controller probe

Probe only; no product polish.

```text
start logger
launch current 5-GB/6-core emulator hidden
locate/authenticate gRPC
get status
verify AVD/runtime
clean shutdown
```

Exit: no visible Qt/QEMU and authenticated controller works reliably.

Stop if this fails.

## Gate 3 — full 1920×1080 raw display

```text
MMAP raw stream
bounded copy
Metal ring
MTKView
complete 1920x1080 image
resize/aspect-fit
10-minute TFT foreground animation
```

Exit: no recurring corruption, tearing, gRPC disconnect, or renderer change.

## Gate 4 — native input

```text
mouse/touch
keyboard
wheel
Back/Home/Overview
```

Exit: Android/TFT can be operated without a visible emulator UI.

## Gate 5 — FPS truth/calibration

```text
source seq/timestamps
Metal present counters
fps.jsonl
native HUD
SurfaceFlinger/Perfetto calibration
```

Exit: displayed FPS label is truthful and raw FPS data advances once/sec.

## Gate 6 — full native Mac UX

```text
real traffic lights
native toolbar
native menus
normal resize
FIT/100%
native fullscreen
Device Controls inspector
all side/device controls
advanced controls capability sheet
```

Exit: every visible control has a deterministic PASS test.

## Gate 7 — Play/TFT lifecycle

```text
clock/time preflight
Play sign-in-needed state
official install/update flow
package applicationId/versionCode/versionName
installer verification
signer digest capture
Riot patch/init state
Riot login surface
TFT restart
```

Exit: clean machine/runtime state can get from app launch to official TFT ready without developer terminal intervention except human authentication.

## Gate 8 — runtime profiles/settings

```text
Baseline/Custom profiles
config hashes
CPU 4/6/8
RAM 4.0/5.0/6.0 GB
ASG 800/400
Apply & Restart
last-known-good rollback
requested-vs-observed verification
```

Exit: approved runtime experiments require no source edit.

## Gate 9 — raw-first logger and SQL

```text
continuous source-of-truth run
capture seal
post-seal hashes
FPS SQL schema
normalization
forced SQL-failure recovery test
abandoned-capture recovery
```

Exit: SQL/post-processing failure cannot lose or delay protection of the raw run.

## Gate 10 — embedded-vs-direct performance A/B

Run current baseline through both paths with the same Android/TFT configuration.

Compare:

```text
source FPS
presented FPS
frame intervals
stream drops
source-to-present latency
SurfaceFlinger/HWC/GPU misses
CPU/RSS
host compression/swap/pageouts
guest memory
input latency
audio
network stability
logger health
```

Exit: native embed passes the frozen regression gate.

Only now is the direct-window wrapper retired as a product path.

## Gate 11 — full real-match acceptance

Complete a real official match entirely in the native app and seal/analyze the run.

Exit: native TFTMAC is `PLAYABLE_NATIVE`.

## Gate 12 — League Voice feasibility

Run only after core app is stable.

Exit: either `SUPPORTED` with legitimate official-client proof or `UNAVAILABLE — RIOT SESSION LIMIT/NO SUPPORTED INTERFACE` with no bypass attempt.

## Gate 13 — signing/notarization/release

```text
Release build
Developer ID signing
notarization
stapling
/Applications launch
release checklist
rollback artifact
```

Exit: production-shippable native app artifact.

---

# 32. Release acceptance checklist

Core native release is not complete until every item below is proven:

```text
[ ] one Finder/Dock TFTMAC app identity
[ ] real red/yellow/green controls
[ ] normal resizable Mac window
[ ] native fullscreen via green button / Control-Command-F
[ ] no visible QEMU title bar
[ ] no visible Android Emulator toolbar
[ ] no Accessibility permission required
[ ] full Android 1920x1080 display embedded in TFTMAC
[ ] complete game UI visible
[ ] correct aspect ratio in windowed mode
[ ] full content fill on 16:9 fullscreen
[ ] FIT works
[ ] 100% works
[ ] mouse/touch works
[ ] keyboard works
[ ] wheel/scroll works
[ ] Back works
[ ] Home works
[ ] Overview works
[ ] Power/Wake works
[ ] Rotate Left works
[ ] Rotate Right works
[ ] Volume Up works
[ ] Volume Down works
[ ] Mute works
[ ] Screenshot works
[ ] Restart TFT works
[ ] Restart Android works
[ ] implemented Advanced Emulator Controls work
[ ] current Google Play ARM64 image verified
[ ] Android date/time preflight works
[ ] TFT applicationId verified
[ ] installer verified as Google Play
[ ] current versionName/versionCode captured
[ ] signer digest captured and retained as package evidence
[ ] official Play install/update flow works
[ ] Riot login/patch flow works
[ ] CPU 4/6/8 UI works
[ ] RAM 4.0/5.0/6.0-GB UI works
[ ] ASG 800/400 UI works
[ ] profile persistence/hash works
[ ] Apply & Restart seals old capture and starts new logger first
[ ] High/60/OFF baseline represented correctly
[ ] Ultra High remains rejected until new evidence promotes it
[ ] live FPS visible
[ ] fps.jsonl advances once/sec
[ ] stream drops measured
[ ] presentation latency measured
[ ] SurfaceFlinger counters continue
[ ] runtime config/hash attached to every run
[ ] logger starts before emulator/gameplay
[ ] Stop/Quit writes raw seal before post-processing
[ ] no SDK/AVD recursive inventory on critical stop path
[ ] SQL failure cannot invalidate a raw-sealed run
[ ] CoreAudio works through a long session
[ ] no recurring network disconnect caused by embed layer
[ ] complete official TFT match succeeds in native app
[ ] embedded presentation passes direct-control performance gate
[ ] app is Developer ID signed
[ ] app is notarized/stapled
[ ] /Applications/TFTMAC.app launch passes
```

League Voice has its own separate release checklist and may remain unavailable without blocking these core requirements.

---

# 33. Explicit stop conditions

Stop adding layers and diagnose the first broken boundary if any of these occurs:

```text
hidden emulator cannot authenticate gRPC
frame stream changes guest resolution or renderer path
MMAP source repeatedly corrupts/tears after bounded-copy protection
gRPC display adds material source-FPS/input regression
native presentation requires software video encoding
raw logger becomes dependent on the render/UI thread
SQL/post-processing can delay or prevent raw sealing
Google Play package cannot be verified as official authority
normal device controls require visible Qt UI and no safe gRPC/ADB equivalent exists
runtime-setting application silently changes more than the selected variable
League Voice requires forging/replaying Riot/Vivox authentication
League Voice breaks the active Android TFT session because of Riot session rules
```

These are architecture faults, not reasons to add wrapper hacks.

---

# 34. Zen Gate / no-overengineering rules

The implementation remains deliberately small:

- one native app;
- one official Google Play AVD;
- one current stock Emulator runtime;
- one embedded display path;
- one bounded frame copy before considering zero-copy;
- one data-driven settings registry;
- one continuous logger architecture;
- one official package authority;
- one optional isolated League Voice provider;
- no source AEMU build unless a measured blocker demands it;
- no custom ANGLE build unless a measured blocker demands it;
- no giant cross-product performance matrix;
- no duplicate runtime on internal storage;
- no second updater/feed/orchestration service;
- no web/Electron shell;
- no fake fullscreen/window management system.

Every new component must either satisfy a user-visible native-app requirement or own a measured causal failure.

---

# 35. Required implementation artifacts

Implementation is expected to leave durable evidence, not just code.

Required artifacts by completion:

```text
TFTMACAPP.md
TFTMAC.xcodeproj
Package.resolved
Vendor/AndroidEmulator/emulator_controller.proto
Vendor/AndroidEmulator/SOURCE.json
Generated/EmulatorController/*.swift
ssot/native-app-probe-results.json
ssot/native-app-release-checklist.md
ssot/native-app-performance-ab.json
ssot/tft-package-authority.json
ssot/emulator-controller-authority.json
runtime profile schema/version
FPS raw schema/version
SQLite FPS migration
unit/integration/UI tests
dist/TFTMAC.app
dist/TFTMAC.dmg
notarization evidence
```

---

# 36. Final execution order

A fresh implementation agent should execute this file from top to bottom with this priority:

```text
1. Preserve current control.
2. Create normal Xcode app and lock protocol/dependencies.
3. Prove hidden emulator + authenticated controller.
4. Prove full 1920x1080 raw Metal display.
5. Prove native input.
6. Add truthful FPS and calibration.
7. Build complete native window/toolbar/device controls.
8. Integrate Play/TFT lifecycle and package verification.
9. Add runtime profiles/settings.
10. Harden continuous logging and raw-first stop/recovery.
11. Run direct-vs-embedded performance A/B.
12. Complete real native-app TFT match acceptance.
13. Run League Voice feasibility separately.
14. Sign, notarize, install, and release.
```

Do not ask the user to choose architecture already resolved by this file. Machine-state discovery should resolve paths, package state, component versions, runtime state, and available controller capabilities automatically.

The only expected human pauses are official Google/Riot authentication, MFA/CAPTCHA/consent, and real gameplay/subjective quality confirmation when a release acceptance test specifically requires it.

---

# 37. Definition of done

TFTMAC native app work is done when the user can click **TFTMAC** in Finder/Dock, see one normal native Mac window, use the entire full-resolution Android/TFT experience inside it, enter normal macOS fullscreen, play an official current TFT match with mouse/keyboard and CoreAudio, operate all required emulator/device controls without a second window, change supported runtime resources from native Settings, see truthful live FPS, finish/quit with the raw run immediately protected, and reopen the app without developer-terminal cleanup.

At that point:

```text
PLAYABLE_NATIVE = YES
FULL_SIZE_EMBEDDED_DISPLAY = YES
NATIVE_FULLSCREEN = YES
OFFICIAL_PLAY_TFT = YES
CONTINUOUS_FPS_TELEMETRY = YES
SAFE_RAW_CAPTURE_SEAL = YES
RUNTIME_SETTINGS = YES
PRODUCTION_SIGNED/NOTARIZED = YES
LEAGUE_VOICE = SUPPORTED or TRUTHFULLY_UNAVAILABLE, never bypassed
```

That is the TFTMACAPP ship target.
