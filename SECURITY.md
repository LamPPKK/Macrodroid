# Security policy

Security fixes are handled on a best-effort basis for the current TFTMAC codebase.

## Reporting

Use GitHub Private Vulnerability Reporting or a private Security Advisory for the repository. Do not disclose an unpatched vulnerability in a public issue.

Include the affected commit/version, macOS version and architecture, impact, reproduction steps, and the smallest proof needed to demonstrate the issue. Explain whether the issue affects the native application, stock emulator control, local runtime state, package-authority checks, or diagnostics.

Sanitize logs before attaching them. Remove usernames, home paths, tokens, cookies, credentials, device identifiers, Google/Riot session data, and unrelated process output. Never attach an AVD image, raw game log, Keychain export, crash-memory dump, or private key.
