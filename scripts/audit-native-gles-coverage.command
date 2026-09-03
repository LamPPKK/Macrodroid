#!/bin/bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  audit-native-gles-coverage.command \
    --lib-unreal PATH \
    --guest-egl PATH \
    --guest-gles PATH \
    --guest-encoder PATH \
    [--gfxstream-source DIR] \
    [--host-egl PATH] [--host-gles PATH] \
    [--output PATH]

Builds a static GLES/EGL symbol-surface matrix for an Android Unreal library.
An absent export or generated entry is actionable; a present entry is only ABI
coverage and does not prove enum validation, caps, shader support, or behavior.
USAGE
}

LIB_UNREAL=""
GUEST_EGL=""
GUEST_GLES=""
GUEST_ENCODER=""
GFXSTREAM_SOURCE=""
HOST_EGL=""
HOST_GLES=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lib-unreal) LIB_UNREAL=${2:-}; shift 2 ;;
    --guest-egl) GUEST_EGL=${2:-}; shift 2 ;;
    --guest-gles) GUEST_GLES=${2:-}; shift 2 ;;
    --guest-encoder) GUEST_ENCODER=${2:-}; shift 2 ;;
    --gfxstream-source) GFXSTREAM_SOURCE=${2:-}; shift 2 ;;
    --host-egl) HOST_EGL=${2:-}; shift 2 ;;
    --host-gles) HOST_GLES=${2:-}; shift 2 ;;
    --output) OUTPUT=${2:-}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for required in "$LIB_UNREAL" "$GUEST_EGL" "$GUEST_GLES" "$GUEST_ENCODER"; do
  if [[ -z "$required" || ! -f "$required" ]]; then
    echo "required input is absent or not a file: ${required:-<empty>}" >&2
    exit 2
  fi
done
if [[ -n "$GFXSTREAM_SOURCE" && ! -d "$GFXSTREAM_SOURCE" ]]; then
  echo "gfxstream source is not a directory: $GFXSTREAM_SOURCE" >&2
  exit 2
fi
for optional in "$HOST_EGL" "$HOST_GLES"; do
  if [[ -n "$optional" && ! -f "$optional" ]]; then
    echo "optional host input is not a file: $optional" >&2
    exit 2
  fi
done

for dependency in strings awk sort comm jq rg file; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "required tool is unavailable: $dependency" >&2
    exit 2
  fi
done
NM_TOOL=$(xcrun --find llvm-nm 2>/dev/null || true)
if [[ -z "$NM_TOOL" || ! -x "$NM_TOOL" ]]; then
  echo "llvm-nm is unavailable through xcrun" >&2
  exit 2
fi

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tftmac-gles-audit.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

extract_exports() {
  local binary=$1
  local destination=$2
  local format
  format=$(file -b "$binary")
  if [[ "$format" == ELF* ]]; then
    "$NM_TOOL" -D --defined-only --format=posix "$binary"
  else
    "$NM_TOOL" --defined-only --format=posix "$binary"
  fi | awk '{name=$1; sub(/^_/, "", name); if (name ~ /^(egl|gl)[A-Z][A-Za-z0-9_]*$/) print name}' \
    | LC_ALL=C sort -u >"$destination"
}

"$NM_TOOL" -D --undefined-only --format=posix "$LIB_UNREAL" \
  | awk '$1 ~ /^(egl|gl)[A-Z][A-Za-z0-9_]*$/ {print $1}' \
  | LC_ALL=C sort -u >"$WORK_DIR/direct.txt"
strings -a "$LIB_UNREAL" \
  | awk '/^(egl|gl)[A-Z][A-Za-z0-9_]*$/ {print}' \
  | LC_ALL=C sort -u >"$WORK_DIR/strings.txt"
LC_ALL=C sort -u "$WORK_DIR/direct.txt" "$WORK_DIR/strings.txt" >"$WORK_DIR/all.txt"
comm -23 "$WORK_DIR/all.txt" "$WORK_DIR/direct.txt" >"$WORK_DIR/dynamic.txt"

extract_exports "$GUEST_EGL" "$WORK_DIR/guest-egl.txt"
extract_exports "$GUEST_GLES" "$WORK_DIR/guest-gles.txt"
LC_ALL=C sort -u "$WORK_DIR/guest-egl.txt" "$WORK_DIR/guest-gles.txt" \
  >"$WORK_DIR/guest-public.txt"
extract_exports "$GUEST_ENCODER" "$WORK_DIR/guest-encoder.txt"
while IFS= read -r symbol; do
  normalized=$(printf '%s\n' "$symbol" \
    | sed -E 's/(ANDROID|ANGLE|AEMU|EXT|KHR|OES|QCOM|OVR|NV|IMG)$//')
  printf '%s\t%s\n' "$normalized" "$symbol"
done <"$WORK_DIR/guest-encoder.txt" >"$WORK_DIR/guest-encoder-normalized.tsv"

: >"$WORK_DIR/host.txt"
if [[ -n "$HOST_EGL" ]]; then
  extract_exports "$HOST_EGL" "$WORK_DIR/host-egl.txt"
fi
if [[ -n "$HOST_GLES" ]]; then
  extract_exports "$HOST_GLES" "$WORK_DIR/host-gles.txt"
fi
LC_ALL=C sort -u "$WORK_DIR"/host-*.txt 2>/dev/null >"$WORK_DIR/host.txt" || true

: >"$WORK_DIR/upstream-protocol.txt"
: >"$WORK_DIR/upstream-dispatch.txt"
if [[ -n "$GFXSTREAM_SOURCE" ]]; then
  rg -o --no-filename 'gl[A-Z][A-Za-z0-9_]*' \
    "$GFXSTREAM_SOURCE/codegen/gles2" 2>/dev/null \
    | LC_ALL=C sort -u >"$WORK_DIR/upstream-protocol.txt" || true
  rg -o --no-filename 'gl[A-Z][A-Za-z0-9_]*' \
    "$GFXSTREAM_SOURCE/host/gl/OpenGLESDispatch"/*.entries 2>/dev/null \
    | LC_ALL=C sort -u >"$WORK_DIR/upstream-dispatch.txt" || true
fi

contains() {
  grep -Fqx "$1" "$2"
}

: >"$WORK_DIR/rows.tsv"
while IFS= read -r symbol; do
  source_kind=dynamic
  contains "$symbol" "$WORK_DIR/direct.txt" && source_kind=direct
  guest_public=false
  guest_encoder=false
  upstream_protocol=null
  upstream_dispatch=null
  host_export=null
  guest_encoder_aliases=""
  contains "$symbol" "$WORK_DIR/guest-public.txt" && guest_public=true
  contains "$symbol" "$WORK_DIR/guest-encoder.txt" && guest_encoder=true
  if [[ -n "$GFXSTREAM_SOURCE" && "$symbol" == gl* ]]; then
    upstream_protocol=false
    upstream_dispatch=false
    contains "$symbol" "$WORK_DIR/upstream-protocol.txt" && upstream_protocol=true
    contains "$symbol" "$WORK_DIR/upstream-dispatch.txt" && upstream_dispatch=true
  fi
  if [[ -n "$HOST_EGL" || -n "$HOST_GLES" ]]; then
    host_export=false
    contains "$symbol" "$WORK_DIR/host.txt" && host_export=true
  fi
  if [[ "$symbol" == gl* ]]; then
    normalized=$(printf '%s\n' "$symbol" \
      | sed -E 's/(ANDROID|ANGLE|AEMU|EXT|KHR|OES|QCOM|OVR|NV|IMG)$//')
    guest_encoder_aliases=$(awk -F '\t' -v key="$normalized" \
      '$1 == key {if (result != "") result=result ","; result=result $2} END {print result}' \
      "$WORK_DIR/guest-encoder-normalized.tsv")
  fi

  status=covered_symbol_surface
  if [[ "$guest_public" != true ]]; then
    if [[ "$source_kind" == direct ]]; then
      status=missing_guest_public_export
    elif [[ -n "$guest_encoder_aliases" ]]; then
      status=dynamic_alias_resolution_required
    else
      status=dynamic_name_absent_from_guest_exports
    fi
  elif [[ "$symbol" == gl* && "$guest_encoder" != true ]]; then
    status=missing_guest_encoder_export
  elif [[ "$symbol" == gl* && "$upstream_protocol" == false ]]; then
    status=missing_upstream_protocol_entry
  elif [[ "$symbol" == gl* && "$upstream_dispatch" == false ]]; then
    status=missing_upstream_dispatch_entry
  elif [[ "$host_export" == false ]]; then
    status=missing_host_export
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$symbol" "$source_kind" "$guest_public" "$guest_encoder" \
    "$upstream_protocol" "$upstream_dispatch" "$host_export" \
    "$guest_encoder_aliases" "$status" \
    >>"$WORK_DIR/rows.tsv"
done <"$WORK_DIR/all.txt"

jq -Rn '[inputs | split("\t") | {
    name: .[0],
    reference: .[1],
    guest_public_export: (.[2] == "true"),
    guest_encoder_export: (.[3] == "true"),
    upstream_protocol_entry: (if .[4] == "null" then null else .[4] == "true" end),
    upstream_dispatch_entry: (if .[5] == "null" then null else .[5] == "true" end),
    host_export: (if .[6] == "null" then null else .[6] == "true" end),
    guest_encoder_alias_candidates: (if .[7] == "" then [] else .[7] | split(",") end),
    status: .[8]
  }]' <"$WORK_DIR/rows.tsv" >"$WORK_DIR/entries.json"

jq -n \
  --arg lib_unreal "$LIB_UNREAL" \
  --arg guest_egl "$GUEST_EGL" \
  --arg guest_gles "$GUEST_GLES" \
  --arg guest_encoder "$GUEST_ENCODER" \
  --arg gfxstream_source "$GFXSTREAM_SOURCE" \
  --arg host_egl "$HOST_EGL" \
  --arg host_gles "$HOST_GLES" \
  --slurpfile entries "$WORK_DIR/entries.json" '
  ($entries[0]) as $rows |
  {
    schema: 1,
    caveat: "Static symbol coverage is necessary but not sufficient; it does not prove caps, enum validation, protocol semantics, shader support, or runtime behavior.",
    inputs: {
      lib_unreal: $lib_unreal,
      guest_egl: $guest_egl,
      guest_gles: $guest_gles,
      guest_encoder: $guest_encoder,
      gfxstream_source: (if $gfxstream_source == "" then null else $gfxstream_source end),
      host_egl: (if $host_egl == "" then null else $host_egl end),
      host_gles: (if $host_gles == "" then null else $host_gles end)
    },
    summary: {
      total_referenced: ($rows | length),
      direct_imports: ($rows | map(select(.reference == "direct")) | length),
      dynamic_names: ($rows | map(select(.reference == "dynamic")) | length),
      by_status: ($rows | group_by(.status) | map({key: .[0].status, value: length}) | from_entries)
    },
    entries: $rows
  }' >"$WORK_DIR/report.json"

if [[ -n "$OUTPUT" ]]; then
  mkdir -p "$(dirname "$OUTPUT")"
  cp "$WORK_DIR/report.json" "$OUTPUT"
  echo "$OUTPUT"
else
  cat "$WORK_DIR/report.json"
fi
