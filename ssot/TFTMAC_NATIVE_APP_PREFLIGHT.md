# TFTMAC Native Embedded App — Full Preflight

**Status:** REQUIRED GO/NO-GO PREFLIGHT BEFORE NATIVE EMBEDDED IMPLEMENTATION  
**Project:** TFTMAC  
**Authority plan:** `ssot/TFTMAC_NATIVE_APP_EMBEDDED_BUILD_PLAN.md`  
**Goal:** Make the native-app rebuild a one-pass architecture change: real macOS app, hidden emulator UI, embedded Android display, complete device controls, runtime settings, continuous FPS, safe logging, and a separately gated League Voice bridge.

---

## 1. Executive decision

The current borderless-wrapper/visible-QEMU-window implementation is **superseded**. Do not spend additional engineering time calibrating Qt window size, `-scale`, HiDPI behavior, Accessibility window movement, toolbar masking, or `emulator-user.ini` placement.

The production architecture is:

```text
TFTMAC.app (real AppKit NSWindow)
  -> native NSToolbar / menus / optional Device Controls inspector
  -> MTKView embedded Android display
  -> authenticated Android Emulator gRPC EmulatorController
  -> hidden Qt UI (`-qt-hide-window`)
  -> existing Android Emulator 37.1.11 runtime
  -> existing API36 Google Play ARM64 guest
  -> official TFT
  -> existing ANGLE -> Vulkan -> gfxstream/ASG -> MoltenVK -> Metal path
```

The graphics execution pipeline is frozen while the presentation architecture is replaced.

**Overall preflight verdict: GO WITH GATES.**

Green and reusable now:

- Apple M4 / 16 GB host is proven capable of completing TFT matches.
- Android Emulator 37.1.11 path is proven.
- Official Google Play ARM64 guest is proven.
- Official Riot TFT package is proven playable.
- 1920x1080 / 320 dpi / 60 Hz guest is proven.
- 5 GB guest RAM is the current operational KEEP.
- 6 vCPU baseline is proven.
- CoreAudio is proven after explicit backend selection.
- ANGLE/Vulkan/gfxstream/ASG/MoltenVK/Metal pipeline is proven active.
- Raw-first continuous logger is proven.
- Existing Android navigation/device actions are proven through ADB.

Must pass before full UI implementation:

1. Hidden emulator boot with no visible Qt window.
2. Authenticated gRPC discovery/handshake against the exact installed Emulator 37.1.11.
3. 1920x1080 raw frame stream into a minimal Mac Metal view.
4. Input injection round trip.
5. Frame-stream FPS calibration against SurfaceFlinger/Perfetto.
6. Long-run performance gate showing embedding does not materially damage gameplay.

League Voice is a **separate conditional feature gate** and must not block the native app if Riot does not permit the required concurrent authenticated session.

---

# 2. Frozen machine/runtime facts

Target host already established by project evidence:

```text
Mac mini Mac16,10
Apple M4
arm64
16 GB unified memory
macOS 26.6.2 / build 25G83
Xcode 26.6 / build 17F113
```

Current Android runtime authority:

```text
Runtime root: /Volumes/MAC MINI M4/TFTMAC/Runtime
Android Emulator: 37.1.11.0 / build 15917651
ADB: 1.0.41
AVD: TFT_Ultra_Tablet
Console port: 5582
ADB server: donor port 5038
Google Play ARM64 API36 image
```

Current TFT/runtime baseline:

```text
Package: com.riotgames.league.teamfighttactics
Guest: 1920x1080
Density: 320 dpi
Refresh target: 60 Hz
CPU: 6 cores
RAM: 5120 MB
Audio: CoreAudio
GPU: host
Transport: virtio-gpu-asg / gfxstream
ASG write buffer: 1 MiB
ASG write step: 16 KiB
ASG data ring: 32 KiB
ASG draw flush: 800
ANGLE ES3.2 compatibility exposure: retained
MoltenVK settings: retained
```

No presentation work may silently alter those graphics/runtime facts.

---

# 3. Build-system preflight

## 3.1 Stop using the ad-hoc `swiftc` app build as the production architecture

The embedded app requires generated protobuf/gRPC sources, Swift package dependencies, native Metal code, resource copying, entitlements, tests, and a real app lifecycle. Move TFTMAC to a normal Xcode project using Swift Package Manager.

Required target:

```text
Product: TFTMAC.app
Architecture: arm64
Minimum macOS: 15.0
Primary language mode: Swift 6.x
UI: AppKit first; SwiftUI may be hosted where useful
Renderer: Metal / MetalKit
```

macOS 15.0 is selected because current gRPC Swift 2.x documents macOS 15 as its availability floor. The actual target host is macOS 26, so this creates no host blocker.

## 3.2 Dependency policy

Use current maintained gRPC Swift 2, not maintenance-only gRPC Swift 1.

Initial dependency family to resolve and freeze into `Package.resolved`:

```text
grpc-swift-2
  current major: 2.x
  current observed release: 2.4.2

grpc-swift-nio-transport
  current observed release family: 2.x
  current observed release: 2.9.1

grpc-swift-protobuf
  current observed release: 2.4.1

SwiftProtobuf
  current observed release: 1.38.1
```

Do not use floating `main` branches in production. Resolve once, build/test, then freeze exact versions/checksums in the normal SwiftPM lock.

## 3.3 Protocol source authority

Do not generate the client from an arbitrary future `emulator_controller.proto` and assume wire compatibility.

Required procedure:

1. Capture the exact installed emulator version/build.
2. Vendor a compatible `emulator_controller.proto` snapshot in the repository.
3. Record source URL/revision/SHA-256.
4. Generate Swift protobuf/gRPC code into a generated target.
5. Validate required RPCs against Emulator 37.1.11 before freezing the generated source.

Required RPC subset:

```text
getStatus
streamScreenshot
sendKey
sendTouch
sendMouse
injectWheel (if practical)
setVmState / getVmState
getScreenshot
streamLogcat (optional; current logger may remain primary)
get/set microphone state where needed
GPS/battery/etc only for advanced controls
```

---

# 4. Android Emulator embedded-control preflight

Google's own Android Studio embedded-emulator implementation is the donor architecture.

Research-verified behavior:

- Android Studio uses `-qt-hide-window` for embedded mode rather than attempting to resize/crop a visible Qt window.
- The EmulatorController exposes raw screenshot streaming.
- MMAP/shared-memory image transport is explicitly supported to reduce gRPC pixel-transfer overhead.
- `sendKey`, `sendTouch`, `sendMouse` are first-class EmulatorController RPCs.
- `setVmState` supports running/pause/reset/restart/shutdown/terminate semantics.
- current emulator tooling documents gRPC as the programmatic control interface.

## 4.1 Required launch flags

The first embedded probe uses the existing runtime arguments plus:

```text
-qt-hide-window
-grpc-use-token
-idle-grpc-timeout 300
```

Do not expose an unauthenticated gRPC service as the production default.

The exact port may be explicitly allocated by TFTMAC or discovered from the emulator registration file; choose one deterministic method and use it everywhere.

## 4.2 Discovery/authentication

The emulator creates a discovery/registration record containing the live gRPC endpoint and token. Official AEMU client code reads `grpc.port` and `grpc.token` from this registration data.

Preflight must prove the exact Emulator 37.1.11 authentication header behavior rather than hardcoding an assumption. Public examples differ across emulator generations (`Bearer` vs `Basic` token presentation), so the TFTMAC controller must:

1. read the discovery record owned by the current emulator process;
2. read endpoint + token in memory;
3. establish authenticated `getStatus`;
4. never persist or log the token;
5. discard it when the emulator exits.

A gRPC auth failure is a **hard Phase-0 stop**. Do not build the UI around an unproven control connection.

---

# 5. Minimal embedded-display proof — mandatory before app polish

Build a tiny `EmbeddedControlProbe` target first.

It should have one ordinary Mac window and one `MTKView`, no settings UI and no product polish.

Test sequence:

1. Launch the exact 5 GB baseline emulator hidden.
2. Connect to EmulatorController.
3. Call `getStatus`; verify version, booted state, 6 CPU cores, 5120 MB RAM.
4. Start `streamScreenshot` for display 0 with width=0, height=0, raw RGBA and MMAP transport.
5. Verify delivered image format resolves to landscape 1920x1080.
6. Show it in `MTKView`.
7. Run for at least 10 minutes, including TFT foreground animation.
8. Send a pointer/touch action.
9. Send Back/Home and restore TFT.
10. Take a native screenshot from the embedded frame.
11. Stop stream cleanly.
12. Gracefully stop emulator.

Exit gate:

```text
No Qt/QEMU window visible.
1920x1080 complete Android image visible inside MTKView.
No stretching/cropping.
Mouse/touch works.
Keyboard/system actions work.
No recurring frame corruption/tearing.
No recurring gRPC disconnect.
CoreAudio still works.
Existing renderer path unchanged.
```

Do not build the full Settings/menus/sidebar until this passes.

---

# 6. MMAP/Metal presentation design

A 1920x1080 RGBA frame is ~8.3 MB. At 60 unique frames/sec that is roughly 500 MB/sec of host memory traffic before overhead. M4 unified memory can handle this class of throughput, but it must still be measured.

First safe implementation:

```text
Emulator MMAP shared region
  -> detect new seq
  -> one bounded host copy into a 2- or 3-buffer Metal presentation ring
  -> present texture
```

Reason: older EmulatorController comments explicitly warn that MMAP can tear when the producer rewrites the shared buffer. A bounded copy into a triple-buffered Metal texture gives deterministic ownership and prevents a half-updated display.

Do not introduce PNG or H.264 just to avoid this copy.

Performance gate later decides whether the single copy is acceptable. Only if it measurably damages TFT do we consider the more invasive IOSurface/direct-host-frame bridge.

---

# 7. FPS preflight and correction

FPS is mandatory, but the number must be truthful.

`gfxinfo` is already proven unsuitable for TFT's native Unreal/Vulkan path.

The EmulatorController `Image` message provides:

```text
seq          monotonically increasing stream sequence; gaps identify dropped stream frames
timestampUs  emulator estimate of frame generation time before copy/transform
```

That is sufficient to measure the embedded delivery pipeline, but **do not call it game-engine FPS until calibrated** because the screenshot stream is a presentation stream and newer descriptions note frames may also be emitted after certain sensor changes.

Required metrics:

```text
emulator_frame_fps     from emulator timestamps
stream_delivery_fps    frames received by TFTMAC
metal_present_fps      distinct frames actually presented
stream_drop_count      from seq gaps
stream_drop_percent
source_to_receive_ms
receive_to_submit_ms
submit_to_present_ms
source_to_present_ms
```

User-facing default FPS:

```text
FPS = metal_present_fps
```

This is the most honest immediate answer to "how many unique frames am I seeing in TFTMAC?"

Expanded diagnostic HUD:

```text
FPS 59.8
EMU 60.0
DROP 0.0%
P95 17.4 ms
```

## 7.1 Calibration gate

Before promoting `emulator_frame_fps` as a game/display-production metric:

1. capture a stable 60-FPS TFT animation window;
2. record EmulatorController frame timestamps/seq;
3. simultaneously take a bounded SurfaceFlinger/FrameTimeline Perfetto trace;
4. compare counts/timing;
5. repeat during a known stutter/heavy-combat interval.

Acceptance:

- stream FPS tracks SurfaceFlinger presentation closely under load;
- seq gaps are distinguishable from guest/display slowdowns;
- Metal presentation FPS accurately reflects what the user sees.

If not, use SurfaceFlinger-derived timing as the source FPS authority and retain the gRPC numbers as embed-transport metrics.

## 7.2 Logging

Always-on raw output:

```text
fps.jsonl
```

Append once per second, not once per frame.

Store at least:

```text
utc
host_mono_ns
emulator_frame_fps_1s
emulator_frame_fps_5s
metal_present_fps_1s
metal_present_fps_5s
seq_first
seq_last
stream_drop_count
stream_drop_percent
source_interval_mean_ms
source_interval_p95_ms
source_to_present_mean_ms
source_to_present_p95_ms
display_refresh_hz
runtime_profile_hash
```

SQL normalizer must populate a time-series FPS table and run rollups after raw capture sealing.

A session without FPS telemetry is `PERFORMANCE_INCOMPLETE`, but failure to normalize FPS into SQLite must never invalidate the sealed raw run.

---

# 8. Native Mac application preflight

## 8.1 One real window

Required `NSWindow` style:

```text
.titled
.closable
.miniaturizable
.resizable
.fullSizeContentView
```

Use real AppKit traffic lights. No simulated red/yellow/green controls.

Use:

```text
collectionBehavior includes .fullScreenPrimary
```

Native green button / `Control-Command-F` / `View > Enter Full Screen` must call normal macOS fullscreen behavior.

No fake fullscreen, Accessibility repositioning, or Dock/menu-bar tricks.

## 8.2 Native controls structure

Permanent right rail is not required and should not consume gameplay width by default.

However, all current device-control buttons must survive as a **native optional Device Controls inspector** on the right, plus toolbar/menu shortcuts.

Inspector can be opened/closed by a toolbar button. When hidden, the game view gets the full content area. When visible, the 1920x1080 image is aspect-fit rather than distorted.

Required user controls:

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
Zoom Fit
Zoom 100%
Restart TFT
Restart Android
Enter/Exit Full Screen
Device Controls inspector toggle
Advanced Emulator Controls
```

## 8.3 Control implementation matrix

Primary input/pointer path:

```text
Mouse -> EmulatorController sendMouse/sendTouch
Touch gesture translation -> sendTouch
Keyboard text/keys -> sendKey
Wheel -> injectWheel where supported
```

System-control path may use the simplest reliable mechanism:

```text
Back/Home/Overview -> gRPC key event, ADB fallback
Volume +/-/Mute -> gRPC key event, ADB fallback
Power/Wake -> gRPC key event/ADB
Rotate -> deterministic Android setting or supported controller path; verify both directions
Screenshot -> current embedded raw frame / getScreenshot
Restart TFT -> existing package force-stop + official activity launch
Restart Android -> setVmState(RESTART) or controlled stop/start when config changes
```

The production app may keep ADB as a service-control fallback; embedding does not require removing a proven reliable control channel.

## 8.4 Button acceptance tests

Every visible button gets an automated or deterministic smoke test before release:

- click sends exactly one action;
- success updates UI state;
- failure surfaces a recoverable error;
- no button silently does nothing;
- no button breaks the logger;
- no button requires the hidden Qt toolbar.

The release checklist must individually mark every button PASS.

---

# 9. Advanced emulator controls

The old Google toolbar's `...` functionality should not disappear; it moves into a native `Device > Advanced Emulator Controls...` sheet.

Prioritize controls TFTMAC could realistically need:

```text
GPS/location
battery state
cellular/network simulation
microphone state
clipboard
camera/sensor status where exposed
VM pause/resume/restart
```

EmulatorController exposes broad device-control RPCs including GPS, battery, phone/SMS, microphone, VM state, display state and notification streams.

Do not rebuild Google's entire Extended Controls UI before shipping TFT. Implement the functions the current sidebars expose and the diagnostic controls relevant to TFT first, then keep the advanced sheet extensible.

---

# 10. Runtime Settings preflight

Initial user-selectable runtime configuration is intentionally small:

```text
CPU cores: 2,3,4,5,6,7,8
RAM: 4.0 GB through 8.0 GB in 0.5 GB increments
ASG draw flush: 400 or 800
```

Defaults:

```text
CPU: 6
RAM: 5.0 GB
ASG draw flush: 800
```

RAM choices:

```text
4.0
4.5
5.0
5.5
6.0
6.5
7.0
7.5
8.0 GB
```

No 9-10 GB testing.

All three are `RESTART_ANDROID` settings.

Changing one:

1. save pending profile;
2. show `Restart required`;
3. `Apply & Restart` seals current raw capture;
4. old VM stops cleanly;
5. new config hash is written;
6. new logger starts before emulator;
7. hidden emulator starts with new values;
8. TFT relaunches;
9. new capture records requested + observed values.

Runtime Settings UI is generated from a setting registry so later values do not require another custom settings screen.

---

# 11. Logging/SQL preflight

Preserve raw-first architecture:

```text
logger start
 -> raw streams
 -> game/session
 -> stop sampler
 -> seal raw capture + manifest
 -> only then SQLite normalization
```

Required new raw streams:

```text
fps.jsonl
embed-present.jsonl or equivalent compact presentation diagnostics
runtime-profile.json
```

Do not write SQL per frame.

Schema migration rules:

- database schema versioned;
- migration tested against the existing live TFTMAC lab DB;
- new FPS tables created idempotently;
- old runs remain readable;
- failed migration writes a normalization error artifact and leaves raw capture COMPLETE;
- no foreign-key failure can prevent runtime shutdown.

---

# 12. League Voice research conclusion

## 12.1 What Riot currently provides

Riot has two relevant voice concepts:

1. Existing **League Voice** for premade parties, historically integrated into the League PC client.
2. A newer **Team Voice** initiative announced by Riot on 2026-03-13. Riot explicitly said it was still being tested/iterated and had no concrete live timeline at that point.

Therefore do not assume current team-wide voice is available in production simply because PBE/client files exist.

The user target for TFTMAC is narrower and plausible:

> Join the same Riot premade-party League Voice room as a family member using the official PC League client.

## 12.2 Known client architecture

Riot's Developer Portal describes the League Client API as a local desktop interface between the League client's front end and local C++ services. Riot says it is not officially supported for third-party applications, but developers using it should disclose/register their use.

Historical League Client schemas expose a `lol-premade-voice` plugin with operations for:

```text
availability
capture devices
participants
participant mute/volume
self mute
input mode
mic level
activation sensitivity
push-to-talk availability
session create/delete
settings
mic test
```

Historical Riot client configuration and third-party endpoint catalogs indicate the underlying provider has been Vivox, but TFTMAC must not rely on an old scraped provider URL as authority.

## 12.3 Safe integration architecture

Do **not** implement TFTMAC as an independent fake Riot/Vivox client.

Do not:

- hardcode Riot voice token endpoints;
- mint/fake channel tokens;
- persist Riot client passwords/tokens;
- log local LCU credentials;
- reverse-engineer a bypass around Riot eligibility/party membership;
- join a channel the account is not entitled to join.

Preferred bridge:

```text
TFTMAC Voice button
 -> detect official Riot/League Client installation
 -> user signs into official client normally
 -> TFTMAC discovers local League Client API endpoint
 -> credentials read only locally/in memory
 -> dynamically verify current voice endpoints
 -> request/join the account's legitimate premade voice session
 -> official League client/plugin performs Riot/Vivox auth and media
```

This keeps channel entitlement and provider authentication under Riot's client.

## 12.4 Mandatory League Voice feasibility test

Before promising the button as functional, prove all of the following on the target Mac:

1. Official League Client can be installed/launched on the host.
2. User logs in through Riot's own UI; TFTMAC never receives credentials.
3. Current local League Client API is discoverable.
4. Current API exposes an equivalent of premade voice availability/session/participant operations.
5. User and son's PC account can be in the same eligible premade party/voice room.
6. **Critical:** the same user account can keep the League desktop client/voice session authenticated while the Android TFT session is active.
7. Joining voice does not cause Android TFT to be logged out/disconnected.
8. Android TFT does not cause League voice to lose authentication.
9. Voice input/output works through the Mac audio devices.
10. participant mute/volume/self-mute work.

If #6 fails because Riot enforces mutually exclusive account sessions, the official-client bridge is not viable. Stop there. Do not work around Riot authentication.

## 12.5 Product behavior

Include the native toolbar action from the beginning:

```text
League Voice
```

States:

```text
Unavailable
League Client Required
Sign In to League Client
Ready
Connecting
Connected
Error
```

The button can ship disabled/unavailable until the feasibility test passes, but the UI architecture should already have a place for it.

When connected, show a native popover:

```text
Connected to League Voice
participants
speaking state if available
self mute
participant mute/volume
input device
output device if exposed
push-to-talk/open mic mode if exposed
Disconnect
```

No voice secrets go into the TFTMAC telemetry database.

## 12.6 Future direct integration

If Riot later publishes a supported Team Voice API/SDK or a supported cross-platform token flow, replace the League Client bridge with that supported mechanism.

The voice module must therefore be an isolated `LeagueVoiceProvider` interface, not intertwined with emulator code.

---

# 13. Architecture modules

Recommended native targets/modules:

```text
TFTMACApp
  AppKit lifecycle, menus, windows, toolbar

EmbeddedEmulator
  discovery/auth, gRPC client, frame stream, input, VM state

MetalPresenter
  MMAP buffer handling, textures, aspect fit, fullscreen presentation

RuntimeProfiles
  CPU/RAM/ASG setting registry, persistence, hashes

RuntimeController
  emulator/TFT lifecycle and existing Node/controller bridge during transition

Telemetry
  raw logger, FPS accumulator, manifests, normalizer trigger

DeviceControls
  Back/Home/Overview/volume/power/rotate/screenshot/advanced controls

LeagueVoice
  optional official League Client bridge behind provider interface
```

Do not put all of this back into one `TFTMACWindowCoordinator` class.

---

# 14. Implementation order — strict

## Gate 0 — preserve current control

- commit current proven runtime/logging evidence;
- keep a launchable direct-window control build for A/B only;
- mark wrapper/window-hacking code superseded.

## Gate 1 — toolchain/project

- create normal Xcode project;
- add/pin SwiftPM dependencies;
- generate/freeze compatible EmulatorController Swift code;
- compile cleanly with Swift concurrency warnings treated seriously.

## Gate 2 — hidden gRPC emulator probe

- hidden boot;
- discovery/auth;
- getStatus;
- clean shutdown.

Do not continue if this fails.

## Gate 3 — raw display/Metal/input

- 1920x1080 stream;
- MTKView;
- input;
- no visible Qt;
- no tearing.

Do not build settings before this passes.

## Gate 4 — FPS calibration

- emulator stream metrics;
- Metal present metrics;
- Perfetto/SurfaceFlinger comparison;
- define truthful HUD number.

## Gate 5 — full native Mac UI

- real traffic lights;
- native fullscreen;
- toolbar/menus;
- optional Device Controls inspector;
- all button tests.

## Gate 6 — settings profiles

- 2-8 CPU;
- 4.0-8.0 GB RAM by 0.5;
- ASG 400/800;
- restart/new-capture workflow.

## Gate 7 — long-game embed A/B

Compare against direct Qt control:

```text
FPS
frame intervals
stream drops
source-to-present latency
SurfaceFlinger/HWC/GPU misses
CPU
RSS
memory compression/pageouts
audio
input reliability
network stability
logger health
```

Embedded presentation must not materially worsen gameplay.

## Gate 8 — League Voice feasibility

Run separately after the Mac app/runtime is stable. Do not mix a Riot-auth investigation into the critical graphics/UI build.

---

# 15. Release acceptance checklist

Native app release requires all of these:

```text
[ ] one Finder/Dock TFTMAC app identity
[ ] real red/yellow/green window controls
[ ] normal resizable Mac window
[ ] native macOS fullscreen via green button / Cmd-Ctrl-F
[ ] no visible qemu-system-aarch64 title
[ ] no visible Android Emulator Qt toolbar
[ ] no Accessibility permission required
[ ] Android display embedded in TFTMAC
[ ] complete 1920x1080 image visible
[ ] correct aspect ratio when windowed
[ ] full display on 16:9 fullscreen
[ ] mouse/touch works
[ ] keyboard works
[ ] wheel/scroll works where relevant
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
[ ] Fit/100% display controls work
[ ] Restart TFT works
[ ] Restart Android works
[ ] advanced controls sheet opens and functional implemented controls work
[ ] CPU 2-8 setting works
[ ] RAM 4.0-8.0 by 0.5 GB works
[ ] ASG 400/800 works
[ ] config hashes persist
[ ] setting restart seals old capture and starts new logger first
[ ] live FPS visible
[ ] FPS raw log advances once/sec
[ ] SQL FPS normalization works
[ ] raw capture survives SQL failure
[ ] CoreAudio works throughout a long game
[ ] official TFT launches and completes a real match
[ ] logger remains healthy throughout
[ ] embedded performance passes direct-window A/B
```

League Voice release gate is separate:

```text
[ ] official League client detected
[ ] user authenticates only through Riot UI
[ ] local voice endpoint dynamically verified
[ ] same-account concurrent League-client + Android-TFT session works
[ ] legitimate party voice session can be joined
[ ] son on PC hears user
[ ] user hears son
[ ] mute/volume/self-mute works
[ ] voice does not disconnect TFT
[ ] no Riot/Vivox secret is persisted/logged
```

If the concurrency gate fails, mark League Voice `UNAVAILABLE — RIOT SESSION LIMIT` and ship the rest of TFTMAC without attempting an authentication bypass.

---

# 16. Stop conditions

Stop implementation and diagnose rather than continue layering code if any of these happens:

- hidden emulator cannot provide authenticated gRPC control;
- gRPC frame stream changes the renderer path or guest resolution;
- MMAP presentation materially damages source FPS/input latency;
- raw logging becomes dependent on the UI thread;
- SQL normalization can break capture sealing;
- a device button requires visible Qt UI to work and no gRPC/ADB equivalent exists;
- League Voice requires forging/replaying Riot/Vivox authentication or breaks same-account TFT play.

Those are architecture problems, not reasons to add another wrapper hack.

---

# 17. Final preflight verdict

**Native embedded TFTMAC:** GO. The architecture is directly supported by the Android Emulator control plane and mirrors Google's own embedded-emulator approach. First implementation must begin with the hidden-gRPC-MMAP probe, not UI polish.

**Runtime settings:** GO. CPU 2-8, RAM 4.0-8.0 in 0.5 GB increments, and ASG 400/800 are small deterministic restart-required variables that can be profile-driven.

**FPS:** GO WITH CALIBRATION. Emulator frame seq/timestamps + Metal presentation timing give the missing always-on FPS/presentation data. Calibrate against SurfaceFlinger/Perfetto before labeling emulator stream FPS as engine/display source truth.

**Device controls:** GO. Required input/navigation/VM APIs are present in EmulatorController and proven ADB fallbacks already exist. Every visible control gets an explicit release test.

**League Voice:** CONDITIONAL GO. There is a legitimate candidate route through the official League Client's local premade-voice service. Direct standalone Riot/Vivox joining is not a public supported API. The decisive test is same-account concurrency between the official League Client voice session and Android TFT. Do not bypass Riot auth if it fails.
