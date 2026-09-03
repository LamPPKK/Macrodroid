# TFTMAC Benchmark and Analysis Contract

**Authority date:** 2026-08-31 America/Chicago
**Formula version:** `tftmac-benchmark-v2`
**Current installed runtime:** TFTMAC 2.3.0 build 8 on the M4 Mac mini; automatic graphics lifecycle and complete stack receipts live-verified, including a 42m27s automatic graphics run
**Purpose:** give a developer or AI agent one exact, reproducible process for turning TFTMAC session data into findings, comparisons, decisions, and explicit unknowns.

This file is the current benchmark-analysis authority. `docs/benchmarks.md` is
the historical M1 Max/userdebug experiment ledger; it must not be mistaken for
current M4 native-runtime evidence. Machine/runtime facts live in `facts.md`,
project history in `project.md`, and active engineering hypotheses in `dev.md`.

## 1. Answer and operating decision

Before this file, the analysis process existed but was split across source,
`facts.md`, `project.md`, `dev.md`, telemetry documentation, SQL tables, and the
historical campaign record. An agent could find the pieces, but it did not have
one complete input/formula/output contract. This file closes that documentation
gap.

TFTMAC recognizes five evidence modes:

| Mode | Meaning | Authority |
| --- | --- | --- |
| `FULL_RUN` | A complete automatically observed TFT process/layer lifetime | Primary evidence for continuous FPS, complete workload, sustained pressure, correctness, and promotion to normal play; user markers are optional annotations |
| `GRAPHICS_RUN` | Automatically observed TFT process/layer lifetime from start through process/app close | The SQL lifecycle identity used by a full run; no battle classifier or user marker is required |
| `BOUNDED_AB` | A 300–480 second continuous-gameplay window under one named preset | Fast controlled screening of one candidate against a compatible Control; currently implemented by the UI/source named Combat Benchmark |
| `DIAGNOSTIC_ONLY` | Launch, login, lobby, unmarked gameplay, partial capture, or isolated incident | Useful for diagnosis; cannot prove full-run performance or promote a candidate |
| `INVALID` | Missing/corrupt boundaries, inadequate coverage, changed identity, correctness failure, or other declared invalidator | Retain as negative/operational evidence; do not use for a positive performance claim |

Full runs are preferred because they include the complete performance envelope,
not a hand-selected scene. Every logged frame and resource/pipeline sample
inside the automatic process/layer lifecycle participates. A bounded A/B
remains useful because it produces a faster controlled answer. It does not
require any semantic phase label. A short winner is not promoted until it also
survives a complete automatic full run. A full run can immediately veto a
candidate for correctness or player experience.

A lobby, a reported `SRC 60`, an `OUT 60`, a successful launch, or an emulator
process is never a gameplay benchmark.

The graphics-only optimization equation is limited to direct graphics cadence,
tail latency, missed-vsync/severe behavior, source freshness, stack receipts,
and conservative owned-boundary joins. The final native presenter is hidden
correctness context only. CPU, RAM, thermal,
power, and audio may invalidate correctness or explain health context, but are
not optimization variables or a substitute graphics owner in this contract.

## 2. Evidence and claim discipline

Every finding must contain these fields:

```text
claim       narrow statement supported by the evidence
evidence    session/benchmark IDs, tables, time range, and calculated values
confidence  DIRECT | CORRELATED | INFERRED | USER | UNKNOWN
unknowns    unmeasured or invalid boundaries
decision    KEEP | REJECT | PROMISING | INCONCLUSIVE | NO_DECISION
```

The labels mean:

- `DIRECT`: the claimed value exists in current raw/normalized evidence or is a
  deterministic calculation from it.
- `CORRELATED`: two signals are time-aligned closely enough to establish
  ordering or co-occurrence, but not sole cause.
- `INFERRED`: the evidence supports a hypothesis but does not observe the
  claimed internal boundary directly.
- `USER`: the player directly reported experience or correctness. This is
  decisive for playability and not sufficient for internal root cause.
- `UNKNOWN`: the current capture cannot support the claim.

Mandatory rules:

1. Exact SurfaceFlinger actual-present intervals for the semantic TFT Unreal
   `SurfaceView` are guest gameplay-cadence authority.
2. `SRC` is distinct completed controller images. `OUT` is TFTMAC's final Metal
   presentation cadence. Neither is Unreal FPS.
3. A fast final presenter can repeatedly present an old source frame. It is not
   a current graphics root-cause candidate and is omitted from causal ranking.
4. Requested configuration, effective receipt, and observed outcome are three
   separate facts.
5. A guest-frame stall does not identify Unreal, ANGLE, ASG/gfxstream,
   MoltenVK, Metal, or TFTMAC as its cause.
6. Cross-host ordering requires valid clock evidence. A trace does not repair a
   bad clock relationship.
7. Never use an average to erase 1% low, p95/p99, severe stalls, any sustained
   under-60 period, or direct player rejection.
8. Never inspect or report credentials, typed text, tokens, cookies, PINs,
   CAPTCHA/MFA values, login screenshots, or raw frame payloads.

## 3. Canonical inputs and read order for an AI agent

An agent analyzing a TFTMAC run reads, in order:

1. `facts.md` for the immutable/current machine, product, security, and runtime
   boundaries.
2. This `benchmark.md` for evidence modes, formulas, validity, SQL, and output
   shape.
3. `dev.md` for the active Control, candidate, negative-result ledger, and
   hypotheses.
4. The selected session's `TFTMAC_NATIVE_RUNTIME.sqlite` as raw session
   authority.
5. `TFTMAC_LAB.sqlite` only for durable benchmark/comparison history.
6. Raw sidecars or traces only when the requested causal question requires them
   and their hash/processor/privacy receipts are valid.

Per-session authority:

```text
~/Library/Application Support/TFTMAC/Captures/<session-id>/
  TFTMAC_NATIVE_RUNTIME.sqlite
```

Persistent comparison authority:

```text
~/Library/Application Support/TFTMAC/TFTMAC_LAB.sqlite
```

Before calculation, create an analysis manifest:

```json
{
  "analysis_schema": "tftmac.benchmark-report.v1",
  "formula_version": "tftmac-benchmark-v2",
  "evidence_mode": "FULL_RUN|BOUNDED_AB|DIAGNOSTIC_ONLY|INVALID",
  "session_id": "<session UUID>",
  "session_database": "<absolute local path>",
  "profile_id": "<effective profile>",
  "configuration_sha256": "<effective configuration hash or UNKNOWN>",
  "comparison_identity_sha256": "<comparison hash or NOT_APPLICABLE>",
  "tft_package_version": "<observed version>",
  "source_commit": "<Git commit used to interpret formulas>",
  "start_event_id": 0,
  "end_event_id": 0,
  "start_monotonic_ns": 0,
  "end_monotonic_ns": 0,
  "analysis_created_utc": "<UTC>"
}
```

If any field is unavailable, write `UNKNOWN` or `null`; do not guess it from a
different session.

## 4. SQL data dictionary

| Table | Meaning | Analysis use |
| --- | --- | --- |
| `sessions` | app-run identity, profile, lifecycle | top-level session authority |
| `runtime_receipts` | requested/effective runtime facts | configuration and version proof |
| `events` | explicit lifecycle/user/app boundaries | full-run, benchmark, stutter, process, and failure segmentation |
| `game_frame_intervals` | exact TFT actual-present deltas | authoritative FPS/tail calculations |
| `game_frame_windows` | one-second gameplay summaries and availability | incident/worst-window discovery and coverage |
| `stream_freshness_windows` | received, changed, identical, and lost controller frames | distinguish upstream freshness from final output |
| `host_presentation_windows` | Metal submit/complete/reuse/error/latency/GPU time | hidden final-presenter correctness/regression context only |
| `presentation_samples` | cumulative/instant source/output behavior | hidden transport/presenter correctness trend |
| `resource_samples` | QEMU CPU/RSS, TFT PID, foreground activity | host-emulator load and process continuity |
| `guest_memory_samples` | guest available memory and swap | Android pressure trajectory |
| `host_resource_samples` | host memory/compression/swap/pageouts/thermal/power | Mac pressure and comparability |
| `clock_sync_samples` | host midpoint, guest uptime, RTT, offset | cross-boundary eligibility |
| `surfaceflinger_samples` | render rate and cumulative miss counters | deltas between valid explicit boundaries only |
| `audio_samples` | backend, active output, rate, stereo, tracks, underruns | audio correctness evidence |
| `logcat_aggregates` | bounded sanitized ANR/fatal/LMK/renderer/audio counts | failure-class evidence, not sole cause |
| `pipeline_log_aggregates` | gfxstream/ASG/Vulkan/MoltenVK/shader/fence signals | named warning/failure evidence, not proof of absence |
| `graphics_pipeline_snapshots` | effective layer/API/renderer state | comparable-path gate |
| `graphics_runs` | automatic TFT process/layer lifetime, configuration SHA, target FPS, and start/end reason | base graphics scope and lifecycle continuity |
| `graphics_pipeline_incidents` | automatic exact-layer degradation, trace link, conservative first boundary, explicit unknowns | incident triage, never a battle classification |
| `diagnostic_artifacts` | trace path/hash/processor/normalization | bounded causal evidence |
| `combat_benchmarks` | finalized bounded-window identity/validity/metrics | controlled `BOUNDED_AB` result; table name is retained from the implementation |
| `combat_incidents` | bad-window trigger, trace, boundary/unknowns | incident analysis |
| `combat_comparisons` | Control/candidate deltas and code decision | controlled A/B output |
| `game_process_sessions` | TFT PID lifetime | restart and process-stability evidence |

The current source schema also stores canonical stack-receipt JSON/SHA-256 on
each graphics snapshot and joins intervals to their containing frame window
where available. Build 8 automatic captures **runtime-verify** this schema and
receipt linkage. The SHA proves receipt identity, not that every row shares a
trusted cross-process work ID.

## 5. Time domains and legal joins

TFTMAC data contains different clocks. They must not be joined as though they
were the same number.

### Host monotonic clock

`events.monotonic_ns`, `game_frame_windows.started_monotonic_ns`, resource
samples, stream/presenter windows, and most SQL sampling boundaries use the host
monotonic clock. Use this clock for automatic lifecycle boundaries, optional
annotations, and ordinary same-host overlap joins.

### Guest SurfaceFlinger clock

`game_frame_intervals.actual_present_ns` is the guest SurfaceFlinger actual-
present timestamp. Subtract adjacent values only inside the same stable layer
epoch. Do not compare it directly to a host marker.

`game_frame_intervals.observed_monotonic_ns` is the host time at which TFTMAC
observed the interval. It is the legal field for assigning intervals to a
host-marked range, with up to approximately one polling window of boundary
uncertainty. Precise event-to-frame attribution requires valid clock mapping or
a common frame ID.

### UTC

UTC strings are for human display and cross-file orientation. Never calculate
frame intervals from UTC wall time.

### Clock quality

- p95 RTT at or below 2 ms: precise cross-boundary attribution permitted.
- above 2 ms through 10 ms: coarse ordering only.
- above 10 ms, missing bracket, or outside the bracket: cross-host cause is
  `UNKNOWN`.

## 6. Exact frame formulas

The formulas below mirror `GameFrameTelemetry.swift`,
`CombatBenchmarkStore.swift`, and `CombatBenchmarkAnalysis.swift`.

For consecutive actual-present timestamps and a SurfaceFlinger refresh period:

```text
interval_ns[i] = actual_present_ns[i] - actual_present_ns[i-1]
interval_ms[i] = interval_ns[i] / 1,000,000

vsyncs[i] = max(1, round(interval_ns[i] / refresh_period_ns))
missed_vsync_equivalents[i] = max(0, vsyncs[i] - 1)

janky[i]  = interval_ns[i] >  1.5 * refresh_period_ns
severe[i] = interval_ns[i] >= 3.0 * refresh_period_ns
```

At the current 60 Hz target, these boundaries are approximately:

```text
janky  > 25.000 ms
severe >= 50.000 ms
```

For an ordered interval population `I` of size `n`:

```text
weighted_fps = n / (sum(I_ms) / 1000)

nearest_rank_percentile(I, q) =
  sort(I)[min(n - 1, max(0, ceil(n * q) - 1))]

slow_count = max(1, ceil(n * 0.01))
one_percent_low_fps = 1000 / mean(slowest slow_count intervals)

jank_rate = count(janky) / max(1, n)
severe_rate = count(severe) / max(1, n)
missed_vsync_rate = sum(missed_vsync_equivalents) / max(1, n)
```

The one-second window metric is deliberately different:

```text
effective_fps = interval_count * 1,000,000,000 /
                max(1, window_end_ns - window_start_ns)
```

Always name which FPS formula is being reported. Do not average per-window FPS
to create a whole-run FPS when raw intervals are available.

### Continuous 60 FPS target

The product target is not “good average FPS.” It is a useful-frame cadence of
at least 60 FPS throughout the complete automatic run:

```text
target_fps = 60
target_frame_budget_ns = 1,000,000,000 / target_fps
target_frame_budget_ms = 16.6666667

budget_miss[i] = interval_ns[i] > target_frame_budget_ns
budget_overrun_ms[i] = max(0, interval_ms[i] - target_frame_budget_ms)

budget_miss_rate = count(budget_miss) / max(1, n)
total_budget_overrun_ms = sum(budget_overrun_ms)
fps_deficit = max(0, target_fps - measured_fps)
```

The analyzer must also calculate the longest consecutive budget-miss run and a
five-second rolling weighted FPS at one-second steps. A continuous-60 claim
requires the complete automatic run—not just its mean—to meet the target, with no
missed-vsync equivalents or severe stalls. Until then, report the exact deficit
and improvement; do not redefine success downward.

Every interval remains in the calculation. Worst intervals are ranked to choose
where to debug first, never to exclude the rest of the run.

### Availability and clock formulas

For an analysis range `[start,end]`:

```text
overlap(window, range) =
  max(0, min(window_end, end) - max(window_start, start))

surface_coverage =
  sum(overlap for AVAILABLE exact-layer windows) /
  sum(overlap for all measured windows)

clock_coverage =
  max(0, min(end, latest_clock_midpoint) -
         max(start, earliest_clock_midpoint)) /
  (end - start)
```

The code's short-benchmark surface availability denominator is measured-window
time, not marker duration. Reports should also state unmeasured boundary time so
an apparently perfect measured-window ratio is not misleading.

### Candidate deltas

For FPS and interval metrics:

```text
delta_percent = ((candidate - control) / control) * 100
```

Positive FPS/1%-low delta is better. Positive p95/p99 interval delta is worse.
Jank, severe, and missed-vsync deltas stored by the current code are fraction
differences (percentage-point changes when multiplied by 100), not relative
percent reductions.

For a relative rate reduction used by the Home Run rule:

```text
relative_reduction = (control_rate - candidate_rate) / control_rate
```

## 7. Full-run collection and continuous analysis

### Collection

1. Launch one clean named profile. The automatic logger begins before the
   emulator/TFT path and opens a `GRAPHICS_RUN` from the observed TFT
   process/layer lifecycle.
2. Do not change a restart-bound setting during the run.
3. Play normally. The automatic graphics run is the dataset; do not wait for or label a
   particular game phase.
4. Optional Match Entry/End and Visible Stutter annotations may add player
   context. Absence of a marker never means
   absence of stutter.
5. Analyze the complete automatic run after normal
   app shutdown and AVD rollback.

The current native menu writes optional `MATCH_ENTRY` and `MATCH_END` annotations.
They never determine full-run validity. No battle or semantic phase classifier
participates in collection, validity, or causal analysis.

### Full-run validity

A full automatic graphics run is valid product evidence when:

- the expected TFT Unreal `SurfaceView` is stable and unambiguous;
- exact-layer measured coverage is at least 95%;
- no SurfaceFlinger history truncation affects the range;
- the effective package/profile/configuration are identified;
- no render/input/audio/login/crash correctness failure invalidates play.

Bad clock quality does not erase direct same-boundary guest-frame performance.
It makes cross-host causal attribution invalid. A full run can therefore be
valid product evidence while its cause remains `UNKNOWN`.

### Continuous timeline and under-target periods

Analyze every raw frame interval and its available `graphics_run_id`,
frame-window, stack-receipt-SHA, source, presenter, clock, and structured-error
join across the range. There is no phase-selection or battle-classifier gate.
Resource, memory, thermal, power, and audio rows remain correctness/health
context; do not rank them as graphics weak links.

For each graphics run/window, publish `TFT` (exact SurfaceFlinger
actual-present) and `PIPE` (controller freshness/delivery). The native Mac
presenter remains hidden correctness context. Where joins cannot prove ordering
or a trusted work handoff is absent, output `UNKNOWN` rather than an owner.

Before interpreting performance, build a completeness matrix for every table in
the SQL data dictionary: row count inside the range, first/last timestamp,
maximum sampling gap, expected cadence where applicable, null/unavailable count,
and boundary coverage. A missing signal becomes an explicit `UNKNOWN`; an agent
may not silently omit it because another signal appears easier to explain.

Produce one-second metrics for the complete timeline, five-second rolling
weighted FPS at one-second steps, and fixed 30-second summaries for readable
trend comparison. Group adjacent windows below the 60 FPS target into
`UNDER_TARGET` episodes. Mark any episode containing a severe frame as
`SEVERE_STALL`. These labels describe measured performance only.

For each 30-second interval calculate weighted FPS, FPS deficit from 60,
budget-miss rate, total budget overrun, p95/p99/max, 1% low, jank rate, severe
rate, missed-vsync rate, source freshness, host-presenter behavior, CPU, memory,
thermal, audio, and structured failure counts. Rank intervals for debugging by:

1. lowest weighted FPS;
2. highest severe rate;
3. highest jank rate;
4. highest missed-vsync rate;
5. largest maximum interval.

Report the full-run distribution, every `UNDER_TARGET`/`SEVERE_STALL` episode,
the worst six 30-second intervals, and every interval overlapping
`VISIBLE_STUTTER`. Ranking only controls investigation order; it never removes
the remaining data from the result.

### Full-run report order

1. Manifest and automatic process/layer lifecycle boundaries; list any markers
   only as optional annotations.
2. Configuration/package/layer identity and correctness.
3. Coverage, clock quality, and invalidators.
4. Whole-run exact frame distribution and continuous-60 target deficit.
5. Complete one-second/rolling timeline and all under-target episodes.
6. Worst 30-second intervals and visible-stutter neighborhoods.
7. Source freshness across the same full timeline; preserve final-presenter
   data only as hidden correctness context.
8. CPU/memory/thermal/power/audio and structured failures across the same full timeline.
9. Valid cross-boundary correlations; otherwise explicit unknowns.
10. Claim ledger and next one-factor candidate.

## 8. Bounded A/B protocol

The current app/source calls this feature Combat Benchmark for compatibility.
Its analysis does not require semantic combat detection. It is simply a bounded
continuous-gameplay A/B used when a full run is not needed for the first screen.

The existing code's short-benchmark validity gate is exactly:

```text
duration >= 300 seconds
surface_availability >= 0.95
clock_coverage >= 0.95
p95_clock_rtt_ms <= 10
history_truncated == false
exact_layer_stable == true
correctness_passed == true
```

It automatically ends at 480 seconds. It records one 20-second/32-MiB start
trace and permits at most two 15-second/32-MiB incident traces. An automatic
incident requires two adjacent bad one-second windows where 1% low is below
30 FPS, p99 is at least 50 ms, or a severe interval exists. Trace cooldown is
120 seconds and traces never overlap.

Control matching in current code requires:

- the newest earlier valid `control` among the latest 20 Controls;
- the same `comparison_identity_sha256`;
- the same TFT package version;
- semantic layer identity equal to
  `SurfaceView[com.riotgames.league.teamfighttactics/com.epicgames.unreal.GameActivity]`;
- Control ended before candidate.

It does not prove equivalent whole-run workload distribution, power/thermal
state, trace overhead, or full-run context. The report must show those as
compatibility fields rather than silently assume them.

### Implemented decision engine

| Decision | Exact implemented rule |
| --- | --- |
| `INCONCLUSIVE` | either run invalid; baseline correctness false; or valid values land between all resolving rules |
| `REJECT` | candidate correctness false; p95 or p99 interval is at least 10% worse; or weighted FPS gain is below 5% |
| `HOME_RUN` | after the 5% FPS guard: 1%-low gain at least 20%; jank and severe rates each fall at least 30% relative; and weighted FPS rises at least 10% **or** p95 interval falls at least 15% |
| `PROMISING` | weighted FPS rises at least 5%; 1%-low rises at least 10%; p95 and p99 intervals do not worsen |

Current code calculates/persists `observer_overhead_invalid` when trace-active
versus trace-inactive FPS or p95 differs by more than 5% with at least ten
intervals in each population. It does not currently include that flag in the
decision engine. The report must therefore show both:

```text
code_decision: <implemented decision>
causal_interpretation: INVALID_OBSERVER_OVERHEAD | ELIGIBLE
```

A `HOME_RUN` or `PROMISING` bounded result requires one cold confirmation and
one complete automatic full run before promotion to normal play.

These relative decisions select whether a change is worth retaining; they do
not redefine the product goal. Every report must separately emit:

```text
continuous_60_status: TARGET_MET | TARGET_NOT_MET | INVALID
```

`TARGET_MET` requires the full-run continuous-60 contract in Section 6. A
candidate may be a measurable improvement while the overall graphics objective
remains unfinished.

## 9. Reproducible SQL recipes

Use bound parameters rather than copying example IDs into a new analysis.

### Select complete automatic full runs

```sql
SELECT graphics_run_id, session_id, game_pid, started_utc, ended_utc,
       start_reason, end_reason, configuration_sha256, target_fps,
       exact_layer_name
FROM graphics_runs
WHERE session_id=:session_id
  AND ended_utc IS NOT NULL
ORDER BY started_monotonic_ns;
```

### Find optional Match Entry/End annotation pairs

```sql
WITH marked AS (
  SELECT id, session_id, kind, observed_utc, monotonic_ns,
         lead(id) OVER (PARTITION BY session_id ORDER BY monotonic_ns) AS next_id,
         lead(kind) OVER (PARTITION BY session_id ORDER BY monotonic_ns) AS next_kind,
         lead(observed_utc) OVER (PARTITION BY session_id ORDER BY monotonic_ns) AS next_utc,
         lead(monotonic_ns) OVER (PARTITION BY session_id ORDER BY monotonic_ns) AS next_ns
  FROM events
  WHERE kind IN ('MATCH_ENTRY','MATCH_END')
)
SELECT *
FROM marked
WHERE kind='MATCH_ENTRY' AND next_kind='MATCH_END'
ORDER BY session_id, monotonic_ns;
```

### Calculate exact whole-range frame metrics

Use `observed_monotonic_ns` for the selected automatic lifecycle range. Optional
host markers may annotate that range but must not determine validity; never
compare them directly to guest `actual_present_ns`.

```sql
WITH raw AS (
  SELECT interval_ms, is_janky, is_severe, missed_vsync_equivalents
  FROM game_frame_intervals
  WHERE session_id=:session_id
    AND observed_monotonic_ns BETWEEN :start_ns AND :end_ns
), ranked AS (
  SELECT *,
         row_number() OVER (ORDER BY interval_ms) AS rn,
         row_number() OVER (ORDER BY interval_ms DESC) AS slow_rn,
         count(*) OVER () AS n
  FROM raw
), summary AS (
  SELECT count(*) AS n,
         sum(interval_ms) AS total_ms,
         max(CASE WHEN rn=(n+1)/2 THEN interval_ms END) AS p50_ms,
         max(CASE WHEN rn=(n*95+99)/100 THEN interval_ms END) AS p95_ms,
         max(CASE WHEN rn=(n*99+99)/100 THEN interval_ms END) AS p99_ms,
         max(interval_ms) AS max_ms,
         sum(is_janky) AS jank_count,
         sum(is_severe) AS severe_count,
         sum(missed_vsync_equivalents) AS missed_vsync_count
  FROM ranked
), slow AS (
  SELECT avg(interval_ms) AS slow_mean_ms
  FROM ranked
  WHERE slow_rn <= (n+99)/100
)
SELECT n,
       1000.0*n/total_ms AS weighted_fps,
       1000.0/slow_mean_ms AS one_percent_low_fps,
       p50_ms, p95_ms, p99_ms, max_ms,
       1.0*jank_count/n AS jank_rate,
       1.0*severe_count/n AS severe_rate,
       1.0*missed_vsync_count/n AS missed_vsync_rate
FROM summary, slow;
```

### Calculate the continuous 60 FPS deficit

```sql
WITH raw AS (
  SELECT actual_present_ns, interval_ns, interval_ms,
         CASE WHEN interval_ns > (1000000000.0/60.0) THEN 1 ELSE 0 END AS miss
  FROM game_frame_intervals
  WHERE session_id=:session_id
    AND observed_monotonic_ns BETWEEN :start_ns AND :end_ns
), grouped AS (
  SELECT *,
         row_number() OVER (ORDER BY actual_present_ns) -
         row_number() OVER (PARTITION BY miss ORDER BY actual_present_ns) AS grp
  FROM raw
), runs AS (
  SELECT miss, grp, count(*) AS length
  FROM grouped
  GROUP BY miss, grp
)
SELECT (SELECT count(*) FROM raw) AS intervals,
       (SELECT sum(miss) FROM raw) AS budget_misses,
       1.0*(SELECT sum(miss) FROM raw)/(SELECT count(*) FROM raw)
         AS budget_miss_rate,
       (SELECT sum(max(0,interval_ms-(1000.0/60.0))) FROM raw)
         AS total_budget_overrun_ms,
       (SELECT max(length) FROM runs WHERE miss=1)
         AS longest_consecutive_budget_miss_run;
```

```sql
SELECT count(*) AS complete_windows,
       sum(effective_fps < 60.0) AS windows_below_60,
       1.0*sum(effective_fps < 60.0)/count(*) AS below_60_rate,
       sum(effective_fps < 50.0) AS windows_below_50,
       sum(effective_fps < 40.0) AS windows_below_40,
       sum(severe_count > 0) AS windows_with_severe_stall,
       min(effective_fps) AS minimum_window_fps
FROM game_frame_windows
WHERE session_id=:session_id
  AND status='AVAILABLE'
  AND started_monotonic_ns>=:start_ns
  AND ended_monotonic_ns<=:end_ns;
```

### Validate exact-layer coverage

```sql
SELECT
  sum(max(0,min(ended_monotonic_ns,:end_ns)-
            max(started_monotonic_ns,:start_ns))) AS measured_ns,
  sum(CASE WHEN status='AVAILABLE' THEN
        max(0,min(ended_monotonic_ns,:end_ns)-
              max(started_monotonic_ns,:start_ns)) ELSE 0 END) AS available_ns,
  count(DISTINCT CASE WHEN status='AVAILABLE' THEN layer_name END) AS exact_layers,
  sum(history_truncated) AS truncated_windows
FROM game_frame_windows
WHERE session_id=:session_id
  AND ended_monotonic_ns>=:start_ns
  AND started_monotonic_ns<=:end_ns;
```

### Find worst one-second windows

```sql
SELECT started_monotonic_ns, ended_monotonic_ns, status, unavailable_reason,
       effective_fps, one_percent_low_fps, p50_interval_ms,
       p95_interval_ms, p99_interval_ms, maximum_interval_ms,
       jank_count, severe_count, missed_vsync_equivalents,
       history_truncated, layer_name
FROM game_frame_windows
WHERE session_id=:session_id
  AND started_monotonic_ns>=:start_ns
  AND ended_monotonic_ns<=:end_ns
ORDER BY maximum_interval_ms DESC, p99_interval_ms DESC
LIMIT 20;
```

### Build deterministic 30-second continuous summaries

```sql
WITH raw AS (
  SELECT CAST((observed_monotonic_ns-:start_ns)/30000000000 AS INTEGER) AS bin,
         interval_ms, is_janky, is_severe, missed_vsync_equivalents
  FROM game_frame_intervals
  WHERE session_id=:session_id
    AND observed_monotonic_ns BETWEEN :start_ns AND :end_ns
)
SELECT bin,
       1000.0*count(*)/sum(interval_ms) AS weighted_fps,
       1.0*sum(is_janky)/count(*) AS jank_rate,
       1.0*sum(is_severe)/count(*) AS severe_rate,
       1.0*sum(missed_vsync_equivalents)/count(*) AS missed_vsync_rate,
       max(interval_ms) AS max_interval_ms
FROM raw
GROUP BY bin
ORDER BY weighted_fps ASC, severe_rate DESC, jank_rate DESC,
         missed_vsync_rate DESC, max_interval_ms DESC;
```

### Check clock eligibility

```sql
WITH c AS (
  SELECT host_midpoint_ns, round_trip_ns,
         row_number() OVER (ORDER BY round_trip_ns) AS rn,
         count(*) OVER () AS n
  FROM clock_sync_samples
  WHERE session_id=:session_id
    AND host_midpoint_ns BETWEEN :start_ns AND :end_ns
)
SELECT count(*) AS samples,
       max(CASE WHEN rn=(n*95+99)/100 THEN round_trip_ns END)/1e6 AS p95_rtt_ms,
       1.0*(max(host_midpoint_ns)-min(host_midpoint_ns))/
           (:end_ns-:start_ns) AS in_range_clock_coverage
FROM c;
```

### Correlate a guest window with source and presenter windows

```sql
SELECT g.started_monotonic_ns, g.ended_monotonic_ns,
       g.effective_fps, g.p99_interval_ms, g.maximum_interval_ms,
       s.content_changes, s.identical_frames, s.longest_identical_run_ms,
       h.unique_source_uploads, h.repeated_source_presents,
       h.drawable_misses, h.command_errors,
       h.p95_completion_latency_ms, h.p95_gpu_time_ms
FROM game_frame_windows g
LEFT JOIN stream_freshness_windows s
  ON s.session_id=g.session_id
 AND s.started_monotonic_ns<=g.ended_monotonic_ns
 AND s.ended_monotonic_ns>=g.started_monotonic_ns
LEFT JOIN host_presentation_windows h
  ON h.session_id=g.session_id
 AND h.started_monotonic_ns<=g.ended_monotonic_ns
 AND h.ended_monotonic_ns>=g.started_monotonic_ns
WHERE g.session_id=:session_id
  AND g.started_monotonic_ns>=:start_ns
  AND g.ended_monotonic_ns<=:end_ns;
```

SurfaceFlinger miss counters are cumulative. Use only max-minus-min deltas
between explicit boundaries, never their absolute value as a full-run metric.

## 10. Required AI-readable output

Every analysis must produce the following logical shape, whether rendered as
JSON, SQL rows, or Markdown:

```json
{
  "manifest": {},
  "validity": {
    "product_evidence": "VALID|PARTIAL|INVALID",
    "comparison_evidence": "VALID|INCONCLUSIVE|NOT_APPLICABLE",
    "surface_coverage": 0.0,
    "clock_coverage": 0.0,
    "p95_clock_rtt_ms": 0.0,
    "invalid_reasons": []
  },
  "whole_run": {
    "duration_seconds": 0.0,
    "intervals": 0,
    "weighted_fps": 0.0,
    "one_percent_low_fps": 0.0,
    "p50_ms": 0.0,
    "p95_ms": 0.0,
    "p99_ms": 0.0,
    "max_ms": 0.0,
    "jank_rate": 0.0,
    "severe_rate": 0.0,
    "missed_vsync_rate": 0.0,
    "target_fps": 60.0,
    "budget_miss_rate": 0.0,
    "total_budget_overrun_ms": 0.0,
    "longest_budget_miss_run": 0
  },
  "under_target_episodes": [
    {
      "episode_id": "...",
      "label": "UNDER_TARGET|SEVERE_STALL|VISIBLE_STUTTER",
      "confidence": "DIRECT|USER",
      "start_ns": 0,
      "end_ns": 0,
      "metrics": {},
      "incidents": []
    }
  ],
  "pipeline_boundaries": {
    "guest_actual_present": {},
    "source_freshness": {},
    "hidden_presenter_correctness": {},
    "resources": {},
    "clock_eligibility": "PRECISE|COARSE|UNKNOWN"
  },
  "comparison": {
    "control_id": null,
    "candidate_id": null,
    "deltas": null,
    "code_decision": "NO_DECISION",
    "promotion_status": "NOT_ELIGIBLE",
    "continuous_60_status": "TARGET_MET|TARGET_NOT_MET|INVALID"
  },
  "findings": [
    {
      "claim": "...",
      "evidence": [],
      "confidence": "DIRECT|CORRELATED|INFERRED|USER|UNKNOWN",
      "unknowns": [],
      "decision": "KEEP|REJECT|PROMISING|INCONCLUSIVE|NO_DECISION"
    }
  ],
  "privacy": {
    "credentials_stored": false,
    "raw_frames_stored": false,
    "raw_sidecars_local_only": true
  }
}
```

Never omit `invalid_reasons`, `unknowns`, or the difference between the code
decision and the engineering/promotion decision.

## 11. Current full-run findings

### 11.1 Latest automatic Build 8 graphics finding

Capture `2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200`
contains an automatic 42m27s exact TFT process/layer run (PID 2774), with
144,364 frame intervals, 99.629% exact-layer coverage, 189 degradation
incidents, 56.98 weighted FPS, 21.49 FPS 1% low, 21.510 ms p95, 33.434 ms p99,
and 53.72% missed 16.667-ms frame budgets. This is valid direct gameplay
performance evidence without a Match Entry/End marker.

It does **not** identify an internal graphics root. Build 8 has no shared work
identity across guest Vulkan, gfxstream, host Vulkan, MoltenVK, and Metal; its
source-level incident owner remains `UNKNOWN_UPSTREAM_OF_OR_AT_GUEST_SURFACE`.
The native Mac presenter remained near 60 Hz and is retained only as hidden
correctness context.

### 11.2 Build 7 Combat Latency A historical finding

#### Identity and boundaries

| Field | Direct finding |
| --- | --- |
| Session | `2026-08-31T02-54-28.329Z-14000b50-bf29-44c6-a963-9203d5313494` |
| Session state at analysis | `RUNNING`; the marked range is saved, but the complete capture is not yet sealed |
| Database | `Captures/<session-id>/TFTMAC_NATIVE_RUNTIME.sqlite` |
| Profile | `tftmac_5gb_native_v1_preset_combat_latency_a` |
| Configuration SHA-256 | `05039d1fd0987f46fc7da8de5f483d8c7ffaf8f39bd1eaecdd1aee11603bbb07` |
| `MATCH_ENTRY` | event 1442, `2026-08-31T03:19:25Z`, host monotonic `262537257186708` |
| `MATCH_END` | event 3065, `2026-08-31T03:51:00Z`, host monotonic `264432310804375` |
| Marked duration | 1,895.054 seconds / 31m35.054s |
| Evidence mode | `FULL_RUN` |

This is a complete marked run, so every frame and supporting sample inside the
range participates. It has no formal bounded-A/B row, which affects comparison
only; it does not reduce the full-run evidence. The marker rows and bounded data
are queryable now. Calculate a final whole-database hash only after normal app
shutdown seals the session.

### Data completeness inventory

| Signal family | Rows in/overlapping marked range |
| --- | ---: |
| Events | 1,624 |
| Frame samples | 1,562 |
| Source frame-interval windows | 1,871 |
| Presentation samples | 1,878 |
| Exact game-frame intervals | 93,724 |
| Exact game-frame windows | 1,695 |
| Stream-freshness windows | 1,871 |
| Host-presentation windows | 1,876 |
| QEMU/TFT resource samples | 357 |
| Guest-memory samples | 357 |
| Host-resource samples | 357 |
| Clock-sync samples | 59 |
| SurfaceFlinger samples | 59 |
| Audio samples | 59 |
| Logcat aggregates | 357 |
| Pipeline-log aggregates | 355 |
| Graphics-pipeline snapshots | 59 |
| Input metadata samples | 15,394 |
| TFT process lifetimes overlapping range | 1 |
| Diagnostic artifacts | 0 |

The session also has 39 startup/runtime receipts. It has zero bounded benchmark,
incident, or comparison rows because that optional feature was not started. That
does not remove any continuous full-run telemetry; it means trace-based cause
and matched A/B decision fields are unavailable.

### Exact guest-frame result

| Metric | Finding |
| --- | ---: |
| Actual-present intervals | 93,724 |
| Weighted FPS | **49.449** |
| 1% low | **16.300 FPS** |
| p50 | 16.965 ms |
| p95 | **33.822 ms** |
| p99 | **48.746 ms** |
| Maximum | **1,254.162 ms** |
| Janky intervals | 17,911 / **19.110%** |
| Severe intervals | 572 / **0.610%** |
| Missed-vsync equivalents | 20,004 / 0.2134 per interval |
| Intervals over the 60 FPS frame budget | 58,925 / **62.871%** |
| Total 60 FPS budget overrun | **357,921.976 ms** |
| Longest consecutive budget-miss run | **325 intervals** |
| Complete one-second windows below 60 FPS | 1,599 / **94.448%** |
| Windows below 50 / below 40 FPS | 678 / 314 |
| Windows containing a severe stall | 353 |

Tail distribution:

| Interval range | Count | Share |
| --- | ---: | ---: |
| at or below 16.667 ms | 34,812 | 37.143% |
| above 16.667 through 20 ms | 39,487 | 42.131% |
| above 20 through 33.334 ms | 12,188 | 13.004% |
| above 33.334 through 50 ms | 6,665 | 7.111% |
| above 50 through 100 ms | 543 | 0.579% |
| above 100 through 250 ms | 23 | 0.025% |
| above 250 ms | 6 | 0.006% |

The exact TFT layer was stable, all 1,695 overlapping windows were available,
measured overlap coverage was 100%, and no window reported history truncation.
The interval sum is about 0.297 seconds longer than the marker duration because
intervals arrive in polling batches at the range edges; weighted FPS uses the
source-defined interval formula, not marker duration.

### Worst continuous 30-second intervals

| Match time | Weighted FPS | Jank | Severe | Missed vsync | Max interval |
| --- | ---: | ---: | ---: | ---: | ---: |
| 17:00–17:30 | 38.490 | 44.38% | 4.464% | 652 | 102.091 ms |
| 18:30–19:00 | 39.863 | 45.56% | 1.962% | 592 | 81.526 ms |
| 20:00–20:30 | 39.147 | 43.90% | 1.212% | 615 | 666.743 ms |
| 21:30–22:00 | **33.436** | **57.60%** | 2.582% | **798** | **1,254.162 ms** |
| 22:30–23:00 | 39.189 | 47.40% | 1.759% | 633 | 66.334 ms |
| 25:30–26:00 | 37.781 | 53.99% | 0.964% | 671 | 91.910 ms |

The worst interval was 21:30–22:00. It is direct evidence of a sustained bad
performance period. Its first late internal graphics boundary remains unknown.

### Source, final presenter, and resources

| Boundary | Direct finding |
| --- | --- |
| Source image rate | mean 49.472 FPS; no sequence-drop increase during marked interval |
| Final Metal output | mean 59.968 FPS |
| Host presentation | 113,618 submitted and completed; 90,387 unique uploads; 23,231 repeated-source presents |
| Presenter correctness | zero drawable misses; zero command errors |
| Final Metal cost | maximum completion latency 7.494 ms; maximum GPU time 3.267 ms |
| Emulator CPU | mean 513.65%; range 385.9–589.0% |
| Emulator RSS | mean 4,429.4 MiB; maximum 5,843.3 MiB |
| Guest memory | minimum 777.7 MiB available / 15.81%; maximum swap used 669.5 MiB |
| Host state | AC power; thermal state always `NOMINAL` |
| Audio | CoreAudio, active 48 kHz stereo, one active track, zero underruns |
| Structured faults | 14 confirmed guest memory-kill signatures in one aggregate near +27:17.774; no match-range ANR, input timeout, TFT fatal, ANGLE/Vulkan warning, or audio-error count |
| Pipeline aggregates | zero named gfxstream warning, ASG stall, Vulkan error, MoltenVK warning, shader error, or fence-timeout counts |

The presenter completed near 60 Hz while reusing 23,231 source frames and while
guest actual presentation was irregular. This directly makes TFTMAC's final
Metal pass a poor explanation for the missing useful frames in this match. It
does not distinguish Unreal, ANGLE, ASG/gfxstream, or MoltenVK upstream.

The 14 memory-kill signatures identify actual guest victims by classifier
syntax, but the normalized aggregate does not store victim identity. Their
relationship to TFT frame loss is therefore `UNKNOWN`; do not say TFT itself was
killed.

### Validity and decision

| Gate | Result |
| --- | --- |
| Full-run product evidence | **VALID** for direct player-facing frame distribution |
| Exact layer/coverage/history | pass |
| In-range clock coverage | 97.494% |
| Clock p95 RTT | **86.757 ms**, above 10 ms |
| Precise/coarse cross-host cause | **INVALID / UNKNOWN** |
| Matched Control | absent |
| Formal short benchmark row | absent |
| Candidate performance decision | **NO_DECISION / INCONCLUSIVE** |
| Continuous 60 FPS status | **TARGET_NOT_MET** |

Direct conclusion: the marked run did not hold 60 FPS. More than 62% of raw
intervals exceeded the 60 FPS frame budget and more than 94% of complete
one-second windows were below 60, despite a near-60 final output cadence. Combat
Latency A is neither promoted nor rejected by this single unmatched run. The run
is a valid candidate baseline and product-performance problem record; exact
internal ownership remains unknown because the clock gate failed and the
frame-ID boundary ring does not yet exist.

## 12. Comparison and promotion policy

For a one-factor candidate:

1. Preserve one current valid Control full run.
2. Run the candidate under the same package, display, High/60/OFF game settings,
   power state, and comparable play pattern.
3. Compare the complete whole-run distributions, continuous timelines,
   under-target episodes, and resource/pipeline correlations.
4. Use the bounded code decision when a valid `BOUNDED_AB` pair exists.
5. Reject immediately for any boot/render/input/audio/login/cleanup regression or
   direct unacceptable player experience.
6. Cold-confirm a short winner.
7. Require one complete automatic full run before normal-play promotion.

A relative winner below the continuous 60 FPS target is retained as progress,
not described as the graphics problem being fixed.

Full runs need not have identical length. Compare:

- whole-run weighted/tail metrics with coverage shown;
- 60 FPS budget-miss rate, total overrun, and longest miss run;
- complete one-second and five-second rolling distributions;
- every under-target episode and the median/worst quartile of fixed intervals;
- worst one-second incidents;
- sustained resource/thermal/memory state;
- correctness and direct player report.

Never declare a gain from one isolated best window, different package/settings,
different semantic layer, lobby-only data, or output cadence alone. Missing
markers alone never invalidates an automatic full run.

## 13. Retention and privacy

Retain:

- latest accepted Control full run;
- latest candidate full run and any matching bounded A/B;
- current package/runtime/configuration receipts;
- every rejected candidate's compact metrics and reason;
- unresolved incident evidence;
- normalized trace summaries and SHA-256 links when valid.

Older raw captures may be compacted only after preserving session ID, automatic
lifecycle range, optional marker annotations, configuration/package/runtime
identity, formula version, verdict, key
metrics, source database hash, and artifact hashes.

Raw logcat, raw traces, and any sensitive sidecars remain local/private. Reports
must never contain credentials, tokens, typed content, login screenshots, or raw
frames.

## 14. Known analysis gaps

1. Current comparison matching does not enforce equivalent whole-run workload,
   thermal/power state, or full-run context.
2. `observer_overhead_invalid` is stored but does not alter the code decision.
3. Cold-confirmation/promotion linkage is policy, not a normalized SQL field.
4. Clock RTT is too high in the current full run for cross-host cause.
5. No common work ID currently spans guest submit through owned emulator
   transport/translation completion. The allocation-free source-built
   correlation ring remains a planned, gated next
   layer; stack-receipt/frame-window joins do not replace it.

These gaps limit attribution and automation; they do not erase the direct
player-facing frame distribution already captured.
