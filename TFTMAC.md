# TFTMAC

TFTMAC is a native macOS application that launches and presents the official
Google Play Teamfight Tactics Android client through Google's stock Android
Emulator on Apple silicon.

## Current status

- Normal-play authority: installed TFTMAC 2.3.0 build 8 using stock Android
  Emulator 37.1.11, High graphics, 60 FPS, and Riot Performance Mode OFF. Its
  hashes match the historical release receipt; current-host signing trust is
  separately blocked by the absent local identity.
- Automatic graphics logging is live-verified for the TFT process/layer
  lifetime. It does not require match markers or a combat classifier.
- The current automatic evidence proves gameplay frame degradation but cannot
  name an internal graphics owner. Source-level causal instrumentation is
  planned; it is not implemented or claimed as complete.
- The final Mac presenter is retained only as a hidden correctness receipt. It
  is not a graphics optimization target or a root-cause candidate.

Read [README.md](README.md) first, then [facts.md](facts.md),
[benchmark.md](benchmark.md), [dev.md](dev.md), and [project.md](project.md).
The prior document is preserved at
`docs/history/2026-08-31-pre-build8/TFTMAC.md`; it is historical and must not
override those authorities.
