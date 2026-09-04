# Historical Source-Build Plan

**Status: historical — do not execute as normal-play work.**

The former source-built AEMU plan is archived at
`docs/history/2026-08-31-pre-build8/TFTMAC_FULL_IMPLEMENTATION_PLAN.md`.

The stock Build 8 runtime is the normal-play authority. A separately isolated,
source-built `tftmac-runtime` diagnostic environment at commit `c8aa26e` is
eligible only for future causal instrumentation. It must never replace the
stock runtime or be compared directly with stock gameplay performance until
its independent correctness and parity gates pass.
