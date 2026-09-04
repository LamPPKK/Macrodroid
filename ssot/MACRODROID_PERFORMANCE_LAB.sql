-- TFTMAC Performance Laboratory
--
-- CLEAN-ROOM PERFORMANCE EVIDENCE DATABASE
-- ========================================
-- This database is intentionally independent from:
--   ssot/TFTMAC_ENGINEERING_MAP.sql
--   ssot/donors/TFTMAC_DONOR_RESEARCH.sql
--
-- Donor measurements, claims, and historical benchmark numbers MUST NOT be
-- inserted here as current product facts. A donor finding may nominate a
-- hypothesis outside this database, but only a current TFTMAC session or a
-- current controlled experiment may support a performance fact here.
--
-- Runtime rule:
--   High-rate telemetry is captured append-only to raw files during gameplay.
--   This SQLite database is populated after or asynchronously from capture so
--   the observer does not become the bottleneck.
--
-- Promotion rule:
--   A hypothesis NEVER becomes a fact merely by changing its status. A current
--   performance fact requires an explicit performance_facts row backed by a
--   current evidence row. KEEP decisions require controlled metrics and, for a
--   performance promotion, cold confirmation unless the decision is explicitly
--   diagnostic only.
--
-- SQLite compatible.

PRAGMA foreign_keys = ON;
BEGIN;

CREATE TABLE lab_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE host_facts (
    id TEXT PRIMARY KEY,
    fact_key TEXT NOT NULL UNIQUE,
    fact_value TEXT NOT NULL,
    unit TEXT,
    provenance_class TEXT NOT NULL CHECK (
        provenance_class IN ('DIRECT_OBSERVATION','PROJECT_LOCK','USER_REQUIREMENT')
    ),
    source_ref TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('OBSERVED','FROZEN','RETIRED')),
    observed_at TEXT NOT NULL,
    notes TEXT
);

CREATE TABLE runtime_configs (
    id TEXT PRIMARY KEY,
    parent_config_id TEXT REFERENCES runtime_configs(id),
    name TEXT NOT NULL,
    config_sha256 TEXT UNIQUE,
    emulator_version TEXT,
    platform_tools_version TEXT,
    system_image_package TEXT,
    system_image_revision INTEGER,
    avd_name TEXT,
    adb_serial TEXT,
    adb_server_port INTEGER,
    emulator_console_port INTEGER,
    vcpu INTEGER CHECK (vcpu IS NULL OR vcpu > 0),
    ram_mb INTEGER CHECK (ram_mb IS NULL OR ram_mb > 0),
    display_width INTEGER CHECK (display_width IS NULL OR display_width > 0),
    display_height INTEGER CHECK (display_height IS NULL OR display_height > 0),
    density_dpi INTEGER CHECK (density_dpi IS NULL OR density_dpi > 0),
    refresh_hz REAL CHECK (refresh_hz IS NULL OR refresh_hz > 0),
    gpu_mode TEXT,
    audio_enabled INTEGER CHECK (audio_enabled IN (0,1) OR audio_enabled IS NULL),
    graphics_transport TEXT,
    angle_mode TEXT,
    vulkan_mode TEXT,
    moltenvk_mode TEXT,
    presentation_mode TEXT,
    state TEXT NOT NULL CHECK (state IN ('CONTROL','CANDIDATE','PROMOTED','REJECTED','RETIRED')),
    created_at TEXT NOT NULL,
    notes TEXT
);

CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    runtime_config_id TEXT NOT NULL REFERENCES runtime_configs(id),
    started_utc TEXT,
    ended_utc TEXT,
    host_start_mono_ns INTEGER,
    host_end_mono_ns INTEGER,
    boot_class TEXT NOT NULL CHECK (boot_class IN ('COLD','WARM','UNKNOWN')),
    workload_class TEXT NOT NULL CHECK (
        workload_class IN ('BOOT','LOGIN','LOBBY','MATCH_ENTRY','TRANSITION','EARLY_COMBAT','HEAVY_COMBAT','MIXED','UNKNOWN')
    ),
    package_name TEXT,
    package_version_name TEXT,
    package_version_code TEXT,
    package_state_sha256 TEXT,
    renderer_state_sha256 TEXT,
    session_manifest_sha256 TEXT,
    package_updated_during_session INTEGER NOT NULL DEFAULT 0 CHECK (package_updated_during_session IN (0,1)),
    capture_state TEXT NOT NULL CHECK (capture_state IN ('PLANNED','CAPTURING','COMPLETE','PARTIAL','INVALID')),
    semantic_valid INTEGER CHECK (semantic_valid IN (0,1) OR semantic_valid IS NULL),
    invalid_reason TEXT,
    notes TEXT
);

CREATE TABLE clock_sync (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    host_t0_ns INTEGER NOT NULL,
    guest_mono_ns INTEGER NOT NULL,
    host_t1_ns INTEGER NOT NULL,
    host_midpoint_ns INTEGER NOT NULL,
    rtt_ns INTEGER NOT NULL CHECK (rtt_ns >= 0),
    estimated_offset_ns INTEGER NOT NULL,
    source TEXT NOT NULL,
    UNIQUE(session_id, host_t0_ns)
);

CREATE TABLE artifacts (
    id TEXT PRIMARY KEY,
    session_id TEXT REFERENCES sessions(id) ON DELETE CASCADE,
    experiment_id TEXT,
    artifact_kind TEXT NOT NULL,
    path TEXT NOT NULL,
    sha256 TEXT,
    byte_count INTEGER CHECK (byte_count IS NULL OR byte_count >= 0),
    required INTEGER NOT NULL DEFAULT 0 CHECK (required IN (0,1)),
    state TEXT NOT NULL CHECK (state IN ('EXPECTED','PRESENT','MISSING','CORRUPT','OPTIONAL_UNAVAILABLE')),
    created_at TEXT,
    notes TEXT
);

CREATE TABLE markers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    host_mono_ns INTEGER NOT NULL,
    guest_mono_ns INTEGER,
    marker_type TEXT NOT NULL CHECK (
        marker_type IN ('USER_STUTTER','AUTO_JANK','AUTO_SEVERE_STALL','MATCH_ENTRY','MATCH_RESULT','COMBAT_START','TRANSITION','PACKAGE_UPDATE','GAME_SETTINGS','USER_QUALITY_REPORT','CUSTOM')
    ),
    label TEXT,
    payload_json TEXT
);

CREATE TABLE frame_samples (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    source TEXT NOT NULL,
    surface_name TEXT,
    frame_number INTEGER,
    presentation_host_ns INTEGER,
    presentation_guest_ns INTEGER,
    frame_interval_ns INTEGER CHECK (frame_interval_ns IS NULL OR frame_interval_ns >= 0),
    classification TEXT CHECK (classification IN ('NORMAL','JANK','SEVERE_STALL','UNKNOWN')),
    raw_artifact_id TEXT REFERENCES artifacts(id),
    UNIQUE(session_id, source, surface_name, frame_number)
);

CREATE TABLE process_samples (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    host_mono_ns INTEGER NOT NULL,
    scope TEXT NOT NULL CHECK (scope IN ('HOST','GUEST')),
    process_name TEXT NOT NULL,
    pid INTEGER,
    tid INTEGER,
    cpu_pct REAL,
    cpu_time_ns INTEGER,
    rss_bytes INTEGER,
    thread_count INTEGER,
    nice_value INTEGER,
    process_state TEXT,
    raw_artifact_id TEXT REFERENCES artifacts(id)
);

CREATE TABLE memory_samples (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    host_mono_ns INTEGER NOT NULL,
    host_used_bytes INTEGER,
    host_available_bytes INTEGER,
    host_compressed_bytes INTEGER,
    host_swap_used_bytes INTEGER,
    host_pressure_state TEXT,
    guest_total_bytes INTEGER,
    guest_available_bytes INTEGER,
    emulator_rss_bytes INTEGER,
    pagein_count INTEGER,
    pageout_count INTEGER,
    raw_artifact_id TEXT REFERENCES artifacts(id)
);

CREATE TABLE graphics_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    host_mono_ns INTEGER,
    guest_mono_ns INTEGER,
    boundary TEXT NOT NULL CHECK (
        boundary IN (
            'UNREAL_GAME','UNREAL_RHI','PSO_SHADER','DEVICE_PROFILE','TEXTURE_ASTC',
            'GUEST_SCHEDULER','ANGLE','GUEST_VULKAN','GFXSTREAM_ASG','HOST_GFXSTREAM',
            'MOLTENVK','METAL','SURFACEFLINGER','MEMORY','AUDIO','PACKAGE','UNKNOWN'
        )
    ),
    event_type TEXT NOT NULL,
    duration_ns INTEGER CHECK (duration_ns IS NULL OR duration_ns >= 0),
    numeric_value REAL,
    unit TEXT,
    details_json TEXT,
    raw_artifact_id TEXT REFERENCES artifacts(id)
);

CREATE TABLE stall_windows (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    start_host_ns INTEGER NOT NULL,
    end_host_ns INTEGER NOT NULL,
    duration_ns INTEGER NOT NULL CHECK (duration_ns >= 0),
    frame_count INTEGER,
    jank_frame_count INTEGER,
    severe_frame_count INTEGER,
    peak_frame_interval_ns INTEGER,
    nearest_marker_id INTEGER REFERENCES markers(id),
    detected_by TEXT NOT NULL,
    classification TEXT NOT NULL CHECK (
        classification IN ('JANK_BURST','SEVERE_STALL','SUSTAINED_LOW_FPS','TRANSITION_STALL','UNKNOWN')
    ),
    causal_status TEXT NOT NULL CHECK (causal_status IN ('UNATTRIBUTED','CANDIDATE_CAUSE','ATTRIBUTED','DISPUTED')),
    notes TEXT,
    CHECK (end_host_ns >= start_host_ns)
);

CREATE TABLE hypotheses (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    boundary TEXT NOT NULL,
    statement TEXT NOT NULL,
    predicted_signature TEXT NOT NULL,
    falsification_condition TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('QUEUED','TESTING','SUPPORTED','REJECTED','DEFERRED')),
    confidence REAL NOT NULL DEFAULT 0.0 CHECK (confidence >= 0.0 AND confidence <= 1.0),
    nominated_from_session_id TEXT REFERENCES sessions(id),
    created_at TEXT NOT NULL,
    notes TEXT
);

CREATE TABLE experiments (
    id TEXT PRIMARY KEY,
    hypothesis_id TEXT REFERENCES hypotheses(id),
    name TEXT NOT NULL,
    experiment_type TEXT NOT NULL CHECK (experiment_type IN ('CONTROL_CAPTURE','OBSERVATION','INTERVENTION')),
    baseline_config_id TEXT REFERENCES runtime_configs(id),
    candidate_config_id TEXT REFERENCES runtime_configs(id),
    run_class TEXT NOT NULL CHECK (run_class IN ('COLD','WARM','TRANSITION','HEAVY','MIXED')),
    one_factor INTEGER NOT NULL CHECK (one_factor IN (0,1)),
    state TEXT NOT NULL CHECK (state IN ('PLANNED','RUNNING','COMPLETE','INVALID','CANCELLED')),
    required_cold_confirmation INTEGER NOT NULL DEFAULT 0 CHECK (required_cold_confirmation IN (0,1)),
    semantic_gate TEXT NOT NULL,
    created_at TEXT NOT NULL,
    completed_at TEXT,
    notes TEXT
);

CREATE TABLE experiment_sessions (
    experiment_id TEXT NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('BASELINE','CANDIDATE','CONFIRMATION','DIAGNOSTIC')),
    PRIMARY KEY (experiment_id, session_id)
);

CREATE TABLE interventions (
    id TEXT PRIMARY KEY,
    experiment_id TEXT NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
    boundary TEXT NOT NULL,
    parameter_name TEXT NOT NULL,
    before_value TEXT,
    after_value TEXT NOT NULL,
    reversible INTEGER NOT NULL CHECK (reversible IN (0,1)),
    rollback_action TEXT NOT NULL,
    applied_config_path TEXT,
    notes TEXT
);

CREATE TABLE metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT REFERENCES sessions(id) ON DELETE CASCADE,
    experiment_id TEXT REFERENCES experiments(id) ON DELETE CASCADE,
    metric_scope TEXT NOT NULL,
    metric_name TEXT NOT NULL,
    metric_value REAL NOT NULL,
    unit TEXT NOT NULL,
    source_artifact_id TEXT REFERENCES artifacts(id),
    semantic_valid INTEGER NOT NULL DEFAULT 1 CHECK (semantic_valid IN (0,1)),
    notes TEXT,
    CHECK (session_id IS NOT NULL OR experiment_id IS NOT NULL)
);

CREATE TABLE comparisons (
    id TEXT PRIMARY KEY,
    experiment_id TEXT NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
    metric_name TEXT NOT NULL,
    baseline_value REAL NOT NULL,
    candidate_value REAL NOT NULL,
    unit TEXT NOT NULL,
    delta_absolute REAL NOT NULL,
    delta_percent REAL,
    preferred_direction TEXT NOT NULL CHECK (preferred_direction IN ('HIGHER','LOWER','TARGET','NONE')),
    threshold_value REAL,
    threshold_pass INTEGER CHECK (threshold_pass IN (0,1) OR threshold_pass IS NULL),
    notes TEXT
);

CREATE TABLE evidence (
    id TEXT PRIMARY KEY,
    hypothesis_id TEXT REFERENCES hypotheses(id),
    session_id TEXT REFERENCES sessions(id),
    experiment_id TEXT REFERENCES experiments(id),
    evidence_type TEXT NOT NULL CHECK (
        evidence_type IN ('DIRECT_MEASUREMENT','TRACE_CORRELATION','CONFIG_OBSERVATION','NEGATIVE_RESULT','REPRODUCTION','FALSIFICATION')
    ),
    claim TEXT NOT NULL,
    relation TEXT NOT NULL CHECK (relation IN ('SUPPORTS','REFUTES','NEUTRAL')),
    strength TEXT NOT NULL CHECK (strength IN ('WEAK','MODERATE','STRONG','DECISIVE')),
    source_artifact_id TEXT REFERENCES artifacts(id),
    created_at TEXT NOT NULL,
    notes TEXT,
    CHECK (session_id IS NOT NULL OR experiment_id IS NOT NULL)
);

CREATE TABLE decisions (
    id TEXT PRIMARY KEY,
    experiment_id TEXT NOT NULL REFERENCES experiments(id),
    decision TEXT NOT NULL CHECK (decision IN ('KEEP','REJECT','INCONCLUSIVE','DIAGNOSTIC_ONLY')),
    rationale TEXT NOT NULL,
    cold_confirmation_complete INTEGER NOT NULL DEFAULT 0 CHECK (cold_confirmation_complete IN (0,1)),
    promoted_config_id TEXT REFERENCES runtime_configs(id),
    decided_at TEXT NOT NULL,
    notes TEXT
);

CREATE TABLE performance_facts (
    id TEXT PRIMARY KEY,
    domain TEXT NOT NULL,
    fact_key TEXT NOT NULL,
    fact_value TEXT NOT NULL,
    unit TEXT,
    source_evidence_id TEXT NOT NULL REFERENCES evidence(id),
    status TEXT NOT NULL CHECK (status IN ('PROMOTED','RETIRED')),
    promoted_at TEXT NOT NULL,
    retired_at TEXT,
    notes TEXT,
    UNIQUE(domain, fact_key, status)
);

CREATE TABLE unknowns (
    id TEXT PRIMARY KEY,
    question TEXT NOT NULL,
    boundary TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('OPEN','RESOLVED','DEFERRED')),
    blocking INTEGER NOT NULL DEFAULT 0 CHECK (blocking IN (0,1)),
    resolution_evidence_id TEXT REFERENCES evidence(id),
    opened_at TEXT NOT NULL,
    resolved_at TEXT,
    notes TEXT
);

CREATE VIEW v_promoted_facts AS
SELECT 'HOST' AS fact_scope,
       hf.id,
       hf.fact_key,
       hf.fact_value,
       hf.unit,
       hf.source_ref,
       hf.observed_at AS promoted_or_observed_at
FROM host_facts hf
WHERE hf.status='FROZEN'
UNION ALL
SELECT pf.domain AS fact_scope,
       pf.id,
       pf.fact_key,
       pf.fact_value,
       pf.unit,
       pf.source_evidence_id AS source_ref,
       pf.promoted_at AS promoted_or_observed_at
FROM performance_facts pf
WHERE pf.status='PROMOTED';

CREATE VIEW v_stall_summary AS
SELECT s.id AS session_id,
       s.boot_class,
       s.workload_class,
       COUNT(sw.id) AS stall_window_count,
       SUM(CASE WHEN sw.classification='SEVERE_STALL' THEN 1 ELSE 0 END) AS severe_stall_windows,
       MAX(sw.peak_frame_interval_ns) AS max_frame_interval_ns,
       SUM(COALESCE(sw.jank_frame_count,0)) AS jank_frames,
       SUM(COALESCE(sw.severe_frame_count,0)) AS severe_frames
FROM sessions s
LEFT JOIN stall_windows sw ON sw.session_id=s.id
GROUP BY s.id,s.boot_class,s.workload_class;

CREATE VIEW v_experiment_scorecard AS
SELECT e.id AS experiment_id,
       e.name,
       e.experiment_type,
       e.run_class,
       e.state,
       h.id AS hypothesis_id,
       h.title AS hypothesis,
       d.decision,
       d.cold_confirmation_complete,
       COUNT(DISTINCT es.session_id) AS session_count,
       COUNT(DISTINCT c.id) AS compared_metric_count
FROM experiments e
LEFT JOIN hypotheses h ON h.id=e.hypothesis_id
LEFT JOIN decisions d ON d.experiment_id=e.id
LEFT JOIN experiment_sessions es ON es.experiment_id=e.id
LEFT JOIN comparisons c ON c.experiment_id=e.id
GROUP BY e.id,e.name,e.experiment_type,e.run_class,e.state,h.id,h.title,d.decision,d.cold_confirmation_complete;

CREATE VIEW v_open_hypotheses AS
SELECT h.id,
       h.title,
       h.boundary,
       h.statement,
       h.predicted_signature,
       h.falsification_condition,
       h.status,
       h.confidence,
       COUNT(DISTINCT ev.id) AS evidence_count,
       COUNT(DISTINCT ex.id) AS experiment_count
FROM hypotheses h
LEFT JOIN evidence ev ON ev.hypothesis_id=h.id
LEFT JOIN experiments ex ON ex.hypothesis_id=h.id
WHERE h.status IN ('QUEUED','TESTING','SUPPORTED')
GROUP BY h.id,h.title,h.boundary,h.statement,h.predicted_signature,h.falsification_condition,h.status,h.confidence
ORDER BY h.status='TESTING' DESC,h.confidence DESC,h.id;

CREATE VIEW v_session_quality AS
SELECT s.id AS session_id,
       s.capture_state,
       s.semantic_valid,
       s.boot_class,
       s.workload_class,
       (SELECT COUNT(*) FROM artifacts a WHERE a.session_id=s.id AND a.required=1) AS required_artifact_count,
       (SELECT COUNT(*) FROM artifacts a WHERE a.session_id=s.id AND a.required=1 AND a.state='PRESENT') AS required_artifacts_present,
       (SELECT COUNT(*) FROM artifacts a WHERE a.session_id=s.id AND a.required=1 AND a.state<>'PRESENT') AS required_artifacts_missing_or_bad,
       (SELECT COUNT(*) FROM frame_samples fs WHERE fs.session_id=s.id) AS frame_sample_count,
       (SELECT COUNT(*) FROM clock_sync cs WHERE cs.session_id=s.id) AS clock_sync_count
FROM sessions s;

INSERT INTO lab_meta(key,value) VALUES
('schema_version','1'),
('created_at','2026-08-28T07:50:00Z'),
('project','TFTMAC'),
('database_role','CURRENT_PERFORMANCE_EVIDENCE_ONLY'),
('donor_contamination_policy','Donor claims and historical benchmarks never enter this database as current facts. Current TFTMAC measurement is required.'),
('capture_policy','Record high-rate telemetry to append-only raw artifacts first; normalize into SQLite after or asynchronously from capture.'),
('promotion_policy','Hypothesis status is not fact promotion. performance_facts requires explicit current evidence.'),
('experiment_policy','One causal factor per intervention where separable; automatic rollback; cold confirmation required before performance baseline promotion.'),
('control_policy','No tweak experiments execute until the direct-play control has produced valid current evidence.'),
('jank_threshold_ns','33334000'),
('severe_stall_threshold_ns','100000000'),
('optimization_target_avg_fps','58.0'),
('optimization_target_p95_ms','20.0'),
('optimization_target_p99_ms','33.334'),
('optimization_target_jank_pct','1.0'),
('optimization_target_severe_stalls_per_600s','3');

INSERT INTO host_facts VALUES
('host_model','hardware_model','Mac16,10',NULL,'PROJECT_LOCK','ssot/STACK.lock.yaml','FROZEN','2026-08-28T04:32:04Z','Target control host.'),
('host_chip','chip','Apple M4',NULL,'DIRECT_OBSERVATION','ssot/host-preflight.json','FROZEN','2026-08-28T04:07:47Z','Apple Silicon target.'),
('host_memory','physical_memory','16','GiB','DIRECT_OBSERVATION','ssot/host-preflight.json','FROZEN','2026-08-28T04:07:47Z','Unified-memory host; memory pressure must be measured.'),
('host_arch','architecture','arm64',NULL,'PROJECT_LOCK','ssot/STACK.lock.yaml','FROZEN','2026-08-28T04:32:04Z',NULL),
('host_macos','macos_version','26.6.2',NULL,'PROJECT_LOCK','ssot/STACK.lock.yaml','FROZEN','2026-08-28T04:32:04Z',NULL),
('host_macos_build','macos_build','25G83',NULL,'PROJECT_LOCK','ssot/STACK.lock.yaml','FROZEN','2026-08-28T04:32:04Z',NULL),
('control_emulator','control_emulator_version','37.1.11',NULL,'PROJECT_LOCK','ssot/STACK.lock.yaml','FROZEN','2026-08-28T04:32:04Z','Released Google emulator control.'),
('control_platform_tools','control_platform_tools_version','37.0.1',NULL,'PROJECT_LOCK','ssot/STACK.lock.yaml','FROZEN','2026-08-28T04:32:04Z',NULL),
('control_image','control_system_image','system-images;android-37.1;google_apis_playstore_ps16k;arm64-v8a',NULL,'PROJECT_LOCK','ssot/STACK.lock.yaml','FROZEN','2026-08-28T08:46:32Z','Current official Play-enabled ARM64 image selected after 37.0 rev 6 reproduced a Google GMS MinuteMaid account-flow crash.'),
('control_image_revision','control_system_image_revision','9',NULL,'PROJECT_LOCK','ssot/STACK.lock.yaml','FROZEN','2026-08-28T08:46:32Z','Google SDK catalog current stable android-37.1 Play ps16k ARM64 revision.'),
('control_package','tft_package','com.riotgames.league.teamfighttactics',NULL,'USER_REQUIREMENT','ssot/TFTMAC_DIRECT_PLAY_CONTROL_BUILD.md','FROZEN','2026-08-28T07:50:00Z','Official Google Play/Riot package authority only.');

INSERT INTO runtime_configs (
    id,name,emulator_version,platform_tools_version,system_image_package,system_image_revision,
    avd_name,adb_serial,adb_server_port,emulator_console_port,vcpu,ram_mb,
    display_width,display_height,density_dpi,refresh_hz,gpu_mode,audio_enabled,
    presentation_mode,state,created_at,notes
) VALUES (
    'control_stock_direct_v0',
    'Stock Google direct-play control v0',
    '37.1.11','37.0.1','system-images;android-37.1;google_apis_playstore_ps16k;arm64-v8a',9,
    'TFTMAC_Live_API37','emulator-5592',5040,5592,6,6144,
    1920,1080,320,60.0,'host',1,
    'direct_native_emulator','CONTROL','2026-08-28T07:50:00Z',
    'config_sha256 and observed graphics selections are intentionally NULL until the implementation captures exact runtime state.'
);

INSERT INTO hypotheses VALUES
('h_pso_compile','PSO/shader compilation causes visible stalls','PSO_SHADER','Bursts of Unreal/ANGLE shader or PSO compilation correlate tightly with severe frame-time windows.','Compile/cache events or compiler-process CPU spikes begin immediately before or during stalls and diminish on warm repetition.','Equivalent stalls reproduce without compile/cache activity, or eliminating/warming the compile path does not reduce matched stall windows.','QUEUED',0.0,NULL,'2026-08-28T07:50:00Z','Current measurement required.'),
('h_rhi_serialization','Unreal RHI/command serialization is the throughput limiter','UNREAL_RHI','Heavy scenes serialize enough render/RHI work that downstream graphics layers starve or wait even when host GPU headroom exists.','Heavy frame windows show dominant game/RHI thread time, serialized submission, and host decoder/Metal idle gaps.','Host GPU/Metal is saturated while RHI remains non-dominant, or intervention at RHI serialization does not change matched heavy windows.','QUEUED',0.0,NULL,'2026-08-28T07:50:00Z',NULL),
('h_asg_backpressure','gfxstream/ASG backpressure contributes to frame collapse','GFXSTREAM_ASG','Guest-host transport packing, ring wait, kick/MMIO, or downstream backpressure expands during stall windows.','ASG-related waits/events rise before frame-time spikes and fall under a causal transport intervention.','Stalls occur with stable transport timing or matched transport changes do not alter the frame-time distribution.','QUEUED',0.0,NULL,'2026-08-28T07:50:00Z',NULL),
('h_mvk_queue_wait','MoltenVK queue or command-buffer waits contribute to stalls','MOLTENVK','Vulkan-to-Metal queue synchronization or command-buffer pressure creates long downstream waits.','MoltenVK/Metal timing events cluster with stalls while upstream work is available.','Matched stalls occur without MoltenVK/Metal wait expansion or queue interventions fail controlled confirmation.','QUEUED',0.0,NULL,'2026-08-28T07:50:00Z',NULL),
('h_texture_astc_stream','Texture streaming or ASTC decompression causes transition/combat stalls','TEXTURE_ASTC','New content/effects trigger texture streaming, ASTC decode, upload, or residency work that blocks timely frames.','Stalls align with new texture/decompression/upload events and are reduced on warm repeats or targeted cache/residency changes.','Cold/warm traces show the same stalls without texture/decompression activity or targeted changes have no effect.','QUEUED',0.0,NULL,'2026-08-28T07:50:00Z',NULL),
('h_memory_pressure','Unified-memory pressure causes severe frame drops','MEMORY','The 16 GiB host crosses compression/swap or pressure thresholds during heavy transitions, delaying emulator and graphics work.','Host compressed/swap/pressure metrics rise immediately before or during stalls and a lower-pressure configuration improves matched windows.','Severe stalls reproduce under low stable memory pressure or memory reductions do not affect matched stalls.','QUEUED',0.0,NULL,'2026-08-28T07:50:00Z',NULL),
('h_present_pacing','Presentation/frame pacing creates apparent FPS collapse','SURFACEFLINGER','Rendering work completes but presentation cadence, SurfaceFlinger, swapchain, or host-window pacing introduces long visible intervals.','Producer work remains timely while presentation timestamps develop gaps or cadence aliasing.','Producer/RHI/GPU timing itself is late by the same amount or presentation changes do not alter matched gaps.','QUEUED',0.0,NULL,'2026-08-28T07:50:00Z',NULL),
('h_guest_scheduler','Guest scheduling/affinity starves critical Unreal or compiler work','GUEST_SCHEDULER','Android scheduling, affinity, or priority leaves critical game/compiler workers unable to run promptly during bursts.','Critical threads are runnable but delayed/preempted or constrained to overloaded CPUs around stalls.','Critical threads receive timely CPU service and scheduling interventions do not improve matched stalls.','QUEUED',0.0,NULL,'2026-08-28T07:50:00Z',NULL),
('h_unreal_device_profile','Unreal selects a poor virtual-device profile','DEVICE_PROFILE','The official TFT build classifies the emulator GPU/device into a profile that imposes inappropriate quality, threading, cache, or renderer settings for Apple M4 execution.','Observed Unreal/device-profile state is generic/low/incorrect and a minimal reversible profile correction changes the intended engine behavior plus measured frame results.','The selected profile is already appropriate or profile correction changes no causal engine behavior/performance.','QUEUED',0.0,NULL,'2026-08-28T07:50:00Z',NULL);

INSERT INTO experiments VALUES
('exp_control_direct_play',NULL,'First current official direct-play control','CONTROL_CAPTURE','control_stock_direct_v0',NULL,'COLD',0,'PLANNED',0,'Official package observed; match entry valid; logger complete enough for current control metrics.','2026-08-28T07:50:00Z',NULL,NULL),
('exp_control_repeat_warm',NULL,'Warm repeat of direct-play control','CONTROL_CAPTURE','control_stock_direct_v0',NULL,'WARM',0,'PLANNED',0,'Same runtime/package/config as cold control; semantic workload comparable.','2026-08-28T07:50:00Z',NULL,NULL),
('exp_transition_capture',NULL,'Loading and transition stall capture','OBSERVATION','control_stock_direct_v0',NULL,'TRANSITION',0,'PLANNED',0,'Timestamped transition with valid frame timing, clocks, process/memory samples, and renderer state.','2026-08-28T07:50:00Z',NULL,NULL),
('exp_heavy_capture',NULL,'Combat-heavy control capture','OBSERVATION','control_stock_direct_v0',NULL,'HEAVY',0,'PLANNED',0,'Combat-heavy window is semantically valid and not compared to lobby/login data.','2026-08-28T07:50:00Z',NULL,NULL);

INSERT INTO unknowns VALUES
('u_current_tft_version','What exact versionName/versionCode/signing digest does Google Play install at the first direct-play control?','PACKAGE','OPEN',0,NULL,'2026-08-28T07:50:00Z',NULL,'Resolve from PackageStateManager after official install/update.'),
('u_observed_renderer_path','What graphics path does the current official TFT build actually select under the direct-play control?','GRAPHICS','OPEN',0,NULL,'2026-08-28T07:50:00Z',NULL,'Resolve from renderer-state capture; do not infer from intended flags.'),
('u_drop_reproduction','Does the severe light-state-to-single-digit-FPS collapse reproduce under the clean official-package control?','PERFORMANCE','OPEN',0,NULL,'2026-08-28T07:50:00Z',NULL,'Prior user observation is diagnostic only until reproduced here.'),
('u_storage_bom','What is the exact shipping/control storage bill of materials after TFT is fully patched?','STORAGE','OPEN',0,NULL,'2026-08-28T07:50:00Z',NULL,'Initial ceiling is 35 GiB; measure actual bytes.'),
('u_one_guest_controls','Can one official Play AVD provide every runtime control needed for compatibility and measurement?','RUNTIME','OPEN',0,NULL,'2026-08-28T07:50:00Z',NULL,'Only activate authority/execution split if current evidence says no.');

-- ---------------------------------------------------------------------------
-- Current playable baseline authority: 2026-08-28 first-place match
-- ---------------------------------------------------------------------------
-- Later rows intentionally supersede stale API37/source-AEMU assumptions while
-- preserving those older rows as historical context elsewhere in the project.

INSERT OR REPLACE INTO lab_meta(key,value) VALUES
('current_playable_baseline','tftmac_official_baseline_v1'),
('current_playable_baseline_session','2026-08-28T11-06-18-553Z-e6d3204f-17c2-4b80-9084-e76642089da2'),
('current_guest','Android 16 / API 36 Google Play ARM64 revision >=7'),
('current_emulator','Google Android Emulator 37.1.11'),
('current_tft','18.1-5392842 / versionCode 8392842 / installer com.android.vending'),
('current_renderer_path','TFT Unreal GameActivity -> ANGLE -> Vulkan/ranchu -> virtio-gpu-asg/gfxstream -> MoltenVK -> Metal'),
('current_measurement_gap','gfxinfo does not expose native Unreal/Vulkan gameplay frames; native frame timing is blocking before graphics tuning'),
('current_trace_sources','Perfetto proven available: android.surfaceflinger.frame, android.surfaceflinger.frametimeline, android.surfaceflinger.layers, android.gpu.memory, linux.ftrace, linux.process_stats, linux.sys_stats'),
('current_trace_collector_smoke','5s smoke succeeded: 7479-byte raw pftrace, SHA-256 214dddf456fa94f0ba634dc564f391d576a27bfc6b58610b6e91314376bd9028, four lightweight SurfaceFlinger/GPU-memory sources, zero missed-frame counter delta during idle smoke'),
('logger_guard_policy','Sampler starts before emulator; sampler must survive startup; launch-game requires a live growth health check; MATCH_ENTRY and COMBAT_START require fresh process, memory and logcat streams; status reports LOGGER_FAULT when the gate is not ready.'),
('raw_capture_seal_policy','Raw JSONL/text telemetry is authoritative and is sealed before SQLite normalization. SQLite/post-processing failure must be recorded as a secondary error and must never prevent capture closure, emulator cleanup, manifest preservation, or control-state release.'),
('continuous_run_validity_policy','A continuous run is semantically valid when official Google Play TFT authority plus process, memory and clock telemetry are present. Match-entry markers and native gfxinfo frame timing are not required for the raw run to be COMPLETE; frame-timing validity is tracked separately.'),
('surfaceflinger_counter_policy','New logger sessions sample SurfaceFlinger total/GPU/HWC missed-frame counters every 10 seconds into surfaceflinger/counters.jsonl so presentation degradation can be correlated to CPU, memory and application events without manual per-match markers.'),
('multi_match_policy','Keep raw telemetry continuous across games. Pair each MATCH_ENTRY with the next MATCH_RESULT; preserve per-match analysis artifacts; ingest match 2+ as distinct <capture-session>-match-N SQL sessions so later games never overwrite earlier evidence.'),
('current_tft_graphics_domain','Low | Medium | High | Ultra High'),
('current_tft_fps_cap_domain','30 | 60 | None'),
('current_tft_graphics_observed','Medium'),
('current_tft_fps_cap_observed','60'),
('current_tft_performance_mode_beta_observed','OFF'),
('current_optimization_priority','Continuous-run analysis is authoritative. Keep the logger running and analyze the whole capture; treat matches, placements, graphics preset, FPS cap, Performance Mode, app restarts, ANRs and user quality reports as timestamped annotations. Change one variable at a time, but do not require per-match start/stop boundaries.');

INSERT OR REPLACE INTO host_facts VALUES
('control_image','control_system_image','system-images;android-36;google_apis_playstore;arm64-v8a',NULL,'DIRECT_OBSERVATION','gameplay-analysis.json','FROZEN','2026-08-28T18:30:59Z','First full official TFT match completed on this real Google Play image family.'),
('control_image_revision','control_system_image_revision','>=7',NULL,'DIRECT_OBSERVATION','runtime inventory + source.properties','FROZEN','2026-08-28T18:30:59Z','Installed API36 Play ARM64 image satisfies revision-7 minimum used by current control.'),
('control_avd','control_avd_name','TFT_Ultra_Tablet',NULL,'DIRECT_OBSERVATION','runtime-state.json','FROZEN','2026-08-28T18:30:59Z','Single official Play AVD used for package authority and gameplay execution.');

INSERT OR REPLACE INTO runtime_configs (
    id,parent_config_id,name,emulator_version,platform_tools_version,system_image_package,system_image_revision,
    avd_name,adb_serial,adb_server_port,emulator_console_port,vcpu,ram_mb,
    display_width,display_height,density_dpi,refresh_hz,gpu_mode,audio_enabled,
    graphics_transport,angle_mode,vulkan_mode,moltenvk_mode,presentation_mode,state,created_at,notes
) VALUES
('tftmac_official_baseline_v1',NULL,'TFTMAC official playable baseline official TFT control v0','37.1.11','37.0.1','system-images;android-36;google_apis_playstore;arm64-v8a',7,'TFT_Ultra_Tablet','emulator-5592',5040,5592,6,6144,1920,1080,320,60.0,'host',1,'virtio-gpu-asg','GuestAngle + explicit exposeNonConformantExtensionsAndVersions/exposeES32ForTesting compatibility adapter','ranchu guest Vulkan','gfxstream host Vulkan -> MoltenVK/Metal','direct emulator window','CONTROL','2026-08-28T11:06:18Z','Completed a full first-place official TFT match. Compatibility exposure is a truthful workload adapter, not GLES conformance proof.'),
('tftmac_5gb_baseline_v1','tftmac_official_baseline_v1','RAM 5 GiB candidate','37.1.11','37.0.1','system-images;android-36;google_apis_playstore;arm64-v8a',7,'TFT_Ultra_Tablet','emulator-5592',5040,5592,6,5120,1920,1080,320,60.0,'host',1,'virtio-gpu-asg','same as baseline','same as baseline','same as baseline','same as baseline','CANDIDATE','2026-08-28T21:31:30Z','One-factor candidate: only guest RAM changes 6144 -> 5120 MB. Direct 4096 MB cut deferred because observed heavy-gameplay guest headroom reaches about 1.64-1.75 GiB.'),
('tftmac_5gb_flush400_exp_v1','tftmac_5gb_baseline_v1','5 GiB + lower draw flush interval candidate','37.1.11','37.0.1','system-images;android-36;google_apis_playstore;arm64-v8a',7,'TFT_Ultra_Tablet','emulator-5592',5040,5592,6,5120,1920,1080,320,60.0,'host',1,'virtio-gpu-asg','same as 5 GiB baseline','same as 5 GiB baseline','same as 5 GiB baseline','same as 5 GiB baseline','CANDIDATE','2026-08-28T23:47:00Z','One-factor graphics-transport candidate: hw.gltransport.drawFlushInterval 800 -> 400 only. AOSP defines this interval as the balance between host-GPU starvation and pipe-notification overhead; test only against SurfaceFlinger miss-rate and resource telemetry.');

UPDATE hypotheses
SET status='TESTING', confidence=0.60,
    nominated_from_session_id=NULL,
    notes='First full match: emulator RSS mean about 5155 MiB, max about 6846 MiB; host compressed memory mean about 4.15 GiB; pageouts +12876. Candidate cause only until controlled A/B.'
WHERE id='h_memory_pressure';

INSERT OR REPLACE INTO hypotheses VALUES
('h_guest_ram_host_pressure','Guest RAM allocation amplifies host memory pressure','MEMORY','The 6144 MB Android guest contributes enough host RSS/compression/pageout pressure to worsen gameplay responsiveness on the 16 GiB M4 host.','A 5120 MB one-factor run lowers emulator RSS/host compression while preserving at least about 1 GiB guest headroom under comparable load and without guest OOM or instability.','5120 MB does not reduce pressure, materially degrades guest headroom, or worsens comparable gameplay.','QUEUED',0.72,NULL,'2026-08-28T21:31:30Z','Game 2 and restart-effect analysis strengthen memory pressure as the current intervention target; 5 GiB is the safer first cut.'),
('h_gpu_frame_miss','GPU-side presentation misses contribute to visible lag','SURFACEFLINGER','A meaningful portion of visible gameplay lag is caused by GPU/presentation misses somewhere in the Unreal -> ANGLE -> Vulkan -> gfxstream -> MoltenVK -> Metal path.','TFT-specific SurfaceFlinger frametimeline traces show GPU-missed or late frames correlated with visible stalls while memory state is controlled.','TFT-specific frametimeline remains healthy during visible stalls, or misses disappear without improving perceived performance.','QUEUED',0.35,NULL,'2026-08-28T18:42:01Z','Nominated from cumulative SurfaceFlinger counters only: 2709 total missed, 2163 GPU missed, 546 HWC missed at the latest post-match read. These counters are since boot and are not match-scoped.');

INSERT OR REPLACE INTO experiments VALUES
('exp_ram_5gb_ab','h_guest_ram_host_pressure','Guest RAM 6144 -> 5120 MB A/B','INTERVENTION','tftmac_official_baseline_v1','tftmac_5gb_baseline_v1','HEAVY',1,'PLANNED',1,'Same official TFT version, renderer path, display, transport and vCPU; compare continuous-run pressure and native frame timing when available.','2026-08-28T21:31:30Z',NULL,'First RAM intervention. One GiB reduction only; 4096 MB is deferred because current guest headroom is insufficient for a safe first cut.'),
('exp_native_frame_trace',NULL,'Native Unreal/Vulkan frame-timing capture','OBSERVATION','tftmac_official_baseline_v1',NULL,'HEAVY',0,'PLANNED',0,'Capture android.surfaceflinger.frame + android.surfaceflinger.frametimeline + android.surfaceflinger.layers + android.gpu.memory during real TFT combat; align to the existing host monotonic clock. Add linux.ftrace only in the heavier validation run.','2026-08-28T18:30:59Z',NULL,'Blocking measurement experiment before renderer/transport tuning. All required Perfetto data sources are directly proven available on the current guest.');

UPDATE experiments
SET baseline_config_id='tftmac_official_baseline_v1',
    state='COMPLETE',
    notes=COALESCE(notes,'') || ' Superseded runtime identity corrected to the proven playable baseline.'
WHERE id='exp_control_direct_play';

UPDATE experiments
SET state='CANCELLED',
    notes=COALESCE(notes,'') || ' Superseded by tftmac_official_baseline_v1 and exp_native_frame_trace.'
WHERE id IN ('exp_control_repeat_warm','exp_transition_capture','exp_heavy_capture')
  AND baseline_config_id='control_stock_direct_v0';

INSERT OR REPLACE INTO unknowns VALUES
('u_native_frame_timing','What is the real Unreal/Vulkan frame-time distribution and which boundary owns visible stalls?','FRAME_TIMING','OPEN',1,NULL,'2026-08-28T18:30:59Z',NULL,'gfxinfo returned zero gameplay frames. Exact available replacement sources: android.surfaceflinger.frame + frametimeline + layers + android.gpu.memory; linux.ftrace/process_stats/sys_stats are available for heavier correlation.'),
('u_drop_reproduction','Does the severe low-performance/laggy behavior reproduce under the clean official-package control?','PERFORMANCE','OPEN',0,NULL,'2026-08-28T07:50:00Z',NULL,'User reported the first full match as laggy/low-performance; resource pressure reproduced, but native frame timing is still missing for quantitative attribution.');

INSERT OR REPLACE INTO hypotheses VALUES
('h_asg_flush_latency','ASG draw flush cadence contributes to presentation lateness','GFXSTREAM_ASG','The current draw-flush cadence allows guest graphics work to reach the host late enough to contribute to SurfaceFlinger/HWC presentation misses even when GPU-miss counters remain flat.','Reducing drawFlushInterval 800 -> 400 lowers HWC/total missed-frame rate in comparable gameplay without a disproportionate CPU or notification-overhead penalty.','HWC/total miss rate does not improve, or host CPU/overhead rises materially enough to offset frame-pacing gains.','QUEUED',0.45,NULL,'2026-08-28T23:47:00Z','Nominated from broad 5 GiB run delta: +524 total misses, +524 HWC misses, +0 GPU misses, plus available host CPU headroom. Requires 10-second SurfaceFlinger counter stream for a clean A/B.');

INSERT OR REPLACE INTO experiments VALUES
('exp_asg_flush400_ab','h_asg_flush_latency','ASG draw flush interval 800 -> 400 A/B','INTERVENTION','tftmac_5gb_baseline_v1','tftmac_5gb_flush400_exp_v1','HEAVY',1,'PLANNED',1,'Keep 5 GiB RAM, 6 vCPU, 1920x1080, Medium/60/Performance OFF, ANGLE/Vulkan/MoltenVK, ASG sizes and TFT package unchanged; compare 10-second SurfaceFlinger HWC/GPU/total miss rate plus CPU/memory.','2026-08-28T23:47:00Z',NULL,'Do not activate until a stable 5 GiB/CoreAudio control run is available with the new SurfaceFlinger counter stream.'),
('exp_tft_performance_mode_ab',NULL,'TFT Performance Mode (Beta) A/B','INTERVENTION','tftmac_official_baseline_v1',NULL,'HEAVY',1,'PLANNED',0,'Keep Medium graphics, 60 FPS cap, emulator/runtime/package identical; change only Performance Mode (Beta) ON/OFF and compare native frame timing + memory/GPU pressure.','2026-08-28T20:11:18Z',NULL,'First game-level intervention after the fully labeled Medium/60 baseline.'),
('exp_tft_fps_cap_ab',NULL,'TFT FPS cap A/B','INTERVENTION','tftmac_official_baseline_v1',NULL,'HEAVY',1,'PLANNED',0,'Hold graphics preset and Performance Mode constant; compare 60 versus None first, with 30 retained as a diagnostic lower-load control if needed.','2026-08-28T20:11:18Z',NULL,'Do not combine FPS-cap changes with graphics-preset changes.'),
('exp_tft_graphics_preset_ab',NULL,'TFT graphics preset A/B','INTERVENTION','tftmac_official_baseline_v1',NULL,'HEAVY',1,'PLANNED',0,'Hold FPS cap and Performance Mode constant; test Low, Medium, High, Ultra High one preset at a time with native frame timing.','2026-08-28T20:11:18Z',NULL,'Target is the highest preset that preserves stable 60-Hz frame pacing and acceptable memory/GPU pressure.');

INSERT OR REPLACE INTO lab_meta(key,value) VALUES
('latest_observed_match_2','placement=1; result=WIN; exact result at 2026-08-28T20:57:14.054Z'),
('latest_observed_match_2_settings','graphics=Medium; fps_cap=60; performance_mode_beta=OFF'),
('latest_observed_match_2_quality','User reported gameplay much better and graphics visibly improved versus Game 1.'),
('latest_observed_match_2_boundary','PARTIAL: exact MATCH_ENTRY missing; resource comparison uses TFT_APP_RESTART_COMPLETE at 2026-08-28T20:17:03.528Z as a non-authoritative start proxy.'),
('latest_observed_match_2_directional_memory','Approximate window vs Game1: host compressed mean -0.783 GiB, host available mean +0.443 GiB, pageout delta difference -2236; emulator CPU/RSS were higher despite better perceived quality.'),
('restart_effect_equal_windows','10/20/30 minute equal pre/post TFT app-restart analysis: host available mean improved by ~0.90-0.94 GiB and host compressed mean fell by ~1.83-1.99 GiB after restart, despite substantially higher emulator CPU/RSS. This supports app-only refresh as a low-risk pressure-relief intervention.'),
('preplay_memory_hygiene_policy','Before a new play run, if host compressed memory >=3.75 GiB or host available <=4.75 GiB, refresh only the TFT app process while preserving emulator and logger. Thresholds were tightened from 4.5/4.25 after the 5 GiB 10-minute trend showed end-of-run pressure at compressed ~3.98 GiB and available ~4.71 GiB. Earlier live refresh changed compressed 4.97 -> 2.48 GiB and available 4.23 -> 5.59 GiB.'),
('ram_candidate_revision','First RAM candidate revised from 4096 MB to 5120 MB. Game 2 guest available minimum ~2.24 GiB at 6144 MB means a 2 GiB cut risks low-memory instability; 1 GiB is the safer reversible step.'),
('ram_5gb_candidate_live','5120 MB candidate cold-booted successfully on the same API36 Play/ANGLE/Vulkan/gfxstream/MoltenVK path. TFT GameActivity is running with logger healthy; initial post-launch pressure sample: host compressed 1.48 GiB, host available 5.97 GiB, guest available 2.40 GiB. This is promising but not causal proof until sustained gameplay is captured.'),
('cold_boot_unlock_fix','Cold boot can leave Android user 0 RUNNING_LOCKED and the display asleep. Automatic PIN/keyguard manipulation was removed after it produced a black-screen workflow. TFTMAC now wakes the guest through the Android power path, keeps the controlled display awake, exposes the lock screen when needed, and leaves secure PIN entry manual.'),
('latest_5gb_trend','Latest closed 5 GiB run: across 10-minute windows, heavy gameplay reached about 245-277% emulator CPU, 6.1-6.5 GiB emulator RSS, 5.1-5.5 GiB host available and 1.64-1.75 GiB guest available. First-to-last run trend: host compressed +2.72 GiB, host available -2.62 GiB, emulator RSS +1.18 GiB. This supports between-game process refresh, not a further guest-RAM cut.'),
('latest_5gb_vs_6gb_rate','Whole-run normalized pageout rate: 6 GiB ~207.18 pages/min versus 5 GiB ~133.54 pages/min, directional reduction ~35.55%. Host compressed mean improved by ~0.45 GiB and p95 by ~1.65 GiB. Workload durations/mixes differ, so retain as directional evidence rather than a final causal promotion.'),
('latest_audio_coreaudio','Current 5 GiB run explicitly uses -audio coreaudio. TFT OpenSL ES playback is active at 44.1 kHz stereo, mixer underruns are 0/0, ranchu pcm_writei I/O errors=0 and ranchu pcmWrite failures=0; user audible confirmation remains the final sound acceptance check.');

UPDATE experiments
SET state='COMPLETE', completed_at='2026-08-28T23:49:00Z',
    notes=COALESCE(notes,'') || ' Completed operational A/B review: 5 GiB reduced normalized pageout rate and host compression while preserving heavy-gameplay guest headroom and avoiding ANR/OOM. Workload mixes differ, so no permanent performance-fact promotion yet.'
WHERE id='exp_ram_5gb_ab';

UPDATE hypotheses
SET status='SUPPORTED', confidence=0.72,
    notes='5 GiB continuous-run evidence supports the guest-RAM/host-pressure relationship directionally: pageouts/min fell ~35.55%, compressed mean ~0.45 GiB, compressed p95 ~1.65 GiB; heavy-gameplay guest available stayed ~1.64-1.75 GiB. Different workload mixes prevent stronger causal promotion.'
WHERE id='h_guest_ram_host_pressure';

INSERT OR REPLACE INTO comparisons(id,experiment_id,metric_name,baseline_value,candidate_value,unit,delta_absolute,delta_percent,preferred_direction,threshold_value,threshold_pass,notes) VALUES
('cmp_ram5_pageouts_per_min','exp_ram_5gb_ab','pageouts_per_minute',207.18249779705226,133.5369774348699,'pages/min',-73.64552036218237,-35.54620739939268,'LOWER',NULL,1,'Normalized whole-run rate; durations/workload mixes differ, so directional only.'),
('cmp_ram5_compressed_mean','exp_ram_5gb_ab','host_compressed_mean_gib',3.2772283171328036,2.827203501142508,'GiB',-0.45002481599029576,-13.73190892053242,'LOWER',NULL,1,'Directional whole-run comparison.'),
('cmp_ram5_compressed_p95','exp_ram_5gb_ab','host_compressed_p95_gib',5.47772216796875,3.8231048583984375,'GiB',-1.6546173095703125,-30.20630377306726,'LOWER',NULL,1,'Directional whole-run comparison.'),
('cmp_ram5_host_available_mean','exp_ram_5gb_ab','host_available_mean_gib',5.165474834410154,5.52483720710668,'GiB',0.35936237269652604,6.956996041806079,'HIGHER',NULL,1,'Directional whole-run comparison.');

INSERT OR REPLACE INTO evidence(id,hypothesis_id,session_id,experiment_id,evidence_type,claim,relation,strength,source_artifact_id,created_at,notes) VALUES
('ev_ram5_operational_keep','h_guest_ram_host_pressure',NULL,'exp_ram_5gb_ab','DIRECT_MEASUREMENT','5 GiB reduced normalized pageout rate from ~207.18/min to ~133.54/min and reduced host compressed-memory mean/p95 while completing a full official TFT win with no ANR, fatal signal or OOM. Heavy-gameplay guest available memory stayed around 1.64-1.75 GiB.','SUPPORTS','STRONG',NULL,'2026-08-28T23:49:00Z','Operational KEEP only; workload-duration mismatch prevents final performance-fact promotion.');

INSERT OR REPLACE INTO decisions(id,experiment_id,decision,rationale,cold_confirmation_complete,promoted_config_id,decided_at,notes) VALUES
('decision_ram5_operational_keep','exp_ram_5gb_ab','KEEP','Retain 5120 MB guest RAM for continued development: host-pressure indicators improved materially and the guest retained usable headroom without OOM/ANR. Do not cut to 4096 MB now.','0',NULL,'2026-08-28T23:49:00Z','KEEP means current development default, not a permanent promoted performance fact.');

INSERT OR REPLACE INTO lab_meta(key,value) VALUES
('latest_closed_run_session','2026-08-28T23-31-16-637Z-df54ebaa-561a-4567-ab20-d94baf0a3619; 3860.24s; tftmac_5gb_baseline_v1; raw SEALED; normalized COMPLETE; 18/18 required artifacts present.'),
('latest_closed_run_memory','Full-run weighted means: emulator CPU 171.87%, RSS 5829 MiB, host available 5.425 GiB, host compressed 2.793 GiB, guest available 2.224 GiB. Heavy windows reproduced about 1.70-1.90 GiB guest headroom. Keep 5120 MB and defer/reject 4096 MB for now.'),
('latest_closed_run_pageouts','10711 pageouts / 3860.24s = 166.48 per minute including cold boot. Excluding first 10 minutes gives about 127.94 per minute, close to prior 5 GiB run 133.54 per minute and below old 6 GiB baseline 207.18 per minute. Treat as repeated directional support, not perfectly matched workload proof.'),
('latest_closed_run_audio','CoreAudio sustained: explicit backend, 0 ranchu pcm_write I/O errors, active TFT 44.1 kHz stereo OpenSL ES track, 0 mixer underruns.'),
('latest_closed_run_network','No emulator/Android network disconnect reproduced: TFT PID stayed 5276; network 101 stayed assigned; end-of-game callback requests were immediately reassigned to network 101.'),
('latest_closed_run_presentation','Surface remains 1280x720 scaled to 1920x1080; post-run total missed=562 and HWC missed=562 at 60 Hz. Zero-valued GPU counter parsing was fixed so zero no longer becomes NULL. Next graphics intervention remains ASG drawFlushInterval 800 -> 400 only.'),
('current_5gb_operational_decision','KEEP 5120 MB as development runtime. Two long runs reproduce lower pressure/pageout direction versus 6144 MB while maintaining adequate heavy-game guest headroom; 4096 MB remains deferred.'),
('current_graphics_experiment','Next one-factor candidate: tftmac_5gb_flush400_exp_v1, drawFlushInterval 800 -> 400 only. Hold RAM, in-game settings, CoreAudio, resolution, vCPU, ANGLE, Vulkan, gfxstream and MoltenVK constant.'),
('latest_graphics_quality_observation','2026-08-28 late game: user changed TFT from Medium to Ultra High, observed Ultra High as unplayable due to severe lag, then returned to Medium and playability recovered. Exact switch timestamps were not instrumented in this legacy run, so do not assign telemetry bins or inferred FPS values to the Ultra High interval.'),
('current_tft_graphics_observed','Medium'),
('ultra_high_current_usability','REJECT for current runtime usability until new native-app FPS/config instrumentation can quantify the boundary; direct user observation is decisive for usability but not causal pipeline attribution.');

UPDATE experiments
SET notes=COALESCE(notes,'') || ' Latest qualitative result: Ultra High was unplayable from severe lag and returning to Medium restored playability. Exact switch timestamps/FPS were not captured, so this is a usability rejection for Ultra High, not a completed quantitative preset A/B.'
WHERE id='exp_tft_graphics_preset_ab';

INSERT OR REPLACE INTO evidence(id,hypothesis_id,session_id,experiment_id,evidence_type,claim,relation,strength,source_artifact_id,created_at,notes) VALUES
('ev_ultra_high_unplayable_user_observation',NULL,NULL,'exp_tft_graphics_preset_ab','CONFIG_OBSERVATION','User directly observed Ultra High as unplayable because of severe lag in the completed late-game run; returning to Medium restored playability.','NEUTRAL','DECISIVE',NULL,'2026-08-29T03:02:00Z','No exact preset-switch timestamp and no trustworthy legacy native-Vulkan FPS stream. Preserve as decisive usability evidence only; do not fabricate a numeric Ultra High frame rate or telemetry window.');

COMMIT;

-- Recommended first queries after ingestion:
-- SELECT * FROM v_session_quality;
-- SELECT * FROM v_stall_summary ORDER BY max_frame_interval_ns DESC;
-- SELECT * FROM v_open_hypotheses;
-- SELECT * FROM v_experiment_scorecard;
-- SELECT * FROM v_promoted_facts;

-- ---------------------------------------------------------------------------
-- 2026-08-30 native AppKit/Metal runtime authority
-- Historical 5040/5592/6144 rows above remain immutable experiment receipts.
-- ---------------------------------------------------------------------------
INSERT OR REPLACE INTO runtime_configs (
    id,parent_config_id,name,emulator_version,platform_tools_version,system_image_package,system_image_revision,
    avd_name,adb_serial,adb_server_port,emulator_console_port,vcpu,ram_mb,
    display_width,display_height,density_dpi,refresh_hz,gpu_mode,audio_enabled,
    graphics_transport,angle_mode,vulkan_mode,moltenvk_mode,presentation_mode,state,created_at,notes
) VALUES
('tftmac_5gb_native_v1','tftmac_5gb_baseline_v1','TFTMAC native full-screen 5 GiB baseline','37.1.11','37.0.1','system-images;android-36;google_apis_playstore;arm64-v8a',7,'TFT_Ultra_Tablet','emulator-5582',5038,5582,6,5120,1920,1080,320,60.0,'host',1,'virtio-gpu-asg','GuestAngle + explicit exposeNonConformantExtensionsAndVersions/exposeES32ForTesting compatibility adapter','ranchu guest Vulkan','gfxstream host Vulkan -> MoltenVK/Metal','authenticated raw gRPC -> AppKit Metal full screen','CONTROL','2026-08-30T08:40:36Z','Donor-compatible logged-in-session launcher: /usr/bin/open -n -W through packaged TFTMAC Emulator Host.app; ADB_VENDOR_KEYS absent. Native lobby acceptance passed; source/presentation counters are transport metrics, not Unreal engine FPS.');

INSERT OR REPLACE INTO sessions(
    id,runtime_config_id,started_utc,ended_utc,host_start_mono_ns,host_end_mono_ns,
    boot_class,workload_class,package_name,package_version_name,package_version_code,
    package_state_sha256,renderer_state_sha256,session_manifest_sha256,
    package_updated_during_session,capture_state,semantic_valid,invalid_reason,notes
) VALUES
('2026-08-30T08-40-36.792Z-5637b7cf-0c8b-435e-adbb-8f4c0e18de94','tftmac_5gb_native_v1','2026-08-30T08:40:36Z',NULL,NULL,NULL,'COLD','LOBBY','com.riotgames.league.teamfighttactics','18.1-5402721','8402721',NULL,NULL,NULL,0,'PARTIAL',1,NULL,'Native full-screen lobby acceptance; capture was still open when this SSOT receipt was written.');

INSERT OR REPLACE INTO lab_meta(key,value) VALUES
('current_playable_baseline','tftmac_5gb_native_v1'),
('current_native_runtime_config','tftmac_5gb_native_v1'),
('current_native_acceptance_session','2026-08-30T08-40-36.792Z-5637b7cf-0c8b-435e-adbb-8f4c0e18de94'),
('current_runtime_identity','ADB 5038; console 5582; serial emulator-5582; packaged app host via /usr/bin/open; no injected ADB_VENDOR_KEYS'),
('current_native_frame_truth','Raw gRPC source-window rate and Metal presentation rate are transport/output metrics only. Do not label either as Unreal engine FPS.'),
('current_native_logger','Private local capture: SQL receipts/events, one-second frame interval windows, presentation, qemu CPU/RSS, guest memory, clock sync, SurfaceFlinger deltas, AudioFlinger health, aggregate logcat signals, game PID sessions, input counts and explicit match/stutter markers.'),
('current_surfaceflinger_counter_policy','Sample the live dumpsys SurfaceFlinger counters every 30 seconds during gameplay and at session boundaries. Compare deltas inside marked windows; absolute counters remain cumulative since boot.'),
('current_optimization_priority','Hold 1920x1080/320 dpi, 5038/5582, 5120 MiB, 6 vCPU, CoreAudio, host GPU and the renderer chain. Run one restart-bound variable A/B at a time and require cold confirmation before promotion.');

INSERT OR REPLACE INTO evidence(id,hypothesis_id,session_id,experiment_id,evidence_type,claim,relation,strength,source_artifact_id,created_at,notes) VALUES
('ev_native_fullscreen_acceptance_20260830',NULL,'2026-08-30T08-40-36.792Z-5637b7cf-0c8b-435e-adbb-8f4c0e18de94',NULL,'DIRECT_MEASUREMENT','Native TFTMAC filled the 1920x1080 display in an AppKit full-screen window, authenticated Emulator37.1.11 gRPC, authorized emulator-5582 on ADB5038, rendered 1920x1080 RGBA through Metal at about 60 output presentations/s, and launched official TFT18.1 into Unreal GameActivity.','NEUTRAL','DECISIVE',NULL,'2026-08-30T08:41:35Z','Capture 2026-08-30T08-40-36.792Z-5637b7cf-0c8b-435e-adbb-8f4c0e18de94. Lobby/input/software-audio path proven; full-match and user-audible acceptance remain separate.');

-- ---------------------------------------------------------------------------
-- 2026-08-31 Build 8 automatic full-run capture: current causal baseline
-- This preserves older measurements while replacing neither their rows nor
-- their historical conclusions. The raw SQLite capture remains private.
-- ---------------------------------------------------------------------------
INSERT OR REPLACE INTO runtime_configs (
    id,parent_config_id,name,emulator_version,platform_tools_version,system_image_package,system_image_revision,
    avd_name,adb_serial,adb_server_port,emulator_console_port,vcpu,ram_mb,
    display_width,display_height,density_dpi,refresh_hz,gpu_mode,audio_enabled,
    graphics_transport,angle_mode,vulkan_mode,moltenvk_mode,presentation_mode,state,created_at,notes
) VALUES (
    'tftmac_stock_build8_high60_control','tftmac_5gb_native_v1','Stock Build 8 High/60 normal-play control','37.1.11','37.0.1','system-images;android-36;google_apis_playstore;arm64-v8a',7,
    'TFT_Ultra_Tablet','emulator-5582',5038,5582,6,5120,1920,1080,320,60.0,'host',1,
    'virtio-gpu-asg','Conditional: do not assume ANGLE is TFT main rendering path','Unreal direct Vulkan observed','gfxstream host Vulkan -> MoltenVK/Metal','authenticated raw gRPC -> AppKit Metal full screen','CONTROL','2026-08-31T22:30:26Z',
    'Normal-play authority. Active observed experiment combat_latency_a uses High/60/Performance Mode OFF and is not a promoted performance intervention.'
);

INSERT OR REPLACE INTO sessions(
    id,runtime_config_id,started_utc,ended_utc,host_start_mono_ns,host_end_mono_ns,
    boot_class,workload_class,package_name,package_version_name,package_version_code,
    package_state_sha256,renderer_state_sha256,session_manifest_sha256,
    package_updated_during_session,capture_state,semantic_valid,invalid_reason,notes
) VALUES (
    '2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200','tftmac_stock_build8_high60_control','2026-08-31T22:31:03Z','2026-08-31T23:13:30Z',NULL,NULL,
    'UNKNOWN','MIXED','com.riotgames.league.teamfighttactics','18.1-5402721','8402721',NULL,NULL,NULL,
    0,'COMPLETE',1,NULL,'42m27s automatic PID/layer-lifetime run. Markers and battle labels are optional annotations; no marker is required for validity or causal analysis.'
);

INSERT OR REPLACE INTO artifacts(id,session_id,experiment_id,artifact_kind,path,sha256,byte_count,required,state,created_at,notes) VALUES
('artifact_build8_current_private_db','2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200',NULL,'PRIVATE_SQLITE_CAPTURE','PRIVATE_LOCAL_ONLY/TFTMAC_NATIVE_RUNTIME.sqlite','c1ef9c9ffe591a297cb86660e3ccfea7e9aeb593f22100e4e732b2fc77d4ee77',63897600,1,'PRESENT','2026-08-31T23:13:30Z','Metadata and integrity hash only; raw database is intentionally excluded from Git.');

INSERT OR REPLACE INTO experiments VALUES
('exp_build8_automatic_full_run',NULL,'Build 8 automatic full-run graphics observation','OBSERVATION','tftmac_stock_build8_high60_control',NULL,'MIXED',0,'COMPLETE',0,'Automatic PID/layer lifetime, exact TFT layer and receipt linkage; markers/battle labels are optional and have no validity role.','2026-08-31T22:30:26Z','2026-08-31T23:13:30Z','Diagnostic observation only; establishes current performance facts and preserves root attribution as UNKNOWN.');

INSERT OR REPLACE INTO experiment_sessions(experiment_id,session_id,role) VALUES
('exp_build8_automatic_full_run','2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200','DIAGNOSTIC');

INSERT INTO metrics(session_id,experiment_id,metric_scope,metric_name,metric_value,unit,source_artifact_id,semantic_valid,notes) VALUES
('2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200','exp_build8_automatic_full_run','GRAPHICS_RUN','weighted_fps',56.98,'fps','artifact_build8_current_private_db',1,'Exact TFT SurfaceFlinger actual-present authority.'),
('2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200','exp_build8_automatic_full_run','GRAPHICS_RUN','fps_1_percent_low',21.49,'fps','artifact_build8_current_private_db',1,'Exact TFT SurfaceFlinger actual-present authority.'),
('2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200','exp_build8_automatic_full_run','GRAPHICS_RUN','p50_frame_interval',16.707,'ms','artifact_build8_current_private_db',1,NULL),
('2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200','exp_build8_automatic_full_run','GRAPHICS_RUN','p95_frame_interval',21.51,'ms','artifact_build8_current_private_db',1,NULL),
('2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200','exp_build8_automatic_full_run','GRAPHICS_RUN','p99_frame_interval',33.434,'ms','artifact_build8_current_private_db',1,NULL),
('2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200','exp_build8_automatic_full_run','GRAPHICS_RUN','max_frame_interval',2233.611,'ms','artifact_build8_current_private_db',1,NULL),
('2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200','exp_build8_automatic_full_run','GRAPHICS_RUN','jank_count',6544,'frames','artifact_build8_current_private_db',1,NULL),
('2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200','exp_build8_automatic_full_run','GRAPHICS_RUN','jank_percent',4.53,'percent','artifact_build8_current_private_db',1,NULL),
('2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200','exp_build8_automatic_full_run','GRAPHICS_RUN','severe_stall_count',144,'windows','artifact_build8_current_private_db',1,NULL),
('2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200','exp_build8_automatic_full_run','GRAPHICS_RUN','missed_vsync_equivalent_count',7644,'frames','artifact_build8_current_private_db',1,NULL),
('2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200','exp_build8_automatic_full_run','GRAPHICS_RUN','exact_layer_coverage',99.629,'percent','artifact_build8_current_private_db',1,NULL),
('2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200','exp_build8_automatic_full_run','GRAPHICS_RUN','frame_interval_count',144364,'intervals','artifact_build8_current_private_db',1,NULL),
('2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200','exp_build8_automatic_full_run','GRAPHICS_RUN','degradation_incident_count',189,'incidents','artifact_build8_current_private_db',1,'Incident count is aggregate; no battle classifier is used as a causal gate.');

INSERT OR REPLACE INTO evidence(id,hypothesis_id,session_id,experiment_id,evidence_type,claim,relation,strength,source_artifact_id,created_at,notes) VALUES
('ev_build8_current_full_run',NULL,'2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200','exp_build8_automatic_full_run','DIRECT_MEASUREMENT','Build 8 automatically captured a complete 42m27s TFT graphics run with 144364 exact-layer frame intervals and 99.629% exact-layer coverage. The observed direct path is Unreal Vulkan -> gfxstream/ASG -> host Vulkan -> MoltenVK -> Metal; ANGLE is conditional, final Mac presentation is context-only, and the first causal boundary remains UNKNOWN.','NEUTRAL','DECISIVE','artifact_build8_current_private_db','2026-08-31T23:13:30Z','No raw database, screenshots, credentials, or frame payloads are committed.'),
('ev_build8_current_root_unknown',NULL,'2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200','exp_build8_automatic_full_run','TRACE_CORRELATION','Current automatic logging proves degradation but cannot identify an internal owned root component because no shared guest-to-host causal work ID exists.','NEUTRAL','DECISIVE','artifact_build8_current_private_db','2026-08-31T23:13:30Z','Do not infer ASG, gfxstream, MoltenVK, Metal, ANGLE, or Unreal ownership from the present capture.');

INSERT OR REPLACE INTO decisions(id,experiment_id,decision,rationale,cold_confirmation_complete,promoted_config_id,decided_at,notes) VALUES
('decision_build8_current_full_run','exp_build8_automatic_full_run','DIAGNOSTIC_ONLY','The capture verifies automatic logging and current full-run degradation metrics, but it is not a controlled promotion and root attribution is UNKNOWN.',0,NULL,'2026-08-31T23:13:30Z','Keep stock Build 8 as normal-play authority; advanced source causal logging is planned.');

INSERT OR REPLACE INTO unknowns(id,question,boundary,status,blocking,resolution_evidence_id,opened_at,resolved_at,notes) VALUES
('u_current_internal_root_cause','Which owned graphics component first diverges before TFT SurfaceFlinger actual-present degradation?','CROSS_STACK_CAUSAL','OPEN',1,NULL,'2026-08-31T23:13:30Z',NULL,'Requires the planned source-instrumented causal logger and complete work-ID joins.');

INSERT OR REPLACE INTO lab_meta(key,value) VALUES
('current_playable_baseline','tftmac_stock_build8_high60_control'),
('current_playable_baseline_session','2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200'),
('current_release_gameplay_benchmark','VERIFIED_CAPTURE_ROOT_ATTRIBUTION_UNKNOWN'),
('current_runtime_mode','STOCK_BUILD8_NORMAL_PLAY_AUTHORITY'),
('current_active_experiment','combat_latency_a observed High/60/Performance Mode OFF; not promoted'),
('current_renderer_path','Unreal direct Vulkan -> gfxstream/ASG -> host Vulkan -> MoltenVK -> Metal; ANGLE conditional only'),
('current_mac_presenter_policy','Final Mac presenter is excluded from causal candidates and retained only as context/correctness telemetry.'),
('current_marker_policy','MATCH_ENTRY, MATCH_END, combat, battle, and quality markers are optional annotations only; automatic process/layer lifetime defines capture validity.'),
('current_root_attribution','UNKNOWN_UPSTREAM_OF_OR_AT_GUEST_SURFACE'),
('advanced_source_causal_logger','PLANNED: isolated non-comparable tftmac-runtime diagnostic build; no causal code-site claim until complete work-ID joins, valid clocks, sealed streams, and overhead gate pass.');

UPDATE experiments
SET state='CANCELLED',
    notes=COALESCE(notes,'') || ' Historical candidate retained; superseded as current work by the verified Build 8 full-run baseline and planned source causal logger. Do not execute as an active tuning recommendation.'
WHERE id IN ('exp_asg_flush400_ab','exp_native_frame_trace','exp_tft_fps_cap_ab','exp_tft_graphics_preset_ab','exp_tft_performance_mode_ab')
  AND state='PLANNED';

INSERT OR REPLACE INTO lab_meta(key,value) VALUES
('current_presentation_candidate','RETIRED_AS_CURRENT_ACTION: final Mac presentation and broad SurfaceFlinger/HWC directional candidates are context only; causal changes wait for the planned source causal logger.'),
('current_graphics_next_action','Build and validate the isolated source causal logger. Do not run a tuning A/B until it identifies an owned first divergent boundary or explicitly reports that the first missing boundary is unowned.');

-- Exact-key overrides for the Build 8 authority. Earlier values remain in the
-- SQL history but cannot survive as the effective current policy.
INSERT OR REPLACE INTO lab_meta(key,value) VALUES
('logger_guard_policy','Automatic logging follows the TFT process and exact layer from game start until process/app close. MATCH_ENTRY, MATCH_END, combat, battle, quality, and result markers are optional annotations only.'),
('multi_match_policy','Keep raw telemetry continuous across every game. Process/layer lifetime and timestamps define validity; marker pairing and battle classification are never required.'),
('current_measurement_gap','Exact TFT SurfaceFlinger actual-present timing is implemented and verified. Internal causal attribution below the guest TFT surface remains unimplemented because owned-stage work IDs are absent.'),
('current_tft_graphics_observed','High'),
('current_tft_fps_cap_observed','60'),
('current_tft_performance_mode_beta_observed','OFF'),
('current_native_frame_truth','Exact TFT SurfaceFlinger actual-present timestamps are FPS authority. Final Mac presentation is hidden correctness context only and is excluded from causal ranking.'),
('current_native_logger','Automatic private SQL capture covers the TFT PID/layer lifetime, exact intervals/windows, receipts, incidents, and bounded supporting telemetry. Markers are optional annotations.'),
('current_surfaceflinger_counter_policy','Exact TFT actual-present intervals and one-second windows are primary. Cumulative counters are supporting context only and do not require marked windows.'),
('current_optimization_priority','Analyze all automatic full-run graphics data. Do not tune or name a root component until the planned source causal logger proves the first divergent owned boundary or explicitly reports UNKNOWN.'),
('current_graphics_experiment','No tuning A/B is active. The next development phase is the PLANNED isolated source causal logger; combat_latency_a is an observed High/60/Performance Mode OFF preset, not a promoted result.');
