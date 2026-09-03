# Contributing

Keep TFTMAC changes narrow, testable, and aligned with the current stock-runtime architecture.

## Development setup

Use an Apple Silicon Mac with macOS 15 or later, Xcode 26.6, zsh, Node.js 24, `jq`, and `ripgrep`. Runtime and game data must remain outside Git.

Run before opening a pull request:

```sh
/bin/zsh scripts/verify-tftmac.command
```

## Rules

- Preserve `com.flashls1.tftmac` as the application identity.
- Preserve the stock Google Android Emulator as runtime authority unless a separately approved measured blocker requires a different architecture.
- Do not add Riot APKs, credentials, Android userdata, tokens, runtime disks, or private session data to the repository.
- Do not add hosted game feeds, APK repacking, re-signing, or binary patching.
- Keep generated build output out of Git.
- Update tests and documentation when behavior changes.
- Keep performance claims tied to reproducible captures and explicit KEEP/REJECT evidence.
- Preserve rollback and fail-closed behavior around runtime mutation.

UI work should include appropriate validation evidence. Runtime work should state the exact owning boundary and failure mode it changes.
