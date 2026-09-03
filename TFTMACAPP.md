# TFTMAC Native App Status

The native AppKit/Metal application is implemented and Build 8 is the current
normal-play authority. The application launches its packaged emulator host in
the logged-in macOS session, keeps the emulator window hidden, presents the
official Android client fullscreen, and uses authenticated local
EmulatorController control.

Current work is advanced graphics diagnosis, not a replacement of the native
app or a direct Node/Clara emulator launch. Build 8 logging is automatic and
verified; internal source-level causal attribution remains planned.

Current implementation truth is in [facts.md](facts.md), [project.md](project.md),
and [dev.md](dev.md). The former implementation plan is retained at
`docs/history/2026-08-31-pre-build8/TFTMACAPP.md` as historical design context.
