#!/bin/zsh
set -euo pipefail

readonly ROOT="${0:A:h:h}"
readonly VERSION="58.2"
readonly EXPECTED_SHA256="d29864d1ba3b36855527bb1b0ca3aa7f703cdce338b9680bb922c5c151b358fa"
readonly EXPECTED_BYTES="13597976"
readonly URL="https://commondatastorage.googleapis.com/perfetto-luci-artifacts/v${VERSION}/mac-arm64/trace_processor_shell"
readonly TOOL_DIRECTORY="${ROOT}/.build/tools/perfetto"
readonly TOOL="${TOOL_DIRECTORY}/trace_processor_shell-v${VERSION}-mac-arm64"

/bin/mkdir -p "${TOOL_DIRECTORY}"
if [[ -f "${TOOL}" ]]; then
  actual_sha="$(/usr/bin/shasum -a 256 "${TOOL}" | /usr/bin/awk '{print $1}')"
  actual_bytes="$(/usr/bin/stat -f '%z' "${TOOL}")"
  if [[ "${actual_sha}" == "${EXPECTED_SHA256}" && "${actual_bytes}" == "${EXPECTED_BYTES}" ]]; then
    /bin/chmod 755 "${TOOL}"
    print -r -- "${TOOL}"
    exit 0
  fi
fi

temporary="$(/usr/bin/mktemp "${TOOL_DIRECTORY}/trace_processor.XXXXXX")"
cleanup() { /bin/rm -f "${temporary}"; }
trap cleanup EXIT
/usr/bin/curl -fsSL "${URL}" -o "${temporary}"
actual_sha="$(/usr/bin/shasum -a 256 "${temporary}" | /usr/bin/awk '{print $1}')"
actual_bytes="$(/usr/bin/stat -f '%z' "${temporary}")"
[[ "${actual_sha}" == "${EXPECTED_SHA256}" ]] || {
  print -u2 "Perfetto trace_processor SHA-256 mismatch: ${actual_sha}"
  exit 1
}
[[ "${actual_bytes}" == "${EXPECTED_BYTES}" ]] || {
  print -u2 "Perfetto trace_processor size mismatch: ${actual_bytes}"
  exit 1
}
/bin/chmod 755 "${temporary}"
/bin/mv -f "${temporary}" "${TOOL}"
trap - EXIT
print -r -- "${TOOL}"
