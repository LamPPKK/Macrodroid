# Changelog

## Unreleased

### Documentation

- Reconciled current Build 8 runtime, automatic-logging, and graphics-causality
  status across the human-readable project record.
- Recorded the latest 42m27s automatic graphics capture as performance evidence
  while retaining internal attribution as unknown.
- Archived obsolete launch/profile/source-build entrypoints under
  `docs/history/2026-08-31-pre-build8/` and replaced them with current pointers.

### Changed

- Split repository/CI verification from the local-only installed-runtime and
  signing audit; CI no longer depends on `/Applications`, an external runtime,
  a private signing identity, credentials, or captures.
- Updated GitHub checkout to `actions/checkout@v7.0.1` while retaining Node 24.
- Reconciled machine-readable runtime, retained-evidence, engineering-map, and
  performance-lab authority around stock Build 8 and the planned isolated
  causal logger.
- Separated historical Build 8 signing acceptance from the current-host
  `CSSMERR_TP_NOT_TRUSTED` audit and its missing login-keychain identity.
- Established TFTMAC as the sole product and repository identity.
- Replaced legacy validation with the native TFTMAC build/test verifier.
- Preserved the proven native AppKit/Metal Gate 1 implementation and frozen installed EmulatorController protocol.
- Removed obsolete launcher, hosted update/feed, helper-host, and branding layers.
- Moved runtime authority to the stock Google Android Emulator and official Google Play TFT lifecycle.
- Began relational migration of retained performance evidence to TFTMAC-owned identifiers.
- Retired source-built emulator work from the normal product path.

### Current target

- Native macOS application bundle: `com.flashls1.tftmac`.
- Stock Android Emulator 37.1.11.
- Official Google Play package `com.riotgames.league.teamfighttactics`.
- 1920x1080 / 60 Hz target on Apple Silicon.
