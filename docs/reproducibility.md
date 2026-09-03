# Reproducibility

TFTMAC separates versioned source authority from mutable runtime state.

## Versioned authority

The repository retains:

- native Xcode project and source;
- tests and validation scripts;
- `Package.resolved`;
- the exact installed EmulatorController protocol snapshot;
- compact runtime/performance evidence and relational SSOT data.

The current protocol authority is recorded in `Vendor/AndroidEmulator/SOURCE.json` and must match `Vendor/AndroidEmulator/emulator_controller.proto` byte-for-byte.

## Mutable runtime state

The repository does not contain:

- Google/Riot credentials or tokens;
- AVD userdata;
- Riot APKs or application data;
- SDK/runtime disk images;
- private session state;
- generated native build products.

The normal runtime root is `/Volumes/MAC MINI M4/TFTMAC/Runtime`.

## Verification

```sh
/bin/zsh scripts/verify-tftmac.command
```

For runtime acceptance, retain the exact emulator version, AVD identity, package version/code, installer authority, signer evidence, selected runtime profile, and compact telemetry/capture hashes used for the decision.

Performance claims require the same workload and configuration on both sides of an A/B comparison. Promising results are cold-confirmed before promotion.
