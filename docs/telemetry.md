# Macrodroid Telemetry & Observability Engine

Macrodroid 5.4 features a **local-first, zero-exfiltration telemetry engine** designed for high-resolution graphics performance auditing, frame pacing diagnostics, and thermal profiling.

---

## 1. Architectural Principles

- **100% Local Storage**: All telemetry is stored in SQLite on the local host machine. No analytics or telemetry packets are ever transmitted over the network.
- **Microsecond Clock Precision**: Utilizes `mach_absolute_time()` synchronized with guest monotonic clocks to correlate Android SurfaceFlinger presentation with macOS Metal 3 display swaps.
- **Zero Overhead During Normal Gameplay**: Metrics are batched in a lock-free ring buffer and written to disk at 1-second intervals via a dedicated background actor.

---

## 2. Storage & File System Layout

Each gaming session generates a private timestamped directory:
```text
~/Library/Application Support/Macrodroid/Captures/<session-uuid>/
├── Macrodroid_RUNTIME.sqlite    <-- Primary relational metrics database
├── native-events.jsonl          <-- Microsecond-accurate input & frame trace
└── session-info.json            <-- Hardware specs, active profile, OS version
```

---

## 3. Database Schema

The SQLite database (`Macrodroid_RUNTIME.sqlite`) contains structured tables for deep performance analysis:

### `graphics_runs`
Records session-level metadata and configuration:
- `session_id` (TEXT PRIMARY KEY)
- `started_at` (INTEGER - Unix timestamp)
- `profile_name` (TEXT - e.g., "Competitive E-Sports 120 FPS")
- `metal_device_name` (TEXT - e.g., "Apple M4 Pro")
- `display_refresh_rate` (REAL - e.g., 120.0)

### `frame_windows`
Records 1-second aggregated frame metrics:
- `window_index` (INTEGER)
- `ingress_fps` (REAL - raw frames received from emulator gRPC)
- `surfaceflinger_fps` (REAL - guest compositor presentation rate)
- `present_fps` (REAL - frames presented to Metal drawable surface)
- `latency_p50_ms` (REAL - median frame delivery latency)
- `latency_p95_ms` (REAL - 95th percentile latency)
- `latency_p99_ms` (REAL - 99th percentile frame spikes / stutters)
- `missed_frames` (INTEGER - frames dropped or late)

### `system_metrics`
Samples host and guest physical utilization:
- `timestamp` (INTEGER)
- `host_cpu_percent` (REAL)
- `guest_ram_used_mb` (INTEGER)
- `thermal_state` (TEXT - "nominal", "fair", "serious", "critical")

---

## 4. Useful Diagnostic Queries

Developers and advanced users can query their telemetry database using `sqlite3`:

### Calculate Average Framerate and Frame Stability:
```sql
SELECT 
  AVG(present_fps) AS avg_metal_fps,
  MIN(present_fps) AS min_metal_fps,
  AVG(latency_p95_ms) AS avg_p95_latency_ms,
  SUM(missed_frames) AS total_dropped_frames
FROM frame_windows;
```

### Detect Thermal Throttling Incidents:
```sql
SELECT timestamp, host_cpu_percent, thermal_state 
FROM system_metrics 
WHERE thermal_state != 'nominal';
```

---

## 5. Privacy & Data Sanitization

- **Credential Exclusion**: Passwords, Google account identifiers, Riot IDs, session cookies, and authentication tokens are strictly filtered at the input layer and never written to telemetry logs.
- **Logcat Redaction**: Raw Android `logcat` streams are scrubbed for PII (Personally Identifiable Information) before being appended to debug buffers.
