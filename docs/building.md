# Building TFTMAC

## Requirements

- Apple Silicon Mac
- macOS 15 or later
- Xcode 26.6
- zsh
- Node.js 24
- `jq` and `ripgrep`

The working stock Android runtime is external to the repository and is not rebuilt during normal native application compilation.

## Build

Repository/CI verification does not require an installed app, external runtime,
credentials, or signing identity. For an intentional local signed package,
create or repair TFTMAC's stable local-only signing identity first:

```sh
/bin/zsh scripts/ensure-local-signing-identity.command
```

The identity remains in the current user's login Keychain so macOS can retain
the removable-volume grant across changed local builds. It is not a Developer
ID and is not suitable for public distribution.

Current-host status (2026-08-31): the identity is absent, the installed Build 8
hashes still match their historical release receipt, and deep/strict trust
verification reports `CSSMERR_TP_NOT_TRUSTED`. Do not rebuild or re-sign the
playable app merely to make source verification pass.

```sh
/bin/zsh scripts/build-native-app.command
```

The Release application is produced under the ignored native build directory,
copied to `dist/TFTMAC.app`, and signed as `TFTMAC Local Code Signing`.

## Test

```sh
/bin/zsh scripts/test-native-app.command
```

The current native tests cover the Gate 1 viewport/input mapping contract and run on Apple Silicon macOS.

## Full validation

```sh
/bin/zsh scripts/verify-tftmac.command
```

Local installed/runtime/signing validation is separate and currently expected
to report the signing blocker:

```sh
/bin/zsh scripts/verify-installed-runtime.command
```

Validation checks:

- TFTMAC bundle identity;
- frozen EmulatorController protocol provenance/hash;
- pinned Swift package graph;
- retained script and JavaScript syntax;
- performance-lab and engineering-map self-tests;
- native Release build;
- native tests;
- Git whitespace integrity;
- no tracked private runtime artifacts.

A transient `TFTMAC_FORBIDDEN_TOKEN` may be supplied for the final ownership-completeness scan. The token itself must not be committed merely to test for its absence.

## Runtime data

Do not commit SDK packages, AVD userdata, Google/Riot credentials, tokens, APKs, runtime disks, logs containing sensitive data, or generated native build products.

The normal runtime root is `/Volumes/MAC MINI M4/TFTMAC/Runtime`. The application must not silently create bulk runtime/build state on the internal disk when the required external runtime authority is unavailable.
