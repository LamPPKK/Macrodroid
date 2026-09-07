#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

readonly ROOT="${0:A:h:h}"
cd "$ROOT"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  elif [[ -d /Applications/Xcode-26.6.0.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
  else
    export DEVELOPER_DIR="$(xcode-select -p)"
  fi
fi

if ! command -v swiftlint >/dev/null 2>&1; then
  print -u2 "swiftlint is not installed or not in PATH"
  exit 1
fi

print "Running SwiftLint on Macrodroid codebase..."
swiftlint lint "$@"
