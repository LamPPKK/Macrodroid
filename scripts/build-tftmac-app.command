#!/bin/zsh
set -euo pipefail

readonly ROOT="${0:A:h:h}"

# Compatibility entrypoint only. The old glob-compiled service-context app
# caused the ADB authorization regression and is not a build authority.
print -u2 "build-tftmac-app.command now delegates to the native Xcode build."
exec /bin/zsh "${ROOT}/scripts/build-native-app.command" "$@"
