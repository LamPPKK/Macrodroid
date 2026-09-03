# TFTMAC

TFTMAC runs the official live Teamfight Tactics Android client on Apple-silicon Macs using a local high-end Android tablet runtime. Riot's game binary is not modified, mirrored, or committed to Git.

## Current working profile

- Runtime: Google Play ARM64 Android 16 / API 36
- Game package: `com.riotgames.league.teamfighttactics`
- Render target: **1920×1080**
- Density: **280 DPI** (617dp tablet-class short side)
- Guest resources: **8 vCPU / 8 GB RAM**
- GPU: host accelerated
- OpenGL ES: **3.2** (`196610`)
- EGL: **ANGLE**
- Vulkan: **1.3**, backed by Apple M4 through the Android emulator graphics stack
- Fallback: Compatibility 1080p without the enhanced ES 3.2 boot flags

The installed application is `/Applications/TFTMAC.app`. Its persistent Android runtime is stored under `~/Library/Application Support/TFTMAC`.

## Use

Open **TFTMAC** from Applications. The launcher starts the high-end tablet runtime and opens live TFT automatically.

- **Enhanced 1080p** is the default renderer profile.
- **Compatibility 1080p** is the fallback if a future Android/Riot update rejects the enhanced renderer flags.
- **Google Play / Update** opens Riot's official TFT listing inside the Android runtime.
- **Stop Android** cleanly shuts down the virtual tablet.

Google credentials are entered only inside Google Play. Riot credentials are entered only inside TFT.

## Trust boundary

TFTMAC keeps the acquisition and game runtime local:

1. Google Play installs Riot's official package.
2. The acquisition helper verifies Google Play installer authority and records SHA-256 evidence locally.
3. Riot APKs, Android userdata, credentials, and AVD disks remain under ignored/protected local paths and are never committed.
4. The Mac launcher controls emulator lifecycle, display geometry, resource allocation, and graphics capability only.

## Development gates

```text
node tools/clara-task.mjs test
node tools/clara-task.mjs build
node tools/clara-task.mjs acceptance
```

`acceptance` installs the runtime under Application Support, installs `TFTMAC.app` into Applications, launches it, and requires live TFT to start with the enhanced 1080p contract before succeeding.

## Unreal transition

The original retired donor PBE implementation is intentionally preserved as donor/reference code. When Riot's live Android client exposes Unreal runtime evidence, TFTMAC can activate a separately validated `UnrealEnhancedAdapter` using the donor ANGLE/MoltenVK/DeviceProfiles research. Until then, the working native live path remains isolated and is never replaced by an unproven Unreal overlay.

See `docs/TFTMAC_GRAPHICS_ARCHITECTURE.md` for the graphics and fallback design.
