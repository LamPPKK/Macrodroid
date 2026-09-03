# TFTMAC graphics-pipeline research and implementation boundary

Authority date: 2026-08-31

> **Historical/conditional research; not current root-cause authority.** The
> GLES/ANGLE and fixed-stage material below remains useful design evidence, but
> must not override the current Build 8 receipt or the automatic-run analysis
> contract in `facts.md`, `benchmark.md`, and `dev.md`.

## Current Build 8 status

- The observed TFT path is **direct Unreal Vulkan → guest Vulkan → gfxstream /
  ASG → host Vulkan → MoltenVK → Metal → SurfaceFlinger**.
- ANGLE is conditional and must not be treated as TFT's active rendering path
  without a new per-run receipt.
- Automatic process/layer logging is verified; Match Entry/End and combat
  classification are optional annotations, not collection or validity gates.
- The final native Mac presenter is hidden correctness context only, never a
  displayed weak link or root-cause candidate.
- Build 8 proves degradation at exact TFT SurfaceFlinger presentation, but the
  internal root remains **UNKNOWN**: no shared work ID crosses guest Vulkan,
  gfxstream, host Vulkan, MoltenVK, and Metal.
- Advanced source-level work-ID/site instrumentation is **PLANNED** only in the
  isolated `tftmac-runtime` diagnostic environment; it is not a normal-play
  Build 8 feature and cannot be claimed from current captures.

This is a graphics-observability design note. It records conditional mechanisms
and research constraints. It neither changes the signed TFT APK nor treats a
requested emulator option as proof that a renderer was selected.

## 1. Pipeline map: proven versus conditional

The app can prove the following owned path during a session:

```text
TFT GameActivity process
  -> exact GameActivity BLAST SurfaceView
  -> SurfaceFlinger actual-present timestamps
  -> authenticated EmulatorController image transport
  -> TFTMAC Metal presenter completion/present
```

The `TFT` SurfaceFlinger clock is guest-compositor truth. The controller-image
and final-Metal clocks are useful, but cannot be renamed as TFT/Unreal FPS.
Metal completion means the GPU finished the app's command buffer; it is not a
receipt that the guest produced a new frame. Apple's command-buffer API defines
the completed-handler boundary directly. [Apple: `addCompletedHandler`](https://developer.apple.com/documentation/metal/mtlcommandbuffer/addcompletedhandler(_:))

The following are historical or conditional routes, not the Build 8 active-path
claim:

```text
Historical Candidate A: TFT GLES/EGL -> guest ANGLE -> Vulkan -> gfxstream -> host Vulkan
                        -> MoltenVK -> Metal
Current receipt: TFT Vulkan -> guest Vulkan -> gfxstream -> host Vulkan
                 -> MoltenVK -> Metal
Candidate C: TFT GLES/EGL -> native guest GLES -> gfxstream -> host renderer
```

The supplied historical findings establish a successful GLES 3.2/ANGLE/gfxstream/
MoltenVK-to-Metal session on an earlier recorded target. They do not establish
that the current Build 8 TFT run selects Candidate A. ANGLE is active only when
the game chose GLES/EGL *and* Android chose ANGLE for that package; MoltenVK is
active only when the host backend actually loaded it.
The authoritative implementation sources are [Android's ANGLE module](https://android.googlesource.com/platform/packages/modules/ANGLE/+/refs/heads/main/),
[Google gfxstream](https://github.com/google/gfxstream), and
[Khronos MoltenVK](https://github.com/KhronosGroup/MoltenVK).

## 2. Active-path receipts required per launch

Do not promote a candidate route from launch intent. Record these receipts at
process start, first exact layer, layer replacement/loss, and app close:

| Boundary | Receipt | What it proves | What it does not prove |
| --- | --- | --- | --- |
| TFT | package version/code, signed package receipt, `pidof` result, resumed activity | The intended package/process/activity is present | Unreal branch, RHI, or shader work |
| SurfaceFlinger | exactly one normalized `GameActivity` BLAST layer plus `--latency` rows | TFT actual-present timing for that layer | Guest CPU/GPU cause of a miss |
| ANGLE | package-specific selection/effective guest setting and an ANGLE runtime identity line | ANGLE was selected for this run | That ANGLE caused or fixed pacing |
| gfxstream | host startup/runtime identity line and pipeline log aggregates | The observed host component initialized or emitted a diagnostic | Queue depth or per-frame transfer latency |
| MoltenVK | host runtime identity line | MoltenVK was observed in this host process | Pipeline-cache hit rate, queue wait, or cause |
| host renderer | selected Vulkan device/composition/swapchain receipt | Observed host renderer configuration | Metal saturation in the emulator renderer |
| TFTMAC presenter | command-buffer scheduled/completed timing, drawable/encoder/command errors | Hidden native correctness receipt | TFT actual presentation or emulator-root ownership |

`dumpsys SurfaceFlinger --latency` is accepted only for the exact selected
layer. Zero, sentinel, malformed, missing, or ambiguous samples are stored as
unavailable rather than converted into fabricated frame intervals. This matches
the purpose of Android's compositor/frame diagnostics: FrameTimeline separates
expected and actual timelines, but its own documentation also warns that
SurfaceViews are not currently supported by that data source. Therefore the
existing exact-layer actual-present collector remains the direct frame authority
for TFT's SurfaceView. [Perfetto: FrameTimeline](https://perfetto.dev/docs/data-sources/frametimeline)

## 3. Supported controls and commands by layer

| Layer | Supported control or observation | Runtime use / limit |
| --- | --- | --- |
| Android Emulator launch | `emulator ... -gpu <mode>` selects the emulator graphics-emulation mode. | This is a documented startup option, not proof of a particular guest RHI or host renderer. [Android Emulator command line](https://developer.android.com/studio/run/emulator-commandline) |
| Android Emulator acceleration | Graphics acceleration and mode selection are runtime/AVD dependent. | Verify the effective run; do not infer acceleration from an AVD setting alone. [Android hardware acceleration](https://developer.android.com/studio/run/emulator-acceleration) |
| Guest/package | `adb shell pidof <package>`, `dumpsys activity`, `dumpsys package`, `getprop`, and package-scoped settings receipts. | Identity and configuration evidence only; never a claim about hidden Unreal internals. |
| Guest compositor | `adb shell dumpsys SurfaceFlinger --list` and exact-layer `--latency`. | One-second actual-present windows; fail closed on no/ambiguous layer. |
| Guest trace | `adb shell perfetto --txt -c - -o <session-scoped-path>`. | Bounded incident capture only; configured sources are SurfaceFlinger frame/layers, FrameTimeline, GPU memory, process/system stats, and selected ftrace scheduling events. Availability remains device/build dependent. Perfetto data-source names must match the producing device. [Perfetto GPU sources](https://perfetto.dev/docs/data-sources/gpu) |
| Host pipeline | session-scoped emulator stdout/stderr and structured startup receipts. | Counts warnings/errors and captures identity; warning counts alone are not latency measurements. |
| Final presenter | Metal `MTLCommandBuffer` scheduled/completed handlers. | Preserve hidden correctness evidence separately from guest production; do not use it for current causal ranking. [Apple: command structure](https://developer.apple.com/documentation/metal/setting-up-a-command-structure) |

Current runtime-only options such as `-feature`, guest properties, ANGLE feature
overrides, and `MVK_CONFIG_*` environment variables are implementation-specific
experiment inputs. They may be retained as configuration receipts, but this note
does not label them portable Android Emulator, ANGLE, or MoltenVK contracts
without a version-matched upstream receipt.

## 4. Collection policy

### Always on for the owned app session

- private SQLite session, append-only event sidecar, emulator stdout/stderr;
- process/layer lifecycle events and `game_process_sessions` closure at app
  seal;
- exact-layer SurfaceFlinger polls: intervals when available and explicit
  unavailable windows otherwise;
- host pipeline-log aggregates, graphics pipeline snapshots at lifecycle edges
  and a modest periodic cadence while TFT has a PID;
- controller ingress/freshness and hidden final Metal correctness windows,
  separately labeled;
- capture health, layer identity changes, and bounded clock-alignment samples.

This is lightweight evidence collection, not profiling. It must start before
TFT activity launch when sources are available, continue through the first
process/layer observation, and end only after the final lifecycle snapshot and
the owned emulator/process shutdown receipt.

### Incident only

- Perfetto traces; current configuration is intentionally a ring buffer with a
  short fixed duration and bounded size;
- additional diagnostic snapshots around a proven degradation;
- any source-built component's verbose per-frame spans.

An automatic graphics incident requires: a current TFT PID, one exact active
layer, two adjacent bad actual-present windows, no capture in progress, and an
independent per-process budget/cooldown. It must write a generic graphics event
and a `diagnostic_artifact`, not fabricate a `combat_incident` whose schema
requires a manual benchmark ID. The existing combat benchmark remains an
opt-in A/B validity protocol.

## 5. Weak-link attribution rules

| Claimed weak link | Minimum evidence gate | Prohibited shortcut |
| --- | --- | --- |
| TFT display pacing | Exact TFT actual-present intervals plus an incident trace when needed | Calling controller ingress or Mac presentation "game FPS" |
| Guest scheduling / Unreal CPU | Correlated process runnable/running pressure; named Unreal spans only if the signed build exposes them | Inferring GameThread, RenderThread, or RHIThread ownership |
| ANGLE | Active-path receipt plus one-factor controlled improvement without correctness regression | Blaming the requested setting or a log mention |
| gfxstream / ASG | Instrumented queue depth or shared frame correlation crossing guest-to-host boundary | Treating a warning count as queue latency |
| MoltenVK | Active-path receipt plus its own queue/pipeline-cache timing or a controlled build | Naming MoltenVK because a host Vulkan device exists |
| Emulator renderer / Metal | Host renderer completion crossing a display deadline with supported counters | Using TFTMAC presenter's GPU time as emulator GPU time |
| TFTMAC presenter | Hidden correctness regression only | Treating a guest hitch as a Mac copy problem or selecting it as the current root |

Perfetto GPU data availability is producer and device specific; the documented
GPU source names can include hardware-specific suffixes and require exact
matching. A missing track is `UNKNOWN`, not evidence that the subsystem was
idle. [Perfetto: GPU data sources](https://perfetto.dev/docs/data-sources/gpu)

## 6. Allocation-free frame/batch correlation ring (future owned-source work)

The present runtime has no cross-process per-frame ID, so it can bracket a
hitch but cannot attribute a single frame across guest submit, gfxstream,
host rendering, and final present. Add this only in source-built components
TFTMAC is authorized to modify; it must never inject into Riot's signed process.

### Design

```text
producer stage -> fixed slot ring -> batch drain -> SQLite/event writer
                         ^
                    monotonically increasing sequence
```

- Use a preallocated power-of-two ring per producer process/thread domain;
  slots are fixed-width POD records, not strings, Swift arrays, closures, or
  heap-backed dictionaries.
- Slot payload: `sequence`, shared `frame_id` when a trusted handoff has one,
  `stage`, monotonic timestamp, queue-depth/byte-count fields, status/flags,
  and a producer-local loss counter. Use `frame_id = 0`/unknown until a real
  owned handoff creates it.
- A producer reserves with an atomic monotonically increasing write sequence,
  writes its slot, then release-publishes the sequence. The single drain worker
  acquire-reads only fully published slots. Each ring records overwrite/loss
  rather than blocking a render or compositor thread.
- Drain on a timed/batch threshold into one SQL transaction. Formatting,
  JSON, hashes, file I/O, locks that can contend, and trace requests are all
  outside the producer path.
- Correlate only records carrying the same trusted `frame_id`; otherwise retain
  time-bounded observations as separate evidence. Do not manufacture a join
  from adjacent timestamps across clocks.
- Version the binary batch schema and retain the producer build SHA, clock
  domain, sequence ranges, capacity, overwritten count, and flush loss count.

This design protects graphics execution from observer allocations and gives an
explicit data-loss receipt. It is intentionally smaller than a universal tracing
framework: no dynamic registration, no per-frame string labels, no unbounded
queue, and no retry that stalls rendering.

## 7. What TFTMAC must not change

- Do not patch, re-sign, instrument, inject into, or alter Riot's signed TFT
  APK/process.
- Do not claim TFT Unreal branch, RHI, thread spans, shader/PSO keys, or cache
  hits without a direct session receipt.
- Do not turn Perfetto into an always-on observer; retain bounded incident
  traces and report observer-overhead validity separately.
- Do not change CPU, RAM, audio, login, network, package authority, or gameplay
  behavior under this graphics-only effort.
- Do not treat AVD/launch flags, a healthy controller, normal log lines, or a
  single fast scene as proof of a graphics cause.
- Do not export raw traces/logcat, private AVD data, or account-bearing content
  as research artifacts.

## 8. Explicit unknowns, licensing, and privacy

Unknowns include TFT's exact Unreal branch/RHI/features, Game/Render/RHI spans,
PSO/shader keys and compile timing, gfxstream guest-submit-to-host-receive
latency, MoltenVK pipeline/cache/queue timing, and emulator-renderer Metal
saturation. These are not filled by a comparable Unreal title or an emulator
configuration request.

TFTMAC source is governed by this repository's `LICENSE`; third-party
components retain their own terms and notices. Android Emulator, AOSP/ANGLE,
gfxstream, Perfetto, MoltenVK, Metal, and Teamfight Tactics are independently
licensed or trademarked. Consult each component's authoritative repository or
vendor terms before distributing a modified build, trace processor, or source
instrumentation.

Captures are local-first and must exclude credentials, tokens, cookies, account
identifiers, private Android userdata, unrelated app data, and unfiltered game
logs. Store raw capture files in the private per-session directory, persist only
necessary aggregates/metadata to SQLite, hash retained incident artifacts, and
sanitize any excerpt before sharing.

## 9. Phased implementation path

1. **Lifecycle closure (native app only).** Add graphics PID/layer start,
   replacement, unavailable, and end events/snapshots; retain the current
   continuous exact-layer windows and pipeline aggregates. Take the final
   graphics snapshot before logcat/ADB teardown.
2. **Automatic graphics incidents (native app only).** Split graphics trace
   admission from manual combat admission. Require exact active layer + current
   PID + two bad windows, use an independent small budget/cooldown, and persist
   generic graphics events plus diagnostic artifacts.
3. **Evidence review.** For real incidents, classify only the first failing
   observed boundary. If all evidence stops at the guest/host handoff, preserve
   the gap rather than guessing the owner.
4. **Source-built gfxstream/AEMU, only for a demonstrated gap.** Add the fixed
   correlation ring and trusted handoff frame ID. Prove loss/overhead behavior
   before using it for causality.
5. **Conditional ANGLE/MoltenVK work.** Instrument one component only after a
   current run proves that component active and the correlation evidence points
   to its boundary.
6. **Controlled change acceptance.** Make one graphics-only factor change,
   retain correctness and actual-present evidence, cold-confirm any promotion,
   and stop when the claimed boundary is proven.
