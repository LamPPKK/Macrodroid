# Historical Phase 0 Source-Build Evidence

**Status:** RETIRED EVIDENCE — NOT EXECUTION GUIDANCE

The former GPU-runtime program attempted a source-built Android Emulator path. It established useful historical facts, including an `emu-master-dev` source freeze, host/toolchain compatibility findings, and a real multi-thousand-step AEMU compile before that architecture was retired.

Current TFTMAC does not require that source checkout or its build outputs. The released Google Android Emulator 37.1.11 is the verified runtime authority, and native TFTMAC freezes the installed EmulatorController protocol directly from that runtime.

Preserved historical conclusions:

- the source family was `emu-master-dev`;
- the source experiment reached a real AEMU/gfxstream compile;
- one observed failure involved an obsolete macOS deployment-target/toolchain mismatch;
- large source/build artifacts were moved to external storage because they were inappropriate for normal internal-disk operation;
- later measured work proved the released stock emulator is the correct product control/runtime path.

Do not restart repository synchronization, source compilation, CTS/reference downloads, or the former source-build workflow from this record. Any future source-runtime effort requires a separately approved measured blocker.
