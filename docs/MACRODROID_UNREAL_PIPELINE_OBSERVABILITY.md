# TFTMAC Unreal graphics observability and patch map

Authority date: 2026-08-31

## Fixed premise and engineering objective

TFT uses Epic's Unreal Engine technology. Fortnite and other shipped Unreal
Android titles are therefore valid architecture and experiment references. The
reference does not make every TFT runtime choice identical: the exact Unreal
branch, RHI, renderer features, shader keys, PSO cache, swapchain, device
profile, and CVars must be identified from this TFT run before a connector is
changed.

The absence of Riot's signed game source changes the interception point. It
does not make the graphics pipeline unknowable. TFTMAC can observe and change
the components it owns: the Android/emulator configuration, AEMU/gfxstream,
ANGLE when active, MoltenVK when active, and the native frame transport. The
final Metal presenter is hidden correctness context only. A future isolated
source-built gfxstream runtime can add a shared
`frame_id` at every guest/host handoff without modifying Riot's APK.

## Transferable Unreal model

The useful Unreal reference pipeline is:

```text
GameThread simulation
  -> RenderThread command construction
  -> optional RHIThread / graphics API submission
  -> guest GPU queue and swapchain
  -> Android compositor actual presentation
```

Unreal Insights can name GameThread, RenderThread, RHIThread, GPU and PSO work
when the application build exposes those trace channels. TFTMAC must leave
those internal spans `UNKNOWN` when the signed TFT build does not expose them.
Android platform traces still establish CPU scheduling, compositor deadlines,
GPU memory, and what the player actually saw.

## Runtime paths that evidence must distinguish

Only a per-session pipeline snapshot may promote one of these candidates:

1. **Current receipt:** Unreal Vulkan -> guest Vulkan -> gfxstream -> host Vulkan -> MoltenVK -> Metal.
2. Conditional: Unreal GLES/EGL -> ANGLE Vulkan -> gfxstream -> host Vulkan -> MoltenVK -> Metal.
3. Unreal GLES/EGL -> native guest GLES -> gfxstream -> host rendering.
4. Another renderer selected by the installed TFT/emulator build.

ANGLE applies only when the game selected a GLES/EGL path and Android selected
ANGLE for that package. MoltenVK applies only when the host Vulkan backend
actually loaded it. Requested launch flags are hypotheses; normal runtime log
identity and effective guest properties are evidence.

## Causal clocks and hidden correctness context

| Label | Measurement | Valid claim |
| --- | --- | --- |
| `TFT` | Exact TFT `GameActivity` BLAST SurfaceView, SurfaceFlinger actual-present timestamps | Frames the guest compositor actually presented for TFT |
| `PIPE` | Authenticated EmulatorController image arrivals plus sampled content identity | Transport delivery and whether delivered images changed |

The final native Metal loop is retained privately as correctness/regression
context, not exposed as a causal clock. A healthy PIPE or native-presenter rate
can coexist with a frozen/repeated TFT frame; neither is Unreal FPS. Reporting
must show `TFT —` when the exact SurfaceView cannot be selected or read and must
never substitute another clock.

## Implemented data contract

Every native app start creates a private SQLite session. The 2.3 telemetry
extension adds:

| Table | Evidence |
| --- | --- |
| `game_frame_intervals` | Every newly observed actual-present interval, direct active stack SHA, frame-window link, jank flag, severe flag and missed-vsync equivalent |
| `game_frame_windows` | One-second TFT FPS, direct active stack SHA, 1% low, p50/p95/p99/max, jank, severe stalls, missed vsyncs, layer identity, refresh period and explicit availability reason |
| `stream_freshness_windows` | Changed/identical sampled content, longest identical run and sequence loss |
| `host_presentation_windows` | Final Metal submissions/completions, unique/repeated sources, drawable/command errors, completion and GPU timing |
| `pipeline_log_aggregates` | Counts of real warning/error/stall lines at gfxstream, ASG, Vulkan, MoltenVK, shader and fence boundaries; normal configuration lines do not become failures |
| `graphics_runs` | Automatic TFT process/layer lifetime, start/end reason, configuration SHA, target FPS and exact-layer receipt |
| `graphics_pipeline_snapshots` | Per-snapshot stack receipt, canonical receipt JSON/SHA-256, completeness/unknown fields, and observed active-path identity |
| `graphics_pipeline_incidents` | Automatic exact-layer degradation window, admitted trace link, first observed boundary, and explicit causal unknowns |
| `diagnostic_artifacts` | SHA-256, byte count, trigger and analysis state for bounded Perfetto captures |
| `host_resource_samples` | Host available/compressed/swap/pageouts, thermal state and power source at five seconds |
| `combat_benchmarks` | Named preset, configuration SHA, 300/480-second boundaries, coverage, validity and summary metrics |
| `combat_incidents` | Optional controlled-A/B visible-stutter/benchmark evidence; not the authority for base graphics logging |
| `combat_comparisons` | Control/candidate deltas and deterministic HOME_RUN/PROMISING/REJECT/INCONCLUSIVE result |

SurfaceFlinger history polls overlap. The collector establishes a first-poll
boundary, de-duplicates actual-present timestamps, resets on layer replacement,
and records bounded-history loss explicitly rather than inventing one giant
frame interval. Interval inserts are committed once per poll so the logger does
not create dozens of disk transactions per second.

The logger begins automatically with the observed TFT process/layer lifecycle
and remains active until process/app close. It does not require a user marker,
battle classifier, or Combat Benchmark. The fixed Combat Benchmark remains an
optional controlled A/B path with one 20-second/32-MiB start trace and up to two
15-second/32-MiB incident traces. Automatic graphics incidents require an
observed TFT process, exact active layer, two adjacent bad one-second windows,
and, outside a controlled A/B, a separate graphics-run budget/cooldown. During
an active A/B the start trace and automatic/manual incidents share that
benchmark's fixed three-trace ceiling. Traces
include SurfaceFlinger, FrameTimeline, layers, Android GPU memory, scheduler
switch/wakeup/waking events, process/system stats, TFT process identity and
guest CPU-frequency events when exposed. Every retained trace is hash-sealed
and normalized immediately with pinned Perfetto `trace_processor_shell` v58.2;
normalization output and hashes are written to SQL. Failure deletes the
unprocessed raw trace and records a trace failure.

`graphics_runs`, stack-receipt SHA-256s, and frame-window joins are implemented
and runtime-verified by Build 8 automatic captures. They establish lifecycle
and observation integrity, not a causal owner.

## Attribution gates

| Candidate blocker | Evidence required before naming it |
| --- | --- |
| Guest display/frame pacing | TFT actual-present misses or long intervals, with bounded SurfaceFlinger/FrameTimeline evidence |
| Unreal CPU thread | A missed frame correlated with named Unreal spans, or at minimum TFT process runnable/running pressure; without named spans report only process CPU pressure |
| gfxstream/ASG transport | Queue depth or submit-to-host receive time from an instrumented gfxstream build; warning counts alone are not latency proof |
| Host emulator GPU | Host renderer command completion crossing display deadlines plus supported Metal/GPU counters |
| PSO/shader hitch | A PSO compile/miss event coincident with the hitch in a controlled UE trace; a fight-only spike is not sufficient |
| ANGLE mismatch | A session snapshot proves ANGLE is active and a one-factor controlled change improves actual-present percentiles without a correctness regression |
| MoltenVK behavior | A snapshot proves MoltenVK is active and its own queue/pipeline-cache instrumentation or a controlled build isolates the change |

The conservative weakest-boundary view may report only the first observed
unhealthy/missing receipt among `TFT` and `PIPE`; it must never turn a
time-adjacent warning, CPU/RAM/audio health sample, or incomplete stack receipt
into a graphics causal claim. CPU/RAM/audio remain correctness and health
context, outside the graphics-only optimization equation.

## Safe code and configuration intervention points

1. Native logger/controller: markers, clock alignment, capture health, loss
   counters, SurfaceFlinger timing and Perfetto lifecycle. This is implemented.
2. **Planned, gated next layer:** isolated `tftmac-runtime` (`c8aa26e`) may emit
   one transport work ID and source-site receipt at guest submit, host receive,
   host queue, host Vulkan submit, MoltenVK enqueue, Metal completion and
   Android buffer release. It is diagnostic-only and cannot replace or be
   performance-compared with normal-play Build 8 until parity gates pass.
3. ANGLE source/build, only if active: log renderer/feature selection, shader
   translation/cache time, queue waits and relevant extension negotiation.
4. MoltenVK source/build, only if active: log pipeline creation/cache hits,
   queue submit, command-buffer scheduling/completion and swapchain behavior.
5. TFTMAC's final Metal presenter: preserve only as a hidden correctness receipt;
   it is not a current graphics optimization or root-cause target.
6. A controlled Unreal Android reference app on the identical emulator stack:
   expose Unreal Insights and systematic PSO/frame-pacing experiments. It
   proves stack capability and causal signatures, not TFT internals by proxy.

Do not patch the signed TFT APK, inject code into Riot's process, copy
Fortnite's PSO cache, or label a guessed shader as Riot's. Unreal/Fortnite
practices remain valuable as test hypotheses: PSO precaching, work off the
interactive frame, stable Android frame pacing, device-profile quality tiers,
and one-factor RHI experiments.

## Automatic full-run and bounded A/B protocol

1. Let automatic process/layer logging run for the full TFT session. Markers and
   classifiers are optional context, not causal gates.
2. Compare complete timelines and automatic degradation episodes using TFT
   actual-present, source freshness, stack receipts, and valid diagnostic spans.
3. Use a bounded A/B only when it screens one named configuration factor.
4. Do not include the Mac presenter in causal ranking.
5. Classify the first divergent boundary; leave later boundaries as effects.
6. If Combat Latency A wins, run the five-minute cold confirmation before promotion.
7. Repeat a comparable fight and a cold-start confirmation. Reject correctness,
   boot, ADB, audio, memory, login, or usability regressions.
8. Use the automatic trace-active/trace-inactive comparison; over 5% change marks causal trace conclusions `OBSERVER_OVERHEAD_INVALID` while retaining performance data.

## Current unknowns to close with data

- Exact TFT Unreal branch and mobile renderer feature set.
- Active per-run RHI and all negotiated graphics extensions/features.
- Game/Render/RHI thread spans when the signed build does not expose them.
- TFT shader/PSO keys, cache hit rate and compile timing.
- gfxstream queue depth and per-frame guest-submit-to-host-receive latency.
- MoltenVK pipeline-cache and queue timing inside the emulator process.
- Host Metal saturation counters for the emulator renderer, independent of the
  hidden final-presenter correctness receipt.
- Observer overhead during a comparable automatic run.

An unknown is not filled by a Fortnite assumption. Fortnite/Unreal tells us
which mechanism and signature to test; the correlated TFT run tells us whether
that mechanism is active and failing here.

## Primary technical references

- Epic, platform-native Android profiling: <https://dev.epicgames.com/documentation/unreal-engine/profile-android-projects-with-platformnative-tools>
- Epic, Unreal Insights channels: <https://dev.epicgames.com/documentation/unreal-engine/unreal-insights-reference-in-unreal-engine-5>
- Epic, mobile frame pacing: <https://dev.epicgames.com/documentation/unreal-engine/frame-pacing-for-mobile-devices>
- Epic, PSO cache optimization: <https://dev.epicgames.com/documentation/unreal-engine/optimizing-rendering-with-pso-caches-in-unreal-engine>
- Epic, PSO precaching: <https://dev.epicgames.com/documentation/unreal-engine/pso-precaching-for-unreal-engine>
- Android, game frame-rate optimization: <https://developer.android.com/games/optimize/framerate>
- Android, frame pacing: <https://source.android.com/docs/core/graphics/frame-pacing>
- Perfetto, FrameTimeline: <https://perfetto.dev/docs/data-sources/frametimeline>
- Perfetto, GPU data sources: <https://perfetto.dev/docs/data-sources/gpu>
- Google gfxstream source: <https://github.com/google/gfxstream>
- ANGLE source: <https://android.googlesource.com/platform/packages/modules/ANGLE/+/refs/heads/main/>
- Khronos Vulkan specification: <https://registry.khronos.org/vulkan/specs/latest/pdf/vkspec.pdf>
- MoltenVK runtime guide: <https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Runtime_UserGuide.md>
- Apple, Metal performance analysis: <https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app/>
