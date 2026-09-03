# TFTMAC Telemetry and Diagnostics

TFTMAC diagnostics are local-first and evidence-driven.

## Native capture

Each native app start creates a private `0700` session directory under:

```text
~/Library/Application Support/TFTMAC/Captures/<session-id>/
```

`TFTMAC_NATIVE_RUNTIME.sqlite` is the queryable session authority. `native-events.jsonl`, emulator stdout/stderr and session-scoped `logcat.raw.txt` are local sidecars. Raw logcat is sensitive, never copied into SQLite, and must not be published.

Useful evidence may include:

- host monotonic timestamps;
- emulator/runtime state;
- one-second native frame-ingress interval windows and visual checkpoints;
- raw-gRPC source freshness plus native Metal presentation internals retained as
  hidden correctness/regression context and never called Unreal FPS;
- aggregate logcat fault counts with raw lines kept outside SQL;
- SurfaceFlinger render-rate and cumulative missed/HWC/GPU counters sampled at boundaries and every 30 seconds during gameplay;
- AudioFlinger active output, sample rate, stereo state, tracks and underruns;
- host CPU/RSS/memory-pressure samples;
- guest `/proc/meminfo` and host/guest monotonic clock calibration;
- renderer/graphics state;
- package version, installer, and signer evidence;
- explicit user stutter markers.

The base graphics logger is automatic: it opens from the observed TFT
process/layer lifecycle, continues through process/layer replacement or loss,
and seals only at TFT process or app close. It does not wait for a match marker,
a battle classifier, or a Combat Benchmark. The Telemetry menu's
`MATCH_ENTRY`, `VISIBLE_STUTTER`, and `MATCH_END` remain optional user context;
the controlled Combat Benchmark remains an optional A/B protocol. `gfxinfo` is
not Unreal/Vulkan frame authority. Perfetto remains a bounded incident
diagnostic rather than an always-on observer.

The current source schema associates automatically captured samples with
`graphics_runs`, records a canonical graphics-stack receipt and SHA-256 at each
snapshot, and links exact guest intervals to their containing frame window when
available. Every exact guest interval and one-second game window also carries
the active immutable `stack_sha256`, so stack identity survives incomplete
window joins and later layer changes. These source-level changes are
**VERIFIED CURRENT runtime** evidence through the Build 8 automatic captures. A stack receipt establishes
the observed route/configuration for that sample; it does not prove causal
ownership of a slow frame.

## Retention

Keep only evidence that protects a current product decision:

- latest successful playable baseline;
- latest native-app acceptance capture;
- current package-authority evidence;
- current promoted A/B evidence;
- current unresolved crash/failure capture.

Superseded runs should be compacted to their session ID, configuration hash, verdict, key metrics, and relevant source hashes before raw bulk is removed.

## Privacy

Diagnostics must not intentionally capture or publish Google/Riot credentials, tokens, cookies, account identifiers, private Android userdata, or unrelated application data. Sanitize any excerpt before sharing it.

No remote telemetry service is required for the current TFTMAC runtime or acceptance path.

## Conservative graphics views

The automatic logger may construct per-window stack joins through
`graphics_run_id`, direct per-frame `stack_sha256`, frame-window linkage, and
the matching snapshot receipt. Its user-facing views are conservative: `TFT`
identifies exact SurfaceFlinger presentation and `PIPE` identifies controller
freshness/transport delivery. The final TFTMAC presenter is retained only as a
hidden correctness receipt. A report must use `UNKNOWN` when a trusted work
handoff is missing; current Build 8 evidence cannot identify an internal
graphics owner. CPU, RAM, thermal, power, and audio samples remain
health/correctness context only in this graphics-only optimization effort.
