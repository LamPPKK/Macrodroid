# TFTMAC Native Embedded macOS App Build Plan

**Status:** Replacement authority for the native macOS application/presentation work  
**Project:** TFTMAC  
**Goal:** Ship one legitimate native macOS application that owns Android/TFT presentation, runtime settings, live FPS, controls, logging, and fullscreen without altering the proven TFT graphics pipeline.

---

## 0. Why this plan exists

The prior wrapper approach is superseded. Trying to resize, rename, cover, or reposition a separate QEMU/Qt window is not the production architecture.

The production application must:

- be one normal macOS application with a normal `NSWindow`;
- use genuine red/yellow/green macOS window controls;
- use normal macOS fullscreen/Spaces behavior;
- hide the emulator Qt UI completely;
- embed the Android display inside TFTMAC using the Android Emulator control interface;
- preserve the current Android framebuffer at 1920x1080;
- preserve the proven graphics path and runtime compatibility configuration;
- provide native Mac controls for Android/TFT actions;
- expose safe runtime tuning controls directly in TFTMAC;
- show live FPS to the user;
- persist FPS and performance telemetry continuously;
- seal raw telemetry before any post-session SQL work;
- make later tunables data-driven so new settings do not require another UI rewrite.

This plan deliberately separates **graphics execution** from **presentation**.

The current execution path stays:

```text
TFT / Unreal
 -> ANGLE
 -> guest Vulkan/ranchu
 -> virtio-gpu-asg / gfxstream
 -> host Vulkan
 -> MoltenVK
 -> Metal / Apple M4
```

The new macOS presentation path becomes:

```text
hidden Android Emulator Qt UI
 -> EmulatorController frame stream
 -> shared-memory raw frame transport
 -> TFTMAC Metal view
 -> native NSWindow / native macOS fullscreen
```

Do not replace or weaken the graphics execution path merely to solve the Mac UI.

---

# 1. Frozen runtime authority

The first native embedded build must preserve the currently proven runtime unless a setting is deliberately changed by the user.

Default baseline:

```text
Guest resolution: 1920x1080
Density: 320 dpi
Refresh target: 60 Hz
CPU: 6 cores
Guest RAM: 5120 MB
GPU mode: host
Audio: CoreAudio
Google Play ARM64 API36 guest
Official Riot TFT package
ANGLE ES3.2 compatibility exposure: unchanged
Graphics transport: virtio-gpu-asg / gfxstream
ASG write buffer: 1048576
ASG write step: 16384
ASG data ring: 32768
ASG draw flush interval: 800
MoltenVK configuration: unchanged
Logger: always-on raw-first architecture
```

The native-app project must not silently modify these defaults.

---

# 2. Real native Mac window

Replace the borderless shell and floating panels with one ordinary AppKit window.

Required window style:

```text
.titled
.closable
.miniaturizable
.resizable
.fullSizeContentView
```

Requirements:

- Real system red/yellow/green controls at top-left.
- Window title: `TFTMAC`.
- Normal Dock identity: `TFTMAC`.
- Normal menu-bar application identity: `TFTMAC`.
- Native `NSToolbar`, preferably compact/unified.
- `.fullScreenPrimary` behavior.
- Green traffic-light button uses macOS fullscreen.
- `View > Enter Full Screen` works.
- `Control-Command-F` works through normal AppKit behavior.
- No custom fake fullscreen implementation.
- No manually hiding the menu bar or Dock as the primary fullscreen mechanism.
- No Accessibility permission required for ordinary operation.

The game display view occupies the content region of this window.

---

# 3. Embedded emulator architecture

Launch Android Emulator in Android-Studio-style embedded mode rather than displaying its Qt UI.

Required launch direction:

```text
-qt-hide-window
-grpc-use-token
-idle-grpc-timeout 300
```

Keep the current runtime arguments for CPU, memory, renderer, audio, system image, ports, compatibility feature list, and other proven settings.

Remove production dependency on:

- external visible Qt window;
- `-scale` window-sizing tricks;
- `emulator-user.ini` window placement;
- Finder desktop bounds;
- AX/Accessibility APIs;
- moving emulator windows off-screen;
- hiding the Google toolbar with overlays;
- renaming QEMU windows;
- physical-monitor-inch assumptions.

QEMU remains the Android VM process but never becomes the user-facing application window.

---

# 4. Embedded frame transport

Implement `EmbeddedEmulatorView` as a native Metal-backed view (`MTKView` or an equivalent AppKit/Metal view).

Use the Android Emulator controller frame stream.

Preferred frame request:

```text
display: 0
width: 0
height: 0
pixel format: RGBA8888
transport: MMAP/shared memory
```

Width/height zero preserves the guest display's current native dimensions, which for TFTMAC remain 1920x1080.

Do not use:

- PNG streaming;
- H.264/VP8 encoding;
- scrcpy;
- software screen recording;
- guest-side video encoding;
- periodic screenshots as the primary display path.

The Mac view scales the 1920x1080 source image to the actual window size.

Windowed behavior:

- preserve aspect ratio;
- default to aspect-fit;
- no stretching;
- no hidden game UI;
- normal letterboxing only when the window is not 16:9.

Fullscreen behavior on a 16:9 display:

- 1920x1080 guest remains unchanged;
- Metal view fills the actual native fullscreen content area;
- no visible Qt/QEMU chrome;
- no duplicate control bars.

---

# 5. Input transport

Translate native Mac input directly through EmulatorController where supported.

Required input classes:

```text
mouse/touch
keyboard
Back
Home
Overview
```

Input mapping must use the displayed image rectangle, not the entire window when letterboxed.

Coordinate mapping:

```text
native mouse/touch position
 -> local image coordinates
 -> normalized image coordinates
 -> 1920x1080 Android coordinates
```

Do not use brittle hardcoded screen coordinates for normal application interaction.

ADB may remain available for service actions, diagnostics, and fallback controls, but the embedded display should have a first-class input path.

---

# 6. Native toolbar and menus

Remove the permanent right-side control rail.

Primary native toolbar items:

- Back
- Home
- Overview
- Volume/Mute
- Screenshot
- Restart TFT
- live FPS display
- optional diagnostics status indicator

Secondary actions belong in native menus or an overflow menu:

- Rotate left/right
- Wake Android
- Restart Android
- Open capture folder
- Open diagnostics
- Reset runtime profile
- Stop runtime

Required application menus:

```text
TFTMAC
  About TFTMAC
  Settings...
  Quit TFTMAC

File
  Screenshot

View
  Enter Full Screen
  Show FPS Overlay

Device
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

Help
```

---

# 7. Data-driven Runtime Settings system

Runtime tuning must become a product feature rather than source-code edits.

Create a persistent `RuntimeProfile` model and a declarative `RuntimeSettingDefinition` registry.

Each setting definition contains at least:

```text
id
label
group
value type
allowed range/options
default value
units
apply mode
restart requirement
runtime/AVD mapping
validation rule
risk level
log key
help text
```

Suggested apply modes:

```text
LIVE
RESTART_TFT
RESTART_ANDROID
NEXT_SESSION
```

The Settings UI should be generated from this registry so future settings can be added with minimal UI coding.

Persist user-selected profiles under:

```text
~/Library/Application Support/TFTMAC/Profiles/
```

Each profile receives a deterministic config hash.

Every capture records the exact profile and hash used.

Provide:

- `Baseline` profile;
- `Custom` profile;
- Save As...;
- Duplicate profile;
- Reset to baseline;
- optional import/export JSON later.

When a restart-required setting changes while Android is running:

1. UI marks it `Restart required`.
2. User can click `Apply & Restart Android`.
3. Current raw logger is sealed safely.
4. Exact new profile is persisted.
5. Emulator restarts hidden with the new configuration.
6. New capture begins before Android/TFT startup.
7. TFT relaunches.

No developer source edit is required.

---

# 8. Initial user-configurable settings

## 8.1 CPU cores

Expose:

```text
2 through 8 cores
```

UI control: stepper or segmented/dropdown control.

Apply mode: `RESTART_ANDROID`.

Launch mapping: emulator CPU-core setting / launch argument used by the current runtime.

Every session logs:

```text
cpu_cores_requested
cpu_cores_observed
```

## 8.2 Guest RAM

Supported product UI range:

```text
4.0 GB through 8.0 GB
```

Increment:

```text
0.5 GB
```

Exact choices:

```text
4.0 / 4.5 / 5.0 / 5.5 / 6.0 / 6.5 / 7.0 / 7.5 / 8.0 GB
```

Do not expose 9 GB or 10 GB. Keep the RAM control simple and inside the supported emulator range.

UI control: stepper/dropdown in 0.5 GB increments.

Apply mode: `RESTART_ANDROID`.

Every session logs:

```text
ram_mb_requested
ram_mb_observed
ram_support_class = VALIDATED | REJECTED
```

## 8.3 ASG draw flush interval

Expose the current graphics connector tuning variable directly.

Initial validated comparison choices:

```text
400
800
```

Default: `800` until evidence promotes another value.

UI label:

```text
ASG Draw Flush Interval
```

Group: `Advanced Graphics`.

Apply mode: `RESTART_ANDROID`.

The UI should explain:

- lower values submit/notify more frequently;
- this can reduce host starvation/presentation latency;
- lower values can increase transport/CPU notification overhead;
- this is an experiment variable, not a universal quality slider.

Future values can be added by modifying the setting definition rather than redesigning the UI.

Every session logs:

```text
asg_draw_flush_interval
```

and its exact config hash.

## 8.4 Initially visible but locked baseline values

Show these in Settings/System Information so the user understands the active environment, but keep them locked during the first native-app release:

```text
Guest resolution: 1920x1080
Density: 320 dpi
Refresh target: 60 Hz
GPU backend: host
Graphics transport: virtio-gpu-asg
ASG write buffer: 1 MiB
ASG write step: 16 KiB
ASG data ring: 32 KiB
Audio backend: CoreAudio
ANGLE compatibility features
MoltenVK settings
```

They can move into Advanced/Experimental settings later if evidence provides a reason.

Do not create dozens of unproven knobs just because they exist.

---

# 9. Future setting extensibility

The architecture must make new tunables cheap to add.

Example future setting definitions may include:

- ASG write step size;
- ASG data ring size;
- ASG write buffer size;
- selected ANGLE feature switches;
- selected MoltenVK queue controls;
- boot mode;
- trace intensity;
- optional presentation interpolation/upscaling controls.

A future setting should require:

1. one setting definition;
2. one validated runtime mapping;
3. one logging field/mapping;
4. no custom Swift view unless the setting genuinely needs a specialized UI.

---

# 10. TFT in-game settings

TFT graphics preset/FPS cap/Performance Mode are important experiment variables, but do not automate them through blind screen-coordinate tapping.

Desired app-facing values:

```text
Graphics: Low / Medium / High / Ultra High
FPS cap: 30 / 60 / None
Performance Mode: On / Off
```

Implementation rule:

- first discover whether Riot/Unreal exposes these settings through a stable accessible configuration file, Android preference, intent, console, or other deterministic local interface;
- if a stable non-invasive interface exists, add it to the Runtime Settings system;
- if only brittle UI-coordinate automation exists, keep the values as observation/experiment annotations until a safer application method is found.

No coordinate-hack setting automation belongs in the production Mac app.

---

# 11. FPS is a required first-class metric

FPS is no longer optional.

The previous logger's `gfxinfo` path does not observe TFT's native Unreal/Vulkan presentation, so `gfxinfo` cannot be the primary FPS source for TFTMAC.

The embedded emulator frame stream becomes the low-overhead live FPS authority for the native application.

Google's emulator frame messages provide:

```text
seq         monotonically increasing frame sequence
             gaps indicate frames dropped by the stream/client path

timestampUs estimated emulator frame-generation time before copy/transform
```

TFTMAC must derive at least three distinct metrics rather than collapsing them into one ambiguous number.

## 11.1 Source FPS

`sourceFPS` = rate of emulator-generated frames using source timestamps/sequence progression.

This is the primary live game/display production rate while TFT is foreground.

Rolling windows:

```text
1 second
5 seconds
30 seconds
```

## 11.2 Presented FPS

`presentedFPS` = rate at which TFTMAC actually presents new emulator frames through Metal.

This represents what the user sees in the native app.

## 11.3 Stream drops

Using sequence gaps:

```text
droppedFrameCount
droppedFramePercent
```

This distinguishes a slow game from a fast game whose embedded presentation transport is dropping frames.

## 11.4 Presentation latency

Use:

```text
emulator timestampUs
host receive monotonic timestamp
Metal submit timestamp
Metal present/completion timestamp where available
```

Derive:

```text
source_to_receive_ms
receive_to_submit_ms
submit_to_present_ms
source_to_present_ms
```

Track mean, p50, p95, p99, max.

This is required because an embedded stream could report 60 source FPS while presenting frames late.

## 11.5 Display refresh

Record actual Mac display refresh rate separately.

Never label 60 Hz refresh as 60 FPS unless frames prove it.

---

# 12. User-visible FPS HUD

TFTMAC must display FPS while playing.

Default overlay:

```text
FPS 59.8
```

Optional expanded diagnostic mode:

```text
SRC 59.8
PRESENT 59.6
P95 18.2 ms
DROP 0.3%
```

Requirements:

- native overlay on top of the Metal view;
- not rendered inside Android;
- does not alter guest resolution;
- does not intercept gameplay clicks outside its small overlay rectangle;
- user toggle through `View > Show FPS Overlay`;
- persisted preference;
- optional selectable corner later.

The toolbar may also display the current FPS, but the in-game overlay is required.

---

# 13. Continuous FPS raw log

Create a dedicated raw artifact:

```text
fps.jsonl
```

Do not write one SQLite transaction per frame.

Each frame updates in-memory counters. Once per second, append one compact summary record.

Example fields:

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

A one-Hz append-only JSONL stream is low overhead and survives SQL/post-processing failures.

---

# 14. SQL FPS schema

Extend the performance lab with a dedicated time-series table rather than storing only one whole-run FPS average.

Required logical table:

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

Indexes:

```text
(session_id, host_mono_ns)
```

Post-session rollups must add:

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
```

Performance experiments must be compared primarily against FPS/frame-time and presentation-latency outcomes, with CPU/memory/pressure as explanatory metrics.

---

# 15. Deep frame attribution remains separate

The always-on embedded FPS metrics answer:

- how many frames are being produced;
- how many reach TFTMAC;
- how many TFTMAC presents;
- whether the embedded transport drops frames;
- how much end-to-end presentation delay exists.

They do not by themselves explain *why* an Android frame was late.

For causal graphics diagnosis continue using bounded Perfetto/SurfaceFlinger traces around representative load.

FrameTimeline remains useful for SurfaceFlinger/display-side jank attribution, but TFT uses a native SurfaceView path and app-side FrameTimeline coverage has limitations. Do not pretend a missing app FrameTimeline slice means the game did not render.

Combine:

```text
always-on source/present FPS
+ SurfaceFlinger/HWC/GPU miss counters
+ bounded Perfetto traces
+ host CPU/memory
+ ASG/gfxstream instrumentation when needed
+ MoltenVK instrumentation when needed
```

---

# 16. Runtime-settings logging contract

Every session must contain a frozen `runtime-profile.json`.

Example:

```json
{
  "cpuCores": 6,
  "ramMB": 5120,
  "resolution": "1920x1080",
  "densityDpi": 320,
  "refreshHz": 60,
  "asgDrawFlushInterval": 800,
  "gpuMode": "host",
  "audioBackend": "coreaudio",
  "configHash": "..."
}
```

Any user change must create an explicit marker:

```text
CONFIG_CHANGE_REQUESTED
CONFIG_CHANGE_APPLIED
```

Restart-required settings must begin a new capture after restart so one run never silently mixes two VM configurations.

---

# 17. Experiment workflow from the UI

A normal user/developer experiment should become:

1. Open TFTMAC Settings.
2. Select or duplicate a profile.
3. Change one setting, e.g. `ASG Draw Flush Interval 800 -> 400`.
4. TFTMAC warns that Android restart is required.
5. Click `Apply & Restart Android`.
6. TFTMAC seals current raw data.
7. TFTMAC starts a fresh capture with the new profile/hash.
8. Android boots hidden.
9. TFT opens inside the native app.
10. Live FPS is visible.
11. Play normally.
12. Data is normalized and compared later without another source edit.

This is the required product loop.

---

# 18. Settings safety classes

Settings should show a small status badge:

```text
BASELINE
VALIDATED
EXPERIMENTAL
UNSUPPORTED
```

Examples:

```text
CPU 2-8 cores: VALIDATED after launch/runtime proof
RAM 4.0-8.0 GB in 0.5 GB increments: VALIDATED range after launch/runtime proof
ASG flush 800: BASELINE
ASG flush 400: EXPERIMENTAL until A/B verdict
1920x1080: BASELINE / locked
CoreAudio: BASELINE / locked
```

Do not allow an unsupported configuration to silently fall back to another value. Fail visibly and preserve the previous known-good profile.

---

# 19. Build phases

## Phase A — architecture reset

- Freeze/preserve current working runtime and logger.
- Mark old wrapper/window-moving code as superseded.
- Add this plan as native-app authority.
- Keep current production branch recoverable.

Exit gate: no ambiguity about which presentation architecture is being implemented.

## Phase B — real AppKit shell

- Build standard `NSWindow`.
- Add traffic lights, native toolbar, menus, settings window.
- Implement normal window/fullscreen lifecycle.
- Keep emulator external during this phase only as temporary development control.

Exit gate: TFTMAC behaves like an ordinary native Mac app even before embedding.

## Phase C — hidden emulator + controller connection

- Launch with `-qt-hide-window` and gRPC token.
- Discover/authenticate controller endpoint.
- Get emulator status.
- Implement lifecycle error handling.

Exit gate: Android boots with no visible QEMU/Qt UI and TFTMAC can query it.

## Phase D — embedded raw Metal display

- Implement MMAP RGBA frame stream.
- Display 1920x1080 in `MTKView`.
- Correct orientation.
- Correct resizing/aspect-fit.
- Implement native fullscreen.

Exit gate: complete Android display visible in TFTMAC only.

## Phase E — input/control integration

- Mouse/touch.
- Keyboard.
- Back/Home/Overview.
- screenshot.
- volume/mute.
- restart TFT.
- restart Android.

Exit gate: user can operate Android/TFT without another visible emulator UI.

## Phase F — runtime profiles/settings

- Implement setting registry.
- Profile persistence/config hashing.
- CPU cores 2-8.
- RAM 4.0-8.0 GB in 0.5 GB increments.
- ASG flush 400/800.
- Apply/restart workflow.

Exit gate: those experiments require no source edit.

## Phase G — FPS + presentation telemetry

- source frame counters.
- seq-gap drops.
- source timestamps.
- Metal presentation counters/timing.
- native FPS overlay.
- `fps.jsonl` one-Hz summaries.
- SQL normalization/time-series table.

Exit gate: live FPS visible and every active run contains FPS telemetry.

## Phase H — embedded-vs-direct performance gate

Compare embedded presentation against the proven direct emulator-window baseline while preserving the same guest/render configuration.

Required comparison:

```text
source FPS
presented FPS
source frame interval p95
SurfaceFlinger misses
HWC misses
GPU misses
source-to-present p95
CPU
RSS
host compressed memory
pageouts
input response
sound
```

Acceptance:

- no material graphics-feature regression;
- no guest-resolution regression;
- no recurring audio regression;
- no recurring disconnect caused by embed layer;
- no meaningful source-FPS regression attributable to embedding;
- no sustained stream drops;
- presentation latency acceptable for normal TFT play;
- raw logging remains healthy for long games.

Only if MMAP embedding fails this gate do we consider a source-level zero-copy IOSurface/Metal presentation bridge.

---

# 20. Final product acceptance

The native app is not complete until all are true:

```text
Finder/Dock icon launches TFTMAC
one Mac application owns the user experience
real red/yellow/green controls
normal native window resize
normal macOS fullscreen
no visible QEMU title bar
no visible Google emulator toolbar
no Accessibility permission needed
Android 1920x1080 display embedded inside TFTMAC
complete game UI visible
mouse/touch/keyboard work
CoreAudio works
TFT launches and plays a full match
CPU selection 2-8 available in Settings
RAM selection 4.0-8.0 GB in 0.5 GB increments available in Settings
ASG flush 800/400 available in Settings
settings persist in profiles
Apply & Restart safely starts a new run
live FPS visible in game
FPS written continuously to raw logs
FPS normalized into SQL
stream drops measurable
presentation latency measurable
runtime configuration/hash attached to every run
logger starts before gameplay
quit/stop seals raw data before normalization
embedded presentation passes performance A/B
```

---

# 21. Engineering rule

The purpose of the Settings and FPS systems is to shorten the development loop.

From this build onward, changing an approved runtime variable must not require a developer to edit source code, and evaluating that variable must not require guessing whether FPS improved.

The normal optimization loop becomes:

```text
select profile
change one variable
restart from TFTMAC
play
observe live FPS
seal continuous run
compare FPS/frame-time + pipeline + resource data
KEEP or REJECT
```

That is the production-level TFTMAC development workflow.
