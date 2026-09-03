# TFTMAC Graphics Architecture

## Win condition

TFTMAC must provide the best practical Teamfight Tactics experience on Apple-silicon Macs while preserving a clean trust boundary:

- Riot's game binary remains official and unmodified whenever possible.
- Google Play remains the live-client acquisition/update authority.
- Engine-specific graphics changes are isolated behind explicit runtime adapters.
- A working live path must never be broken by experimental Unreal tuning.

## Runtime model

TFTMAC uses a two-layer architecture:

1. **Engine-neutral Mac shell**
   - owns the native SwiftUI launcher;
   - owns Android emulator lifecycle;
   - owns display size, DPI, CPU/RAM, window behavior, input, audio and local diagnostics;
   - detects the active Riot engine/runtime;
   - exposes safe graphics presets.

2. **Engine adapter**
   - `LiveNativeAdapter`: current Google Play live client, stock Riot runtime;
   - `UnrealEnhancedAdapter`: future/live Unreal client, harvesting the proven retired-donor PBE renderer work;
   - adapters are selected by evidence, never by version-string guesswork.

## Engine detection

Evidence is evaluated in order:

1. resolved Android launch activity;
2. package/native-library inventory;
3. running-process mappings when accessible;
4. SurfaceFlinger layer/activity evidence;
5. app-managed patch/runtime files when observable;
6. Unreal markers such as `libUnreal.so`, `UECommandLine.txt`, `UnrealGame`, `DeviceProfiles.ini`, or Unreal-specific log output.

Current live evidence after the completed in-game patch:

- package: `com.riotgames.league.teamfighttactics`
- launch activity: `com.riotgames.leagueoflegends.RiotNativeActivity`
- Google Play package version: `16.16.8042660`
- base APK SHA-256: `9ed691e1b7e976394cc0dd91c0717df954429320a323e751e4848f6214c34919`
- native payload includes `libleagueoflegends.so`
- no `libUnreal.so` or `assets/UECommandLine.txt` in the Play Store base APK
- post-patch process/storage inspection found no Unreal runtime evidence
- the current live client therefore remains on Riot's native Android runtime for this build

The Unreal adapter remains prepared from retired-donor work and must activate only when future live runtime evidence proves the engine transition.

## Graphics presets

Graphics presets are engine-neutral and map to display geometry plus resource allocation.

| Preset | Framebuffer | DPI | Intent |
| --- | --- | ---: | --- |
| **Enhanced 1080p** | **1920×1080** | **280** | **Primary target; 617dp tablet-class short side** |
| 1440p | 2560×1440 | 416 | Experimental only |
| 1800p | 3200×1800 | 520 | Experimental only |
| 4K | 3840×2160 | 640 | Experimental only |

The launcher applies both emulator geometry and guest `wm size` / `wm density` so Android layout and the host window agree. TFTMAC deliberately targets 1080p rather than using supersampled resolution as a substitute for renderer quality. GPU budget should be spent first on anti-aliasing, texture filtering, stable frame pacing, shader behavior and renderer quality.

## LiveNativeAdapter

The current safe path uses:

- official Google Play system image;
- Apple-silicon ARM64 Android emulator;
- `-gpu host`;
- Riot's untouched package;
- no APK overlay;
- no root requirement;
- normal Google Play and Riot authentication.

Safe enhancement surface:

- resolution and DPI;
- host GPU mode;
- guest CPU and memory;
- window sizing/fullscreen;
- input mapping;
- audio handling;
- emulator transport flags proven not to alter Riot code;
- frame pacing measurement.

## UnrealEnhancedAdapter

When live TFT exposes the Unreal runtime, harvest the proven retired-donor PBE work rather than rediscovering it.

Candidate stack:

`Unreal -> OpenGL ES / ANGLE -> gfxstream -> Metal`

or where supported:

`Unreal -> Vulkan -> gfxstream / MoltenVK -> Metal`

Donor capabilities already present in this repository include:

- `run-tft-root-affinity.command`;
- `run-tft-angle-opengl.command`;
- `run-tft-best-verified.command`;
- temporary verified APK overlay support;
- `DeviceProfiles.ini` injection with rollback;
- `UECommandLine.txt` overlay preparation;
- MoltenVK queue and fast-math tuning;
- ANGLE feature controls;
- ASG transport tuning;
- frame-pacing and input-latency instrumentation;
- 1080p/1440p/1800p/4K profiles.

The adapter must only activate when the running live build proves the expected Unreal artifact/layout. A hash/version/layout mismatch must fall back to `LiveNativeAdapter`, not attempt a stale overlay.

## Future enhancement ladder

### Tier 1 — safe/live now

- Enhanced 1080p target at 1920×1080 / 280 DPI (617dp tablet class);
- 8 vCPU / 8 GB guest RAM on the validated Mac Mini profile;
- host GPU acceleration;
- OpenGL ES 3.2 capability (`196610`);
- ANGLE EGL with Vulkan 1.3 on Apple M4;
- native fullscreen/window fill;
- FPS overlay and frame-time diagnostics.

### Tier 2 — Unreal enhanced

- verified ANGLE/OpenGL path;
- guest DeviceProfiles tuning;
- anisotropic filtering and anti-aliasing profiles;
- shader/prewarm experiments;
- asynchronous MoltenVK queue submission where validated;
- bounded Metal command-buffer tuning;
- ASG transport tuning.

### Tier 3 — measured quality optimizer

TFTMAC should benchmark candidate profiles instead of assuming "higher" means "better". Score each profile on:

- median FPS;
- p95/p99 frame time;
- janky frames;
- input latency;
- visual resolution;
- crash-free session duration;
- host CPU/GPU pressure.

The winning profile is the highest visual-quality configuration that remains inside an explicit frame-pacing envelope.

## Non-goals

- modifying Riot gameplay logic;
- bypassing Riot authentication or anti-cheat;
- intercepting Riot credentials;
- embedding third-party or mirrored Riot APKs in Git;
- blindly applying PBE hashes/configuration to live builds;
- claiming an Unreal profile is valid without runtime evidence.

## Acceptance gates

### Current live gate

- official Google Play installer authority confirmed;
- live TFT starts from TFTMAC;
- Riot login works;
- a full live match can be entered and completed;
- no Riot binary modification is required.

### Unreal-enhanced gate

- post-patch live client proves Unreal runtime/layout;
- donor overlay/profile assumptions are revalidated against the exact live build;
- graphics adapter is reversible and hash-gated;
- quality profile materially improves visual quality without unacceptable frame pacing;
- fallback to stock live remains one click away.
