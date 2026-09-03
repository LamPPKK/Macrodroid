# Macrodroid

Macrodroid is a native macOS application that launches and presents the official
Android clients and mobile games (optimized for Teamfight Tactics) through Google's
stock Android Emulator on Apple Silicon using an embedded Metal presentation layer.

## Current status

- **Product Target**: Macrodroid (Native AppKit + MetalKit Client).
- **Presentation Architecture**: Pure native window with embedded MetalKit presentation layer, authenticated loopback gRPC (`EmulatorController`), and headless Android Emulator.
- **Input Pipeline**: Zero-delay touch mapping from AppKit cursor to Android multi-touch coordinates.
- **Telemetry & Logging**: Continuous graphics and combat telemetry stored in a local SQLite database under `~/Library/Application Support/Macrodroid`.
- **Integrity**: Zero game APK binary modification; official Google Play and Riot authentication flows.

Read [README.md](README.md) first, then [facts.md](facts.md), [benchmark.md](benchmark.md), [dev.md](dev.md), and [project.md](project.md).
