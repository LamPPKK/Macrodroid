# TFTMAC Native Runtime Knowledge Base

**Authority date:** 2026-08-31

**Product target:** Native macOS TFT client experience backed by the official Android TFT package

**Current profile:** `tftmac_5gb_native_v1`

## 1. Current outcome ledger

| Claim | State | Decisive evidence |
| --- | --- | --- |
| TFTMAC is a real native Mac app | VERIFIED | AppKit `NSWindow`, native macOS full-screen space, Metal presenter, normal menus/window behavior |
| Full display is 1920x1080 | VERIFIED | AX window receipt was origin `0,0`, size `1920x1080`, `AXFullScreen=true`; gRPC frames are exactly 1920x1080 RGBA |
| Correctly oriented live Android video | VERIFIED | Live screenshot and input mapping on native Metal output |
| Donor-compatible launch architecture | VERIFIED | Packaged `TFTMAC Emulator Host.app` launched with `/usr/bin/open -n -W --env ... --args ...` in the logged-in Mac session |
| Correct ADB identity | VERIFIED | ADB server `5038`, console `5582`, serial `emulator-5582`; observed transition `offline -> unauthorized -> device` |
| No manual ADB key injection | VERIFIED | `ADB_VENDOR_KEYS` absent in launch receipt; inherited service socket/address variables cleared |
| Authenticated hidden-emulator control | VERIFIED | Exact PID-bound `pid_*.ini`, loopback gRPC `8554`, bearer token used in memory only, Emulator `37.1.11.0` authenticated |
| Native frame transport | VERIFIED | Raw gRPC `RGBA8888`, 8,294,400 bytes per 1920x1080 frame; 16-MiB request/response limits on pinned gRPC transport |
| Native presentation near 60 Hz in lobby | VERIFIED | Live session observed source-window max `61.1` and Metal-output max `60.5`; these are transport/output metrics, not Unreal FPS |
| Official current TFT launches | VERIFIED | Package `com.riotgames.league.teamfighttactics`, version `18.1-5402721`, SplashActivity then `com.epicgames.unreal.GameActivity`, PID observed |
| Riot account can reach the TFT lobby | VERIFIED | Live rendered lobby on the existing signed-in official app state |
| Primary touch and keyboard transport | VERIFIED | Mac primary-pointer down/drag/up uses EmulatorController `TouchEvent` with stable identifier `0` and pressure `1 -> 0`; keyboard remains gRPC evdev input; SQL records coordinates, pressure, counts and special keys, never typed content |
| CoreAudio software path | VERIFIED | Emulator launched `-audio coreaudio`; active AudioFlinger output, stereo, 48 kHz on the live check, one active track, zero partial/empty underruns |
| User can hear sound | USER ACCEPTANCE REQUIRED | The software path is healthy; only the person at the Mac can confirm audible output |
| Automatic full-session graphics evidence | LIVE VERIFIED | Latest Build 8 automatic process/layer run lasted 42m27s with 144,364 exact intervals and 99.629% coverage; markers were not required |
| Historical Build 8 release acceptance | VERIFIED HISTORICAL | All 43 native tests passed and `/Applications/TFTMAC.app` was deep-code-sign-valid when the signed 2.3.0 build 8 release receipt was created. |
| Current-host installed-runtime audit | BLOCKED | Main and emulator-host hashes still match Build 8, but the login keychain exposes zero valid signing identities and current deep/strict verification reports `CSSMERR_TP_NOT_TRUSTED`. Repair is a separate operational task. |
| Build 7 live launch | VERIFIED | Capture `2026-08-31T02-54-28.329Z-14000b50-bf29-44c6-a963-9203d5313494` reached authorized ADB, 1920x1080 first frame, powered/stay-awake guest, healthy SQL logger, official TFT and `TFT_READY_FOR_USER` under Combat Latency A |
| Build 8 automatic graphics logger | LIVE VERIFIED | Capture `2026-08-31T21-39-18.396Z-fe34e3a1-fb91-44eb-804f-4ca8519dfc31` proves automatic PID/layer admission, `COMPLETE` stack receipts, and direct run/hash/window/receipt linkage for every observed frame fact. |
| Internal graphics root cause | UNKNOWN / PLANNED | Build 8 has no shared work ID across guest Vulkan, gfxstream, host Vulkan, MoltenVK and Metal. It cannot name an internal owner; isolated diagnostic instrumentation is planned. |
| Combat Latency A performance | OBSERVED / NOT PROMOTED | Latest Build 8 run captured the preset at High/60/Performance OFF, but no controlled gain is established; scheduling testing is deferred behind causal instrumentation |
| External-runtime permission retention | VERIFIED | Stable designated requirement installed; a clean second launch immediately reopened `/Volumes/MAC MINI M4/TFTMAC/Runtime` and started QEMU without another drive-access dialog |
| Secure-unlock display | VERIFIED | Secure unlock stays manual and logged, while non-error runtime instructions are suppressed from the Android display; live signed launch showed no TFTMAC center overlay |

Primary live acceptance capture:

```text
~/Library/Application Support/TFTMAC/Captures/
  2026-08-30T08-40-36.792Z-5637b7cf-0c8b-435e-adbb-8f4c0e18de94/
```

Final release receipts:

```text
Verified Build 8 executable SHA-256:
  d3bf7c249a3e5f11b81f778b063e1a8cfe2e7fdeec0537ee6bd8447b1c2268d2

Build 8 automatic-logger live acceptance:
  2026-08-31T21-39-18.396Z-fe34e3a1-fb91-44eb-804f-4ca8519dfc31

Build 7 live-ready launch:
  2026-08-31T02-54-28.329Z-14000b50-bf29-44c6-a963-9203d5313494

Live match/lobby plus clean shutdown:
  2026-08-30T09-25-17.519Z-1a9d0227-3cf8-4a19-b353-c0f135ccf31c

Stable-signed release launch plus clean shutdown:
  2026-08-30T20-24-24.969Z-998c4e53-ff91-4cf3-8002-21543dc5d46f

Second launch proving retained drive consent:
  2026-08-30T20-25-43.388Z-8373817a-5c4c-4b47-9459-8c2a8751b096

Build 4 primary-touch/login investigation:
  2026-08-30T20-41-22.662Z-4bdb8a3f-813d-4e70-b8bd-67c0b6b5766f
```

Official launcher artwork is the full-bleed 1254×1254 PNG at
`tftmac/Assets/TFTMAC-Official-Icon.png`, generated with the built-in ImageGen
tool from the requested penguin-samurai, single-sword and exact stacked
`TFT`/`MAC` brief. The master has no baked-in rounded rectangle or outer gutter;
macOS owns the final corner mask. Build 7 derives and signs every `.icns`
representation from this hash-sealed source.

The first receipt reached Unreal `GameActivity`, rendered a live match and the
fully colored post-match lobby, recorded source/output maxima of 60.95/60.53,
zero sequence drops, active 48-kHz stereo output with zero underruns, and zero
confirmed memory kills. Its normal Quit sealed SQL as `STOPPED`, confirmed the
owned emulator exit, restored the exact AVD hash, and removed both transaction
and lease markers. The second receipt covers the last runtime-identical signed
build. The subsequent icon release changed release metadata and signed launcher
artwork. Build 7 then added the Combat Latency A scheduling receipt, permanent
guest gameplay-power gate and cross-session combat-layer fix. Its live-ready
capture is recorded above; it is not yet a performance result. The earlier live
native window was re-verified at origin
`0,0`, size `1920x1080`,
`AXFullScreen=true`; SQL later observed source/output maxima of 60.99/60.33,
active 48-kHz stereo output with one active track and zero underruns, and zero
confirmed memory kills. Four cumulative sequence gaps appeared only after
repeatedly backgrounding the app and switching Spaces for release captures; the
separate uninterrupted match/lobby receipt retained zero sequence drops. The
installed-release session also captured one real
Riot `MobileFREWebViewActivity` input-dispatch ANR after a five-second
MotionEvent timeout. That process recovered automatically from PID 2348 to PID
4439; the session remained `RUNNING`, with no fatal, Vulkan, or audio-error
aggregate. Secure Android PIN entry remains deliberately manual.

## 2. Non-negotiable runtime invariants

These values are product authority, not suggestions:

```text
Engine fact: Unreal Engine
Runtime root: /Volumes/MAC MINI M4/TFTMAC/Runtime
Emulator: Google Android Emulator 37.1.11 / build 15917651
AVD: TFT_Ultra_Tablet / API36 Google Play ARM64
Package: com.riotgames.league.teamfighttactics
Launcher: /usr/bin/open -n -W -> packaged TFTMAC Emulator Host.app
ADB server: 5038
Console: 5582
Serial: emulator-5582
ADB_VENDOR_KEYS: absent
Controller: authenticated loopback gRPC, default port 8554
Display: 1920x1080 / 320 dpi / 60-Hz default
CPU/RAM default: 6 vCPU / 5120 MiB
GPU/audio: host / CoreAudio
Graphics transport: virtio-gpu-asg
ASG: 1 MiB write buffer / 16 KiB write step / 32 KiB ring / flush 800
ANGLE enabled: exposeNonConformantExtensionsAndVersions:exposeES32ForTesting
ANGLE disabled: preferSubmitAtFBOBoundary
MoltenVK requested: synchronous submits 0 / max active command buffers 64 / fast math 1
```

The previous `5040 / 5592 / emulator-5592` service-context route is a historical regression. It must remain only as failure evidence. It is not a fallback and must never overwrite current authority.

## 3. Architecture and ownership boundaries

```text
Official TFT Unreal GameActivity
  -> Android application graphics contract
  -> ANGLE GLES compatibility layer
  -> guest Vulkan/ranchu
  -> virtio-gpu-asg + gfxstream
  -> host Vulkan
  -> emulator-bundled MoltenVK
  -> Apple Metal executes emulator rendering
  -> authenticated EmulatorController raw RGBA stream
  -> latest-only TFTMAC mailbox
  -> persistent native Metal queue / triple texture storage
  -> AppKit full-screen Mac window
```

There are two Metal owners:

1. MoltenVK uses Metal internally for the emulator's host Vulkan work.
2. TFTMAC uses its own Metal presenter for the completed Android image.

Do not assign a stall to Unreal, ANGLE, gfxstream, MoltenVK, TFTMAC Metal, or macOS presentation from a metric owned by a different boundary.

## 4. What frame telemetry means

Player-facing causal reporting uses:

```text
TFT <exact actual-present rate/tails> · PIPE <source freshness>
```

- `TFT` is derived from exact SurfaceFlinger actual-present timestamps.
- `PIPE` reports completed-source freshness through authenticated gRPC.
- Raw native-presenter cadence/GPU data remains stored only as hidden
  correctness/regression context; it is not displayed or ranked as a root.
- Neither controller-source nor native-presenter cadence is Unreal engine FPS.
- Deep attribution requires the planned shared work-ID/source-site diagnostic
  logger; optional markers and aggregate Perfetto counts cannot supply it.
- `dumpsys gfxinfo` is blind to the native Unreal/Vulkan workload and must not be used as primary FPS authority.

## 5. Native logging system

Every app launch creates a private session directory:

```text
~/Library/Application Support/TFTMAC/Captures/<session-id>/
```

The directory is mode `0700`. Queryable authority is `TFTMAC_NATIVE_RUNTIME.sqlite`; local sidecars include `native-events.jsonl`, emulator stdout/stderr, a reversible AVD backup, and session-scoped `logcat.raw.txt`.

| SQL table | What it establishes | Normal cadence |
| --- | --- | --- |
| `sessions` | Start/end/status/profile | One row per app run |
| `runtime_receipts` | Ports, launcher, AVD, renderer requests, profile | At startup |
| `events` | Lifecycle, package, ADB transitions, markers, failures | Event-driven |
| `frame_samples` | Visual/hash checkpoints, dimensions, sequence | First frame and bounded checkpoints |
| `frame_interval_windows` | Source ingress count, drops, mean/p95/max interval | One-second windows |
| `presentation_samples` | SRC/OUT rate, mailbox replacement and drops | About once per second |
| `game_frame_intervals` | Exact TFT SurfaceView actual-present intervals, jank/severe flags and missed-vsync equivalents | Every newly observed guest frame |
| `game_frame_windows` | TFT FPS, 1% low, p50/p95/p99/max, jank/severe counts and explicit unavailable status | One-second windows |
| `stream_freshness_windows` | Sampled content changes, repeated images, longest static run and transport loss | One-second windows |
| `host_presentation_windows` | Final Metal completion/GPU timing, unique/repeated source use, drawable misses and command errors | One-second windows |
| `resource_samples` | QEMU CPU/RSS, TFT PID, resumed activity | Five seconds |
| `guest_memory_samples` | MemTotal/MemAvailable/swap | Five seconds |
| `host_resource_samples` | Host available/compressed/swap/pageouts, thermal state and AC/battery source | Five seconds |
| `clock_sync_samples` | Host/guest monotonic alignment and RTT | Thirty seconds |
| `surfaceflinger_samples` | Render rate and cumulative total/HWC/GPU misses | Start/end and 30 seconds during gameplay |
| `audio_samples` | CoreAudio receipt plus active output/rate/stereo/tracks/underruns | Start/end and 30 seconds during gameplay |
| `logcat_aggregates` | Counts only: ANR, input timeout, fatal, LMK/OOM, skipped frames, ANGLE/Vulkan warnings, PCM errors | Five seconds |
| `pipeline_log_aggregates` | Counts only real gfxstream/ASG/Vulkan/MoltenVK/shader/fence warnings, errors, stalls and timeouts | Five seconds |
| `graphics_runs` | Automatic TFT PID/layer lifecycle, configuration SHA, target FPS and close reason | Process/layer transition |
| `graphics_pipeline_snapshots` | Canonical stack receipt/SHA plus TFT SurfaceView, Unreal graphics API, ANGLE, gfxstream, MoltenVK, host Vulkan and Metal identity | Start/change/end and thirty seconds during gameplay |
| `graphics_pipeline_incidents` | Exact-layer degradation, admitted trace link, first observed boundary, conservative causal owner/confidence, and explicit unknowns | Automatic event |
| `diagnostic_artifacts` | Raw and normalized trace paths/hashes, pinned processor hash, normalized SQL summary and analysis state | Event-driven |
| `combat_benchmarks` | Named preset, complete configuration hash, coverage, validity, exact layer and combat metrics | Benchmark boundary |
| `combat_incidents` | Bad-window or visible-stutter trigger, frame state, trace sequence and explicit unknown boundary | Event-driven during benchmark |
| `combat_comparisons` | Control/candidate deltas, correctness, observer overhead and HOME_RUN/PROMISING/REJECT/INCONCLUSIVE decision | Candidate benchmark end |
| `game_process_sessions` | TFT PID start/end | PID transition |
| `input_samples` | Primary-touch coordinate/pressure, secondary-mouse button, and keyboard character count/special key | Input event; no typed content |

Raw logcat is local sensitive data. It is excluded from SQL and must never be uploaded or pasted without deliberate sanitization. It begins at a guest timestamp taken after ADB authorization so stale ring-buffer events do not contaminate the run.

### Automatic graphics logging and optional A/B (2.3.0 build 8 installed)

The base logger requires no menu action. It starts when the TFT process or exact
GameActivity layer is observed, records the complete graphics lifecycle, and
closes with the process/app. `Mark Visible Stutter` is optional context. The
renamed controlled A/B window remains valid after 300 seconds and closes at 480
seconds. Automatic incident traces require two adjacent bad one-second windows,
use a 120-second cooldown, and are capped at two per graphics run. During an
active A/B those incidents share the benchmark's two-incident budget in addition
to its one 20-second start trace.

`Control` is the exact 1920x1080/320-dpi/60-Hz, 6-vCPU, 5120-MiB proven
configuration with TFT High / 60 FPS / Performance Mode OFF. `Combat Latency A`
changes only the packaged emulator host's requested macOS QoS class to
`user_interactive`. The host records the requested value, return code and
pre-exec effective class before replacing itself with Android Emulator. It does
not claim that every QEMU worker inherited the class without combat evidence.
All graphics, ASG, MoltenVK, CPU, RAM, resolution and audio values remain locked.

`Home Run A` and Riot Performance Mode Beta are retired. The completed
480.65-second run recorded 56.665 weighted FPS but only 17.698 FPS 1% low,
517.488 ms maximum frame interval and two automatic degradation incidents. The
user rejected the experience as unacceptable. Cross-boundary causal attribution
remains unknown because clock RTT and trace observer-overhead gates failed; that
does not override the direct usability rejection.

Every valid Perfetto artifact is processed locally by the packaged
`trace_processor_shell` v58.2 ARM64 binary. Its pinned SHA-256 is
`d29864d1ba3b36855527bb1b0ca3aa7f703cdce338b9680bb922c5c151b358fa`.
If normalization fails or that receipt changes, TFTMAC removes the unprocessed
raw trace and records the failure; it does not retain a trace indefinitely in a
raw-only state. The persistent comparison authority is:

```text
~/Library/Application Support/TFTMAC/TFTMAC_LAB.sqlite
```

The build, SQL schema, preset invariants and decision engine are statically
verified. The current 42m27s automatic Build 8 run proves logging and the
performance deficit while leaving internal attribution unknown. The next
development gate is isolated source instrumentation, not another mandatory
match-marker or combat-pair run.

### Riot login input contract

Build 4 removed the desktop-mouse assumption from primary interaction. A Mac
left press, drag and release now becomes Android multitouch identifier `0`,
with non-zero pressure while in contact and an unconditional zero-pressure
release at the last valid Android coordinate. The live build-4 capture logged
`PRIMARY_TOUCH_INPUT_ACTIVE`; pressure-down and pressure-up rows were persisted
without credential content.

The same investigation found the guest WebView provider at
`133.0.6943.137`. Google Play exposed and installed the signed stable update
`151.0.7922.199`; Riot's `MobileFREWebViewActivity` restarted on that provider.
WebView is a mutable guest dependency and its exact version belongs in runtime
receipts whenever login behavior changes.

Riot's official form labels the first field `USERNAME`. It requires the private
Riot account login username, not an email address and not the public Riot ID
(`Name#Tag`). Riot's official recovery flow starts from the account email and
sends back the username: <https://recovery.riotgames.com/en-us/forgot-username>.
Passwords, usernames, email addresses and form screenshots are never retained
as TFTMAC evidence.

`memory_kill_count` is intentionally conservative: it counts only an LMKD line
that names an actual kill victim or a kernel `Out of memory: Killed process`
line. LMKD connection, memevent, tracepoint, monitor and policy setup messages
remain in the private raw log but do not become false-positive kills in SQL.

Useful queries:

```sql
-- Run and exact profile
SELECT * FROM sessions;
SELECT receipt_key, receipt_value, confidence
FROM runtime_receipts ORDER BY id;

-- Frame ingress and native output
SELECT started_monotonic_ns, frame_count, sequence_drop_count,
       mean_interval_ms, p95_interval_ms, maximum_interval_ms
FROM frame_interval_windows ORDER BY started_monotonic_ns;

SELECT sampled_monotonic_ns, source_fps, presentation_fps,
       mailbox_replacements, sequence_drops
FROM presentation_samples ORDER BY sampled_monotonic_ns;

-- Player-visible TFT guest frame truth
SELECT started_monotonic_ns, status, unavailable_reason,
       effective_fps, one_percent_low_fps,
       p95_interval_ms, p99_interval_ms, maximum_interval_ms,
       jank_count, severe_count, missed_vsync_equivalents
FROM game_frame_windows ORDER BY started_monotonic_ns;

-- Delivery freshness is causal context; final Mac presenter is hidden correctness context
SELECT * FROM stream_freshness_windows ORDER BY started_monotonic_ns;
SELECT * FROM host_presentation_windows ORDER BY started_monotonic_ns;

-- Optional user annotations; never required for automatic full-run validity
SELECT kind, monotonic_ns FROM events
WHERE kind IN ('MATCH_ENTRY','COMBAT_START','VISIBLE_STUTTER','MATCH_END')
ORDER BY monotonic_ns;

-- SurfaceFlinger deltas belong inside the automatic graphics-run lifetime
SELECT sample_label, monotonic_ns, render_rate_hz,
       total_missed_frames, hwc_missed_frames, gpu_missed_frames
FROM surfaceflinger_samples ORDER BY monotonic_ns;

-- Sound-health regressions
SELECT sample_label, active_output, sample_rate_hz, stereo_output,
       active_tracks, partial_underruns, empty_underruns
FROM audio_samples ORDER BY monotonic_ns;

-- Crash, memory and renderer signals without exposing raw log text
SELECT * FROM logcat_aggregates
WHERE anr_count + fatal_count + memory_kill_count
    + angle_warning_count + vulkan_warning_count + audio_error_count > 0;

SELECT * FROM pipeline_log_aggregates
WHERE gfxstream_warning_count + asg_stall_count + vulkan_error_count
    + moltenvk_warning_count + shader_error_count + fence_timeout_count > 0;
```

Run `scripts/summarize-native-session.command` with no argument for the latest
capture or pass one capture directory. It validates SQLite first, summarizes
every evidence layer, and reports missing telemetry explicitly without printing
raw logs, credentials or tokens.

## 6. Performance Lab controls

The app's `Performance Lab…` window persists only validated, restart-bound values. Restart is mandatory so the logger has one attributable profile and the AVD transaction remains reversible.

| Variable | Safe UI domain | Default | Evidence rule |
| --- | --- | --- | --- |
| vCPU | `4, 6, 8` | `6` | One-factor test; watch host CPU and frame windows |
| Guest RAM | `4096, 5120, 6144 MiB` | `5120` | 5120 is KEEP; 4096 remains deferred unless a deliberate test is run |
| Refresh target | `30, 60 Hz` | `60` | Do not confuse refresh target with engine FPS |
| ASG draw flush | `400, 800` | `800` | 400 is experimental; score SurfaceFlinger delta and host CPU overhead |

The following remain fixed in the UI: 1920x1080, 320 dpi, ports, AVD/image, official package, host GPU, CoreAudio, ASG buffer/step/ring, ANGLE compatibility flags, MoltenVK requests and native presenter design.

The Telemetry menu records exact user-observed boundaries:

```text
Command-Shift-1  MATCH_ENTRY
Command-Shift-2  COMBAT_START
Command-Shift-3  VISIBLE_STUTTER
Command-Shift-4  MATCH_END
```

`COMBAT_START` and `VISIBLE_STUTTER` also request a bounded 15-second Perfetto
ring trace. Severe actual-present degradation may request a rate-limited trace
automatically. A raw trace is evidence to normalize later, not an automatic
root-cause verdict.

## 7. Experiment protocol

1. Start from `tftmac_5gb_native_v1`.
2. Change exactly one restart-bound variable.
3. Quit cleanly and relaunch; never mutate an AVD profile mid-match.
4. Keep the same TFT build, graphics preset, FPS cap, workload phase and login state where practical.
5. Let the automatic process/layer logger define the full run. Match, combat and
   visible-stutter markers are optional annotations only.
6. Compare exact full-run cadence/tails, source freshness, stack receipts and
   valid owned diagnostic spans. Resource/audio data remains correctness context.
7. Reject any boot, ADB, package, crash, memory, audio or usability regression.
8. KEEP only after a comparable repeat plus cold confirmation.
9. Record why a candidate was kept or rejected; never promote from a single lobby sample.

Current product decisions:

- KEEP 5120 MiB. Sustained donor runs showed lower pressure direction than 6144 MiB while retaining guest headroom.
- DEFER 4096 MiB. It lacks sufficient heavy-game safety margin.
- KEEP High / 60 / Performance OFF as the user-confirmed current in-game control.
- REJECT Ultra High for current usability; direct user observation found severe lag, without fabricating a numeric FPS.
- RETAIN 800 µs ASG flush in Control; do not recycle the historical 400 µs screen as a new result.
- DEFER Combat Latency A promotion; its latest active observation is not a
  controlled gain and the causal logger is now the next development layer.
- KEEP raw gRPC as the working native presentation transport now.
- DEFER MMAP until producer readiness, tear-free integrity, frame-age and performance are empirically proven.

A transient black/white end-of-match frame was investigated before release.
The following guest-side screenshot and native Metal frame both showed the same
fully colored lobby, so no graphics feature override was promoted from that
single transient. `BypassVulkanDeviceFeatureOverrides` remains an unproven
one-factor diagnostic candidate only; use it only if a same-moment guest/native
capture proves repeatable missing board materials during active combat.

## 8. ZoeMC and graphics-council conclusion

The earlier 10,000-world simulation was reproducible but used subjective priors. It was correctly retained as hypothesis-ordering evidence, not as proof of a winning architecture. ZoeMC v0.2 concluded that real authenticated frame delivery was the decisive next test.

That test has now resolved the first branch:

- Raw authenticated gRPC is empirically viable for correct 1920x1080 native lobby presentation and input.
- MMAP remains a possible later efficiency optimization, not a requirement to play TFT.
- Direct MMAP zero-copy is invalid without producer-readiness/integrity fencing.
- Direct MoltenVK texture handoff has no supported resource-sharing contract.
- Encoded video/scrcpy and an external emulator window do not satisfy the native product target.

Specialist boundary findings retained from the council:

- Unreal owns game/render/RHI workload behavior, not macOS panel visibility.
- ANGLE owns the GLES-to-Vulkan compatibility boundary; exposed ES3.2 is a named nonconformant workload adapter, not conformance proof.
- gfxstream/ASG owns guest-to-host graphics command transport; requested ring/buffer values are not per-frame latency proof.
- MoltenVK owns host Vulkan-to-Metal translation; environment values are requested until effective readback is available.
- TFTMAC owns the final frame copy, orientation, scaling, input transform, output cadence and native Mac experience.
- Fortnite/Unreal guidance supplies transferable measurement categories, not TFT-specific capability or performance proof.

The complete Unreal/Fortnite transfer map, attribution gates, owned patch
points and current unknown ledger are maintained in
`docs/TFTMAC_UNREAL_PIPELINE_OBSERVABILITY.md`.

Source research artifacts:

- `outputs/ZoeMC_TFTMAC_Unreal_Graphics_v0.2/REPORT.md`
- `outputs/ZoeMC_TFTMAC_Unreal_Graphics_v0.2/VARIABLE_MANIFEST.json`
- `outputs/ZoeMC_TFTMAC_Unreal_Graphics_v0.2/NEXT_TESTS.md`
- `outputs/TFTMAC_UNREAL_GRAPHICS_COUNCIL_FINDINGS.md`

## 9. Safety and recovery

- TFTMAC acquires an exclusive interprocess lease before touching the shared AVD.
- Launch fails closed if `TFT_Ultra_Tablet`, console `5582`, or controller `8554` is already occupied.
- The emulator command line carries a unique per-session marker.
- Cleanup kills only the exact process that still matches that ownership marker.
- AVD configuration is backed up, hashed, applied atomically and restored only after the owned emulator exits.
- Interrupted recovery accepts only the exact discovered AVD config path and a backup inside TFTMAC's capture root.
- A repeated Quit remains `terminateLater`; it cannot bypass telemetry sealing or AVD restoration.
- Google/Riot passwords, MFA, CAPTCHA and consent remain manual official-UI actions and are never logged or automated.
- Android secure-lock content may be intentionally blank in the authenticated screenshot stream. TFTMAC wakes the display and accepts manual PIN keyboard input without placing instructions over Android. SQL records the unlock-required state and input character counts, never the PIN.

## 10. Remaining decisive gaps

1. User confirms sound is audible at the Mac speakers/headphones.
2. Implement source-level causal work-ID instrumentation in the isolated
   diagnostic runtime; normal-play Build 8 evidence must not fabricate an owner.
3. Correlate bounded diagnostic traces with SQL clock sync and SurfaceFlinger
   deltas before attributing a graphics bottleneck.
4. Validate whether MMAP improves CPU/frame age without tearing; keep raw gRPC if it does not.
5. Treat source rate, output rate, guest frame timing and panel visibility as separate clocks and claims.
6. If black/white or missing board materials recur during active combat, mark `VISIBLE_STUTTER` and take guest/native screenshots at the same instant before changing ANGLE, Vulkan, gfxstream or MoltenVK flags.

These are optimization and final user-acceptance gaps. They do not undo the proven native launch, lobby, rendering, input, official-package or software-audio path.
