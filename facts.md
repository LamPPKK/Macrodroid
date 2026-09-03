# TFTMAC Facts

**Authority date:** 2026-08-31 America/Chicago
**Observed runtime evidence through:** 2026-08-31T23:13:30Z
**Purpose:** preserve facts and hard boundaries that future TFTMAC work must not casually reinterpret.

This file separates durable product facts from mutable observations and historical
results. A statement becomes a project fact only when it has direct machine,
runtime, source, SQL, or user-acceptance evidence. Requested settings are not
effective settings; presentation cadence is not Unreal FPS; a hypothesis is not a
result.

Exact benchmark formulas, automatic full-run analysis, AI-readable output
shape, and current findings live in `benchmark.md`.

## Evidence vocabulary

| Label | Meaning |
| --- | --- |
| **LOCKED** | Product or safety contract. Change only through an explicit, evidence-backed project decision. |
| **VERIFIED CURRENT** | Directly observed on the current Mac, installed app, source tree, or live runtime. Mutable software/version facts must retain an observation date. |
| **VERIFIED HISTORICAL** | Direct result from an earlier capture or campaign. Useful evidence, but not automatically transferable to the current M4/native runtime. |
| **USER ACCEPTED/REJECTED** | Direct usability evidence supplied by the person playing TFT. It is decisive for playability but does not by itself identify a software boundary. |
| **INFERRED** | Evidence-supported explanation that has not been observed at the claimed internal boundary. |
| **UNKNOWN** | Not measured or not validly attributable. Never silently promote this to fact. |

## 1. Host machine

| Fact | State | Evidence |
| --- | --- | --- |
| Computer | **VERIFIED CURRENT:** Mac mini, model identifier `Mac16,10`, model number `MU9D3LL/A` | `system_profiler SPHardwareDataType`, 2026-08-30 |
| SoC | **VERIFIED CURRENT:** Apple M4 | `system_profiler` |
| CPU topology | **VERIFIED CURRENT:** 10 physical/logical cores: 4 performance and 6 efficiency | `system_profiler`; `sysctl hw.physicalcpu`, `hw.perflevel*` |
| GPU | **VERIFIED CURRENT:** integrated Apple M4 GPU, 10 cores, Metal supported | `system_profiler SPDisplaysDataType` |
| Unified memory | **VERIFIED CURRENT:** 16 GB; exact `hw.memsize` is 17,179,869,184 bytes | `system_profiler`; `sysctl hw.memsize` |
| CPU/GPU clock | **VERIFIED CURRENT BOUNDARY:** this Mac does not expose a fixed project-controlled CPU or GPU MHz value through the audited `system_profiler`/`sysctl` fields. Frequency is not a TFTMAC emulator knob. Do not invent an 800 MHz or 1600 MHz virtual-GPU fact. | Live host audit |
| Power | **VERIFIED CURRENT at audit:** AC power | `pmset -g batt` |
| Thermal/power warnings | **VERIFIED CURRENT at audit:** no thermal, performance, or CPU-power warning had been recorded | `pmset -g therm` |
| macOS | **VERIFIED CURRENT:** macOS 26.6.2, build 25G83; Darwin 25.6.0 | `sw_vers`; `system_profiler` |
| Architecture | **VERIFIED CURRENT:** arm64 | Xcode/Swift target and stack lock |
| Xcode | **VERIFIED CURRENT:** Xcode 26.6, build 17F113, authoritative path `/Applications/Xcode-26.6.0.app/Contents/Developer` | `xcodebuild -version`; `ssot/STACK.lock.yaml` |
| Swift | **VERIFIED CURRENT:** Apple Swift 6.3.3, arm64 macOS target | `swift --version` |

The current Mac is not the same host as the older M1 Max performance campaign.
Historical M1 Max results remain valid for their recorded environment, but they
must never be presented as measurements of this M4 Mac mini.

## 2. Product identity and user experience

- **LOCKED:** TFTMAC is its own native macOS application. It is not a Clara app,
  does not ship through Node, and does not depend on a Clara service to play.
- **LOCKED:** the application uses AppKit window behavior, a native Metal-backed
  display, normal macOS menus and window controls, and native macOS fullscreen.
- **LOCKED:** the Android Emulator's Qt window stays hidden in normal operation.
- **LOCKED:** the complete Android display is shown aspect-correctly. The normal
  guest/output target is 1920×1080; a 16:9 fullscreen content region is filled.
- **LOCKED:** no scrcpy or encoded-video path is the production display path.
- **VERIFIED CURRENT:** bundle identifier `com.flashls1.tftmac`.
- **VERIFIED CURRENT:** installed release `/Applications/TFTMAC.app`, version
  2.3.0, build 8, arm64. Capture
  `2026-08-31T21-39-18.396Z-fe34e3a1-fb91-44eb-804f-4ca8519dfc31`
  directly proves authorized ADB, official TFT PID observation, exact
  `GameActivity` SurfaceView selection, automatic graphics-run admission,
  `COMPLETE` stack receipts, and frame-to-run/hash/window/receipt linkage.
- **VERIFIED CURRENT:** `/Users/flash/Desktop/TFTMAC.app` is a symlink to the
  installed `/Applications/TFTMAC.app`, so the Desktop launcher opens the same
  release rather than a second copy.
- **VERIFIED CURRENT:** `LSSupportsGameMode=true` is present in the installed
  bundle. This establishes Game Mode eligibility, not proof that macOS activated
  it during a particular match.
- **VERIFIED CURRENT:** the official full-bleed penguin-samurai icon is embedded.
  The source, 1024-pixel output, and ICNS hashes are frozen in
  `ssot/runtime-authority.json`.
- **VERIFIED HISTORICAL RELEASE ACCEPTANCE:** Build 8 was signed with the local
  `TFTMAC Local Code Signing` identity and passed deep/strict verification when
  the release receipt was created. It is not notarized for public distribution.
- **VERIFIED CURRENT HOST AUDIT (2026-08-31T23:13:30Z):** the installed TFTMAC
  executable and emulator-host hashes still match that Build 8 receipt, but the
  login keychain now exposes zero valid code-signing identities and
  `codesign --verify --deep --strict` fails with `CSSMERR_TP_NOT_TRUSTED`.
  Current-host installed-runtime verification is therefore blocked until the
  local identity is repaired in a separate operational task. This does not
  rewrite the historical acceptance result.

## 3. Launch and ADB architecture

- **LOCKED:** launch the emulator through the packaged `TFTMAC Emulator Host.app`
  in the logged-in user's macOS session:

  ```text
  /usr/bin/open -n -W --env ... --args ...
  ```

- **LOCKED:** do not replace that host chain with direct Node/Clara `spawn()`.
  The discarded direct-service path changed the ADB execution/session identity
  and produced an unauthorized guest.
- **LOCKED:** ADB server port `5038`; emulator console port `5582`; serial
  `emulator-5582`.
- **LOCKED:** do not inject `ADB_VENDOR_KEYS`. The launcher uses the logged-in
  user's established ADB identity and clears inherited `ADB_SERVER_SOCKET` and
  `ANDROID_ADB_SERVER_ADDRESS` values.
- **VERIFIED HISTORICAL ROOT CAUSE:** the incorrect direct path used `5040`,
  `5592`, and `emulator-5592`, leading to `unauthorized` and eventually
  `Timed out waiting for emulator ADB device.` The Android runtime, AVD, GPU,
  RAM, CPU, and proven host launcher were not the cause of that failure.
- **LOCKED:** authenticated EmulatorController is loopback-only, discovered from
  the launched emulator's PID-bound registration, and authenticated with a token
  held only in memory.
- **VERIFIED CURRENT:** controller port request `8554`; emulator option
  `-grpc-use-token`; raw controller frame limit raised to 16 MiB because a
  1920×1080 RGBA frame is 8,294,400 bytes and exceeds gRPC's former 4 MiB
  default.

## 4. Android runtime and official package

| Item | Current authority |
| --- | --- |
| Runtime root | `/Volumes/MAC MINI M4/TFTMAC/Runtime` |
| SDK root | `/Volumes/MAC MINI M4/TFTMAC/Runtime/SDK` |
| Emulator | Android Emulator 37.1.11.0, build 15917651 |
| AVD | `TFT_Ultra_Tablet` |
| Guest | Official Google Play ARM64 system image, API 36, image revision 7 |
| Platform tools | 37.0.1 |
| WebView provider | `com.google.android.webview` |
| WebView version observed | 151.0.7922.199 |
| TFT package | `com.riotgames.league.teamfighttactics` |
| TFT version observed | `18.1-5402721`, version code `8402721` |
| Installer authority | `com.android.vending` / Google Play |
| Unreal activity | `com.epicgames.unreal.GameActivity` |
| Riot login activity | `com.riotgames.platformui.mobilefre.MobileFREWebViewActivity` |

- **LOCKED USER FACT:** current TFT uses Unreal Engine. Engineering work must
  reason about the current Unreal-based client, not the retired legacy engine.
- **LOCKED USER PREMISE:** the former native Mac path no longer supplies the
  current playable client after the engine transition; TFTMAC exists to present
  the official Android Unreal client as a native Mac experience.
- **LOCKED:** Google Play owns install/update delivery; Riot owns authentication,
  game content, and the signed TFT package.
- **LOCKED:** do not mirror, modify, patch, inject into, re-sign, or privately
  distribute Riot's APK or signed assets.
- **LOCKED:** Riot credentials, Google credentials, CAPTCHA, MFA, and consent are
  entered manually in the official UI. Do not log or automate them.
- **MUTABLE:** package and WebView versions can change through their official
  stores. Every session must record what was actually installed.
- **UNKNOWN:** the TFT signer digest has been observed in Android package output,
  but has not yet been promoted as a durable project-authority digest.

## 5. Current graphics and audio pipeline

```text
TFT Unreal direct-Vulkan workload
  -> guest Vulkan command stream
  -> gfxstream over virtio-gpu ASG
  -> MoltenVK Vulkan-to-Metal translation
  -> Apple Metal / M4 GPU
  -> Android SurfaceFlinger actual presentation
  -> authenticated raw RGBA frame stream
  -> TFTMAC Metal presenter
  -> native macOS fullscreen window
```

Boundary rules:

- Unreal owns game simulation, effects, render-thread/RHI workload, and the
  game's actual frame production.
- **VERIFIED CURRENT PATH:** the latest stack receipt identifies
  `UNREAL_ENGINE_VULKAN`. ANGLE may be present for another guest/package path,
  but is not assumed to render TFT unless a per-run receipt proves it.
- ANGLE owns GLES-to-Vulkan translation only when a game selects GLES/EGL and
  Android selects ANGLE for that package. Its ES 3.2 exposure is a compatibility
  route, not general conformance proof.
- gfxstream/ASG owns guest-to-host graphics command transport. Configured ring,
  buffer, and flush values do not prove per-frame transport latency.
- MoltenVK owns host Vulkan-to-Metal translation. Environment values are
  requested values unless effective behavior is directly measured.
- TFTMAC owns host launch/session control, the final completed-frame copy,
  orientation/scaling, native input mapping, output cadence, and local evidence.
- Two different components use Metal: MoltenVK for emulated Vulkan work and
  TFTMAC for final image presentation. A fast final presenter does not prove the
  upstream game/transport pipeline is fast.

## 6. Proven Control profile

The current control is the following complete configuration. Change one
declared test factor at a time; do not silently mix profiles.

| Variable | Control |
| --- | --- |
| Profile | `tftmac_5gb_native_v1` |
| Guest display | 1920×1080 |
| Density | 320 dpi |
| Refresh target | 60 Hz |
| vCPU | 6 |
| Guest RAM | 5120 MiB |
| GPU | host |
| Audio | CoreAudio |
| Transport | `virtio-gpu-asg` |
| ASG write buffer | 1,048,576 bytes / 1 MiB |
| ASG write step | 16,384 bytes / 16 KiB |
| ASG data ring | 32,768 bytes / 32 KiB |
| ASG draw flush | 800 microseconds |
| Emulator features | `GLESDynamicVersion,Vulkan,GuestAngle,-GLPipeChecksum,VulkanBatchedDescriptorSetUpdate,AsyncComposeSupport,VirtioGpuFenceContexts` |
| ANGLE enabled | `exposeNonConformantExtensionsAndVersions:exposeES32ForTesting` |
| ANGLE disabled | `preferSubmitAtFBOBoundary` |
| MoltenVK synchronous submits | 0 / disabled |
| MoltenVK max active command buffers | 64 |
| MoltenVK fast math | 1 / enabled |
| TFT graphics | High |
| TFT FPS cap | 60 |
| Riot Performance Mode Beta | OFF |

The current settings UI safely exposes only:

- vCPU: 4, 6, 8;
- guest RAM: 4096, 5120, 6144 MiB;
- refresh target: 30 or 60 Hz;
- ASG draw flush: 400 or 800 microseconds;
- named experiment: Control or Combat Latency A.

The existence of a UI choice does not mean it is faster. All restart-bound
values require a clean, logged relaunch.

## 7. Native input, login, power, and audio

- **VERIFIED CURRENT:** Mac primary-button down/drag/up maps to Android
  EmulatorController `TouchEvent`, identifier `0`, non-zero contact pressure,
  and explicit zero-pressure release. Desktop mouse events are not the primary
  touch path.
- **VERIFIED CURRENT:** keyboard input uses EmulatorController `sendKey`.
  SQLite stores character count and special-key name only, never typed text.
- **VERIFIED HISTORICAL:** the Riot login form expects the private Riot account
  username, not an email address and not the public `Name#Tag` Riot ID.
- **VERIFIED CURRENT RISK:** Riot's WebView can ANR on input dispatch. The narrow
  proven recovery keeps TFTMAC and the emulator alive, restores
  `show_ime_with_hard_keyboard=0`, restarts only Riot's failed process, and
  reopens the official activity. This is recovery evidence, not proof that the
  mutable WebView/IME defect can never recur.
- **LOCKED:** secure Android PIN unlock stays manual. TFTMAC may record that
  unlock is required, but never the PIN or typed content.
- **VERIFIED CURRENT:** Build 7 establishes virtual AC power, Android stay-awake
  state, and `mWakefulness=Awake` before unlock/gameplay. It logs
  `GUEST_GAMEPLAY_POWER_READY` or fails clearly.
- **VERIFIED CURRENT:** emulator requests `-audio coreaudio`; prior live evidence
  observed active 48 kHz stereo output and no partial/empty underruns.
- **UNKNOWN/USER ACCEPTANCE:** software audio health does not prove the user can
  hear sound at their selected speakers/headphones.

## 8. Frame-rate truth

The on-screen overlay labels two host-facing rates:

```text
SRC <distinct source-image rate> · OUT <native Metal presentation rate>
```

- `SRC` is distinct authenticated gRPC images received per second.
- `OUT` is TFTMAC Metal presentation cadence.
- Neither is automatically Unreal gameplay FPS.
- A repeated/static image can be presented at 60 OUT while TFT produces fewer
  useful frames.
- `dumpsys gfxinfo` is not authoritative for TFT's native Unreal/Vulkan
  SurfaceView.
- Player-visible game-frame authority is the exact TFT SurfaceFlinger layer's
  actual-present timestamps, summarized into one-second windows.
- p95, p99, maximum interval, 1% low, jank, severe stalls, repeated images, and
  visible-stutter markers matter more than a flattering average.

## 9. Logging and SQL authority

Every app launch creates a private mode-0700 capture directory:

```text
~/Library/Application Support/TFTMAC/Captures/<session-id>/
  TFTMAC_NATIVE_RUNTIME.sqlite
  native-events.jsonl
  emulator.stdout.log
  emulator.stderr.log
  logcat.raw.txt
  bounded diagnostic artifacts
```

Persistent normalized comparison authority:

```text
~/Library/Application Support/TFTMAC/TFTMAC_LAB.sqlite
```

The implemented “SQL logging system” is local SQLite. It is not a MySQL server
and does not require a network database service.

The session database is raw query authority. The persistent lab links raw
captures by session/configuration/artifact identity rather than duplicating
credential-bearing or full raw data.

| SQL table | Fact represented | Normal cadence |
| --- | --- | --- |
| `sessions` | session start/end/status/profile | boundary |
| `runtime_receipts` | requested/effective launch, package, ports, renderer, profile | startup and receipts |
| `events` | lifecycle, ADB, package, markers, failures, process/layer changes | event-driven |
| `frame_samples` | bounded image/hash/dimension/sequence checkpoints | boundary/checkpoint |
| `frame_interval_windows` | source ingress intervals/drops | 1 second |
| `presentation_samples` | labeled SRC/OUT/mailbox behavior | about 1 second |
| `game_frame_intervals` | exact TFT actual-present intervals and flags | each observed guest frame |
| `game_frame_windows` | FPS, 1% low, p50/p95/p99/max, jank/severe/misses | 1 second |
| `stream_freshness_windows` | changed/repeated frames and transport loss | 1 second |
| `host_presentation_windows` | final Metal submissions/completions/GPU time/errors | 1 second |
| `resource_samples` | QEMU CPU/RSS, TFT PID/activity | 5 seconds |
| `guest_memory_samples` | guest memory and swap | 5 seconds |
| `host_resource_samples` | host memory pressure, thermal, power source | 5 seconds |
| `clock_sync_samples` | host/guest midpoint and round-trip error | 30 seconds |
| `surfaceflinger_samples` | render rate and cumulative miss counters | boundaries and 30 seconds |
| `audio_samples` | audio output/rate/stereo/tracks/underruns | boundaries and 30 seconds |
| `logcat_aggregates` | ANR/fatal/LMK/renderer/audio counts | 5 seconds |
| `pipeline_log_aggregates` | gfxstream/ASG/Vulkan/MoltenVK/shader/fence counts | 5 seconds |
| `graphics_pipeline_snapshots` | effective layer and graphics identities | 30 seconds |
| `graphics_runs` | automatic TFT process/layer lifetime, configuration SHA, target FPS, start/end reason | process/layer lifecycle |
| `graphics_pipeline_incidents` | automatic exact-layer degradation and conservative causal unknowns | bounded incident |
| `diagnostic_artifacts` | trace path/hash/processor/normalization status | event-driven |
| `combat_benchmarks` | complete benchmark configuration, coverage, validity, metrics | benchmark end |
| `combat_incidents` | trigger metrics, trace link, first divergent boundary/unknowns | incident |
| `combat_comparisons` | control/candidate deltas and decision | comparison |
| `game_process_sessions` | TFT PID lifetime | process transition |
| `input_samples` | touch metadata and keyboard counts only | each input event |

- **VERIFIED CURRENT:** base graphics logging opens automatically from the
  observed TFT process/layer and seals only at process/app close. It is
  independent of match markers, Combat Benchmark controls, and battle
  classification.
- **VERIFIED CURRENT:** stack receipts, SHA-256, `graphics_run_id`, and exact
  interval/window joins are written continuously. They prove scope and receipt
  integrity, not internal causal ownership.
- **LOCKED:** the final native Mac presenter remains a hidden correctness
  receipt. It is not displayed, ranked, or selected as a graphics root cause.
- **UNKNOWN / PLANNED:** no shared work ID or source-site span currently crosses
  guest submit, ASG/gfxstream, host Vulkan, MoltenVK, and Metal. The current
  logger cannot identify an internal root; advanced causal instrumentation is
  planned in an isolated diagnostic runtime.

Privacy facts:

- Raw logcat and raw traces are sensitive local sidecars and are not pasted or
  published without deliberate sanitization.
- No screenshot, raw frame payload, username, password, email, token, cookie,
  PIN, CAPTCHA, MFA value, or typed content belongs in SQL or project history.
- No remote telemetry service is required.

## 10. Benchmark contract

- **LOCKED:** complete automatic TFT process/layer runs are preferred
  product-performance evidence. Every logged frame and resource/pipeline sample
  inside the lifecycle participates; match/combat markers and classifiers are
  optional annotations only.
- **LOCKED:** the current UI/source-named Combat Benchmark remains a faster
  5–8 minute bounded A/B screen; it does not gate base graphics logging or
  replace a full-run promotion check.
- **LOCKED:** graphics optimization decisions use graphics cadence and boundary
  evidence. CPU/RAM/audio observations remain health/correctness context only;
  this effort does not optimize them.
- **LOCKED:** the product target is useful-frame cadence of at least 60 FPS
  throughout the complete run, not a flattering average or selected scene.
- **LOCKED:** `benchmark.md` is the formula and reporting authority. Historical
  `docs/benchmarks.md` results retain their original M1 Max/userdebug scope.

- Start the bounded A/B during representative continuous gameplay; no semantic
  phase marker is required.
- Minimum valid combat duration: 300 seconds.
- Automatic close: 480 seconds.
- Exact TFT layer/timestamp availability: at least 95%.
- Clock coverage: at least 95%.
- p95 clock RTT at or below 2 ms permits precise cross-boundary attribution;
  2–10 ms permits coarse ordering; above 10 ms means cross-host cause UNKNOWN.
- Start trace: one bounded 20-second, 32-MiB Perfetto trace.
- Incident traces: at most two 15-second, 32-MiB traces.
- Automatic incident trigger: two adjacent one-second windows with 1% low below
  30 FPS, p99 at least 50 ms, or severe stalls.
- Trace cooldown: 120 seconds; no concurrent traces.
- If trace-active versus trace-inactive windows differ by more than 5%, retain
  performance data but mark trace causality `OBSERVER_OVERHEAD_INVALID`.
- Valid traces are SHA-256 sealed and normalized by pinned
  `trace_processor_shell` v58.2. Pinned SHA-256:
  `d29864d1ba3b36855527bb1b0ca3aa7f703cdce338b9680bb922c5c151b358fa`.

Decision rules:

- **HOME_RUN:** after the weighted-FPS +5% guard, 1% low +20% or more, jank and
  severe rates each -30% or more relative, and either weighted FPS +10% or p95
  interval -15%.
- **PROMISING:** weighted FPS +5% or more and 1% low +10% or more, with no
  correctness or tail regression.
- **REJECT:** gain below 5%, p95/p99 worsens at least 10%, or any boot, render,
  input, audio, login, memory, cleanup, or usability regression.
- **INCONCLUSIVE:** invalid workload/coverage/synchronization, incompatible
  configuration identity, or result between thresholds.
- A winning candidate still requires a five-minute cold confirmation before
  normal-use promotion.
- **LOCKED:** `HOME_RUN`/`PROMISING` are relative candidate decisions, not proof
  that the product target is met. The separate full-run status remains
  `TARGET_NOT_MET` until useful-frame cadence holds at least 60 FPS throughout.

## 11. Verified results and decisions

### Current native/runtime evidence

- **VERIFIED CURRENT:** automatic capture
  `2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200` recorded an
  uninterrupted 42m27s TFT graphics run (PID 2774) with 144,364 exact
  SurfaceFlinger intervals, 99.629% exact-layer coverage, and 189 degradation
  incidents. Weighted FPS was 56.98, 1% low 21.49 FPS, p95 21.510 ms, p99
  33.434 ms, and 53.72% of intervals missed the 60-FPS budget.
- **VERIFIED CURRENT BOUNDARY:** final native presentation remained near 60 Hz
  during this run, so it is retained only as hidden correctness context. The
  first internal graphics boundary remains `UNKNOWN`; present evidence localizes
  lateness upstream of or at the exact TFT SurfaceFlinger layer.

- **VERIFIED CURRENT:** Build 7 live capture
  `2026-08-31T02-54-28.329Z-14000b50-bf29-44c6-a963-9203d5313494`
  reached authenticated ADB, a 1920×1080 RGBA first frame, awake/stay-on guest
  power, logger health, official TFT package receipt, and
  `TFT_READY_FOR_USER` under `combat_latency_a`.
- **VERIFIED CURRENT:** configuration SHA-256
  `05039d1fd0987f46fc7da8de5f483d8c7ffaf8f39bd1eaecdd1aee11603bbb07`.
- **VERIFIED CURRENT:** host pre-exec QoS request returned 0 and read back
  `user_interactive`, relative priority 0.
- **UNKNOWN:** this does not prove every QEMU worker inherited that scheduling
  class or that combat performance improved.
- **VERIFIED CURRENT:** the same live session recorded Riot WebView/input ANR
  aggregates and a narrow Riot-only recovery. Do not misclassify that as a
  graphics improvement or as a whole-emulator crash.
- **VERIFIED CURRENT:** the user marked one complete Build 7 match in that same
  session from event 1442 at `2026-08-31T03:19:25Z` through event 3065 at
  `2026-08-31T03:51:00Z`, a 1,895.054-second / 31m35.054s range.
- **VERIFIED CURRENT:** the marked run contains 93,724 exact TFT
  actual-present intervals: weighted FPS 49.449, 1% low 16.300 FPS, p95
  33.822 ms, p99 48.746 ms, maximum 1,254.162 ms, 19.110% jank, and 0.610%
  severe intervals. Exact-layer measured coverage was 100%, with one stable
  layer and no history truncation.
- **VERIFIED CURRENT:** 58,925 intervals (62.871%) exceeded the 60 FPS frame
  budget; total budget overrun was 357,921.976 ms; the longest consecutive
  budget-miss run was 325 intervals; and 1,599 of 1,693 complete one-second
  windows (94.448%) were below 60 FPS.
- **VERIFIED CURRENT:** final TFTMAC Metal output averaged 59.968 FPS with zero
  drawable/command errors and maximum recorded final-presenter GPU time
  3.267 ms, while 23,231 presentations reused a source frame. This makes the
  final pass a poor explanation for the missing useful frames in this match; it
  does not identify which upstream component was first late.
- **UNKNOWN:** this full run is not a candidate-vs-Control decision. It has no
  matched Control/formal benchmark row, and p95 clock RTT was 86.757 ms, so
  cross-host ownership is invalid. `benchmark.md` preserves the complete result.

### Rejected Home Run A / Riot Performance Mode Beta

- **USER REJECTED:** worst gameplay/graphics experience; do not select again.
- **VERIFIED HISTORICAL:** 480.646 seconds; weighted FPS 56.665; 1% low 17.698;
  p95 21.760 ms; p99 34.335 ms; maximum frame 517.488 ms; jank rate 4.554%;
  severe rate 0.290%.
- **VERIFIED HISTORICAL:** incident 1% lows 1.932 and 4.629 FPS; one incident
  included a 517.488 ms p99/max interval.
- **INVALID FOR CAUSAL ATTRIBUTION:** p95 clock RTT 87.318 ms and observer
  overhead invalidated cross-boundary ownership claims.
- **LOCKED DECISION:** `home_run_a` remains only as a historical migration/raw
  receipt enum. It is not selectable. Riot Performance Mode Beta stays OFF.

### Earlier fixed-stage graphics campaign

These are **VERIFIED HISTORICAL** results from a different M1 Max/userdebug
campaign, useful for candidate selection but not current M4 runtime performance:

- ASG versus pipe at exact stage 1-1: 40.1 FPS / 34.85 ms p95 versus
  29.6 FPS / 49.75 ms p95. ASG selected.
- Three controls at Trial 1-2/1-5/1-8: 40.60 / 36.03 / 27.83 FPS.
- Confirmed 67% effects/LOD profile: 45.20 / 38.50 / 33.80 FPS; stage-1-8
  p95 35.07–35.95 ms.
- 16 KiB ASG write step beat paired 4 KiB control and was retained.
- 2560×1440 versus 1600×900 changed a controlled stage-1-5 result only from
  30.5 to 31.3 FPS despite 2.56× source pixels, indicating that scene was not
  primarily pixel-fill bound.
- The historical selected stack did not achieve the 57 FPS heavy-scene goal and
  did not reproduce the user's worst approximately 15 FPS gameplay period.

### Graphics council and ZoeMC simulation

- **VERIFIED HISTORICAL:** specialist research covered Unreal, ANGLE, gfxstream/
  ASG, MoltenVK, Metal, and transferable Fortnite/Unreal measurement categories.
- **VERIFIED HISTORICAL:** the 10,000-world ZoeMC v0.2 run used declared
  subjective priors. It is hypothesis-ordering evidence, not empirical proof.
- **RESOLVED BRANCH:** the simulation's decisive next test—authenticated native
  frame delivery—was completed. Raw authenticated gRPC is viable for correct
  1920×1080 native presentation and input.
- **NOT PROMOTED:** direct MMAP zero-copy without producer fencing, direct
  MoltenVK texture sharing without a supported contract, encoded video/scrcpy,
  and external emulator-window presentation.
- Fortnite/Unreal research can suggest counters, trace categories, pipeline-cache
  ideas, and workload hypotheses. It does not prove TFT-specific capabilities or
  justify altering Riot's signed shaders.

### Settings that must not be recycled without new causal evidence

- Pipe transport.
- MoltenVK 128/256 command buffers.
- Synchronous MoltenVK queue submission.
- Guest submit thread and broad shader prewarm.
- Native GLES and direct Vulkan routes.
- `VirtioGpuNativeSync`, `VirtioGpuNext`, disabled Vulkan descriptor batching.
- ASG 8/32 KiB write steps, 64/128 KiB rings, 512 KiB write buffer, and 2/4 ms
  flush screens.
- Active-consumer host patch.
- More guest RAM or an eighth vCPU as an assumed optimization.
- Audio disabled.
- MSAA2, material quality 1, `r.OneFrameThreadLag=0`, forced half-rate skeletal
  animation, extreme effects/LOD, blind 50% scale, and blind PSO prewarm.
- Riot Performance Mode Beta and the combined Home Run A host flags.

## 12. Current experiment: Combat Latency A

- **LOCKED TEST SHAPE:** Control remains High/60/OFF and the complete proven
  emulator stack.
- **CANDIDATE:** changes only the packaged emulator host's requested pre-exec
  QoS to `user_interactive`; declares Game Mode eligibility.
- **VERIFIED IMPLEMENTATION:** candidate/configuration hashing, stale-preset
  migration, host QoS receipt parsing, guest power gate, correctness rollback,
  and stable semantic TFT-layer comparison have native tests.
- **VERIFIED LAUNCH:** Build 7 established the requested QoS at the host
  pre-exec boundary and reached TFT ready with logging active.
- **UNKNOWN:** comparative combat benefit. One full candidate match is now
  measured, but no matched valid Control/Combat Latency A pair exists. Never
  call it faster until a compatible comparison exists.

## 13. Explicit unknowns and open acceptance

1. Combat Latency A's effect on continuous whole-run FPS, 1% low, p95/p99,
   frame-budget misses, and visible stutter versus Control.
2. Whether QEMU decoder/render/submission workers actually receive beneficial
   scheduling after exec.
3. The first divergent boundary in the run's worst sustained under-60 periods.
4. Exact ASG-versus-gfxstream-versus-MoltenVK ownership without a frame-ID
   correlation ring and valid synchronized trace. Direct per-frame stack SHA
   and per-window joins improve scope integrity but do not close this gap.
5. Whether persistent MoltenVK pipeline caching removes meaningful frame stalls
   in this exact shipping path.
6. Whether MMAP can reduce host copy/frame age without tearing or ownership
   corruption. Raw gRPC remains the working control.
7. Whether current sound is audibly correct at the user's output device.
8. Whether Riot WebView input ANR recurs after future TFT/WebView updates.
9. Public distribution acceptance: Build 8 has a historical local-signing
   receipt, current-host trust is blocked, and no notarization is claimed.
10. Whether any owned candidate can hold the complete automatic run at the 60 FPS
    target without correctness, audio, login, memory, or cleanup regression.

## 14. Authority and update rule

Use this precedence for current truth:

1. direct current machine/runtime/SQL evidence;
2. `ssot/runtime-authority.json` and `ssot/STACK.lock.yaml` after reconciliation;
3. current native source and tests;
4. `benchmark.md` for formulas, validity, analysis output, and current findings;
5. `docs/TFTMAC_NATIVE_RUNTIME_KNOWLEDGE_BASE.md` and `dev.md`;
6. historical campaign docs and SQL, explicitly labeled historical;
7. plans, simulations, and research as hypotheses only.

`TFTMAC.md`, old launchers, old Node helpers, old source-build plans, and old
Medium-profile records are not current runtime authority. When a mutable fact
changes, record the observation time and evidence; do not silently rewrite a
historical result to look current.
