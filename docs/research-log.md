# Research log

> **Historical research only.** This log preserves earlier GLES/ANGLE, donor,
> overlay, and fixed-stage work. It must not override current Build 8 facts,
> direct Unreal Vulkan receipts, stock-runtime normal-play authority, or the
> current no-marker automatic-logging policy.

This edited log preserves the useful technical chronology and negative results.
Benchmark tables and acceptance rules are summarized separately in
[Benchmarks](benchmarks.md).

## Contents

1. [Compatibility problem](#compatibility-problem)
2. [Working GLES 3.2 path](#working-gles-32-path)
3. [Native window and host scheduling](#native-window-and-host-scheduling)
4. [Resolution, memory, and CPU](#resolution-memory-and-cpu)
5. [Device profile and overlays](#device-profile-and-overlays)
6. [First-use stalls and root scheduling](#first-use-stalls-and-root-scheduling)
7. [Input and game-owned latency](#input-and-game-owned-latency)
8. [Transport and renderer experiments](#transport-and-renderer-experiments)
9. [Login WebView failures](#login-webview-failures)
10. [Fixed-stage campaign](#fixed-stage-campaign)
11. [Historical and rejected findings](#historical-and-rejected-findings)

## Compatibility problem

The initial Android 12 environments installed the unmodified TFT PBE package but
exposed only OpenGL ES 2/3/3.1. TFT PBE `18.1-5212127` requires ES 3.2 or newer,
so installation success did not imply a runnable client. Generic Vulkan flags
did not make the Shipping build select a compatible GLES context.

The small [`angle-egl-probe.cpp`](../artifacts/angle-egl-probe.cpp) probe and
early runtime observations established the graphics-version boundary. Raw crash
tombstones are no longer retained in the public repository.

## Working GLES 3.2 path

Android Emulator 37.1.11 was configured to select ANGLE for the TFT package and
enable `exposeNonConformantExtensionsAndVersions:exposeES32ForTesting`. TFT then
observed GLES 3.2 while ANGLE rendered through Vulkan and the emulator mapped
gfxstream/MoltenVK to Metal. The game reached UI, downloaded content,
authenticated, and entered a match, validating more than process startup.

The lower-level renderer entrypoint is
[`run-tft-angle-opengl.command`](../run-tft-angle-opengl.command); the canonical
wrapper is [`run-tft-best-verified.command`](../run-tft-best-verified.command).

## Native window and host scheduling

The original scrcpy display path used software video encoders inside the guest.
That competed with TFT and shader workers and introduced random freezes.
Right-click also mapped to Android Back, which looked like a crash but was a
normal pause/focus loss. Moving to the Emulator's native window removed the
encode path and preserved normal mouse behavior.

zsh's default `BG_NICE` silently started background-orchestrated QEMU at nice 5.
All launch wrappers now disable `BG_NICE`, preserving normal nice 0 host
scheduling.

## Resolution, memory, and CPU

Stretching a 1280×720 emulator surface improved neither source detail nor frame
rate. The selected device profile forces 100% screen percentage and disables
dynamic resolution. A controlled stage-1-5 switch measured 31.3 FPS at
2560×1440 versus 30.5 at 1600×900, despite 2.56× source pixels. This was a
CPU/RHI-bound scene, not proof that resolution is universally free.

Seven guest CPUs left capacity outside TFT's observed five-core PSO mask. Later
samples showed roughly 4.5 of seven guest CPUs idle and only about 1.3 CPUs used
by TFT, so an eighth vCPU was not justified. Guest memory also retained several
GiB of available/cache memory; indiscriminately raising RAM could increase host
pressure without addressing the measured bottleneck.

## Device profile and overlays

TFT selected generic low-performance fragments for the virtual Apple GPU. The
verified profile raised screen percentage, disabled dynamic resolution, enabled
mobile GPU-scene textures, bypassed the queued RHI command path, and retained
FXAA4/aniso8. Direct Unreal Vulkan remained disabled; Vulkan is used below
ANGLE.

An ordinary copied `DeviceProfiles.ini` was consumed after one TFT start. A
later process restart fell back to 1280×720 buffers inside a 2560×1440 display.
The launcher now checksum-verifies and bind-mounts the profile transactionally
for the whole AVD session. The installed APK remains intact, and cleanup restores
or removes every temporary mount.

Profiles are under
[`artifacts/tft-pbe-18.1-5212127-angle-opengl/`](../artifacts/tft-pbe-18.1-5212127-angle-opengl/).

## First-use stalls and root scheduling

Unreal logs and behavior separated first-use shader/PSO stalls from steady
frame rate. A broad prewarm that forced `r.PSOPrecaching=1` reproducibly crashed
inside OpenGL program-cache initialization and was rejected without deleting
the persistent program-binary cache.

Four `psoprogramservice` processes were restricted to guest CPUs 0–2 even
though TFT could use 0–6. A separate official Android 36 Google APIs `userdebug`
AVD enabled supported, visible `adb root`. The launcher kept every PSO-service
thread on CPUs 0–6 and raised only their 28 `ANGLE-Worker` threads from nice 19
to nice 0. The user observed that large first-use effect stalls disappeared,
although steady match rendering remained heavy.

TFT PBE `18.1-5300314` later changed the inherited Android profile from four
remote OpenGL program compiler services to zero. The first launch therefore
recreated the update-specific program-binary cache, and a later match still
started with only 341 cached programs / 20.8 MB versus 2,353 programs / 106.4 MB
on the previous build. Unreal reported both `Remote PSO services disabled` and
`Ignoring precache PSO, external compiler not active`; the cache grew to 34 MB
during that match. The launcher profiles now explicitly request the previously
verified four OpenGL compiler services instead of inheriting this patch-varying
game default.

[`scripts/watch-root-pso.command`](../scripts/watch-root-pso.command) reapplies
the setting every ten seconds because Android task profiles can restore the old
affinity. One-second polling was rejected as unnecessary ADB/thread-scan noise.

## Input and game-owned latency

Android input channels were responsive, with no pending event and empty inbound
and command queues. A later drag capture delivered touch reports around
119–120 Hz. Renderer queue experiments therefore targeted click-to-next-frame
latency rather than replacing mouse injection.

The stage-1-2 input A/B rejected no-frame-ahead (-21.9% FPS) and synchronous
submit (-10.3%). Disabling async composition stayed within the original 10%
budget but cost 7.6% without a proven visible improvement. Explicit native
swapchain was already enabled by default.

An exact shop toggle showed immediate button response followed by a roughly
250 ms panel transition while frames continued. Touchscreen, stylus, rapid
double-tap, and zero Android animation scales did not remove it. Static evidence
points to a cooked CommonUI animated switcher, so modifying signed game assets
or trading away FPS was rejected.

The tools are [`scripts/run-input-latency-experiment.command`](../scripts/run-input-latency-experiment.command),
[`scripts/capture-input-latency.command`](../scripts/capture-input-latency.command),
and [`scripts/compare-input-latency.command`](../scripts/compare-input-latency.command).

## Transport and renderer experiments

The early ASG comparison mixed menu and match scenes and is historical. A later
exact stage-1-1 A/B measured 40.1 FPS / 34.85 ms p95 on ASG versus 29.6 FPS /
49.75 ms p95 on pipe. ASG was selected through the reversible
[`scripts/run-asg-experiment.command`](../scripts/run-asg-experiment.command).

Raising the ASG write buffer above 1 MiB crashed startup with
`External address size too small`; 1 MiB/4 KiB remains the limit. MSAA2 blacked
out the 3D pass. Material quality 1 was neutral/noisier. RHIThread profiling
moved the dominant evidence toward guest-to-host ASG writes after GPU-scene
textures removed the earlier buffer-view hotspot.

MoltenVK async submission and 64 active Metal command buffers were retained.
The 128-buffer candidate produced one strong run but failed cold and sustained
reproduction; see
[`run-tft-mvk128-experimental.command`](../run-tft-mvk128-experimental.command).
The isolated active-consumer host patch produced a severe same-scene regression
and now requires explicit forensic opt-in.

## Login WebView failures

The official Riot WebView originally deadlocked when a field interaction caused
Skia Vulkan rendering to wait through gfxstream. Selecting Android HWUI's Skia
OpenGL renderer avoided that WebView path without disabling Vulkan underneath
TFT's ANGLE SurfaceView.

A separate repaint issue made two fields disappear while their DOM geometry and
hit boxes remained valid. Both wrappers retained completed 800 ms
`fill: forwards` animations. Launcher 1.6.8 added a scoped service that, only
while the exact official login activity is top-resumed, connects through a
temporary loopback ADB forward, cancels those two animations, verifies the
expected fields/wrappers, and removes the forward. It generates no focus or
input and reads no credentials or form values.

The optional [`scripts/login-tft-from-keychain.command`](../scripts/login-tft-from-keychain.command)
is separate automation. It performs a no-secret preflight, refuses visible
CAPTCHA/MFA, then reads a local Keychain item and submits the official form
through native DOM setters. Credentials and Android login state are never part
of the repository.

## Fixed-stage campaign

On 2026-08-05/06, the autonomous harness replaced ad-hoc screens with fresh
Trial stages 1-2, 1-5, and 1-8, semantic before/after gates, active hashes, and
verified rollback. Three controls averaged 40.60/36.03/27.83 FPS. Submit thread,
shader prewarm, submit+prewarm, and upstream ASG failed promotion.

The first bounded navigation loop used XP-first actions, no rerolls, one shop
purchase pass, one bench deployment pass, and one early item pass. It reduced
normal preparation to 20–22 seconds and recorded every stage in
`planning-events.jsonl`.

On 2026-08-09/10, the loop was replaced by combat-overlapped shop analysis,
one expensive-card purchase, batched reward waypoints and XP taps, a single
evidence-driven board placement, and a one-time carry item batch. Normal
preparation now takes 1–3 seconds; representative complete runs averaged
1.9–2.1 seconds with zero rerolls. Choice screens are classified explicitly,
early deaths use `PLAY AGAIN` in the same emulator, and valid stage captures
survive a replay. A stale Trial is surrendered before a fresh 1-1. These changes
make short 1-5 screens practical and reserve 1-8 for promising candidates.

The final transport screens used the selected 67% profile and 16 KiB ASG write
step. `VirtioGpuNativeSync` regressed stage 1-5 to 37.5 FPS, while
`VirtioGpuNext` was neutral at 42.4 FPS versus the 43.0 FPS wrapper integration
control. Disabling Vulkan batched descriptor updates also regressed to 40.3
FPS. A heavier-scene hypothesis that forced skeletal animation updates every
second frame with interpolation measured 39.4/33.1 FPS at stages 1-5/1-8 and
worsened the 1-8 tail to 37.01 ms p95 and 47.11 ms p99. None was promoted.

The same campaign isolated scene work from transport work. At 67% 3D scale,
aggressive effect/particle limits plus shorter view/mesh LOD retained 32.0 and
35.6 FPS in two complete 1-8 runs. A paired ASG sweep selected a 16 KiB write
step: two full runs averaged 41.45 FPS at 1-5 and 34.60 at 1-8 versus a new 4
KiB control at 38.0/32.8. Guest profiling supported the mechanism: total
samples fell from 17,000 to 14,408, `writew` from 13.31% to 12.69%, speculative
reads from 3.71% to 2.50%, and ring waits from 3.29% to 2.92%. The 8/32 KiB
screens, 64/128 KiB data rings, 2/4 ms flush variants, 50% resolution, and
isolated or extreme effect/LOD profiles did not pass promotion gates. A 512 KiB
ASG write buffer failed twice during startup and was rolled back; 1 MiB remains
required by this emulator build.

Disabling emulator audio also screened neutral/slower at 42.1 FPS versus the
43.0 FPS Performance Max integration run, so AudioMixer sampling weight was not
treated as proof of a frame-time bottleneck.

The campaign entrypoint is
[`scripts/run-performance-campaign.command`](../scripts/run-performance-campaign.command);
candidates are declared in
[`scripts/performance-candidates.json`](../scripts/performance-candidates.json).

## Historical and rejected findings

- Direct TFT Vulkan, external UE command lines, raw native GLES, more RAM, an
  eighth vCPU, Android Game Mode FPS caps, stretched windows, scrcpy video, and
  broad shader prewarm did not solve the verified problem.
- Pinning RHIThread to CPUs 0–1 worsened frame time and was rolled back.
- Restricting PSO workers to CPUs 2–6 produced a worse directional sample and
  was rolled back.
- A 30-minute sustained Trial was not completed; partial runs remain diagnostic.
- The 1800p result is provisional because power source and tail latency were not
  controlled identically.
- The old low-resolution, pre-fast-quality, menu, lobby, and login observations
  are historical and must not be combined with fixed-stage battle data.

Negative results remain represented by explicit profiles where reproducibility
has engineering value. Their status is indexed in
[Launch profiles](launch-profiles.md).
