# TFTMAC Direct-Play Control Build

**Status:** SUPERSEDED HISTORICAL CONTROL-BUILD RECEIPT
**Date:** 2026-08-28  
**Project:** `TFTMAC`  
**Repository:** `flashls1/TFTMAC`  
**Purpose:** Build the smallest trustworthy TFT-on-Mac control product, launch the current official TFT client through Google Play/Riot authority, and capture enough synchronized telemetry to make subsequent performance work causal rather than speculative.

> This dated direct-play/Node control plan is preserved as evidence. It is not current launch authority. Current native authority is `ssot/runtime-authority.json` and `TFTMAC_GPU_RUNTIME_SSOT.md`; in particular, do not reuse this receipt's `5040/5592` service-context identity or 6144-MiB control value.

---

# 0. Fresh-chat execution directive

A fresh implementation agent must begin here.

Read these files first, in this order:

1. `ssot/TFTMAC_DIRECT_PLAY_CONTROL_BUILD.md`
2. `ssot/TFTMAC_PERFORMANCE_LAB.sql`
3. `ssot/TFTMAC_REBUILD_PREFLIGHT.md`
4. `ssot/donors/TFTMAC_DONOR_RESEARCH.sql`
5. `ssot/STACK.lock.yaml`

Then execute the control build end to end.

Do **not** ask broad architecture questions. Do **not** restart the old source-AEMU Phase 1 build. Do **not** substitute a third-party TFT APK, hosted community game feed, or mirrored Riot package if the official package path has a problem. Diagnose the first failed authoritative boundary and repair the minimum reversible layer.

The only expected user-interactive pauses are Google Play and/or Riot sign-in if those services require credentials, MFA, CAPTCHA, consent, or other human authentication. Never read, store, automate, intercept, or transmit those credentials.

The agent may discover exact paths, current component versions, package state, and available runtime capabilities without asking the user. If a previously frozen value has drifted, record the observed value and continue when it is compatible with this contract; do not silently force an obsolete pin merely because an older plan named it.

The first completion target is **not perfect performance**. The first completion target is:

> **A current official TFT client, installed from Google Play/Riot authority, launching through a stock Google Android Emulator runtime on the Apple M4, with audio, a usable native Mac presentation, and the complete telemetry system already recording from before emulator launch through shutdown.**

---

# 1. Strategic supersession

This build supersedes the old **source-built-AEMU-first** strategy for the normal product path.

Preserve all old source research, source locks, probes, patches, negative results, and engineering maps. They remain valuable evidence. However:

- do not resume the existing `emu-master-dev` compilation;
- do not require the AEMU source tree to play TFT;
- do not carry a 100–200+ GB development checkout as a shipping dependency;
- do not modify AEMU source until a current stock-runtime measurement proves that an AEMU-owned limitation is the first causal blocker;
- do not use source age, architectural ambition, or prior sunk cost as a reason to keep source-built AEMU on the critical path.

The normal control product uses released Google runtime artifacts.

Source AEMU becomes a **conditional research adapter** only.

---

# 2. Product thesis

The problem has changed.

We no longer need to prove that TFT can be made to start on Apple Silicon. A current donor runtime has already demonstrated the compatibility route on this exact target host.

The current engineering problem is:

> **Why does a working Unreal/Android graphics stack produce severe frame-time collapses, and which boundary can be improved with the smallest reversible intervention?**

Therefore TFTMAC must first own a clean reproducible control and its measurement system.

The control architecture is:

```text
TFTMAC.app
    |
    v
stock Google Android Emulator 37.1.11 control
    |
    v
official Google Play ARM64 Android guest
    |
    v
Google Play -> official current TFT package
    |
    v
Riot login / Riot content / Riot matchmaking
    |
    v
TFT / Unreal renderer
    |
    v
Android graphics stack
    |
    v
gfxstream / ANGLE / Vulkan / MoltenVK / Metal as actually selected
    |
    v
Apple M4
```

The logger observes what the runtime actually selects. Do not claim a graphics path from configuration intent alone.

---

# 3. Frozen target host facts

Current target machine:

```text
Hardware model: Mac16,10
Machine: Mac mini
Chip: Apple M4
Memory: 16 GB unified memory
Architecture: arm64
macOS: 26.6.2
macOS build: 25G83
```

Available Apple toolchain evidence:

```text
Xcode: 26.6
Build: 17F113
Bundled macOS SDK: 26.5
```

The native TFTMAC application should retain a minimum deployment target of **macOS 12.0** where practical. Xcode 26.6 is a current build tool on this host; it is not a product runtime dependency.

---

# 4. Frozen Android control facts

Known installed Google components:

```text
Android Emulator: 37.1.11
Platform Tools: 37.0.1
Play system image:
  system-images;android-37.1;google_apis_playstore_ps16k;arm64-v8a
Image revision: 9
Architecture: arm64-v8a

Observed control drift on 2026-08-28:

- the earlier official `android-37.0` Play ps16k ARM64 revision 6 guest booted and had validated Google connectivity, correct clock/timezone, working Play unauthenticated APIs, and successful Google account pre-checks;
- Google Play Services then launched `com.google.android.gms/.auth.uiflows.minutemaid.MinuteMaidActivity`, which crashed and was force-finished back to the unauthenticated Play Store screen before any Google account was created;
- the Google SDK catalog exposed the newer stable official `android-37.1` Play ps16k ARM64 image at revision 9;
- the control therefore advances only the official guest image from 37.0 rev 6 to 37.1 rev 9 while keeping Emulator 37.1.11 and the frozen resource/display profile unchanged;
- the failed 37.0 session is preserved as diagnostic evidence and is not performance truth.
```

Known production/control AVD identity from the current stack:

```text
AVD: TFTMAC_Live_API37
Emulator console port: 5592
ADB serial: emulator-5592
Isolated ADB server port: 5040
```

Implementation rule:

1. Inspect the existing official Play AVD.
2. Reuse it only if its state is clearly authoritative, clean enough for the control, and not contaminated by obsolete experimental package modifications.
3. Otherwise create a new clean Play-enabled ARM64 AVD from the already installed official image.
4. Do not ask the user which option to choose; choose the lower-risk path from observed state.

The first control guest must prefer **one official Google Play AVD**. Do not introduce a second execution guest unless the one-guest path is proven insufficient for a specific required runtime control.

---

# 5. Riot/TFT package authority

Package identity:

```text
com.riotgames.league.teamfighttactics
```

Production package authority is:

```text
Google Play / Google-delivered Android package
                +
Riot's own in-game content/update services
```

Explicitly forbidden as production authority:

- the retired donor's hosted TFT feed;
- the retired donor's bundled TFT package;
- stale PBE package pins;
- community APK mirrors;
- public APK download sites;
- privately repackaged Riot APKs;
- re-signed Riot binaries;
- patched Riot gameplay binaries.

The retired implementation is donor/reference evidence only.

## 5.1 PackageStateManager

Implement a package-state service in TFTMAC. It must be able to classify at least:

```text
MISSING
PLAY_AVAILABLE
INSTALLING
INSTALLED_UNKNOWN_VERSION
INSTALLED_CURRENT_OBSERVED
UPDATE_AVAILABLE
PATCHING_OR_INITIALIZING
READY_FOR_LAUNCH
PACKAGE_DAMAGED_OR_INCOMPLETE
```

For every observation, capture:

- package name;
- `versionName`;
- `versionCode` / long version code;
- installer package when observable;
- base APK path;
- split APK paths;
- signing certificate digest(s) when observable through public package tooling;
- base/split file SHA-256 values when accessible without altering the package;
- first-install time and last-update time when available;
- launch activity;
- whether package private data exists;
- whether Riot/Unreal runtime markers are observable after launch.

If the package is missing or Google Play reports an update, TFTMAC must route the user to the official Play installation/update surface instead of pretending the package is current.

After any update, re-query the exact package state before allowing the session to be labeled `MATCH_READY`.

A launcher version string is never proof that the game is current.

## 5.2 Conditional authority/execution split

Use this only if the official Play guest cannot provide a specific runtime control that is proven necessary.

Allowed architecture:

```text
Official Play authority guest
    -> Google-delivered exact Riot split APKs
    -> record package/signature/hash identity
    -> copy the user's exact installed package set unchanged
    -> rootable execution guest
```

Requirements:

- exact package name preserved;
- exact signatures preserved;
- exact APK bytes/hashes preserved;
- no Riot binary modification;
- no re-signing;
- no third-party package source;
- authority guest remains the update source;
- execution guest is rebuilt/reconciled from the authoritative package after every package update.

Do not create this split speculatively.

---

# 6. Storage contract

Bulk runtime root:

```text
/Volumes/MAC MINI M4/TFTMAC/Runtime
```

Small local state may live under:

```text
~/Library/Application Support/TFTMAC
```

Recommended control-state layout:

```text
~/Library/Application Support/TFTMAC/
├── State/
├── Logs/
├── Captures/
├── Diagnostics/
└── Rollback/
```

Large capture artifacts may spill to the external TFTMAC runtime/capture tree if required, with a small index under Application Support.

Rules:

- `/Volumes/MAC MINI M4` is mandatory for bulk runtime data;
- fail closed if the external volume is not mounted;
- never silently create a duplicate bulk SDK/AVD on the internal disk;
- no AEMU source checkout is required for the direct-play control;
- initial total runtime budget is **<= 35 GiB** for emulator + selected image + one AVD + fully patched TFT + normal control caches;
- measure the actual storage bill of materials after the first successful session and reduce the budget from evidence.

## 6.1 Old large source/build cleanup

The prior giant AEMU development tree is now a reproducible research cache, not product state.

Before deleting any large old tree:

1. inventory the directories and sizes;
2. identify unique non-reproducible artifacts;
3. preserve unique locks, patches, manifests, logs, benchmark summaries, and source-hash evidence in the repository or a compact archive;
4. record hashes and retained locations;
5. delete only reproducible source checkouts, build outputs, downloaded archives, and generated object trees that are no longer required by this control path.

Never delete a unique experiment artifact merely to reach a disk-size target.

---

# 7. Initial control runtime profile

Use the simplest profile already proven capable of booting TFT on the target M4 as the **starting control**, not as the final optimized profile:

```text
vCPU: 6
Guest RAM: 6144 MB
Display: 1920x1080
Density: 320 dpi
Refresh target: 60 Hz
GPU: host
Audio: enabled
Device frame: disabled
Snapshots: not required for the control; cold-boot capability must remain available
```

Do not allocate 8+ GB RAM or additional vCPUs merely because they exist. This 16 GB host needs macOS, the native app, emulator, graphics drivers, caches, and capture tooling to coexist without memory pressure.

Resource tuning happens later from measured host/guest utilization.

## 7.1 Graphics control rule

The first official-package control should be as close to stock Google behavior as possible while remaining capable of running TFT.

Use the known donor graphics configuration only to the minimum extent required to cross a real compatibility boundary. Every non-default graphics control must be captured in `runtime-state.json` and `renderer-state.json`.

Do not inherit the retired donor's nonconformant GLES-version exposure into the product silently. If TFT requires it for this control, label it explicitly as a temporary compatibility adapter and keep the existing genuine-capability laboratory as the truth test.

---

# 8. Presentation contract

The control must use the Emulator's direct native rendering path. Do not use scrcpy, software display encoding, or a video-stream presentation layer.

Control presentation requirements:

- no Android device frame;
- landscape;
- correct 1920x1080 framebuffer;
- window can be resized/fitted to the Mac display without changing the source framebuffer unexpectedly;
- use the stock emulator's native fullscreen/window-fill capability where stable;
- normal keyboard/mouse input remains functional;
- FPS HUD and stutter marker remain visible/accessible without intercepting gameplay input.

The final product requirement remains stronger:

> **One legitimate native TFTMAC macOS application with a standard AppKit window, native traffic-light controls/fullscreen, and the Android Emulator embedded through its controller interface with the Qt window hidden.**

The implementation authority for that product layer is `ssot/TFTMAC_NATIVE_APP_EMBEDDED_BUILD_PLAN.md`. The old separate-QEMU-window resizing/Accessibility/overlay approach is superseded and must not be resumed as the production architecture.

The embedded presentation layer does **not** block the first control. When implemented, it must be compared against the direct emulator control and rejected or redesigned if it materially worsens source FPS, presentation FPS, frame timing, input latency, audio, or graphics capability.

No presentation system is allowed to reintroduce guest software video encoding.

---

# 9. Native TFTMAC application

Use the strongest reusable open-source/donor product patterns already in the repository instead of re-inventing basic launcher UX.

Allowed retired-donor concepts/code patterns under their applicable license include:

- SwiftUI launcher structure;
- install/readiness/running/failure states;
- installer progress surfaces;
- resumable verified downloads;
- component integrity checks;
- durable install-state checkpoints;
- repair and reset flows;
- resource controls;
- emulator lifecycle;
- FPS overlay pattern;
- diagnostics collection;
- bounded opt-in telemetry patterns;
- updater UI patterns;
- rollback and sidecar recovery patterns;
- user-facing errors that map to recovery actions.

Replace or retire:

- hosted TFT package feed;
- bundled Riot package assumptions;
- PBE-specific naming/hashes;
- hardcoded stale game-version acceptance;
- fatal generic exit when TFT package/private data is temporarily absent;
- any graphics assumption that is not confirmed on the current official package.

The app state machine should represent the real product, roughly:

```text
NeedsRuntime
  -> InstallingRuntime
  -> NeedsGooglePlaySignIn / NeedsTFTInstall
  -> NeedsTFTUpdate
  -> Ready
  -> Launching
  -> PlayingAndCapturing
  -> Stopping
  -> Ready

Failure states route to Repair, not mystery shutdown.
```

---

# 10. Logging is a first-class product requirement

The logger must be operational **before the first official TFT launch**.

Do not write high-frequency telemetry synchronously into SQLite during gameplay. That risks turning the observer into the bottleneck.

Architecture:

```text
runtime producers
      |
      v
append-only raw artifacts / JSONL / trace files
      |
      v
post-session normalizer
      |
      v
TFTMAC_PERFORMANCE_LAB.sql database
      |
      v
causal comparisons / KEEP-REJECT decisions
```

Every capture has a unique `session_id` and immutable control-config hash.

Suggested capture root:

```text
~/Library/Application Support/TFTMAC/Captures/<session-id>/
```

Large binary traces may instead live under the external runtime and be referenced by path/hash.

## 10.1 Required capture artifacts

Every usable control session should attempt to produce:

```text
session.json
runtime-state.json
package-state.json
renderer-state.json
host-events.jsonl
clock-sync.jsonl
markers.jsonl
emulator.stdout.log
emulator.stderr.log
logcat.raw.txt
logcat.filtered.txt
surfaceflinger/
gfxinfo/
host-process.csv or .jsonl
host-memory.csv or .jsonl
trace.perfetto-trace        # when available without destabilizing the run
powermetrics.*              # optional; only if privilege/access is available
manifest.sha256
```

Missing optional artifacts do not invalidate the control. Missing package state, runtime state, renderer state, clocks, or frame timing **does** make a performance session incomplete.

## 10.2 Session manifest

`session.json` must include at least:

- session UUID;
- UTC start/end timestamps;
- host monotonic start/end timestamps;
- host hardware/OS identity;
- TFTMAC app build/commit;
- runtime config hash;
- emulator version/build;
- system-image package/revision;
- AVD identity;
- package versionName/versionCode;
- package/signature/hash observation reference;
- display size/density/refresh;
- vCPU/RAM;
- audio state;
- launch arguments;
- relevant runtime environment variables;
- whether cold/warm boot;
- whether package was updated during the session;
- capture completeness state;
- user-defined workload label when provided.

## 10.3 Runtime/renderer observation

Capture, where available:

- emulator-reported graphics backend;
- host GPU selected;
- MoltenVK/Vulkan identity/version;
- Android `getprop` graphics properties;
- hardware EGL selection;
- GuestAngle state;
- graphics transport name;
- ASG settings if active;
- Vulkan guest maximum API version;
- SurfaceFlinger/display state;
- Android HWUI renderer;
- game activity and process identity;
- Unreal/runtime markers emitted by the game;
- package-specific ANGLE selection/feature overrides if any;
- current foreground surface/layer information.

The logger records **observed state**, not merely intended launch flags.

## 10.4 Frame timing

Primary sources should include SurfaceFlinger presentation timing and any relevant framestats that work for the current game surface.

Store enough raw timing to calculate:

- presented FPS;
- mean/median frame interval;
- p95;
- p99;
- maximum frame interval;
- jank count/rate;
- severe-stall count;
- contiguous stall windows;
- before/after timing around user stutter markers.

Do not compare lobby/menu FPS against combat as if they were the same workload.

## 10.5 Host process sampling

At a practical low-overhead interval, sample the emulator/QEMU, TFTMAC, and important associated processes for:

- CPU percentage / CPU time;
- RSS/resident memory;
- thread count;
- nice/priority;
- process state;
- optional per-thread CPU where collection cost is acceptable.

Sampling must be cheap enough not to dominate the workload.

## 10.6 Host memory sampling

Capture sufficient host memory evidence to identify unified-memory pressure:

- physical memory in use/available when obtainable;
- memory pressure state;
- compressed memory;
- swap use;
- page-in/page-out indicators where useful;
- emulator/QEMU RSS trend;
- major pressure transitions.

A frame drop correlated with memory compression/swap is a different bug than one correlated with GPU submission waits.

## 10.7 Perfetto

If current Android/emulator tooling exposes Perfetto without destructive/root-only changes, capture bounded traces around selected performance sessions.

Prefer focused categories useful for:

- scheduling;
- frequency/CPU activity;
- SurfaceFlinger;
- graphics;
- binder;
- memory;
- Android app/process slices.

Do not leave a high-overhead trace configuration enabled for ordinary gameplay.

## 10.8 Manual stutter marker

Implement a lightweight hotkey, initially **F8** unless that conflicts with gameplay/system behavior.

Pressing it must write a monotonic timestamped event such as:

```json
{"event":"USER_STUTTER_MARK","host_mono_ns":1234567890,"utc":"..."}
```

It must not inject input into the Android guest.

This gives the user a way to mark a visibly bad moment so the analyzer can inspect the surrounding 5–15 seconds.

---

# 11. Clock synchronization

Cross-layer correlation is required.

At capture start and periodically during the session:

1. record host monotonic time `t0`;
2. issue a bounded guest query for a monotonic/boottime value such as `elapsedRealtimeNanos` or a stable equivalent;
3. record host monotonic time `t1` immediately after response;
4. map the guest sample to host midpoint `(t0+t1)/2`;
5. store round-trip duration as uncertainty;
6. repeat periodically so drift can be estimated rather than assumed zero.

Each record in `clock-sync.jsonl` should include:

```text
host_t0_ns
guest_mono_ns
host_t1_ns
host_midpoint_ns
rtt_ns
estimated_offset_ns
```

Use monotonic clocks for causal ordering. Wall-clock UTC exists for human navigation only.

---

# 12. Performance contract

The old frozen quality target remains the **optimization target**, not the first-control gate:

```text
Average presented FPS >= 58.0
P95 frame interval <= 20.0 ms
P99 frame interval <= 33.334 ms
Janky frame threshold > 33.334 ms
Janky frames <= 1.0%
Severe stall threshold > 100 ms
Severe stalls <= 3 per 600 seconds
```

The first direct-play control is allowed to miss these thresholds.

It must be:

- playable enough to reach a real match;
- correctly current relative to another live client;
- stable enough to capture meaningful data;
- completely instrumented.

The prior user-observed donor drop from roughly 60 FPS to roughly 6 FPS is an **anecdotal diagnostic signal**, not a promoted performance fact. Reproduce it under the direct official-package control before making it a root-cause input.

---

# 13. Capture-run methodology

Do not design the optimizer around completing full 30–40 minute TFT matches.

A performance capture is a controlled workload, not a ranked-play commitment.

Preferred early workflow:

1. cold launch control;
2. enter current live TFT;
3. capture login/lobby only for system-health reference, not gameplay FPS;
4. enter a normal game mode suitable for legitimate testing;
5. capture loading/transition behavior;
6. capture several early combats and board interactions;
7. if a normal surrender option becomes available, use it rather than intentionally abandoning games;
8. stop capture cleanly;
9. normalize and analyze.

Initial useful run length is roughly **8–12 minutes when the game mode permits**. Do not intentionally accumulate penalties just to shorten experiments.

Later, when a candidate specifically targets heavy-board behavior, collect a longer heavy-state sample or use a repeatable in-game mode/harness if Riot exposes one legitimately.

---

# 14. Performance laboratory: causal workflow

All normalized analysis uses `ssot/TFTMAC_PERFORMANCE_LAB.sql`.

The database is intentionally separate from donor research and the broad engineering map.

Rule:

> **Donor evidence can nominate a hypothesis. Only current TFTMAC measurements can promote it to a current product fact.**

## 14.1 Control first

Before any optimization experiment:

- capture a direct-play cold session;
- capture a warm repeat if practical;
- capture at least one transition/loading stall window;
- capture at least one combat-heavy window accessible without excessive play time;
- freeze the exact control config hash.

No graphics tweak is allowed to become the new baseline without a controlled comparison.

## 14.2 Candidate causal boundaries

The analyzer should classify evidence around stalls across at least these boundaries:

```text
Unreal game thread
Unreal render/RHI thread
PSO/shader compile/cache activity
Unreal device-profile selection
texture streaming / ASTC decompression
Guest Android CPU scheduling
PSO/compiler service scheduling
ANGLE worker activity
pipeline/descriptor churn
Guest Vulkan submission
Gfxstream/ASG packing or backpressure
Guest-host synchronization/fence waits
Host gfxstream decode/queue state
MoltenVK shader/pipeline translation
MoltenVK queue wait / command-buffer pressure
Metal command-buffer scheduling / presentation
SurfaceFlinger/display pacing
Unified-memory pressure / compression / swap
Audio only when timestamp correlation makes it causal
```

A high count at an observation point is not proof that the observation point owns the delay.

## 14.3 Experiment rule

Each experiment changes **one causal factor** unless a coupled change is inseparable by design.

Each experiment must have:

- hypothesis ID;
- exact control session/config;
- intervention description;
- expected causal signature;
- rollback action;
- run classification: cold/warm/transition/heavy;
- before/after metrics;
- semantic validity;
- decision: `KEEP`, `REJECT`, `INCONCLUSIVE`, or `DIAGNOSTIC_ONLY`.

Promising performance wins require cold confirmation before baseline promotion.

A one-run FPS increase is not promotion evidence.

## 14.4 Runtime configurability

Design the runtime so validated experiments can be applied as small reversible profile/config changes rather than app rebuilds wherever possible.

Examples of candidate knobs, only when supported by evidence:

- guest CPU/RAM profile;
- graphics transport parameters;
- specific emulator feature switches;
- ANGLE feature overrides;
- MoltenVK environment/config controls;
- Android renderer selection;
- Unreal/device-profile controls that do not patch Riot gameplay binaries;
- scheduling/affinity controls on a rootable execution guest if that architecture is activated;
- presentation/frame pacing controls.

Every knob must be represented in the runtime config hash and rollback manifest.

## 14.5 Donor negative-result rule

Do not casually repeat these donor failures without new current causal evidence:

- scrcpy/software encoded display;
- generic “more RAM”;
- generic extra vCPU;
- broad PSO prewarm;
- forced guest submit thread;
- MoltenVK 128-buffer promotion from one run;
- 50% render scaling as a universal fix;
- disabling audio as a presumed FPS fix;
- arbitrary larger ASG rings/buffers;
- native GLES version spoofing without the required semantics.

The donor database contains the detailed provenance; the clean performance lab does not treat these as current facts.

---

# 15. Direct-play implementation sequence

Execute in this order unless a step's direct evidence makes the following step impossible.

## Step 1 — Preserve and orient

- connect to the exact TFTMAC managed worktree;
- read the five authority files named in Section 0;
- preserve the current dirty preflight/donor work;
- do not clean or rebase away those files;
- inventory the currently installed Google SDK/runtime and AVD state.

## Step 2 — Build the native control shell

Create/refactor `TFTMAC.app` around a small native state machine:

- runtime installed/healthy;
- Play/TFT package state;
- Ready;
- Launching;
- Playing/Capturing;
- Repair;
- Reset runtime state if explicitly needed.

Reuse donor SwiftUI patterns where they accelerate this.

## Step 3 — Own a small released Google runtime

Use verified released artifacts already installed or acquire them directly from Google.

The control must not require the AEMU source tree.

Record exact emulator and platform-tools versions and hashes where practical.

## Step 4 — Prepare official Play AVD

Use the existing clean API37 Play ARM64 AVD if safe; otherwise create a fresh one.

Configure:

```text
1920x1080
320 dpi initial control
6 vCPU
6144 MB RAM
host GPU
landscape
audio enabled
keyboard/mouse enabled
no device frame
isolated ADB port5040
```

Boot and prove Google Play opens.

## Step 5 — Implement PackageStateManager

Before TFT is installed, TFTMAC should show a clear official-install action.

Open/navigate the guest to the official Google Play TFT listing or Google Play surface. The user completes Google sign-in if needed.

After installation/update, capture exact package state.

## Step 6 — Start logger before game launch

Create the capture session and all mandatory manifest/raw streams **before** launching TFT.

Start clock synchronization and low-overhead host/guest samplers.

## Step 7 — Launch current official TFT

Launch only the observed official package.

If Riot requires sign-in, stop automation at the credential boundary and allow the user to authenticate directly in Riot's UI.

Capture renderer/runtime selection once the game process is live.

## Step 8 — Current-version proof

Reach the TFT lobby and verify the package/update state is settled.

The strongest first proof is entering a live game with another current client without Riot returning a game-version mismatch.

If version mismatch occurs, do not tune graphics. Return to package authority/update state first.

## Step 9 — First control capture

Capture at least:

- app launch;
- emulator boot;
- package launch;
- loading transition;
- lobby reference;
- match entry;
- early gameplay/combat;
- at least one user-marked or automatically detected stall window if observed;
- clean shutdown.

## Step 10 — Normalize performance data

Post-session only:

- hash artifacts;
- ingest session metadata into the performance lab;
- compute frame statistics;
- detect jank/severe-stall windows;
- correlate clock-aligned process/memory/graphics events;
- create queued hypotheses from evidence.

Do not automatically change runtime settings after the first capture.

## Step 11 — Native fullscreen control

Use the emulator's direct native fullscreen/window-fill mode if stable.

If a custom single-window macOS presentation layer already exists in donor/local code, keep it off the critical path until direct-play is proven. Then compare it against the native emulator control for frame time/input overhead.

## Step 12 — Storage BOM

After the first fully patched playable session, measure:

- SDK/emulator bytes;
- selected system-image bytes;
- AVD bytes;
- TFT package/game-data bytes;
- caches;
- capture/log overhead.

Write the bill of materials and update the target from the provisional 35 GiB ceiling.

## Step 13 — Preserve the control

Freeze:

- runtime config hash;
- package state;
- renderer state;
- first valid capture ID;
- app build SHA;
- artifact manifest SHA.

This becomes Experiment Control 0.

Only now start performance interventions.

---

# 16. Failure routing

Do not turn every failure into a renderer project.

Route to the first failed boundary:

```text
External volume missing
  -> storage/preflight

Google runtime absent/corrupt
  -> runtime installer/repair

Play guest will not boot
  -> AVD/runtime

Google Play unavailable
  -> official image/Play provisioning

TFT missing/outdated/version mismatch
  -> PackageStateManager / Google Play / Riot update state

TFT launches but fails renderer requirement
  -> renderer-state capture, then minimum compatibility adapter

TFT plays but hitches
  -> performance capture/analyzer

Fullscreen wrapper hurts performance
  -> presentation layer, keep direct emulator control
```

If the official Play package cannot render under a clean stock control, capture the exact failure first. Then introduce the minimum known donor-compatible adapter required to run the official package.

Do not substitute an unofficial game package to make the symptom disappear.

---

# 17. First-control acceptance gate

The direct-play control is **PASS** only when all of these are true:

1. `TFTMAC.app` builds and launches natively on the target M4.
2. The app starts an owned/reproducible stock Google Emulator runtime without using a source-AEMU build tree.
3. The active Android guest is an official Play-enabled ARM64 guest or a documented authority/execution split activated only because one-guest operation was proven insufficient.
4. Google Play is the authoritative TFT package source.
5. The current official TFT package is installed or updated through Google/Riot authority.
6. Exact package metadata is captured after installation/update.
7. Riot login works through Riot's own UI.
8. TFT reaches the lobby.
9. TFT can enter a current live match with another current client without a game-version mismatch.
10. Audio works.
11. The direct native emulator presentation is usable, with device frame removed and native fullscreen/window-fill available if stable.
12. The logger starts before emulator/game launch and continues through shutdown.
13. Required runtime, package, renderer, clock, and frame-timing artifacts are captured.
14. A session artifact manifest is hashed.
15. No retired-donor server/feed/bundled Riot package is required.
16. No giant AEMU source checkout is required for ordinary launch.
17. Poor FPS is allowed at this gate if the workload is playable enough to produce valid measurements.

Do **not** call the overall TFTMAC product complete at this point.

This gate establishes the trustworthy control from which the performance product is built.

---

# 18. Performance-product exit condition

After the control passes, the optimizer runs until evidence supports the shipping target or proves a deeper architectural change is required.

The final performance product must ultimately address:

- transition/loading stalls;
- heavy-board combat performance;
- shader/PSO first-use behavior;
- tail frame time, not just average FPS;
- native fullscreen presentation;
- audio and microphone transport;
- update/repair resilience;
- low storage footprint;
- package-version drift;
- reproducible rollback.

If the first proven bottleneck ultimately requires source changes to ANGLE, gfxstream, MoltenVK, AEMU, or a new Metal adaptation layer, activate that work **only with the causal trace that justifies it**.

---

# 19. Agent completion behavior

A fresh agent executing this file should continue autonomously through discovery, implementation, build, launch, and evidence capture.

It must not stop to ask the user questions already answered by this contract.

It may stop for user action only when an external authentication surface requires the user to sign in or satisfy MFA/CAPTCHA/consent.

After authentication is complete, continue immediately.

Completion report must provide:

- native app build result;
- exact runtime versions;
- exact AVD/image identity;
- exact official TFT package version/signature observation;
- whether match entry succeeded without version mismatch;
- audio result;
- presentation/fullscreen result;
- capture session ID;
- capture manifest hash;
- first frame-time metrics;
- observed renderer path;
- storage bill of materials;
- any first causal performance hypotheses, explicitly marked as hypotheses.

The recommended fresh-chat instruction is:

> **Connect to Clara, open TFTMAC, read `ssot/TFTMAC_DIRECT_PLAY_CONTROL_BUILD.md` and execute it end to end. Do not resume source-built AEMU. Build, launch, and capture the first direct-play control session. Pause only if Google or Riot requires me to sign in.**
