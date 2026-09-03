# Launch profiles

The root entrypoints remain in place because they share relative paths with the
runtime, reversible AVD wrapper, experiment profiles, and benchmark harness.
Only the first row is the canonical recommendation.

| Entrypoint | Status | Purpose | Differences | Safe default |
| --- | --- | --- | --- | --- |
| `run-tft-best-verified.command` | Recommended | Canonical audited source launch | Pins ASG, ANGLE/OpenGL, MoltenVK async/64, control profile, 1440p default, and clears inherited experiment flags | Yes |
| `run-tft-fast-quality.command` | Stable fallback | Customizable stable stack | Same base stack without the canonical argument parser/override reset | No |
| `run-tft-performance-max.command` | App render-base / source entrypoint | Reduce CPU/RHI and guest-host transport work while retaining full-resolution UI | 67% 3D scale, confirmed low-cost effects/LOD, 16 KiB ASG writes, and disabled ANGLE FBO-boundary submit; Trial 1-8 remained 34.1–35.1 FPS in two full transport confirmations | No |
| `run-tft-angle-opengl.command` | Required lower-level profile | Apply verified ANGLE/OpenGL overlay | Renderer delegate used by the stable stack; not a complete safety wrapper by itself | No |
| `run-tft-root-affinity.command` | Diagnostic/lower-level | Direct emulator and guest orchestration | Owns rootable AVD, overlay, PSO scheduling, HWUI repair, and cleanup | No |
| `run-tft-gles32.command` | Legacy stable fallback | Non-root external AVD launch | Older pipe-era AVD, 1600×900, 6 GiB, no root scheduling or selected ASG stack | No |
| `run-tft-mvk128-experimental.command` | Experimental, not promoted | Reproduce MoltenVK 128-buffer candidate | One strong run failed cold and sustained reproducibility | No |
| `run-tft-fast-quality-angle-no-fbo-submit.command` | Provisional experiment | Disable ANGLE FBO-boundary deferred submit | Strong first run; lacks the required cold reproducibility confirmation | No |
| `run-tft-fast-quality-shader-prewarm.command` | Rejected for default | Preload a narrow shader set | Neutral lobby, rejected by fixed-stage campaign; retained for comparison | No |
| `run-tft-fast-quality-submit-thread.command` | Rejected | Move guest Vulkan submission/marshalling | Regressed to 37.40/32.60/25.80 FPS in fixed stages | No |
| `run-tft-fast-quality-submit-thread-control.command` | Diagnostic control | Validate submit wrapper without enabling the candidate | Mesa on-demand behavior through the same wrapper | No |
| `run-tft-fast-quality-upstream-asg.command` | Rejected campaign candidate | Force upstream ASG-related features | Did not pass the campaign gates | No |
| `run-tft-fast-quality-asg-active-consumer.command` | Rejected/historical | Reproduce isolated four-byte host patch | 11.2 FPS / 334 ms p95 versus stable lobby control; requires explicit override | No |
| `run-tft-fast-quality-native-gles.command` | High-risk diagnostic | Disable guest ANGLE | Tests native gfxstream GLES path; no accepted result | No |
| `run-tft-fast-quality-native-gles30.command` | Rejected/historical | Relax the native gate to ES 3.0 | TFT crashes before first frame because required GLES APIs are absent | No |
| `run-tft-fast-quality-native-gles31.command` | Rejected/historical | Relax the native gate to ES 3.1 | Host exposes only native GLES 3.0, so the strict gate fails correctly | No |
| `run-tft-fast-quality-ubo-direct-write.command` | Experimental | Test direct uniform-buffer writes | Isolated risky device profile; no promotion evidence | No |
| `run-tft-fast-quality-ubo-pool.command` | Experimental | Test a larger uniform-buffer pool | Isolated risky device profile; no promotion evidence | No |
| `run-tft-direct-vulkan.command` | Rejected/historical diagnostic | Test direct Unreal Vulkan | The selected Shipping device profile disables direct Vulkan RHI; Vulkan remains below ANGLE | No |

Resolution status in the canonical launcher is independent of graphics profile:
1440p is verified, 1620p has a verified full-size SurfaceView but no accepted
battle result, 1800p is provisional, and 2160p is experimental.

The packaged launcher displays a click-through 62×20 FPS HUD at the right edge
of the active Emulator title bar. It samples existing SurfaceFlinger presentation
timestamps once per second, hides when the Emulator loses focus, and stops with
the game session.

Rejected profiles are retained to make negative results reproducible. Do not
infer recommendation from file naming, and never compare login/lobby FPS with
an active-match result.
