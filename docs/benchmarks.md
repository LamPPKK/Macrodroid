# Benchmarks

> **Historical evidence only.** This is the M1 Max/API36 userdebug fixed-stage
> campaign. It is not authority for the M4 Build 8 stock runtime, its current
> direct Unreal Vulkan receipt, or current automatic full-session analysis.

This document summarizes the retained performance evidence without promoting
single runs or comparisons from different scenes.

## Test environment

Unless a row says otherwise, measurements were collected on an Apple M1 Max Mac
with 32 GiB RAM, eight performance and two efficiency cores, macOS 26.6
(25G72), Android Emulator 37.1.11 build 15917651, and an Android 36 ARM64 Google
APIs `userdebug` AVD. The selected graphics path was TFT GLES → guest ANGLE →
Vulkan → gfxstream/MoltenVK → Metal.

The selected display profile used 2560×1440 at density 416, seven vCPUs, and a
separately configurable guest memory value. The quality-preserving control used
100% Unreal screen percentage, FXAA quality 4, anisotropy 8, and a 4 KiB ASG
write step. Performance Max keeps the native-resolution UI but uses a 67% 3D
screen percentage, anisotropy 2, lower-cost effects/LOD, and a 16 KiB ASG write
step. Both use the verified 1 MiB ASG write buffer and 800 µs draw flush.

## Fixed-scene methodology

Early menu/lobby observations were useful diagnostically but are not benchmark
claims. The later harness starts a fresh Tocker's Trial, advances using bounded
XP-first/no-reroll actions, and captures stages 1-2, 1-5, and 1-8 only when both
the stage and combat-phase classifier agree before and after the window.

Each accepted sample records:

- display size and density;
- requested graphics/profile/environment flags;
- active APK, device-profile, emulator, QEMU, and gfxstream hashes;
- host power and thermal state;
- frame count, FPS, mean, median, p95, p99, max, and long-frame counts;
- semantic before/after classifications;
- launch completion and AVD/process-wrapper rollback.

The current navigation loop records planning duration and asserts zero rerolls.
It analyzes one shop while combat is running, buys at most one expensive unit,
batches reward collection, XP, and a one-time carry item pass, and performs at
most one evidence-driven board placement per round. Early deaths replay in the
same emulator and preserve already valid target captures. An obscuring choice
screen, wrong stage/phase, login/lobby state, changed SurfaceView, missing
summary, incomplete Trial, or failed rollback invalidates the affected result.
A transient capture failure is retried at most once and only after a fresh
screenshot still proves the same stage/combat with the shop closed.

## Cold, warm, and sustained runs

- **Cold** means a new emulator/AVD session for the candidate. Cold confirmation
  is required for promotion.
- **Warm/live switch** keeps more state constant and is useful for narrow
  resolution or flag A/B tests, but cannot prove cold-start reproducibility.
- **Sustained** requires the declared minimum Trial duration and every semantic
  gate. Partial long runs remain diagnostic/provisional.

Rows with fewer than two complete runs are provisional unless an immediate
rejection gate applies. The campaign repeats the two strongest one-factor
candidates. Promotion requires at least two successful runs and at least a 3%
reproducible improvement on the relevant heavy score without unacceptable tail
latency, semantic, or rollback failures.

## Confirmed results

| Comparison | Scene | Result | Classification |
| --- | --- | --- | --- |
| `virtio-gpu-asg` vs old `pipe` | Exact stage 1-1 battle | ASG 40.1 FPS / 34.85 ms p95; pipe 29.6 FPS / 49.75 ms p95 | Accepted; ASG selected |
| Selected GPU-scene/RHI/MoltenVK stack | Later stage 1-5 | 36.0–36.8 FPS, p95 near 35 ms | Confirmed range for that scene |
| 2560×1440 vs live 1600×900 | Controlled stage 1-5 | 31.3 vs 30.5 FPS while source pixels increased 2.56× | Accepted narrow A/B; CPU/RHI-bound scene only |
| Three campaign controls | Fresh Trial stages 1-2/1-5/1-8 | Mean 40.60 / 36.03 / 27.83 FPS; heavy score 27.83 | Reproducible control |
| Faster navigation smoke | Fresh Trial stages 1-2/1-5/1-8 | 40.3 / 29.8 / 28.0 FPS; 20.875 s mean preparation, zero rerolls | Harness validation, not a new leaderboard |
| Accelerated navigation | Multiple fresh/replayed Trials | 1–3 s preparation; representative complete runs averaged 1.9–2.1 s with zero rerolls | Accepted harness speedup; roughly 10× less planning time |
| Effects/LOD at 67% | Two complete Trials at stages 1-2/1-5/1-8 | Mean 45.20 / 38.50 / 33.80 FPS; stage-1-8 p95 35.07–35.95 ms | Accepted render profile; retains more resolution than the 50% candidate |
| 16 KiB vs 4 KiB ASG write step | Three complete 16 KiB Trials plus a paired 4 KiB control | 16 KiB 41.3–43.0 / 34.1–35.1 FPS at 1-5/1-8; paired 4 KiB 38.0 / 32.8 | Accepted for Performance Max; wrapper integration reproduced 43.0 / 34.7 |

The selected stack did not meet the 57 FPS heavy-scene objective. It does keep
the reproducible Trial 1-8 proxy above 30 FPS in five complete selected-profile
runs (32.0–35.6 FPS). This does not prove 30 FPS in the user's unreproduced
late-game battle that falls to about 15 FPS; lobby or light-scene observations
near 60 FPS are not substituted for that workload.

## Provisional results

At 3200×1800, an unobscured stage-1-8 sample measured 27.5 FPS / 50.916 ms p95
versus a same-day 2560×1440 control at 28.0 FPS / 49.892 ms p95. The higher
resolution retained 98.2% of FPS while rendering 56.25% more pixels. It remains
provisional because the control recorded battery power while the candidate
recorded AC power, and its p99/frames-over-50-ms were worse. A clean cold A/B is
still required.

Disabling ANGLE `preferSubmitAtFBOBoundary` produced a promising
46.90 / 36.10 / 29.60 FPS first pass. Without the required cold confirmation it
remains provisional and is not the default.

The earlier Performance Max profile used milder effect/LOD limits. Its two cold
runs measured 42.4–44.4 FPS at 1-2, 38.8–50.2 at 1-5, and 29.4–31.5 at 1-8,
with stage-1-8 p95 varying from 34.71 to 48.99 ms. It is superseded by the
confirmed 67% effects/LOD profile and 16 KiB write step above. The
quality-preserving source launcher remains available as a rollback path.

An earlier apparent 30-to-60 FPS jump is excluded from optimization evidence:
the in-game maximum was manually changed from 30 to 60 immediately before that
observation. Mobile frame-pacing CVars were restored to their stock values and
were not credited for the change.

## Rejected and non-promoted experiments

| Candidate | Evidence | Outcome |
| --- | --- | --- |
| MoltenVK 128 buffers | Strong 40.20/34.50/32.40 run; cold confirmation 39.5/31.6/23.3; two-run mean heavy FPS 27.85 with worse p95 | Failed reproducibility; experimental only |
| MoltenVK 256 buffers | 37.60 at 1-2 and 33.30 at 1-5 with a 133 ms frame; Trial ended before 1-8 | Rejected/incomplete |
| Guest submit thread | 37.40/32.60/25.80 | Rejected regression |
| Shader prewarm / submit+prewarm / upstream ASG | Failed campaign promotion gates | Rejected for default |
| 50% 3D scale | 46.0/36.8 FPS at 1-2/1-5; three attempts ended before 1-8 | No advantage over the 67% effects/LOD profile; incomplete |
| Effects-only / LOD-only split | Particles/effects reached 31.1 FPS at 1-8 with 48.53 ms p95; LOD-only fell to 32.9 FPS at 1-5 with 45.71 ms p95 | Combined profile selected; isolated factors not promoted |
| ASG draw flush 4 ms | Two complete 1-8 runs at 34.2/31.8 FPS; second p95 46.32 ms | Reduced sampled CPU work but hurt reproducibility/tail latency |
| ASG draw flush 2 ms | One 33.4 FPS 1-8 run; confirmation exhausted five attempts before 1-8 | Not promoted |
| ASG write step 8/32 KiB | Both screened at 38.7 FPS on 1-5; 32 KiB included a 62.71 ms frame | Rejected; only 16 KiB passed full confirmation |
| ASG data ring 64/128 KiB | 64 KiB screened at 44.0 but repeated at 41.3/34.6 FPS on 1-5/1-8; 128 KiB screened at 40.5 with 35.86 ms p95 | No reproducible gain over the default 32 KiB ring |
| ASG write buffer 512 KiB | Two boots failed before TFT-ready with `Failed to unbox VkPipeline`; rollback verified | Rejected startup incompatibility; 1 MiB retained |
| Extreme effects/LOD at 67% | 34.9 FPS at 1-5, p99 65.86 ms, max 130.54 ms | Rejected regression; lower quality was not monotonic |
| Emulator audio disabled | 42.1 FPS at 1-5 versus 43.0 for the Performance Max integration run with audio | No FPS benefit; user audio remains enabled |
| VirtioGpuNativeSync | 37.5 FPS at 1-5, p95 35.21 ms, max 53.43 ms | Rejected regression |
| VirtioGpuNext | 42.4 FPS at 1-5, p95 33.72 ms, no frames over 40 ms | Neutral versus the 43.0 FPS integration control; not promoted |
| Forced half-rate skeletal animation with interpolation | 39.4/33.1 FPS at 1-5/1-8; 1-8 p95 37.01 ms and p99 47.11 ms | Rejected; did not scale with unit count and worsened tails |
| Vulkan batched descriptor updates disabled | 40.3 FPS at 1-5 versus 43.0 for the integration control; max 50.58 ms | Rejected regression; batching retained |
| `r.OneFrameThreadLag=0` | 23.6 FPS, -21.9% versus input baseline | Rejected |
| Synchronous MoltenVK submit | 27.1 FPS, -10.3% | Rejected below budget |
| Disable async composition | 27.9 FPS, -7.6%; no proven visible latency reduction | Eligible under original 10% budget, not promoted |
| Explicit native swapchain | 28.9 FPS, -4.3%; feature already enabled in baseline boot log | No-op/not promoted |
| MSAA2 | Black 3D pass with UI still visible | Rejected immediately |
| Material quality 1 | Neutral/noisier | Not selected |
| ASG active-consumer host patch | 11.2 FPS / 334 ms p95 versus 60 FPS / 18.44 ms p95 in same lobby scene | Rejected; explicit forensic opt-in only |
| Native GLES 3.0/3.1 gates | ES 3.0 path crashed before first frame; host native path exposed only GLES 3.0 for the ES 3.1 test | Rejected |

Input captures found approximately 119–120 Hz touch delivery and healthy empty
Android input queues across the tested factors. A separate shop open/close
capture showed about 250 ms between immediate button feedback and panel change
while frames continued normally, consistent with a game-owned UI transition
rather than emulator input backlog.

## Hashes and rollback

External release hashes and active profile hashes are listed in
[Reproducibility](reproducibility.md). The capture scripts record the hashes
actually active for each run instead of trusting a filename.

The ASG wrapper backs up both `config.ini` and generated `hardware-qemu.ini`,
uses a lock with owner verification, and restores both on normal or interrupted
flows. The guest profile/APK mounts and process wrapper are also verified during
cleanup. A sample with failed cleanup is excluded even when its FPS looks good.

## Comparison limits

Do not compare different stages, combat with planning, lobby/login with a match,
obscured and unobscured boards, AC and battery runs, cold and warm results, or
different TFT/emulator versions as if they were controlled. FPS is only one
signal; p95/p99, long frames, semantic validity, stability, and rollback are
part of acceptance.
