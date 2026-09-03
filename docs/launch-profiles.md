# Launch Profiles

## Current profile

Stock Build 8 is the only normal-play authority. Its runtime base is
`tftmac_5gb_native_v1`, and its current SQL capture configuration is
`tftmac_stock_build8_high60_control`:

- 1920×1080, 320 dpi, 60 Hz
- 6 vCPU, 5120 MiB guest RAM, host GPU, CoreAudio
- `virtio-gpu-asg` with the retained ASG/ANGLE/MoltenVK control values
- TFT High graphics, 60 FPS, Riot Performance Mode OFF

TFTMAC launches through the packaged emulator host using the locked logged-in
macOS-session chain and ADB 5038 / console 5582 identity. It does not use old
script launchers, Node, Clara, or a direct service-context spawn.

`combat_latency_a` is a launch-verified but not performance-promoted historical
candidate. Riot Performance Mode Beta and Home Run A are rejected and are not
selectable. A future isolated `advanced_diagnostics` runtime is diagnostic-only,
not a play profile.

The legacy launcher table is archived at
`history/2026-08-31-pre-build8/launch-profiles.md`.
