#!/bin/zsh
set -euo pipefail
readonly ROOT="${0:A:h:h}"
exec "$ROOT/scripts/automate-test-all.command" "$@"
