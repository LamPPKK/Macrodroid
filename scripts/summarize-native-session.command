#!/bin/zsh
# Summarize one native TFTMAC capture without exposing raw guest/emulator logs.
set -euo pipefail

readonly SQLITE3_BIN="${TFT_SQLITE3:-$(command -v sqlite3 2>/dev/null || true)}"
readonly CAPTURE_ROOT_INPUT="${TFTMAC_CAPTURE_ROOT:-$HOME/Library/Application Support/TFTMAC/Captures}"

fail() {
    print -u2 -- "$*"
    exit 1
}

canonical_directory() {
    [[ -d "$1" ]] || return 1
    (cd "$1" && pwd -P)
}

[[ -n "$SQLITE3_BIN" && -x "$SQLITE3_BIN" ]] || fail "sqlite3 is required to summarize a native TFTMAC session."
readonly CAPTURE_ROOT="$(canonical_directory "$CAPTURE_ROOT_INPUT")" \
    || fail "Capture root does not exist: $CAPTURE_ROOT_INPUT"

typeset capture_input
if (( $# > 1 )); then
    fail "Usage: ${0:t} [capture-directory]"
elif (( $# == 1 )); then
    capture_input="$1"
else
    typeset -a captures
    captures=("$CAPTURE_ROOT"/*(N/om[1]))
    (( ${#captures} > 0 )) || fail "No capture directories were found under $CAPTURE_ROOT"
    capture_input="$captures[1]"
fi

readonly CAPTURE_DIR="$(canonical_directory "$capture_input")" \
    || fail "Capture directory does not exist: $capture_input"
if [[ "$CAPTURE_DIR" != "$CAPTURE_ROOT" && "$CAPTURE_DIR" != "$CAPTURE_ROOT"/* ]]; then
    fail "Capture directory must be inside $CAPTURE_ROOT"
fi

readonly DATABASE="$CAPTURE_DIR/TFTMAC_NATIVE_RUNTIME.sqlite"
[[ -f "$DATABASE" ]] || fail "Missing TFTMAC_NATIVE_RUNTIME.sqlite in $CAPTURE_DIR"

sql() {
    "$SQLITE3_BIN" -readonly -noheader -batch "$DATABASE" "$1"
}

table_exists() {
    [[ "$(sql "SELECT count(*) FROM sqlite_master WHERE type='table' AND name=$(sql_quote "$1");")" == "1" ]]
}

sql_quote() {
    local value="$1"
    value="${value//\'/\'\'}"
    print -r -- "'$value'"
}

has_column() {
    local table="$1" column="$2"
    [[ "$(sql "SELECT count(*) FROM pragma_table_info($(sql_quote "$table")) WHERE name=$(sql_quote "$column");")" == "1" ]]
}

first_column() {
    local table="$1"
    shift
    local candidate
    for candidate in "$@"; do
        if has_column "$table" "$candidate"; then
            print -r -- "$candidate"
            return 0
        fi
    done
    return 1
}

column_or_null() {
    local table="$1"
    shift
    local column
    column="$(first_column "$table" "$@" 2>/dev/null || true)"
    [[ -n "$column" ]] && print -r -- "\"$column\"" || print -r -- "NULL"
}

print_table_coverage() {
    local table="$1" time_column rows earliest latest
    if ! table_exists "$table"; then
        print "  $table: UNAVAILABLE (this app version did not create the table)"
        return
    fi
    rows="$(sql "SELECT count(*) FROM \"$table\";")"
    time_column="$(first_column "$table" observed_utc started_utc ended_utc sampled_utc created_utc timestamp_utc started_monotonic_ns sampled_monotonic_ns monotonic_ns 2>/dev/null || true)"
    if [[ -z "$time_column" ]]; then
        print "  $table: rows=$rows coverage=timestamp-column-unavailable"
        return
    fi
    earliest="$(sql "SELECT COALESCE(min(\"$time_column\"), '—') FROM \"$table\";")"
    latest="$(sql "SELECT COALESCE(max(\"$time_column\"), '—') FROM \"$table\";")"
    print "  $table: rows=$rows coverage=$earliest .. $latest"
}

print_section() {
    print ""
    print "$1"
}

print "TFTMAC native-session report"
print "capture=$CAPTURE_DIR"
print "database=$DATABASE"
print "generated_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

readonly INTEGRITY="$(sql 'PRAGMA integrity_check;' | tr '\n' ' ')"
readonly QUICK="$(sql 'PRAGMA quick_check;' | tr '\n' ' ')"
print "integrity_check=$INTEGRITY"
print "quick_check=$QUICK"
[[ "$INTEGRITY" == "ok " && "$QUICK" == "ok " ]] || fail "Database integrity check failed; report stopped."

print_section "Coverage"
for table in sessions runtime_receipts events presentation_samples frame_interval_windows \
    game_frame_windows game_frame_intervals stream_freshness_windows \
    host_presentation_windows resource_samples guest_memory_samples \
    surfaceflinger_samples audio_samples logcat_aggregates pipeline_log_aggregates \
    graphics_pipeline_snapshots diagnostic_artifacts; do
    print_table_coverage "$table"
done

print_section "Guest TFT frame truth (SurfaceFlinger timing)"
if table_exists game_frame_windows; then
    readonly GUEST_LOW="$(column_or_null game_frame_windows rolling_1pct_low_fps one_percent_low_fps one_percent_low)"
    readonly GUEST_P95="$(column_or_null game_frame_windows p95_interval_ms p95_ms)"
    readonly GUEST_P99="$(column_or_null game_frame_windows p99_interval_ms p99_ms)"
    readonly GUEST_MAX="$(column_or_null game_frame_windows maximum_interval_ms max_interval_ms max_ms)"
    readonly GUEST_JANK="$(column_or_null game_frame_windows jank_count janky_frames)"
    readonly GUEST_SEVERE="$(column_or_null game_frame_windows severe_count severe_frames)"
    readonly GUEST_MISSED="$(column_or_null game_frame_windows missed_vsync_equivalents missed_vsync_count missed_vsyncs)"
    readonly GUEST_ORDER="$(first_column game_frame_windows rolling_1pct_low_fps one_percent_low_fps p99_interval_ms maximum_interval_ms started_monotonic_ns 2>/dev/null || true)"
    if [[ -n "$GUEST_ORDER" ]]; then
        sql "SELECT '  worst window: 1%-low=' || COALESCE(CAST($GUEST_LOW AS TEXT), '—') ||
             ' p95ms=' || COALESCE(CAST($GUEST_P95 AS TEXT), '—') ||
             ' p99ms=' || COALESCE(CAST($GUEST_P99 AS TEXT), '—') ||
             ' maxms=' || COALESCE(CAST($GUEST_MAX AS TEXT), '—') ||
             ' jank=' || COALESCE(CAST($GUEST_JANK AS TEXT), '—') ||
             ' severe=' || COALESCE(CAST($GUEST_SEVERE AS TEXT), '—') ||
             ' missed-vsync=' || COALESCE(CAST($GUEST_MISSED AS TEXT), '—')
             FROM game_frame_windows
             WHERE status = 'AVAILABLE'
             ORDER BY \"$GUEST_ORDER\" ASC LIMIT 1;" || true
    else
        print "  telemetry rows exist, but the expected frame-window fields are unavailable"
    fi
else
    print "  UNAVAILABLE: no game_frame_windows table; SRC/OUT must not be treated as TFT FPS."
fi

print_section "Transport freshness and Mac presentation"
if table_exists stream_freshness_windows; then
    readonly FREEZE_COL="$(column_or_null stream_freshness_windows longest_identical_run_ms longest_static_run_ms freeze_ms)"
    readonly IDENTICAL_COL="$(column_or_null stream_freshness_windows identical_frames repeated_frames)"
    print "  worst stream freeze_ms=$(sql "SELECT COALESCE(max($FREEZE_COL), '—') FROM stream_freshness_windows;") identical_frames=$(sql "SELECT COALESCE(sum($IDENTICAL_COL), '—') FROM stream_freshness_windows;")"
else
    print "  stream freshness: UNAVAILABLE"
fi
if table_exists host_presentation_windows; then
    readonly HOST_GPU_P95="$(column_or_null host_presentation_windows p95_gpu_time_ms gpu_p95_ms p95_gpu_ms)"
    readonly HOST_ERRORS="$(column_or_null host_presentation_windows command_errors command_error_count errors)"
    readonly HOST_MISSES="$(column_or_null host_presentation_windows drawable_miss_count drawable_misses)"
    print "  host Metal: gpu_p95ms=$(sql "SELECT COALESCE(max($HOST_GPU_P95), '—') FROM host_presentation_windows;") errors=$(sql "SELECT COALESCE(sum($HOST_ERRORS), '—') FROM host_presentation_windows;") drawable_misses=$(sql "SELECT COALESCE(sum($HOST_MISSES), '—') FROM host_presentation_windows;")"
else
    print "  host Metal timing: UNAVAILABLE"
fi

print_section "Resources and graphics-pipeline signals"
if table_exists resource_samples; then
    readonly CPU_COL="$(column_or_null resource_samples emulator_cpu_percent cpu_percent)"
    readonly RSS_COL="$(column_or_null resource_samples emulator_rss_kib rss_kib)"
    print "  emulator CPU peak=$(sql "SELECT COALESCE(max($CPU_COL), '—') FROM resource_samples;")% RSS peak KiB=$(sql "SELECT COALESCE(max($RSS_COL), '—') FROM resource_samples;")"
else
    print "  resources: UNAVAILABLE"
fi
if table_exists guest_memory_samples; then
    readonly AVAILABLE_MEM_COL="$(column_or_null guest_memory_samples available_kib mem_available_kib)"
    readonly SWAP_FREE_COL="$(column_or_null guest_memory_samples swap_free_kib)"
    print "  guest memory: minimum_available_kib=$(sql "SELECT COALESCE(min($AVAILABLE_MEM_COL), '—') FROM guest_memory_samples;") minimum_swap_free_kib=$(sql "SELECT COALESCE(min($SWAP_FREE_COL), '—') FROM guest_memory_samples;")"
else
    print "  guest memory: UNAVAILABLE"
fi
if table_exists pipeline_log_aggregates; then
    readonly GFX_COL="$(column_or_null pipeline_log_aggregates gfxstream_warning_count gfxstream_warnings)"
    readonly ASG_COL="$(column_or_null pipeline_log_aggregates asg_stall_count asg_stalls)"
    readonly VK_COL="$(column_or_null pipeline_log_aggregates vulkan_error_count vulkan_errors)"
    readonly MVK_COL="$(column_or_null pipeline_log_aggregates moltenvk_warning_count moltenvk_warnings)"
    readonly SHADER_COL="$(column_or_null pipeline_log_aggregates shader_error_count shader_errors)"
    readonly FENCE_COL="$(column_or_null pipeline_log_aggregates fence_timeout_count fence_timeouts)"
    print "  pipeline aggregate: gfxstream_warn=$(sql "SELECT COALESCE(sum($GFX_COL), '—') FROM pipeline_log_aggregates;") asg_stall=$(sql "SELECT COALESCE(sum($ASG_COL), '—') FROM pipeline_log_aggregates;") vulkan_error=$(sql "SELECT COALESCE(sum($VK_COL), '—') FROM pipeline_log_aggregates;") mvk_warn=$(sql "SELECT COALESCE(sum($MVK_COL), '—') FROM pipeline_log_aggregates;") shader_error=$(sql "SELECT COALESCE(sum($SHADER_COL), '—') FROM pipeline_log_aggregates;") fence_timeout=$(sql "SELECT COALESCE(sum($FENCE_COL), '—') FROM pipeline_log_aggregates;")"
else
    print "  pipeline aggregates: UNAVAILABLE (raw logs are intentionally not printed)"
fi
if table_exists graphics_pipeline_snapshots; then
    sql "SELECT '  latest stack evidence: TFT-surface=' || tft_surface_state ||
         ' ANGLE=' || angle_state || ' gfxstream=' || gfxstream_state ||
         ' MoltenVK=' || moltenvk_state || ' host-device=' || COALESCE(host_vulkan_device, '—')
         FROM graphics_pipeline_snapshots ORDER BY monotonic_ns DESC LIMIT 1;" || true
else
    print "  graphics pipeline identity: UNAVAILABLE"
fi

print_section "Markers, incidents, and diagnostic artifacts"
if table_exists events; then
    readonly EVENT_KIND="$(first_column events event_type kind name 2>/dev/null || true)"
    if [[ -n "$EVENT_KIND" ]]; then
        print "  events_total=$(sql 'SELECT count(*) FROM events;') incident_like=$(sql "SELECT count(*) FROM events WHERE upper(\"$EVENT_KIND\") LIKE '%INCIDENT%' OR upper(\"$EVENT_KIND\") LIKE '%STUTTER%' OR upper(\"$EVENT_KIND\") LIKE '%DEGRAD%';")"
    else
        print "  events_total=$(sql 'SELECT count(*) FROM events;')"
    fi
else
    print "  events: UNAVAILABLE"
fi
if table_exists diagnostic_artifacts; then
    print "  diagnostic_artifacts=$(sql 'SELECT count(*) FROM diagnostic_artifacts;') (artifact paths and trace contents withheld)"
else
    print "  diagnostic artifacts: UNAVAILABLE"
fi

print_section "Explicit telemetry gaps"
typeset -a gaps
gaps=()
for table in game_frame_windows game_frame_intervals stream_freshness_windows host_presentation_windows pipeline_log_aggregates graphics_pipeline_snapshots diagnostic_artifacts; do
    table_exists "$table" || gaps+=("$table")
done
if (( ${#gaps} == 0 )); then
    print "  No required telemetry table is missing. Empty rows still mean no sampled evidence for that layer."
else
    print "  Missing tables: ${(j:, :)gaps}"
fi
if table_exists game_frame_windows && [[ "$(sql 'SELECT count(*) FROM game_frame_windows;')" == "0" ]]; then
    print "  Guest frame table has no rows: no evidence yet for real TFT combat FPS."
fi
print "  This report deliberately excludes raw logcat/emulator text, credentials, and tokens."
