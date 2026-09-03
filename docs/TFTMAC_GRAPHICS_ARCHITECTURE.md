# TFTMAC Graphics Architecture

## Current normal-play path

```text
Official TFT Unreal Vulkan workload
  -> guest Vulkan
  -> gfxstream / virtio-gpu ASG
  -> host Vulkan
  -> MoltenVK
  -> Metal / Apple M4 GPU
  -> Android SurfaceFlinger actual-present
  -> authenticated raw RGBA transport
  -> TFTMAC native presenter (hidden correctness receipt)
```

The stock Build 8 runtime is the normal-play authority. TFTMAC owns the native
window, launcher/session control, input, transport, and evidence collection;
it does not modify Riot's package, credentials, shaders, or process.

ANGLE is conditional. A receipt may show ANGLE is present in the guest, but the
currently observed TFT game path is direct Unreal Vulkan. Do not attribute TFT
rendering to ANGLE unless a future per-run receipt proves it.

## Diagnostic boundary

The current logger proves exact SurfaceFlinger degradation and continuous
process/layer coverage, but it has no shared work ID across guest submission,
gfxstream, MoltenVK, and Metal. It therefore cannot name an internal root cause.
The next planned layer is an isolated source-built `tftmac-runtime` diagnostic
stack pinned at `c8aa26e`; it is never the normal-play runtime and its results
are non-comparable to stock until parity gates pass.

For current facts and data contracts, use [../facts.md](../facts.md),
[../benchmark.md](../benchmark.md), and [../dev.md](../dev.md). The prior
adapter architecture is archived at
`history/2026-08-31-pre-build8/TFTMAC_GRAPHICS_ARCHITECTURE.md`.
