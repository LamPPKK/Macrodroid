#!/bin/zsh
set -euo pipefail

readonly ROOT="${0:A:h:h}"

print -u2 "Building native Macrodroid application..."
exec /bin/zsh "${ROOT}/scripts/build-native-app.command" "$@"
