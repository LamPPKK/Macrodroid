# Releasing TFTMAC

TFTMAC releases are native macOS application builds. The release process does not publish or redistribute Riot application packages.

## Release identity

```text
Application: TFTMAC
Bundle ID: com.flashls1.tftmac
Architecture: arm64
Minimum macOS: 15.0
```

The working Android SDK/AVD is runtime state outside the application bundle and repository.

## Pre-release validation

Run the source/CI contract on the exact release commit:

```sh
/bin/zsh scripts/verify-tftmac.command
```

Before any local install or package promotion, separately run:

```sh
/bin/zsh scripts/verify-installed-runtime.command
```

The second contract checks private local machine state and must never run in
GitHub CI. Also verify that the frozen EmulatorController protocol still matches
the intended stock emulator authority and that no private runtime artifacts are
tracked.

## Package authority

The application does not package or publish TFT APKs. The supported Android package is `com.riotgames.league.teamfighttactics`, installed and updated through `com.android.vending`. Riot owns its own content initialization after launch.

## Signing

Local builds use the stable `TFTMAC Local Code Signing` identity created once by
`scripts/ensure-local-signing-identity.command`. This lets macOS recognize
updated local builds as the same app and retain removable-volume consent. The
private key remains in the user's login Keychain and never enters Git. This
local identity is not a public distribution identity; public distribution still
requires Developer ID signing, hardened runtime, notarization, and stapling.

Current-host status (2026-08-31): Build 8 executable/host hashes match the
historical signed release, but the login keychain has zero valid local signing
identities and deep/strict verification reports `CSSMERR_TP_NOT_TRUSTED`.
Historical acceptance remains valid as historical evidence; a new release is
blocked until the identity is repaired and the installed-runtime verifier passes.

## Release evidence

Retain compact evidence for:

- exact source commit;
- native build/test result;
- bundle identity;
- stock emulator/protocol authority;
- package/installer identity when runtime acceptance is part of the release;
- acceptance result and rollback state.

Do not retain giant generated build trees as release authority.
