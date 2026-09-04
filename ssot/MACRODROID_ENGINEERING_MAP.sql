-- TFTMAC Engineering Knowledge Map
-- Purpose: persistent, queryable systems map for architecture, dependencies,
-- experiments, compatibility, failures, evidence, unknowns, and invention paths.
--
-- Operating rule:
--   A material discovery MUST be recorded here before the next architecture-
--   changing action. This file is not a diary. It is the project's dependency
--   and decision graph.
--
-- SQLite compatible.

PRAGMA foreign_keys = ON;

BEGIN;

CREATE TABLE IF NOT EXISTS map_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS components (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    kind TEXT NOT NULL,
    layer TEXT NOT NULL,
    ownership TEXT NOT NULL CHECK (ownership IN ('TFTMAC','UPSTREAM','APPLE','GOOGLE','RIOT','KHRONOS','REFERENCE','UNKNOWN')),
    status TEXT NOT NULL CHECK (status IN ('PROVEN','AVAILABLE','ACTIVE','BLOCKED','CONDITIONAL','REJECTED','UNKNOWN')),
    purpose TEXT NOT NULL,
    notes TEXT
);

CREATE TABLE IF NOT EXISTS component_versions (
    id TEXT PRIMARY KEY,
    component_id TEXT NOT NULL REFERENCES components(id),
    version TEXT,
    commit_sha TEXT,
    artifact_sha256 TEXT,
    source_authority TEXT,
    frozen INTEGER NOT NULL DEFAULT 0 CHECK (frozen IN (0,1)),
    notes TEXT
);

CREATE TABLE IF NOT EXISTS capabilities (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    layer TEXT NOT NULL,
    description TEXT NOT NULL,
    acceptance_rule TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS component_capabilities (
    component_id TEXT NOT NULL REFERENCES components(id),
    capability_id TEXT NOT NULL REFERENCES capabilities(id),
    state TEXT NOT NULL CHECK (state IN ('PASS','FAIL','PARTIAL','EXPECTED','UNKNOWN','NOT_APPLICABLE')),
    evidence_id TEXT,
    notes TEXT,
    PRIMARY KEY (component_id, capability_id)
);

CREATE TABLE IF NOT EXISTS interfaces (
    id TEXT PRIMARY KEY,
    from_component TEXT NOT NULL REFERENCES components(id),
    to_component TEXT NOT NULL REFERENCES components(id),
    interface_type TEXT NOT NULL,
    contract TEXT NOT NULL,
    state TEXT NOT NULL CHECK (state IN ('PROVEN','VIABLE','BLOCKED','CONDITIONAL','UNKNOWN')),
    notes TEXT
);

CREATE TABLE IF NOT EXISTS dependencies (
    id TEXT PRIMARY KEY,
    consumer_component TEXT NOT NULL REFERENCES components(id),
    provider_component TEXT NOT NULL REFERENCES components(id),
    relationship TEXT NOT NULL,
    required INTEGER NOT NULL DEFAULT 1 CHECK (required IN (0,1)),
    compatibility_state TEXT NOT NULL CHECK (compatibility_state IN ('PASS','FAIL','WORKAROUND','CONDITIONAL','UNKNOWN')),
    evidence_id TEXT,
    notes TEXT
);

CREATE TABLE IF NOT EXISTS constraints (
    id TEXT PRIMARY KEY,
    category TEXT NOT NULL,
    statement TEXT NOT NULL,
    severity TEXT NOT NULL CHECK (severity IN ('HARD','HIGH','MEDIUM','LOW')),
    mutable INTEGER NOT NULL DEFAULT 0 CHECK (mutable IN (0,1)),
    rationale TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS evidence (
    id TEXT PRIMARY KEY,
    observed_at TEXT NOT NULL,
    kind TEXT NOT NULL,
    source_path TEXT,
    source_sha256 TEXT,
    statement TEXT NOT NULL,
    confidence TEXT NOT NULL CHECK (confidence IN ('DIRECT','STRONG','INFERRED','HYPOTHESIS')),
    notes TEXT
);

CREATE TABLE IF NOT EXISTS experiments (
    id TEXT PRIMARY KEY,
    observed_at TEXT NOT NULL,
    title TEXT NOT NULL,
    layer TEXT NOT NULL,
    hypothesis TEXT NOT NULL,
    action TEXT NOT NULL,
    result TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('PASS','FAIL','MIXED','RUNNING','SUPERSEDED')),
    reusable_lesson TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS failures (
    id TEXT PRIMARY KEY,
    experiment_id TEXT REFERENCES experiments(id),
    symptom TEXT NOT NULL,
    root_cause TEXT NOT NULL,
    owning_layer TEXT NOT NULL,
    workaround TEXT,
    permanent_fix TEXT,
    state TEXT NOT NULL CHECK (state IN ('OPEN','WORKAROUND','FIXED','AVOID'))
);

CREATE TABLE IF NOT EXISTS experiment_evidence (
    experiment_id TEXT NOT NULL REFERENCES experiments(id),
    evidence_id TEXT NOT NULL REFERENCES evidence(id),
    PRIMARY KEY (experiment_id, evidence_id)
);

CREATE TABLE IF NOT EXISTS architecture_candidates (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    summary TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('PRIMARY','VIABLE','CONDITIONAL','RESEARCH','REJECTED')),
    integration_cost INTEGER NOT NULL CHECK (integration_cost BETWEEN 1 AND 10),
    invention_level INTEGER NOT NULL CHECK (invention_level BETWEEN 1 AND 10),
    expected_control INTEGER NOT NULL CHECK (expected_control BETWEEN 1 AND 10),
    expected_risk INTEGER NOT NULL CHECK (expected_risk BETWEEN 1 AND 10),
    rationale TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS candidate_components (
    candidate_id TEXT NOT NULL REFERENCES architecture_candidates(id),
    component_id TEXT NOT NULL REFERENCES components(id),
    role TEXT NOT NULL,
    required INTEGER NOT NULL DEFAULT 1 CHECK (required IN (0,1)),
    PRIMARY KEY (candidate_id, component_id, role)
);

CREATE TABLE IF NOT EXISTS decisions (
    id TEXT PRIMARY KEY,
    decided_at TEXT NOT NULL,
    decision TEXT NOT NULL,
    rationale TEXT NOT NULL,
    state TEXT NOT NULL CHECK (state IN ('ACTIVE','CONDITIONAL','SUPERSEDED','REJECTED')),
    evidence_id TEXT,
    supersedes TEXT REFERENCES decisions(id)
);

CREATE TABLE IF NOT EXISTS unknowns (
    id TEXT PRIMARY KEY,
    question TEXT NOT NULL,
    owning_layer TEXT NOT NULL,
    blocking INTEGER NOT NULL DEFAULT 0 CHECK (blocking IN (0,1)),
    next_probe TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('OPEN','TESTING','RESOLVED','DEFERRED')),
    resolution TEXT
);

CREATE TABLE IF NOT EXISTS invention_opportunities (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    problem TEXT NOT NULL,
    tftmac_owned_solution TEXT NOT NULL,
    replaces_or_bypasses TEXT NOT NULL,
    benefit TEXT NOT NULL,
    risk TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('RECOMMENDED','VIABLE','RESEARCH','DEFERRED','REJECTED'))
);

CREATE TABLE IF NOT EXISTS paths (
    id TEXT PRIMARY KEY,
    purpose TEXT NOT NULL,
    path TEXT NOT NULL,
    storage_class TEXT NOT NULL CHECK (storage_class IN ('EXTERNAL_BULK','INTERNAL_SMALL','TEMP_ALIAS','SOURCE','RUNTIME','REFERENCE')),
    mandatory INTEGER NOT NULL DEFAULT 0 CHECK (mandatory IN (0,1)),
    fallback_policy TEXT NOT NULL,
    notes TEXT
);

CREATE TABLE IF NOT EXISTS update_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    observed_at TEXT NOT NULL,
    subject TEXT NOT NULL,
    change_summary TEXT NOT NULL,
    evidence_id TEXT REFERENCES evidence(id)
);

CREATE INDEX IF NOT EXISTS idx_components_layer ON components(layer);
CREATE INDEX IF NOT EXISTS idx_dependencies_consumer ON dependencies(consumer_component);
CREATE INDEX IF NOT EXISTS idx_dependencies_provider ON dependencies(provider_component);
CREATE INDEX IF NOT EXISTS idx_experiments_status ON experiments(status);
CREATE INDEX IF NOT EXISTS idx_unknowns_status ON unknowns(status);
CREATE INDEX IF NOT EXISTS idx_evidence_kind ON evidence(kind);

CREATE VIEW IF NOT EXISTS v_open_questions AS
SELECT id, question, owning_layer, blocking, next_probe
FROM unknowns
WHERE status IN ('OPEN','TESTING')
ORDER BY blocking DESC, owning_layer, id;

CREATE VIEW IF NOT EXISTS v_failed_or_workaround_dependencies AS
SELECT d.id,
       c1.name AS consumer,
       c2.name AS provider,
       d.relationship,
       d.compatibility_state,
       d.notes
FROM dependencies d
JOIN components c1 ON c1.id = d.consumer_component
JOIN components c2 ON c2.id = d.provider_component
WHERE d.compatibility_state IN ('FAIL','WORKAROUND','CONDITIONAL')
ORDER BY d.compatibility_state, d.id;

CREATE VIEW IF NOT EXISTS v_architecture_options AS
SELECT id, name, status, integration_cost, invention_level,
       expected_control, expected_risk,
       (expected_control + invention_level) - (integration_cost + expected_risk) AS exploration_score,
       rationale
FROM architecture_candidates
ORDER BY CASE status
           WHEN 'PRIMARY' THEN 0
           WHEN 'VIABLE' THEN 1
           WHEN 'CONDITIONAL' THEN 2
           WHEN 'RESEARCH' THEN 3
           ELSE 4
         END,
         exploration_score DESC;

CREATE VIEW IF NOT EXISTS v_proven_chain AS
SELECT i.id, f.name AS from_name, t.name AS to_name,
       i.interface_type, i.contract, i.state
FROM interfaces i
JOIN components f ON f.id = i.from_component
JOIN components t ON t.id = i.to_component
WHERE i.state IN ('PROVEN','VIABLE')
ORDER BY i.id;

INSERT OR REPLACE INTO map_meta(key, value) VALUES
('schema_version','1'),
('project','TFTMAC'),
('created_at','2026-08-28T05:10:00Z'),
('purpose','Persistent engineering dependency graph and evidence map used to prevent repeated rabbit holes and support invention.'),
('update_rule','Record each material finding, failed path, new dependency, or architecture decision before the next architecture-changing action.'),
('current_phase','Phase 1 source AEMU build / architecture reevaluation'),
('phase0_status','PASS'),
('knowledge_policy','Facts require evidence. Hypotheses stay hypotheses. A workaround must never silently become architecture.'),
('decision_policy','Prefer the smallest owned layer that removes repeated upstream friction. Do not rewrite a proven component merely to avoid one integration bug.');

INSERT OR REPLACE INTO components(id,name,kind,layer,ownership,status,purpose,notes) VALUES
('host_m4','Apple M4 Mac mini','hardware','host','APPLE','PROVEN','Physical host for TFTMAC','Mac16,10, arm64, 16 GB RAM.'),
('macos','macOS 26.6.2','operating_system','host','APPLE','PROVEN','Host operating system','Build 25G83.'),
('xcode','Xcode 26.6','toolchain','host_build','APPLE','PROVEN','Native compiler/toolchain authority','Build 17F113; selected explicitly.'),
('macos_sdk','macOS SDK 26.5','sdk','host_build','APPLE','PROVEN','Host SDK used for AEMU compilation','Located inside Xcode 26.6.'),
('tftmac_harness','TFTMAC build/runtime harness','owned_code','orchestration','TFTMAC','ACTIVE','Own compatibility, evidence, storage, build and runtime orchestration','This is the correct place to absorb stale upstream build-system assumptions.'),
('tftmac_shell','TFTMAC native macOS shell','owned_code','presentation','TFTMAC','AVAILABLE','Native single-window launcher/runtime UI','Existing SwiftUI donor-derived foundation exists.'),
('android_guest','Android 17 Google Play ARM64 guest','guest_os','guest','GOOGLE','PROVEN','Official production Android guest','API 37; Google Play ARM64 ps16k image revision 6.'),
('google_play','Google Play','package_authority','guest','GOOGLE','PROVEN','Authoritative TFT acquisition/update path','Production app authority; avoid third-party APK mirrors.'),
('tft_android','Teamfight Tactics Android client','workload','application','RIOT','AVAILABLE','Primary production workload','Current live package is com.riotgames.league.teamfighttactics. Current evidence says Riot native Android runtime, not Unreal.'),
('aemu','Android Emulator / AEMU','hypervisor_runtime','virtualization','UPSTREAM','ACTIVE','Android machine/runtime host','Authority branch emu-master-dev.'),
('gfxstream','gfxstream','gpu_transport','graphics_transport','UPSTREAM','AVAILABLE','Transports guest graphics/Vulkan to host','Required boundary between guest Vulkan and host Vulkan.'),
('angle','Android built-in ANGLE','graphics_translation','guest_graphics','GOOGLE','PROVEN','GLES to Vulkan translation path','GuestAngle source semantics proven in locked QEMU.'),
('moltenvk_integrated','AEMU-integrated MoltenVK','graphics_translation','host_graphics','UPSTREAM','AVAILABLE','Vulkan to Metal translation used by integrated stack','Exact locked commit recorded.'),
('moltenvk_reference','MoltenVK v1.4.2 reference','reference','host_graphics','KHRONOS','AVAILABLE','Comparison/donor baseline','Do not wholesale replace integrated revision without evidence.'),
('metal','Metal','graphics_api','host_graphics','APPLE','PROVEN','Final Apple GPU API','Target host graphics backend.'),
('vulkan_sdk','Vulkan SDK 1.4.357.0','toolchain','graphics_validation','KHRONOS','PROVEN','Host Vulkan development and validation tools','Installed externally and phase0-vulkan PASS.'),
('qt_regular','AEMU Qt darwin-aarch64 prebuilt','ui_prebuilt','host_ui','UPSTREAM','BLOCKED','AEMU Qt UI package','Package exists but libexec/uic and moc are absent.'),
('qt_noweb','AEMU Qt darwin-aarch64-nowebengine prebuilt','ui_prebuilt','host_ui','UPSTREAM','AVAILABLE','Complete no-WebEngine Qt host tools','Contains qmake, qtpaths, libexec/uic and libexec/moc.'),
('khronos_gles_cts','Khronos GLES CTS','validation','graphics_validation','KHRONOS','AVAILABLE','Generality/conformance evidence','Pinned opengl-es-cts-3.2.14.1.'),
('khronos_vk_cts','Khronos Vulkan CTS','validation','graphics_validation','KHRONOS','AVAILABLE','Vulkan required-case evidence','Pinned vulkan-cts-1.4.6.1.'),
('tftmac_runtime_donor','Existing TFTMAC runtime/emulator donor work','reference','donor','TFTMAC','AVAILABLE','Prior proof that AEMU can build/run on this Apple Silicon host family','Use as donor/evidence, not as unexamined authority.');

INSERT OR REPLACE INTO component_versions(id,component_id,version,commit_sha,artifact_sha256,source_authority,frozen,notes) VALUES
('ver_xcode','xcode','26.6 / 17F113',NULL,NULL,'Apple Xcode installation',1,'Selected /Applications/Xcode-26.6.0.app.'),
('ver_macos_sdk','macos_sdk','26.5',NULL,NULL,'Xcode 26.6',1,'Verified path in STACK.lock.'),
('ver_android_guest','android_guest','API 37 / image rev 6',NULL,NULL,'Google sdkmanager',1,'system-images;android-37.0;google_apis_playstore_ps16k;arm64-v8a.'),
('ver_android_platform_tools','android_guest','platform-tools 37.0.1',NULL,NULL,'Google sdkmanager',1,NULL),
('ver_android_emulator_control','aemu','37.1.11 control reference',NULL,NULL,'Google sdkmanager',1,'Control reference is separate from source-built AEMU authority.'),
('ver_qemu','aemu','emu-master-dev','ae9d18d2b6261179fbd57fffec720a04f7bfb053',NULL,'resolved AOSP manifest',1,NULL),
('ver_aemu_common','aemu','locked','3c1ced8a369417db591eb7cd083af5bb2c317975',NULL,'resolved AOSP manifest',1,NULL),
('ver_gfxstream','gfxstream','locked','d047a57228332d995d36600792fa9ccc26cf8ae6',NULL,'resolved AOSP manifest',1,NULL),
('ver_angle','angle','locked','901e32aa9923b05c3a2af846f8a28fc79c93d0be',NULL,'resolved AOSP manifest',1,NULL),
('ver_moltenvk_integrated','moltenvk_integrated','locked','fb26612eb84576adb974fe7f18a49d263072116f',NULL,'resolved AOSP manifest',1,NULL),
('ver_moltenvk_reference','moltenvk_reference','v1.4.2','db66022459ffb663aa2b50f6b018bc2e124f5edf',NULL,'Khronos upstream reference',1,NULL),
('ver_vulkan_sdk','vulkan_sdk','1.4.357.0',NULL,'539433589c83522e6f31b1c7b418a4167e21597a4a361ab119e1dc0760cf3865','LunarG/Khronos',1,NULL),
('ver_gles_cts','khronos_gles_cts','opengl-es-cts-3.2.14.1','067e8832315e79817ede1c4863804e440f5d1c80',NULL,'Khronos',1,NULL),
('ver_vk_cts','khronos_vk_cts','vulkan-cts-1.4.6.1','5c8aae22885448d70a2873e94a93b24b49505c32',NULL,'Khronos',1,NULL);

INSERT OR REPLACE INTO capabilities(id,name,layer,description,acceptance_rule) VALUES
('cap_guestangle','GuestAngle activation','guest_graphics','AEMU configures Android EGL to ANGLE and guest Vulkan path.','Locked-source proof plus runtime boot proof.'),
('cap_gles32','Genuine OpenGL ES 3.2','guest_graphics','Real GLES 3.2 EGL context and required features.','3.2 context creates; GL_VERSION reports ES 3.2; executable feature probes and known frame pass; no nonconformant exposure.'),
('cap_guest_vulkan','Required guest Vulkan','graphics_transport','Guest sees executable Vulkan features required by ANGLE/TFT.','Guest executable probe passes; host-green/guest-red delta is empty for required set.'),
('cap_host_vulkan','Required host Vulkan','host_graphics','MoltenVK exposes and executes required Vulkan features.','Host executable Vulkan probe passes.'),
('cap_metal','Metal rendering','host_graphics','Final Apple GPU rendering backend.','MoltenVK/Metal runtime renders representative workloads.'),
('cap_play_store','Official Play Store update path','application','Official TFT can install/update without binary modification.','Installer is com.android.vending; package identity/signature captured.'),
('cap_native_ui','Native Mac presentation','presentation','One native macOS window hides emulator chrome.','Latency and usability thresholds pass.'),
('cap_source_build','Source-built AEMU','host_build','Locked AEMU source configures, compiles and produces runnable emulator.','Build + tests + boot acceptance pass.');

INSERT OR REPLACE INTO evidence(id,observed_at,kind,source_path,source_sha256,statement,confidence,notes) VALUES
('ev_phase0_pass','2026-08-28T04:32:56.370Z','phase_gate','ssot/preflight-report.md','0ce58e1a891a3a250f1dcca1bccab5ace8c4ae08ed05877dbd0206327081136b','Phase 0 authority/preflight is PASS with no blockers.','DIRECT',NULL),
('ev_stack_lock','2026-08-28T04:32:56.368Z','machine_lock','ssot/STACK.lock.yaml','a570433d39ecebc1f4dc8c9b08e5c92547ab2b91a0826abc6b70b1f725289f2c','Exact host, Android, AEMU, gfxstream, ANGLE, MoltenVK, CTS and performance authority is frozen.','DIRECT',NULL),
('ev_guestangle','2026-08-28T04:03:25.796Z','source_proof','ssot/guestangle-authority.json','d10e51b341852dafb8aa565c8e2d7e48137d6da6e5700f08a733951b8f6b0bee','Locked QEMU source proves GuestAngle sets hardware EGL=angle, requires Vulkan, sets hardware.vulkan=ranchu, and disables nonconformant exposure.','DIRECT',NULL),
('ev_external_storage','2026-08-28T04:32:56.370Z','architecture','TFTMAC_FULL_IMPLEMENTATION_PLAN.md','81bd386c1d9d47f26659c93af914ec9a92568ee689e7bed47eb0f2afd6dd5f1a','Bulk Build and Runtime storage is external under /Volumes/MAC MINI M4/TFTMAC; internal fallback is forbidden.','DIRECT',NULL),
('ev_phase1_configure','2026-08-28T05:07:45Z','build_log','/Volumes/MAC MINI M4/TFTMAC/Build/logs/phase1-build.stdout.log',NULL,'AEMU CMake configuration completed successfully and generated Ninja build files after host-compatibility adaptations.','DIRECT','Build reported Configuring done / Generating done / Build files written.'),
('ev_phase1_compile','2026-08-28T05:07:45Z','build_log','/Volumes/MAC MINI M4/TFTMAC/Build/logs/phase1-build.stdout.log',NULL,'AEMU entered a 9,854-step Ninja compile and compiled real aemu/gfxstream objects.','DIRECT','Observed through at least steps 1-38 before missing ranlib was exposed.'),
('ev_phase1_running','2026-08-28T05:09:15Z','worker_state','/Volumes/MAC MINI M4/TFTMAC/Runtime/Manifests/phase1-build-worker.json',NULL,'After adding the host-tool wrappers, detached Phase 1 worker is RUNNING in BUILD stage.','DIRECT','Do not launch a duplicate build until this worker is reconciled.'),
('ev_qt_layout','2026-08-28T05:01:17Z','filesystem','AEMU Qt prebuilt tree',NULL,'darwin-aarch64 lacks libexec/uic and moc while darwin-aarch64-nowebengine contains them.','DIRECT',NULL),
('ev_tft_native_runtime','2026-08-27T00:00:00Z','package_inspection','docs/TFTMAC_GRAPHICS_ARCHITECTURE.md',NULL,'Current official TFT Android package contains Riot native runtime evidence and no libUnreal.so/UECommandLine.txt evidence.','STRONG','Treat current client as Riot native Android runtime unless a future package inspection changes this.');

INSERT OR REPLACE INTO constraints(id,category,statement,severity,mutable,rationale) VALUES
('con_external_bulk','storage','Build and Runtime bulk data must live on /Volumes/MAC MINI M4/TFTMAC and must never silently fall back to the internal disk.','HARD',0,'Internal disk exhaustion already caused Phase 0 source failure and wasted recovery time.'),
('con_no_spoof','graphics_truth','Do not satisfy GLES 3.2 by property/version spoof or exposeNonConformantExtensionsAndVersions.','HARD',0,'The product must provide real executable graphics capability.'),
('con_no_riot_patch','workload_integrity','Do not modify or re-sign Riot binaries.','HARD',0,'Preserves app integrity and package authority.'),
('con_play_authority','package_authority','Google Play is production TFT install/update authority.','HIGH',0,'Avoids mirror drift and unverifiable package provenance.'),
('con_one_layer','debug_method','Repair the first boundary where evidence changes from PASS to FAIL.','HIGH',0,'Prevents broad speculative patching.'),
('con_update_map','process','Every material finding must be inserted into this engineering map before the next architecture-changing action.','HIGH',0,'Prevents repeated rabbit holes and lost causal information.'),
('con_no_duplicate_build','process','Do not start another Phase 1 build while the detached worker is alive.','HIGH',1,'Avoids corrupting evidence and wasting CPU/storage.'),
('con_owned_harness','architecture','Stale upstream build-system compatibility belongs in TFTMAC-owned harness code unless runtime behavior itself requires an upstream source change.','HIGH',1,'Separates build plumbing from graphics/runtime invention.');

INSERT OR REPLACE INTO interfaces(id,from_component,to_component,interface_type,contract,state,notes) VALUES
('if_tft_angle','tft_android','angle','GLES','TFT requests GLES through Android graphics stack.','VIABLE','Exact required feature set still needs runtime probe.'),
('if_angle_vk','angle','gfxstream','Vulkan guest path','GuestAngle uses Vulkan/ranchu path.','PROVEN','Source semantics proven; runtime execution remains Phase 5 evidence.'),
('if_gfx_mvk','gfxstream','moltenvk_integrated','host Vulkan','gfxstream host Vulkan calls reach MoltenVK.','VIABLE','Exact required feature delta to be measured.'),
('if_mvk_metal','moltenvk_integrated','metal','Metal','MoltenVK translates Vulkan to Metal.','VIABLE',NULL),
('if_play_tft','google_play','tft_android','package install/update','Official package acquisition and updates.','PROVEN',NULL),
('if_shell_aemu','tftmac_shell','aemu','runtime control','Native shell launches/controls emulator and later consumes authenticated control/video interfaces.','VIABLE',NULL),
('if_harness_aemu','tftmac_harness','aemu','build compatibility','Owned harness adapts stale AEMU build assumptions to current Apple/Xcode/storage environment.','PROVEN','This has already turned impossible configuration into a real 9,854-step build.');

INSERT OR REPLACE INTO dependencies(id,consumer_component,provider_component,relationship,required,compatibility_state,evidence_id,notes) VALUES
('dep_aemu_xcode','aemu','xcode','native compiler/toolchain',1,'WORKAROUND','ev_phase1_configure','Locked AEMU helper predates Xcode 26.6/macOS SDK 26.5; TFTMAC harness bridges the gap.'),
('dep_aemu_sdk','aemu','macos_sdk','host SDK',1,'WORKAROUND','ev_phase1_configure','Upstream helper recognized SDKs only through 15.2 and parsed new xcodebuild output incorrectly.'),
('dep_aemu_qt','aemu','qt_regular','host UI tools',1,'WORKAROUND','ev_qt_layout','Regular Darwin ARM64 Qt package lacks libexec/uic/moc; temporary bridge from sibling nowebengine package works.'),
('dep_aemu_qt_noweb','aemu','qt_noweb','host UI tools donor',1,'PASS','ev_qt_layout','Provides qmake, qtpaths, uic and moc.'),
('dep_aemu_harness','aemu','tftmac_harness','host compatibility',1,'PASS','ev_phase1_compile','Owned harness solves path-space, Path typing, SDK parser, Xcode selection, compiler wrappers, Qt host tools and binutils without changing emulator graphics behavior.'),
('dep_angle_guestvk','angle','gfxstream','guest Vulkan transport',1,'CONDITIONAL','ev_guestangle','Source authority proves required path exists; executable feature parity still to be measured.'),
('dep_gfx_mvk','gfxstream','moltenvk_integrated','host Vulkan provider',1,'UNKNOWN',NULL,'Phase 2/3 probes must identify exact host/guest feature delta.'),
('dep_mvk_metal','moltenvk_integrated','metal','Apple GPU backend',1,'PASS',NULL,'Known architectural role; executable required-feature proof still pending.'),
('dep_tft_gles32','tft_android','angle','GLES 3.2 capability',1,'UNKNOWN',NULL,'Must be proven by real EGL 3.2 context and TFT workload.'),
('dep_tft_play','tft_android','google_play','install/update authority',1,'PASS',NULL,NULL);

INSERT OR REPLACE INTO component_capabilities(component_id,capability_id,state,evidence_id,notes) VALUES
('aemu','cap_source_build','PARTIAL','ev_phase1_compile','CMake config succeeds and real compile starts; full build/test/boot not yet complete.'),
('angle','cap_guestangle','PASS','ev_guestangle','Locked-source semantics proven.'),
('android_guest','cap_play_store','PASS','ev_stack_lock','Official Google Play image revision 6.'),
('moltenvk_integrated','cap_host_vulkan','UNKNOWN',NULL,'Requires executable probe.'),
('gfxstream','cap_guest_vulkan','UNKNOWN',NULL,'Requires host-vs-guest delta probe.'),
('angle','cap_gles32','UNKNOWN',NULL,'Do not infer from properties.'),
('metal','cap_metal','EXPECTED',NULL,'Final backend; runtime proof pending.'),
('tftmac_shell','cap_native_ui','EXPECTED',NULL,'Later phase after runtime capability is green.');

INSERT OR REPLACE INTO experiments(id,observed_at,title,layer,hypothesis,action,result,status,reusable_lesson) VALUES
('exp_phase0','2026-08-28T04:32:56Z','Freeze Phase 0 authority','system','Exact versions and source authority can be made deterministic before mutation.','Resolved host/Android/AEMU/MoltenVK/CTS inputs and generated locked artifacts.','Phase 0 PASS with no blockers.','PASS','Freeze facts first; implementation should not carry version ambiguity.'),
('exp_internal_disk','2026-08-27T00:00:00Z','AEMU source sync on internal disk','storage','Default Application Support Build root is sufficient.','repo sync used internal Build root.','Failed with No space left on device.','FAIL','Bulk build/source data cannot live on the internal disk.'),
('exp_external_migration','2026-08-28T00:00:00Z','Move Build root to external M4','storage','AEMU source can be preserved intact on external storage without a symlinked Xcode Developer tree.','Migrated Build intact and made external root mandatory.','Verified migration; Phase 0 source resumed and completed.','PASS','External storage is viable and should be explicit, not a hidden symlink fallback.'),
('exp_space_path','2026-08-28T04:40:00Z','Run AEMU rebuild from external path with spaces','host_build','Upstream rebuild.sh handles a normal macOS volume path with spaces.','Ran rebuild.sh from /Volumes/MAC MINI M4/...','Shell expanded bundled Python path incorrectly and attempted /Volumes as command.','FAIL','Legacy AEMU shell tooling is not space-safe.'),
('exp_temp_alias','2026-08-28T04:44:00Z','No-space temporary AEMU alias','host_build','A no-space alias can isolate legacy path parsing while keeping bytes external.','Created /private/tmp/tftmac-aemu symlink to external AEMU tree.','Useful but AEMU Python driver canonicalized paths unless explicit --aosp was supplied.','MIXED','Temporary aliases work only if every owning tool is forced to consume the alias.'),
('exp_aosp_type','2026-08-28T04:46:00Z','Explicit --aosp override','host_build','Supplying the no-space alias through --aosp will preserve it.','Passed --aosp /private/tmp/tftmac-aemu.','Driver crashed because argparse returns str while code assumes pathlib.Path.','FAIL','AEMU build driver contains a concrete type bug; compatibility shim can repair this without source fork.'),
('exp_sdk265','2026-08-28T04:51:00Z','Use Xcode 26.6 / SDK 26.5 with locked AEMU','host_build','Old AEMU helper can use current Xcode directly.','Ran CMake driver under selected Xcode 26.6.','Helper recognized SDKs only through 15.2 and parsed current xcodebuild output incorrectly.','FAIL','Modern-host support should be owned by a narrow TFTMAC compatibility layer.'),
('exp_xcode_clang','2026-08-28T04:56:00Z','Use Xcode Clang instead of absent AOSP macOS Clang prebuilt','host_build','Current Xcode compiler can satisfy native AEMU toolchain.','Preseeded compiler wrappers around Xcode clang/clang++.','CMake identified AppleClang 21 and passed compiler ABI checks.','PASS','The resolved manifest does not need a separate macOS Clang prebuilt for native build if TFTMAC owns correct wrappers.'),
('exp_qt_tools','2026-08-28T05:01:00Z','Resolve Qt uic/moc failure','host_build','Required Qt host tools may already exist elsewhere in the manifest.','Inspected Qt prebuilt layouts.','nowebengine sibling contains uic/moc; regular darwin-aarch64 does not.','PASS','Before downloading a dependency, map sibling prebuilts and reuse compatible host-only tools.'),
('exp_webengine_force','2026-08-28T05:05:00Z','Disable unnecessary QtWebEngine','host_build','CLI flag should select no-WebEngine Qt.','Tested branch behavior and inspected configure.py.','Darwin branch hardcodes QTWEBENGINE=True; compatibility launcher override removes injection.','PASS','Stale policy in build orchestration should be bypassed in TFTMAC harness rather than accepted as architecture.'),
('exp_qt_bridge','2026-08-28T05:07:00Z','Bridge Qt libexec host tools','host_build','Host-only uic/moc from sibling Qt package can satisfy regular package configuration.','Temporarily bridged darwin-aarch64/libexec to darwin-aarch64-nowebengine/libexec.','CMake configured completely and generated 9,854 Ninja build steps.','PASS','A narrow host-tool bridge is enough; no Qt rebuild/download required.'),
('exp_host_binutils','2026-08-28T05:09:00Z','Provide Darwin host binutils wrappers','host_build','Compile failure at ranlib is another missing wrapper, not source incompatibility.','Preseeded ranlib/ar/nm/strip/ld/libtool/strings/otool/install_name_tool/dsymutil wrappers from Xcode/macOS.','Detached build remains alive in BUILD stage after prior ranlib failure.','RUNNING','Provide the complete host-tool contract once, not one tool at a time.');

INSERT OR REPLACE INTO experiment_evidence(experiment_id,evidence_id) VALUES
('exp_phase0','ev_phase0_pass'),
('exp_xcode_clang','ev_phase1_configure'),
('exp_qt_tools','ev_qt_layout'),
('exp_qt_bridge','ev_phase1_configure'),
('exp_qt_bridge','ev_phase1_compile'),
('exp_host_binutils','ev_phase1_running');

INSERT OR REPLACE INTO failures(id,experiment_id,symptom,root_cause,owning_layer,workaround,permanent_fix,state) VALUES
('fail_internal_space','exp_internal_disk','repo sync failed with No space left on device','Bulk AEMU Build/source lived on internal disk.','storage','Move Build/Runtime roots to external M4.','External roots are now architecture authority and internal fallback is forbidden.','FIXED'),
('fail_space_unsafe_shell','exp_space_path','rebuild.sh attempted to execute /Volumes','Unquoted legacy shell expansion cannot handle spaces in volume path.','host_build','Use no-space execution alias and argument-safe process APIs.','Keep upstream shell wrappers out of TFTMAC critical path.','WORKAROUND'),
('fail_aosp_str_path','exp_aosp_type','unsupported operand type(s) for /: str and str','AEMU --aosp argparse value is str but code later assumes Path.','host_build','Compatibility launcher converts aosp/out/dist arguments to pathlib.Path.','Owned build adapter should normalize upstream argument types.','WORKAROUND'),
('fail_sdk_parser','exp_sdk265','No supported OSX SDK found despite SDK 26.5 installed','Old helper support list ends at 15.2 and xcodebuild parser does not understand Xcode 26 output.','host_build','Temporary helper adaptation uses xcrun, SDK 26.5 and selected DEVELOPER_DIR.','Move host version detection into TFTMAC harness and pass resolved values downstream.','WORKAROUND'),
('fail_missing_host_clang','exp_xcode_clang','Generated toolchain lacked gcc/g++ wrappers','Resolved manifest has no matching AOSP macOS Clang prebuilt for stale helper assumption.','host_build','Generate wrappers targeting Xcode 26.6 clang/clang++.','Own a deterministic macOS host toolchain adapter.','WORKAROUND'),
('fail_qt_uic','exp_qt_tools','Qt6::uic missing at regular Darwin ARM64 prebuilt path','Regular Qt package lacks libexec host tools; sibling nowebengine package contains them.','host_build','Temporary libexec bridge to sibling package.','Teach harness to resolve Qt host tools by capability rather than hardcoded package directory.','WORKAROUND'),
('fail_webengine_forced','exp_webengine_force','QTWEBENGINE=True emitted even when WebEngine not requested','configure.py hardcodes WebEngine on Darwin targets.','host_build','Compatibility launcher overrides with_webengine for Phase 1.','Owned build adapter should express actual product requirement instead of inherited stale defaults.','WORKAROUND'),
('fail_ranlib','exp_host_binutils','Ninja failed linking static libraries because toolchain/ranlib was missing','Legacy generator omitted required Darwin binutils wrappers.','host_build','Preseed complete host-tool wrapper set.','Own the entire host-tool contract in the TFTMAC build adapter.','WORKAROUND');

INSERT OR REPLACE INTO decisions(id,decided_at,decision,rationale,state,evidence_id,supersedes) VALUES
('dec_external_storage','2026-08-28T04:32:56Z','External M4 is mandatory Build/Runtime storage authority.','Internal storage exhaustion was proven and external migration completed successfully.','ACTIVE','ev_external_storage',NULL),
('dec_locked_aemu','2026-08-28T04:32:56Z','Use one frozen emu-master-dev manifest as AEMU source authority.','Prevents mixing branch behavior and makes capability evidence reproducible.','ACTIVE','ev_stack_lock',NULL),
('dec_guestangle_primary','2026-08-28T04:03:25Z','Built-in Android ANGLE via GuestAngle remains the primary GLES path.','Locked source proves correct EGL/Vulkan/nonconformant semantics.','ACTIVE','ev_guestangle',NULL),
('dec_host_compat_owned','2026-08-28T05:09:00Z','Treat stale macOS AEMU build plumbing as a TFTMAC-owned compatibility layer, not as graphics architecture.','Multiple failures were build-system assumptions; the same source progressed once the harness supplied modern host contracts.','ACTIVE','ev_phase1_compile',NULL),
('dec_no_full_rewrite_yet','2026-08-28T05:10:00Z','Do not rewrite the Android emulator/runtime yet.','AEMU has now fully configured and entered real compilation; the difficult failures so far are host-build integration, not proof that AEMU runtime architecture is unusable.','ACTIVE','ev_phase1_compile',NULL),
('dec_invention_allowed','2026-08-28T05:10:00Z','New TFTMAC-owned code is preferred where it can replace repeated brittle upstream adaptation with a small stable contract.','The build adapter already demonstrates that invention at the right boundary can remove multiple unrelated blockers.','ACTIVE','ev_phase1_compile',NULL);

INSERT OR REPLACE INTO architecture_candidates(id,name,summary,status,integration_cost,invention_level,expected_control,expected_risk,rationale) VALUES
('arch_a','Locked AEMU + TFTMAC compatibility/build adapter','Keep AEMU/gfxstream/ANGLE/MoltenVK runtime architecture, but own the macOS build/runtime compatibility boundary in TFTMAC instead of relying on stale upstream helper assumptions.','PRIMARY',5,5,8,4,'Current evidence strongly supports this: locked source fully configured and entered real compilation once the owned adapter supplied modern host contracts.'),
('arch_b','Stock Google emulator + TFTMAC native shell','Use official emulator binary wherever its graphics capability is already sufficient; avoid source build unless a measured capability gap requires source control.','VIABLE',2,2,4,3,'Could dramatically reduce maintenance if stock emulator passes the future Vulkan/GLES probes. Must be decided by capability evidence, not convenience.'),
('arch_c','Hybrid stock AEMU + TFTMAC-owned graphics adapter','Keep machine/runtime from official AEMU but own only the minimum graphics bridge/driver integration required to supply missing guest capability.','RESEARCH',6,7,9,6,'Potentially a better long-term product if the failure is isolated to graphics transport, but feasibility depends on extension points discovered in Phase 2-5.'),
('arch_d','Google Play authority guest + custom execution guest','Use official Play guest for package/update authority and a controlled execution guest only if built-in ANGLE is proven to be the remaining blocker.','CONDITIONAL',7,6,8,7,'Already defined as a conditional path. Do not build unless guest Vulkan is green and built-in ANGLE is causally red.'),
('arch_e','TFTMAC-owned minimal Android VM/runtime','Replace substantial AEMU machinery with owned virtualization/device/runtime code.','RESEARCH',10,10,10,10,'This is true invention but enormous scope: CPU/VM, devices, Binder/Android boot, graphics, input, audio, Play compatibility. Only rational if AEMU runtime itself is proven unworkable, which has not happened.'),
('arch_f','Native/non-Android TFT translation layer','Run/translate TFT without Android runtime.','REJECTED',10,10,10,10,'Would require recreating Android/Riot runtime assumptions and likely package/update/security behavior. Current evidence gives no reason to choose this over a functioning Android guest architecture.'),
('arch_g','Reuse existing TFTMAC-runtime donor emulator','Harvest known-good prior AEMU build/signing/launch solutions from the separate donor project where versions/components align.','VIABLE',3,2,5,3,'Can reduce duplicate discovery. Must compare exact versions and copy only compatible causal fixes.');

INSERT OR REPLACE INTO candidate_components(candidate_id,component_id,role,required) VALUES
('arch_a','aemu','Android runtime',1),
('arch_a','gfxstream','GPU transport',1),
('arch_a','angle','GLES translation',1),
('arch_a','moltenvk_integrated','Vulkan-to-Metal',1),
('arch_a','tftmac_harness','Owned host compatibility boundary',1),
('arch_a','tftmac_shell','Native product surface',1),
('arch_b','aemu','Official prebuilt emulator runtime',1),
('arch_b','tftmac_shell','Native product surface',1),
('arch_c','aemu','Machine/runtime host',1),
('arch_c','tftmac_harness','Owned runtime/graphics integration',1),
('arch_c','gfxstream','Potential replace/extend boundary',1),
('arch_d','android_guest','Package authority guest',1),
('arch_d','angle','Potential custom execution ANGLE',1),
('arch_g','tftmac_runtime_donor','Prior solution donor',1);

INSERT OR REPLACE INTO unknowns(id,question,owning_layer,blocking,next_probe,status,resolution) VALUES
('unk_phase1_result','Does the current 9,854-step AEMU build complete with the full host-tool wrapper set?','host_build',1,'Reconcile the existing detached worker; do not start another build.','TESTING',NULL),
('unk_stock_capability','Does official Emulator 37.1.11 already provide every required guest Vulkan/GLES capability for current TFT?','graphics_capability',0,'Run the permanent host/guest Vulkan and GLES probes against stock control runtime before choosing source patches.','OPEN',NULL),
('unk_host_vulkan_delta','Which required Vulkan features are missing on integrated MoltenVK?','host_graphics',0,'Run executable host Vulkan probe against integrated MoltenVK and v1.4.2 reference.','OPEN',NULL),
('unk_transport_delta','Which host-green Vulkan features become guest-red through gfxstream?','graphics_transport',0,'Run guest Vulkan probe and compare structured deltas.','OPEN',NULL),
('unk_angle32','After Vulkan is correct, will built-in Android 17 ANGLE create a genuine ES 3.2 context?','guest_graphics',0,'Run guest GLES 3.2 executable probe without nonconformant exposure.','OPEN',NULL),
('unk_tft_exact_req','What exact graphics/runtime requirement makes current TFT pass or fail after genuine GLES 3.2 is available?','application',0,'Launch current official Play TFT only after general probes are green and capture precise failure boundary.','OPEN',NULL),
('unk_donor_reuse','Which fixes from tftmac-runtime are version-compatible with this locked AEMU family?','donor_analysis',0,'Diff exact build/runtime approaches against current commits and classify reusable vs stale.','OPEN',NULL),
('unk_owned_gpu_bridge','Can gfxstream/MoltenVK be isolated behind a smaller TFTMAC-owned adapter while retaining stock AEMU machine/runtime?','architecture',0,'Map AEMU graphics plugin/host interfaces after Phase 2 capability evidence.','OPEN',NULL);

INSERT OR REPLACE INTO invention_opportunities(id,title,problem,tftmac_owned_solution,replaces_or_bypasses,benefit,risk,status) VALUES
('inv_build_adapter','TFTMAC Host Build Adapter','AEMU build helpers encode stale assumptions about paths, SDK versions, Clang prebuilts, Qt layout and Darwin tools.','Create a first-class TFTMAC-owned macOS build adapter that resolves Xcode/SDK/tool paths, creates a no-space execution view, supplies compiler/binutils wrappers, resolves Qt tools by capability, and invokes CMake directly.','rebuild.sh, stale SDK parser, stale toolchain wrapper generator, stale WebEngine policy','Turns repeated build rabbit holes into one stable host contract and keeps upstream runtime source clean.','Must track upstream CMake contract changes.','RECOMMENDED'),
('inv_capability_graph','Executable Capability Graph','Graphics decisions are currently spread across components and guesses.','Represent each required GLES feature as a dependency on concrete guest Vulkan, gfxstream and host Vulkan capabilities, with probe results updating graph edges.','human memory and broad trial-and-error patching','Makes causal failure routing mechanical and exposes smallest code layer to invent or patch.','Requires disciplined probe schema.','RECOMMENDED'),
('inv_runtime_adapter','TFTMAC Graphics Runtime Adapter','If stock AEMU is good except for a narrow graphics boundary, rebuilding all AEMU may be unnecessary.','Define a TFTMAC-owned interface around host Vulkan/gfxstream integration and replace only the proven failing sublayer.','full emulator forks for graphics-only defects','Could reduce long-term maintenance while preserving official Android machine behavior.','Feasibility unknown until interfaces are mapped.','RESEARCH'),
('inv_package_execution_split','Package Authority / Execution Split','A custom execution environment may conflict with Google Play/root constraints.','Keep official Play guest as package authority and copy verified official splits to a controlled execution guest only when necessary.','forcing one guest to satisfy mutually incompatible package-authority and driver-injection requirements','Preserves official package provenance while enabling controlled graphics experimentation.','Complexity and app integrity/runtime compatibility.','VIABLE'),
('inv_probe_first_release','Probe-First Runtime Promotion','Game launch currently risks becoming the diagnostic tool for the entire graphics stack.','Make host Vulkan, guest Vulkan and GLES probes mandatory runtime promotion gates; TFT is only the final workload.','game-driven debugging','Prevents Riot/TFT behavior from obscuring lower-layer defects and makes future game updates diagnosable.','Requires maintaining representative probes.','RECOMMENDED');

INSERT OR REPLACE INTO paths(id,purpose,path,storage_class,mandatory,fallback_policy,notes) VALUES
('path_build','AEMU source/build bulk data','/Volumes/MAC MINI M4/TFTMAC/Build','EXTERNAL_BULK',1,'FAIL_CLOSED','Never fall back to internal disk.'),
('path_runtime','Android SDK/AVD/packages/probes/runtime bulk data','/Volumes/MAC MINI M4/TFTMAC/Runtime','EXTERNAL_BULK',1,'FAIL_CLOSED','Never fall back to internal disk.'),
('path_logs','Small TFTMAC control/log state','~/Library/Application Support/TFTMAC/Logs','INTERNAL_SMALL',0,'ALLOW_INTERNAL_SMALL','Do not place bulk compiler/runtime data here.'),
('path_diag','Small diagnostics metadata','~/Library/Application Support/TFTMAC/Diagnostics','INTERNAL_SMALL',0,'ALLOW_INTERNAL_SMALL',NULL),
('path_aemu_alias','Space-free execution alias','/private/tmp/tftmac-aemu','TEMP_ALIAS',0,'RECREATE','Alias only; bytes remain on external M4.'),
('path_repo','TFTMAC managed worktree','/Volumes/MAC MINI M4/Clara/Worktrees/flashls1--tftmac/tftmac--7774a669-d9f7-4188-a1d4-fa185fb7eec8','SOURCE',1,'NONE',NULL);

INSERT INTO update_log(observed_at,subject,change_summary,evidence_id) VALUES
('2026-08-28T05:10:00Z','Engineering process','Created persistent SQL engineering map to replace memory-driven integration work.',NULL),
('2026-08-28T05:10:00Z','Architecture','Reclassified repeated Phase 1 failures as host-build compatibility defects rather than evidence that the AEMU runtime architecture is invalid.','ev_phase1_compile'),
('2026-08-28T05:10:00Z','Invention direction','Promoted TFTMAC-owned Host Build Adapter and Executable Capability Graph as recommended owned-code opportunities.','ev_phase1_compile');

-- ---------------------------------------------------------------------------
-- Schema v2: version/time/environment truth, source freshness, and field metadata
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS environment_snapshots (
    id TEXT PRIMARY KEY,
    observed_at TEXT NOT NULL,
    host_model TEXT,
    host_arch TEXT,
    host_memory_gb REAL,
    macos_version TEXT,
    macos_build TEXT,
    xcode_version TEXT,
    xcode_build TEXT,
    macos_sdk_version TEXT,
    developer_dir TEXT,
    source_kind TEXT NOT NULL,
    source_ref TEXT NOT NULL,
    confidence TEXT NOT NULL CHECK (confidence IN ('DIRECT','STRONG','INFERRED','HYPOTHESIS')),
    notes TEXT
);

CREATE TABLE IF NOT EXISTS source_documents (
    id TEXT PRIMARY KEY,
    path TEXT NOT NULL UNIQUE,
    sha256 TEXT,
    role TEXT NOT NULL,
    authority_rank INTEGER NOT NULL CHECK (authority_rank BETWEEN 0 AND 100),
    temporal_status TEXT NOT NULL CHECK (temporal_status IN ('CURRENT','CURRENT_WITH_LEGACY_CONTENT','HISTORICAL','STALE','DONOR','REFERENCE')),
    scope TEXT NOT NULL,
    last_verified_at TEXT,
    conflicts_with_current_authority INTEGER NOT NULL DEFAULT 0 CHECK (conflicts_with_current_authority IN (0,1)),
    notes TEXT
);

CREATE TABLE IF NOT EXISTS external_sources (
    id TEXT PRIMARY KEY,
    authority TEXT NOT NULL,
    url TEXT NOT NULL UNIQUE,
    retrieved_at TEXT NOT NULL,
    source_type TEXT NOT NULL,
    claim_summary TEXT NOT NULL,
    freshness TEXT NOT NULL CHECK (freshness IN ('CURRENT','HISTORICAL','ARCHIVED')),
    notes TEXT
);

CREATE TABLE IF NOT EXISTS version_catalog (
    id TEXT PRIMARY KEY,
    component_id TEXT REFERENCES components(id),
    product TEXT NOT NULL,
    version_label TEXT NOT NULL,
    release_date TEXT,
    channel TEXT,
    architecture TEXT,
    host_os_min TEXT,
    host_os_max TEXT,
    guest_api_min INTEGER,
    guest_api_max INTEGER,
    bundled_sdk_version TEXT,
    deployment_target_min TEXT,
    deployment_target_max TEXT,
    source_kind TEXT NOT NULL,
    source_ref TEXT NOT NULL,
    evidence_class TEXT NOT NULL CHECK (evidence_class IN ('DIRECT_OBSERVED','PROJECT_ATTESTED','OFFICIAL_DOCUMENTED','HISTORICAL_PROJECT','CROSS_PROJECT_CLAIM','INFERRED','UNVERIFIED')),
    lifecycle_state TEXT NOT NULL CHECK (lifecycle_state IN ('CURRENT_AUTHORITY','CURRENT_CONTROL','KNOWN_GOOD_DONOR','HISTORICAL','CANDIDATE','REJECTED','UNKNOWN')),
    compatibility_state TEXT NOT NULL CHECK (compatibility_state IN ('PROVEN','CLAIMED','PARTIAL','CONDITIONAL','INCOMPATIBLE','UNKNOWN')),
    last_verified_at TEXT,
    exact_claim TEXT NOT NULL,
    limitations TEXT,
    candidate_role TEXT
);

CREATE TABLE IF NOT EXISTS compatibility_claims (
    id TEXT PRIMARY KEY,
    version_id TEXT REFERENCES version_catalog(id),
    environment_id TEXT REFERENCES environment_snapshots(id),
    subject TEXT NOT NULL,
    predicate TEXT NOT NULL,
    object TEXT NOT NULL,
    claim_kind TEXT NOT NULL CHECK (claim_kind IN ('OBSERVED','OFFICIAL_DOCUMENTED','PROJECT_DOCUMENTED','INFERRED','HYPOTHESIS')),
    result TEXT NOT NULL CHECK (result IN ('SUPPORTS','BLOCKS','CONDITIONAL','UNKNOWN','SUPERSEDED')),
    evidence_id TEXT REFERENCES evidence(id),
    external_source_id TEXT REFERENCES external_sources(id),
    source_document_id TEXT REFERENCES source_documents(id),
    observed_at TEXT,
    last_revalidated_at TEXT,
    stale_after TEXT,
    notes TEXT
);

CREATE TABLE IF NOT EXISTS deployment_target_candidates (
    target_version TEXT PRIMARY KEY,
    candidate_state TEXT NOT NULL CHECK (candidate_state IN ('RECOMMENDED','VIABLE','CONDITIONAL','REJECTED','UNKNOWN')),
    xcode26_6_supported INTEGER NOT NULL CHECK (xcode26_6_supported IN (0,1)),
    satisfies_std_filesystem INTEGER NOT NULL CHECK (satisfies_std_filesystem IN (0,1)),
    matches_existing_product_minimum INTEGER NOT NULL CHECK (matches_existing_product_minimum IN (0,1)),
    compatibility_score INTEGER NOT NULL CHECK (compatibility_score BETWEEN 0 AND 100),
    source_basis TEXT NOT NULL,
    rationale TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS stack_profiles (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    purpose TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('CURRENT_AUTHORITY','KNOWN_GOOD_DONOR','HISTORICAL','CANDIDATE','REJECTED','UNKNOWN')),
    confidence TEXT NOT NULL CHECK (confidence IN ('DIRECT','STRONG','INFERRED','HYPOTHESIS')),
    environment_id TEXT REFERENCES environment_snapshots(id),
    workload TEXT,
    exact_result TEXT NOT NULL,
    limitations TEXT,
    next_use TEXT
);

CREATE TABLE IF NOT EXISTS stack_profile_members (
    stack_id TEXT NOT NULL REFERENCES stack_profiles(id),
    version_id TEXT NOT NULL REFERENCES version_catalog(id),
    role TEXT NOT NULL,
    required INTEGER NOT NULL DEFAULT 1 CHECK (required IN (0,1)),
    PRIMARY KEY (stack_id, version_id, role)
);

CREATE TABLE IF NOT EXISTS table_metadata (
    table_name TEXT PRIMARY KEY,
    purpose TEXT NOT NULL,
    authority TEXT NOT NULL,
    update_policy TEXT NOT NULL,
    retention_policy TEXT NOT NULL,
    notes TEXT
);

CREATE TABLE IF NOT EXISTS field_metadata (
    table_name TEXT NOT NULL,
    column_name TEXT NOT NULL,
    declared_type TEXT,
    not_null INTEGER NOT NULL DEFAULT 0,
    default_value TEXT,
    primary_key INTEGER NOT NULL DEFAULT 0,
    semantic_role TEXT,
    unit TEXT,
    source_of_truth TEXT,
    volatility TEXT,
    notes TEXT,
    PRIMARY KEY (table_name, column_name)
);

CREATE INDEX IF NOT EXISTS idx_version_catalog_product ON version_catalog(product, version_label);
CREATE INDEX IF NOT EXISTS idx_version_catalog_state ON version_catalog(lifecycle_state, compatibility_state);
CREATE INDEX IF NOT EXISTS idx_compat_claims_subject ON compatibility_claims(subject, predicate);
CREATE INDEX IF NOT EXISTS idx_source_documents_status ON source_documents(temporal_status, authority_rank);
CREATE INDEX IF NOT EXISTS idx_stack_profiles_status ON stack_profiles(status);

CREATE VIEW IF NOT EXISTS v_current_environment AS
SELECT * FROM environment_snapshots
ORDER BY observed_at DESC
LIMIT 1;

CREATE VIEW IF NOT EXISTS v_version_candidates AS
SELECT product, version_label, lifecycle_state, compatibility_state,
       host_os_min, host_os_max, bundled_sdk_version,
       deployment_target_min, deployment_target_max,
       evidence_class, exact_claim, limitations, candidate_role
FROM version_catalog
WHERE lifecycle_state IN ('CURRENT_AUTHORITY','CURRENT_CONTROL','KNOWN_GOOD_DONOR','CANDIDATE')
ORDER BY CASE lifecycle_state
           WHEN 'CURRENT_AUTHORITY' THEN 0
           WHEN 'CURRENT_CONTROL' THEN 1
           WHEN 'KNOWN_GOOD_DONOR' THEN 2
           ELSE 3
         END, product, version_label;

CREATE VIEW IF NOT EXISTS v_document_truth_status AS
SELECT path, role, authority_rank, temporal_status, conflicts_with_current_authority,
       last_verified_at, notes
FROM source_documents
ORDER BY authority_rank DESC, path;

CREATE VIEW IF NOT EXISTS v_deployment_target_options AS
SELECT target_version, candidate_state, compatibility_score,
       xcode26_6_supported, satisfies_std_filesystem,
       matches_existing_product_minimum, rationale
FROM deployment_target_candidates
ORDER BY compatibility_score DESC, target_version;

CREATE VIEW IF NOT EXISTS v_compatibility_claims_current AS
SELECT c.id, c.subject, c.predicate, c.object, c.claim_kind, c.result,
       v.product, v.version_label, e.macos_version, e.xcode_version,
       c.last_revalidated_at, c.notes
FROM compatibility_claims c
LEFT JOIN version_catalog v ON v.id = c.version_id
LEFT JOIN environment_snapshots e ON e.id = c.environment_id
WHERE c.result <> 'SUPERSEDED'
ORDER BY c.subject, c.predicate, c.id;

INSERT OR REPLACE INTO map_meta(key, value) VALUES
('schema_version','2'),
('last_truth_audit_at','2026-08-28T05:19:03.867Z'),
('current_phase','Phase 1 architecture/version reevaluation after build failure at Ninja step 885/9854'),
('current_host_os','macOS 26.6.2 (25G83)'),
('current_xcode','26.6 (17F113)'),
('current_macos_sdk','26.5'),
('deployment_target_policy','Host OS, SDK, and deployment target are independent variables. Never inherit an upstream deployment target without validating it against current Xcode support, source API availability, and product compatibility goals.'),
('version_policy','Newest is not automatically preferred. Keep exact older versions as candidates when they have credible compatibility evidence; classify claims by provenance and revalidate before promotion.'),
('document_policy','Current authority, historical donor evidence, stale reports, and legacy claims must be distinguishable in queries; no whole-document trust by filename alone.');

INSERT OR REPLACE INTO components(id,name,kind,layer,ownership,status,purpose,notes) VALUES
('legacy_launcher_donor','Retired launcher/runtime donor','legacy_product','donor','UPSTREAM','AVAILABLE','Known working Apple-Silicon TFT PBE donor implementation','Useful compatibility evidence must be harvested field-by-field; legacy architecture is not v2 authority.'),
('android36_guest','Android 16 / API 36 ARM64 guests','guest_os','guest','GOOGLE','AVAILABLE','Historical working guest family for retired-donor/TFTMAC experiments','Includes Google APIs userdebug and Google Play variants; not current v2 production authority.'),
('gfxstream_main_dev_donor','emu-main-dev gfxstream donor build','gpu_transport','donor','UPSTREAM','AVAILABLE','Historical source-build evidence for native GLES/gfxstream experiments','Revision a9184fd was built successfully with local warning-compatibility allowances; not co-authoritative with locked emu-master-dev.'),
('deployment_target','macOS deployment target','build_contract','host_build','TFTMAC','ACTIVE','Defines minimum macOS API availability for produced native binaries','Must be selected independently from host OS and SDK version.');

INSERT OR REPLACE INTO evidence(id,observed_at,kind,source_path,source_sha256,statement,confidence,notes) VALUES
('ev_host_26_6_2','2026-08-28T04:07:47.479Z','host_preflight','ssot/host-preflight.json','c32ab07bdc18afa5ea261c4ab702f75a087319bce6f8cfe0efff9a3f898e5b97','Current host is Apple M4 Mac mini Mac16,10, arm64, 16 GB RAM, macOS 26.6.2 build 25G83; selected Xcode is 26.6 build 17F113 with macOS SDK 26.5.','DIRECT','This is current machine truth and must qualify every host-build compatibility claim.'),
('ev_legacy_target12','2026-08-27T01:46:26.991Z','source_build_contract','historical:removed-build-script','21932700a90aecf88a80e4d68fe0cdc748050aa39c0571bf2673a91228ff9c74','Retired donor production Swift and emulator-host binaries explicitly targeted arm64-apple-macosx12.0; historical launcher metadata also declared minimum macOS 12.0.','DIRECT','This is strong project-local evidence that 12.0 is a real compatibility target, not an invented number.'),
('ev_phase1_target1014_fail','2026-08-28T05:10:20.931Z','compiler_failure','/Volumes/MAC MINI M4/TFTMAC/Build/logs/phase1-build.stderr.log',NULL,'Phase 1 advanced through Ninja step 885/9854 and failed because AEMU host tooling set macOS deployment target 10.14 while source uses std::filesystem APIs marked available from macOS 10.15.','DIRECT','The current build worker is FAILED, not RUNNING. The failure is host build-contract compatibility, not a graphics capability failure.'),
('ev_aemu_legacy_target1014','2026-08-28T05:19:00Z','source_audit','external/qemu/android/scripts/unix/gen-android-sdk-toolchain.sh',NULL,'Locked AEMU helper carries OSX_DEPLOYMENT_TARGET=10.14 / OSX_REQUIRED=10.14 despite current upstream macOS development guidance requiring SDK 10.15 or later.','DIRECT','Treat this helper value as stale upstream build plumbing.'),
('ev_legacy_stack','2026-08-27T01:46:26.986Z','release_manifest','launcher/Resources/release-manifest.json','ec5b31e1d0fc6c05de087ea6bcd6dc4c9acfebb575b2d4fdcfe45d8a98de892c','Retired donor release evidence pins Platform Tools 36.0.2, Android Emulator 37.1.11 build 15917651, Android 36 Google APIs ARM64 system image r07, and TFT PBE 18.1-5212127.','DIRECT','Exact archived donor component set.'),
('ev_benchmark_m1max_stack','2026-08-27T01:46:26.981Z','benchmark_document','docs/benchmarks.md','526507229e293e92155fc3ba588bc48d6a149cc7c164d24e5d10ac33755d7965','Historical benchmark environment used M1 Max, macOS 26.6 build 25G72, Emulator 37.1.11 build 15917651, Android 36 ARM64 Google APIs userdebug, with ANGLE->Vulkan->gfxstream/MoltenVK->Metal.','DIRECT','This proves a specific older guest/runtime family ran extensively on macOS 26.x, but not on this exact M4 host.'),
('ev_native_gles_main_dev','2026-08-27T01:46:26.982Z','historical_source_build','docs/native-gles-transport-experiment.md','9b92313317a5eebd1900f5008c9db7018f467b20b6a6029dfc33523f240c650c','A historical emu-main-dev gfxstream host backend at revision a9184fd built successfully on the Mac after two AppleClang warning-compatibility adjustments; standalone backend was not a production drop-in.','DIRECT','Useful donor evidence only; do not mix branch authority.'),
('ev_live_tft_native','2026-08-27T01:46:35.222Z','package_architecture','docs/TFTMAC_GRAPHICS_ARCHITECTURE.md','06b7f5bf6ed6a84e7be2f3f296563a0fa9b436ec462eca0700d5bd8483490c59','Live TFT 16.16.8042660 base APK SHA 9ed691... launches RiotNativeActivity, contains libleagueoflegends.so, and showed no Unreal runtime markers.','DIRECT','Current workload engine evidence; separate from legacy PBE Unreal experiments.');

INSERT OR REPLACE INTO external_sources(id,authority,url,retrieved_at,source_type,claim_summary,freshness,notes) VALUES
('ext_apple_xcode_matrix','Apple','https://developer.apple.com/xcode/system-requirements','2026-08-28T05:20:00Z','official_support_matrix','Xcode 26.6 requires macOS Tahoe 26.2 or later, ships macOS SDK 26.5, and supports macOS deployment targets 11 through 26.5.','CURRENT','Use for host/deployment-target viability, not AEMU-specific compatibility.'),
('ext_apple_xcode266_notes','Apple','https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes','2026-08-28T05:20:00Z','official_release_notes','Xcode 26.6 includes macOS SDK 26.5 and requires macOS Tahoe 26.2 or later.','CURRENT',NULL),
('ext_aemu_darwin_dev','Google AOSP','https://android.googlesource.com/platform/external/qemu/+/emu-master-dev/android/docs/DARWIN-DEV.md','2026-08-28T05:20:00Z','official_development_guide','Current emu-master-dev macOS guide requires Xcode 10.1 or newer, recommends historical Xcode 13.4 / SDK 12.3, and requires macOS SDK 10.15 or later.','CURRENT','The guide is broader than the stale helper implementation.'),
('ext_aemu_helper','Google AOSP','https://android.googlesource.com/platform/external/qemu/+/bc5ef478bafb8091ef670236f9ba9f3b526cfa87/android/scripts/unix/gen-android-sdk-toolchain.sh','2026-08-28T05:20:00Z','official_source_snapshot','AEMU Darwin helper historically hardcodes OSX_DEPLOYMENT_TARGET=10.14 and a finite SDK allowlist.','HISTORICAL','Illustrates why source helper assumptions can lag platform documentation.'),
('ext_emulator_releases','Google Android Developers','https://developer.android.com/studio/releases/emulator','2026-08-28T05:20:00Z','official_release_notes','Emulator 37.1.11 Stable (2026-07-30) adds Vulkan extensions required for API 37; 36.6.11 raises API 37 minimum RAM to 4 GB and includes a macOS 26.3 Hypervisor cleanup fix; 36.5.10 introduces the new multi-device networking stack; 36.4.9 contains the documented Vulkan loader/backend/composition improvements.','CURRENT','Older stable versions remain candidates only after exact workload/guest testing.');

INSERT OR REPLACE INTO environment_snapshots(id,observed_at,host_model,host_arch,host_memory_gb,macos_version,macos_build,xcode_version,xcode_build,macos_sdk_version,developer_dir,source_kind,source_ref,confidence,notes) VALUES
('env_current_m4','2026-08-28T04:07:47.479Z','Mac16,10 Apple M4 Mac mini','arm64',16,'26.6.2','25G83','26.6','17F113','26.5','/Applications/Xcode-26.6.0.app/Contents/Developer','PROJECT_EVIDENCE','ssot/host-preflight.json','DIRECT','Current authoritative host environment.'),
('env_benchmark_m1max','2026-08-27T01:46:26.981Z','Apple M1 Max Mac','arm64',32,'26.6','25G72',NULL,NULL,NULL,NULL,'HISTORICAL_PROJECT','docs/benchmarks.md','DIRECT','Historical benchmark host; useful donor evidence but not this M4 machine.');

INSERT OR REPLACE INTO source_documents(id,path,sha256,role,authority_rank,temporal_status,scope,last_verified_at,conflicts_with_current_authority,notes) VALUES
('doc_stack','ssot/STACK.lock.yaml','a570433d39ecebc1f4dc8c9b08e5c92547ab2b91a0826abc6b70b1f725289f2c','machine-resolved authority',100,'CURRENT','Exact Phase 0 host/Android/AEMU/version lock','2026-08-28T05:19:03.867Z',0,'Machine values win over remembered prose.'),
('doc_ssot','TFTMAC_GPU_RUNTIME_SSOT.md','4c905ad35a676aa8f4ad0a22416e73d640120851ce9f41e742349ac61ceab1ea','architecture authority',95,'CURRENT','Product architecture and acceptance rules','2026-08-28T05:19:03.867Z',0,NULL),
('doc_plan','TFTMAC_FULL_IMPLEMENTATION_PLAN.md','81bd386c1d9d47f26659c93af914ec9a92568ee689e7bed47eb0f2afd6dd5f1a','execution authority',95,'CURRENT','Phase plan and causal routing','2026-08-28T05:19:03.867Z',0,'Must be revised with SSOT if architecture changes.'),
('doc_map','ssot/TFTMAC_ENGINEERING_MAP.sql',NULL,'dynamic engineering knowledge graph',90,'CURRENT','Cross-version evidence, dependencies, experiments, options and claims','2026-08-28T05:19:03.867Z',0,'Self-hash changes as this file is updated.'),
('doc_preflight','ssot/preflight-report.md','0ce58e1a891a3a250f1dcca1bccab5ace8c4ae08ed05877dbd0206327081136b','Phase 0 gate evidence',90,'CURRENT','Phase 0 PASS only','2026-08-28T05:19:03.867Z',0,'Does not imply Phase 1 success.'),
('doc_phase0_remediation','ssot/phase0-remediation-inventory.md','608c258b56a57ab4775100cd2e7b333db183df86464e09c9c4419892623b2622','historical remediation log',30,'STALE','Pre-Phase-0 blocker inventory','2026-08-28T05:19:03.867Z',1,'Still lists blockers already resolved; never use as current status.'),
('doc_tftmac_legacy','TFTMAC.md','a93a4c96a37b89033b627520bdbe848cb39b68a12d257caec31ca77ea703e37c','legacy live-profile claim',35,'CURRENT_WITH_LEGACY_CONTENT','Pre-v2 live TFT architecture claims','2026-08-28T05:19:03.867Z',1,'Contains Android 16/API36 and ES3.2 property-era claims; candidate evidence only.'),
('doc_graphics_legacy','docs/TFTMAC_GRAPHICS_ARCHITECTURE.md','06b7f5bf6ed6a84e7be2f3f296563a0fa9b436ec462eca0700d5bd8483490c59','live engine evidence + legacy adapter design',45,'CURRENT_WITH_LEGACY_CONTENT','Live TFT engine identification and pre-v2 adapter architecture','2026-08-28T05:19:03.867Z',1,'Live package inspection remains useful; architecture is not v2 authority.'),
('doc_readme_legacy','README.md','810e1d7117f4e9f6253d680bef270958f18645d7e275dcf9384c7db1a8cd6a13','Retired donor overview',30,'DONOR','Legacy product requirements/version pins/performance summary','2026-08-28T05:19:03.867Z',1,'Do not treat nonconformant GLES3.2-era behavior as v2 acceptance.'),
('doc_legacy_build','historical:removed-build-script','21932700a90aecf88a80e4d68fe0cdc748050aa39c0571bf2673a91228ff9c74','legacy build implementation evidence',50,'DONOR','macOS 12 deployment, signing, packaging','2026-08-28T05:19:03.867Z',0,'Strong donor for native macOS compatibility target.'),
('doc_legacy_manifest','launcher/Resources/release-manifest.json','ec5b31e1d0fc6c05de087ea6bcd6dc4c9acfebb575b2d4fdcfe45d8a98de892c','legacy exact version manifest',55,'DONOR','Retired donor Android/emulator/game component pins','2026-08-28T05:19:03.867Z',0,'Exact archived component versions.'),
('doc_benchmarks','docs/benchmarks.md','526507229e293e92155fc3ba588bc48d6a149cc7c164d24e5d10ac33755d7965','historical performance evidence',55,'HISTORICAL','M1 Max / Android36 / Emulator37.1.11 performance experiments','2026-08-28T05:19:03.867Z',0,'Scene-specific results; not current acceptance thresholds.'),
('doc_native_gles','docs/native-gles-transport-experiment.md','9b92313317a5eebd1900f5008c9db7018f467b20b6a6029dfc33523f240c650c','historical graphics capability research',65,'HISTORICAL','ANGLE/gfxstream/native GLES source and runtime experiments','2026-08-28T05:19:03.867Z',0,'Contains valuable negative evidence and emu-main-dev donor build results.'),
('doc_research_log','docs/research-log.md','e24b935ebcb6235db53130357121a26e724da0eec9186cbc90b6a0a1a6967dce','historical experiment chronology',50,'HISTORICAL','Compatibility/performance/rejected experiments','2026-08-28T05:19:03.867Z',0,'Useful for avoiding repeated failed experiments.');

INSERT OR REPLACE INTO version_catalog(id,component_id,product,version_label,release_date,channel,architecture,host_os_min,host_os_max,guest_api_min,guest_api_max,bundled_sdk_version,deployment_target_min,deployment_target_max,source_kind,source_ref,evidence_class,lifecycle_state,compatibility_state,last_verified_at,exact_claim,limitations,candidate_role) VALUES
('vc_macos_current','macos','macOS','26.6.2 / 25G83',NULL,'stable','arm64',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'project evidence','ssot/host-preflight.json','DIRECT_OBSERVED','CURRENT_AUTHORITY','PROVEN','2026-08-28T04:07:47.479Z','Current M4 host OS.','Host version is not a deployment target or SDK version.','Current host'),
('vc_xcode266','xcode','Xcode','26.6 / 17F113',NULL,'stable','arm64','26.2','26.x',NULL,NULL,'26.5','11','26.5','Apple support matrix','ext_apple_xcode_matrix','OFFICIAL_DOCUMENTED','CURRENT_AUTHORITY','PROVEN','2026-08-28T05:20:00Z','Installed and selected on current host; Apple supports it on Tahoe 26.2+ and documents macOS deployment targets 11-26.5.','Locked AEMU helper does not natively understand SDK 26.5.','Current compiler'),
('vc_xcode263','xcode','Xcode','26.3',NULL,'stable','arm64','15.6','26.x',NULL,NULL,'26.2','11','26.2','Apple support matrix','ext_apple_xcode_matrix','OFFICIAL_DOCUMENTED','CANDIDATE','CONDITIONAL','2026-08-28T05:20:00Z','Officially supports Tahoe 26.x and ships SDK 26.2.','Still outside locked AEMU helper SDK allowlist; would require compatibility adapter and is not currently installed.','Older current-host-compatible compiler candidate'),
('vc_xcode262','xcode','Xcode','26.2',NULL,'stable','arm64','15.6','26.x',NULL,NULL,'26.2','11','26.2','Apple support matrix','ext_apple_xcode_matrix','OFFICIAL_DOCUMENTED','CANDIDATE','CONDITIONAL','2026-08-28T05:20:00Z','Officially supports Tahoe 26.x and ships SDK 26.2.','Still outside locked AEMU helper SDK allowlist; would require adapter and is not currently installed.','Older current-host-compatible compiler candidate'),
('vc_xcode164','xcode','Xcode','16.4',NULL,'stable','arm64','15.3','26.1.x',NULL,NULL,'15.5','10.13','15','Apple support matrix','ext_apple_xcode_matrix','OFFICIAL_DOCUMENTED','CANDIDATE','INCOMPATIBLE','2026-08-28T05:20:00Z','Ships SDK 15.5 and has older deployment range.','Apple support matrix stops host support at Tahoe 26.1.x; current host is 26.6.2. SDK 15.5 also exceeds locked helper allowlist ending at 15.2.','Rejected on current host unless isolated older build environment'),
('vc_xcode162','xcode','Xcode','16.2',NULL,'stable','arm64','14.5','15.x',NULL,NULL,'15.2','10.13','15','Apple support matrix','ext_apple_xcode_matrix','OFFICIAL_DOCUMENTED','CANDIDATE','INCOMPATIBLE','2026-08-28T05:20:00Z','Ships SDK 15.2, which matches the locked helper allowlist.','Apple does not support Xcode 16.2 on macOS 26.6.2. Could be useful only on a separate older macOS build environment.','Historical helper-compatible compiler candidate'),
('vc_xcode134','xcode','Xcode','13.4 / 13F17a',NULL,'historical','arm64',NULL,NULL,NULL,NULL,'12.3',NULL,NULL,'Google AEMU guide','ext_aemu_darwin_dev','OFFICIAL_DOCUMENTED','HISTORICAL','CLAIMED','2026-08-28T05:20:00Z','Current AEMU macOS guide names Xcode 13.4 with SDK 12.3 as a recommended historical build stack.','Not supported as a current-host installation claim; would require a compatible separate build OS.','Historical upstream reference'),
('vc_emulator37111','aemu','Android Emulator','37.1.11 / build 15917651','2026-07-30','stable','darwin-aarch64',NULL,NULL,36,37,NULL,NULL,NULL,'Google release notes + project manifest','ext_emulator_releases','PROJECT_ATTESTED','CURRENT_CONTROL','PROVEN','2026-08-28T05:20:00Z','Pinned by retired donor; benchmarked on macOS 26.6 M1 Max; Google 37.1.11 release adds Vulkan extensions required for API 37.','Stock graphics capability for genuine conformant ES3.2 on current M4/API37 is not yet proven.','High-value stock-control candidate'),
('vc_emulator36611','aemu','Android Emulator','36.6.11','2026-06-02','stable','darwin-aarch64',NULL,NULL,37,37,NULL,NULL,NULL,'Google release notes','ext_emulator_releases','OFFICIAL_DOCUMENTED','CANDIDATE','CLAIMED','2026-08-28T05:20:00Z','Explicitly supports API37 memory requirements and includes a macOS 26.3 Hypervisor cleanup fix.','No project-local TFT run yet; exact API37 Vulkan extension coverage versus 37.1.11 must be tested.','Older stable emulator candidate'),
('vc_emulator36510','aemu','Android Emulator','36.5.10','2026-04-02','stable','darwin-aarch64',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'Google release notes','ext_emulator_releases','OFFICIAL_DOCUMENTED','CANDIDATE','CLAIMED','2026-08-28T05:35:30Z','Introduces the newer multi-device networking stack and includes a macOS crashpad high-CPU fix.','No official release-note evidence that this release adds the Vulkan improvements previously attributed to it; it also predates 37.1.11 API37 Vulkan-extension additions.','Older general-runtime control candidate'),
('vc_emulator3649','aemu','Android Emulator','36.4.9','2026-02-10','stable','darwin-aarch64',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'Google release notes','ext_emulator_releases','OFFICIAL_DOCUMENTED','CANDIDATE','CLAIMED','2026-08-28T05:35:30Z','Updates the bundled Vulkan loader, fixes Vulkan backend invalid-use cases, adds SkiaVk graphics-queue-emulation support and VulkanNativeSwapchain composition support; release notes describe macOS Vulkan support as experimental.','Older than API37-specific 36.6/37.1 changes; must be tested with the exact current guest and workload before any promotion.','Older Vulkan-focused emulator candidate'),
('vc_platformtools3602','android36_guest','Android Platform Tools','36.0.2',NULL,'stable','darwin',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'retired-donor manifest','launcher/Resources/release-manifest.json','PROJECT_ATTESTED','KNOWN_GOOD_DONOR','PROVEN','2026-08-27T01:46:26.986Z','Exact retired-donor platform-tools pin.','Not current v2 control revision.','Legacy donor'),
('vc_android36_r07','android36_guest','Android system image','Android 36 Google APIs ARM64 r07',NULL,'stable','arm64',NULL,NULL,36,36,NULL,NULL,NULL,'retired-donor manifest','launcher/Resources/release-manifest.json','PROJECT_ATTESTED','KNOWN_GOOD_DONOR','PROVEN','2026-08-27T01:46:26.986Z','Exact retired-donor system-image archive pin.','No Google Play in this exact manifest entry; rootable/Google Play variants were separate.','Legacy guest candidate'),
('vc_android37_r6','android_guest','Android system image','Android 17 / API37 Google Play ps16k ARM64 rev6',NULL,'stable','arm64',NULL,NULL,37,37,NULL,NULL,NULL,'STACK.lock','ssot/STACK.lock.yaml','DIRECT_OBSERVED','CURRENT_AUTHORITY','PROVEN','2026-08-28T04:32:56.368Z','Current frozen production guest image.','Runtime graphics acceptance not yet completed.','Current guest'),
('vc_legacy_launcher104','legacy_launcher_donor','Retired donor launcher','1.0.4 build 40',NULL,'release','arm64','12.0',NULL,36,36,NULL,'12.0',NULL,'project source','README.md + launcher/Info.plist','PROJECT_ATTESTED','KNOWN_GOOD_DONOR','PROVEN','2026-08-27T01:46:26.986Z','Legacy Apple-Silicon launcher/runtime with minimum macOS 12.0 and exact Emulator37.1.11/Android36 pins.','Experimental/best-effort; PBE workload; historical nonconformant ES3.2 exposure was used and cannot satisfy v2 graphics truth.','Native shell/build/runtime donor'),
('vc_tft_live1616','tft_android','TFT Android live','16.16.8042660',NULL,'Google Play','arm64',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'package inspection','docs/TFTMAC_GRAPHICS_ARCHITECTURE.md','PROJECT_ATTESTED','CURRENT_CONTROL','PROVEN','2026-08-27T01:46:35.222Z','Current inspected live package uses RiotNativeActivity/libleagueoflegends.so with no Unreal markers.','Compatibility with v2 API37 source-built runtime still requires vertical-slice proof.','Current workload'),
('vc_pbe1815212127','tft_android','TFT PBE','18.1-5212127',NULL,'PBE','arm64',NULL,NULL,36,36,NULL,NULL,NULL,'retired-donor manifest','launcher/Resources/release-manifest.json','PROJECT_ATTESTED','HISTORICAL','PROVEN','2026-08-27T01:46:26.986Z','Exact historical PBE workload used for retired-donor benchmarks.','Not the current live production client.','Historical graphics/workload donor'),
('vc_gfx_main_a9184fd','gfxstream_main_dev_donor','gfxstream host backend','emu-main-dev a9184fd',NULL,'development','darwin-aarch64',NULL,NULL,NULL,NULL,NULL,NULL,NULL,'historical project source build','docs/native-gles-transport-experiment.md','HISTORICAL_PROJECT','KNOWN_GOOD_DONOR','PARTIAL','2026-08-27T01:46:26.982Z','Standalone gfxstream_backend built successfully after two AppleClang warning allowances.','Export surface was not production drop-in; branch is not current authority.','Source-build donor'),
('vc_aemu_locked','aemu','AEMU/QEMU source','emu-master-dev qemu ae9d18d2',NULL,'development','darwin-aarch64',NULL,NULL,37,37,NULL,'10.14',NULL,'resolved manifest + source','ssot/STACK.lock.yaml','DIRECT_OBSERVED','CURRENT_AUTHORITY','PARTIAL','2026-08-28T05:19:03.867Z','Locked source configured fully and compiled through Ninja step 885/9854 with TFTMAC host adapters.','Upstream helper deployment target 10.14 is stale/incompatible with current source+Xcode; build not complete.','Current source authority');

INSERT OR REPLACE INTO compatibility_claims(id,version_id,environment_id,subject,predicate,object,claim_kind,result,evidence_id,external_source_id,source_document_id,observed_at,last_revalidated_at,stale_after,notes) VALUES
('cc_current_host','vc_xcode266','env_current_m4','Xcode 26.6','runs on','macOS 26.6.2','OBSERVED','SUPPORTS','ev_host_26_6_2','ext_apple_xcode_matrix','doc_stack','2026-08-28T04:07:47.479Z','2026-08-28T05:20:00Z',NULL,'Installed and selected successfully.'),
('cc_xcode266_deployment','vc_xcode266','env_current_m4','Xcode 26.6','supports macOS deployment target','11 through 26.5','OFFICIAL_DOCUMENTED','SUPPORTS',NULL,'ext_apple_xcode_matrix',NULL,NULL,'2026-08-28T05:20:00Z',NULL,'Therefore 10.14 is outside the officially supported deployment-target range.'),
('cc_aemu_target1014','vc_aemu_locked','env_current_m4','Locked AEMU helper','forces deployment target','10.14','OBSERVED','BLOCKS','ev_phase1_target1014_fail','ext_aemu_helper',NULL,'2026-08-28T05:10:20.931Z','2026-08-28T05:19:03.867Z',NULL,'Directly caused std::filesystem availability compile errors under SDK26.5.'),
('cc_legacy_target12','vc_legacy_launcher104','env_current_m4','Retired donor build','targets minimum macOS','12.0','OBSERVED','SUPPORTS','ev_legacy_target12',NULL,'doc_legacy_build','2026-08-27T01:46:26.991Z','2026-08-28T05:19:03.867Z',NULL,'12.0 is inside Xcode26.6 supported deployment range and satisfies std::filesystem availability.'),
('cc_xcode162_helper','vc_xcode162','env_current_m4','Xcode 16.2 SDK15.2','matches locked AEMU helper SDK allowlist','yes','INFERRED','BLOCKS',NULL,'ext_apple_xcode_matrix',NULL,NULL,'2026-08-28T05:20:00Z',NULL,'SDK matches helper but Apple does not support Xcode16.2 on current macOS26.6.2, so it is not a direct current-host solution.'),
('cc_xcode263_helper','vc_xcode263','env_current_m4','Xcode 26.3 SDK26.2','matches locked AEMU helper SDK allowlist','no','INFERRED','CONDITIONAL',NULL,'ext_apple_xcode_matrix',NULL,NULL,'2026-08-28T05:20:00Z',NULL,'Can run on current host but still needs adapter for stale AEMU helper.'),
('cc_emulator37111_mac26','vc_emulator37111','env_benchmark_m1max','Emulator 37.1.11','runs extensively on','macOS 26.6 M1 Max + Android36 userdebug','OBSERVED','SUPPORTS','ev_benchmark_m1max_stack',NULL,'doc_benchmarks','2026-08-27T01:46:26.981Z','2026-08-28T05:19:03.867Z',NULL,'Historical project benchmark evidence, not a guarantee for every guest or M4.'),
('cc_emulator37111_api37','vc_emulator37111',NULL,'Emulator 37.1.11','adds Vulkan extensions required for','API37 system images','OFFICIAL_DOCUMENTED','SUPPORTS',NULL,'ext_emulator_releases',NULL,'2026-07-30','2026-08-28T05:20:00Z',NULL,'High-value reason to keep 37.1.11 as stock control.'),
('cc_emulator36611_api37','vc_emulator36611',NULL,'Emulator 36.6.11','supports minimum VM memory behavior for','API37','OFFICIAL_DOCUMENTED','SUPPORTS',NULL,'ext_emulator_releases',NULL,'2026-06-02','2026-08-28T05:20:00Z',NULL,'Candidate older stable control; graphics extension parity not assumed.'),
('cc_emulator3649_vulkan','vc_emulator3649',NULL,'Emulator 36.4.9','documents Vulkan improvements including','loader/backend/SkiaVk/VulkanNativeSwapchain','OFFICIAL_DOCUMENTED','SUPPORTS',NULL,'ext_emulator_releases',NULL,'2026-02-10','2026-08-28T05:35:30Z',NULL,'Useful older graphics-focused control candidate, but macOS Vulkan was still described as experimental and API37 parity is not assumed.'),
('cc_legacy_es32','vc_legacy_launcher104','env_benchmark_m1max','Historical retired-donor graphics path','claimed ES3.2 using','exposeNonConformantExtensionsAndVersions','PROJECT_DOCUMENTED','BLOCKS',NULL,NULL,'doc_research_log',NULL,'2026-08-28T05:19:03.867Z',NULL,'Worked as historical workload-enablement evidence but is forbidden as v2 conformance proof.'),
('cc_live_api36_claim','vc_tft_live1616',NULL,'Legacy TFTMAC live profile','claims live TFT runs on','Android16/API36 stock/high-end tablet runtime','PROJECT_DOCUMENTED','CONDITIONAL','ev_live_tft_native',NULL,'doc_tftmac_legacy','2026-08-27T01:46:35.222Z','2026-08-28T05:19:03.867Z',NULL,'Useful older-stack candidate claim, but current v2 preflight explicitly quarantines legacy claims until revalidated.');

INSERT OR REPLACE INTO deployment_target_candidates(target_version,candidate_state,xcode26_6_supported,satisfies_std_filesystem,matches_existing_product_minimum,compatibility_score,source_basis,rationale) VALUES
('10.14','REJECTED',0,0,0,0,'AEMU stale helper + Apple Xcode26.6 matrix + direct compile failure','Outside Xcode26.6 supported deployment range and directly fails current AEMU std::filesystem compilation.'),
('10.15','REJECTED',0,1,0,25,'std::filesystem availability + Apple Xcode26.6 matrix','Meets std::filesystem introduction point but is still below Xcode26.6 official minimum deployment target 11.'),
('11.0','VIABLE',1,1,0,75,'Apple Xcode26.6 support matrix','Technically supported by current Xcode and source APIs, but lower than the project’s already-proven macOS12 minimum and therefore adds compatibility surface without proven product value.'),
('12.0','RECOMMENDED',1,1,1,95,'Apple Xcode26.6 support matrix + retired-donor build metadata','Supported by current Xcode, satisfies source APIs, and matches a proven Apple-Silicon product deployment target already used throughout this repository.'),
('15.0','VIABLE',1,1,0,70,'Apple Xcode26.6 support matrix','Modern and supported but unnecessarily narrows product compatibility relative to proven macOS12 target.'),
('26.5','CONDITIONAL',1,1,0,45,'Apple Xcode26.6 SDK/deployment matrix','Would minimize availability ambiguity but would restrict produced binaries to the newest OS family and discard useful Apple-Silicon compatibility for no current evidence-based benefit.');

INSERT OR REPLACE INTO stack_profiles(id,name,purpose,status,confidence,environment_id,workload,exact_result,limitations,next_use) VALUES
('stack_v2_current','TFTMAC v2 frozen API37 source stack','Current architecture authority','CURRENT_AUTHORITY','DIRECT','env_current_m4','Current live TFT','Phase0 PASS; locked AEMU fully configures and compiles to step 885/9854 before host deployment-target mismatch.','Phase1 build not complete; graphics/runtime probes not yet complete.','Test deployment target 12.0 through existing detached build harness; then resume smallest Phase1 proof.'),
('stack_legacy_launcher104','Retired donor Android36 / Emulator37.1.11','Legacy known-good donor','KNOWN_GOOD_DONOR','DIRECT',NULL,'TFT PBE 18.1-5212127','Native SwiftUI launcher, exact pinned SDK/emulator/system image, extensive game/runtime experiments.','Historical PBE and nonconformant ES32 workaround; not v2 conformance.','Harvest packaging, macOS12 target, runtime state machine, Emulator37.1.11 control behavior.'),
('stack_m1max_benchmark','M1 Max Android36 userdebug performance stack','Historical performance donor','HISTORICAL','DIRECT','env_benchmark_m1max','TFT PBE','Extensive fixed-stage benchmark evidence on Emulator37.1.11 / Android36 / ANGLE-Vulkan-gfxstream-MoltenVK-Metal.','Different hardware and PBE workload; many results are scene-specific.','Use only for causal/relative graphics insights and older-version compatibility candidates.'),
('stack_stock37111_api37','Stock Emulator37.1.11 + current API37 Play image','Low-maintenance control candidate','CANDIDATE','STRONG','env_current_m4','Current live TFT','Official release explicitly adds Vulkan extensions required for API37; current guest is already frozen.','Genuine ES3.2/GuestAngle capability on current M4 not yet measured.','Run permanent host/guest Vulkan and GLES probes before source-patching AEMU graphics.'),
('stack_stock36611_api37','Stock Emulator36.6.11 + API37','Older stable control candidate','CANDIDATE','STRONG','env_current_m4','Capability probes first','Official API37 memory behavior; macOS26.3 Hypervisor fix indicates active macOS26 support work.','May lack Vulkan additions explicitly delivered in 37.1.11.','Only test if 37.1.11 behavior regresses or source build remains disproportionately costly.'),
('stack_old_xcode_vm','Older macOS build environment + helper-compatible Xcode/SDK','Isolated build-tool compatibility candidate','CANDIDATE','INFERRED',NULL,'Build only','Xcode16.2 ships SDK15.2 matching stale helper allowlist; upstream AEMU historically recommends Xcode13.4/SDK12.3.','Neither is supported directly on current macOS26.6.2; requires separate compatible macOS build environment and binary transfer validation.','Keep as fallback if owned host adapter becomes harder than maintaining an isolated build environment.');

INSERT OR REPLACE INTO stack_profile_members(stack_id,version_id,role,required) VALUES
('stack_v2_current','vc_macos_current','host OS',1),
('stack_v2_current','vc_xcode266','compiler',1),
('stack_v2_current','vc_android37_r6','guest',1),
('stack_v2_current','vc_aemu_locked','source runtime',1),
('stack_v2_current','vc_tft_live1616','workload',1),
('stack_legacy_launcher104','vc_legacy_launcher104','launcher/runtime product',1),
('stack_legacy_launcher104','vc_emulator37111','emulator',1),
('stack_legacy_launcher104','vc_platformtools3602','platform tools',1),
('stack_legacy_launcher104','vc_android36_r07','guest image',1),
('stack_legacy_launcher104','vc_pbe1815212127','workload',1),
('stack_m1max_benchmark','vc_emulator37111','emulator',1),
('stack_m1max_benchmark','vc_pbe1815212127','workload',1),
('stack_stock37111_api37','vc_emulator37111','stock emulator',1),
('stack_stock37111_api37','vc_android37_r6','guest',1),
('stack_stock37111_api37','vc_tft_live1616','workload',1),
('stack_stock36611_api37','vc_emulator36611','stock emulator',1),
('stack_stock36611_api37','vc_android37_r6','guest',1),
('stack_old_xcode_vm','vc_xcode162','helper-compatible Xcode candidate',0),
('stack_old_xcode_vm','vc_xcode134','upstream-recommended historical Xcode candidate',0);

-- Correct stale Phase-1 rows with the latest durable observation.
INSERT OR REPLACE INTO experiments(id,observed_at,title,layer,hypothesis,action,result,status,reusable_lesson) VALUES
('exp_host_binutils','2026-08-28T05:10:20.931Z','Provide complete Darwin host tool wrappers','host_build','Once the missing compiler/binutils/Qt host contracts are supplied, the locked AEMU source will reach genuine compilation.','Preseeded Xcode clang/clang++ and Darwin tool wrappers plus Qt host-tool bridge.','PASS for bootstrap objective: configuration completed and Ninja advanced to step 885/9854; next failure is independent deployment-target API availability.','PASS','The owned host adapter is causally effective. Stop treating later source/API failures as the same toolchain-wrapper problem.'),
('exp_deployment_target_1014','2026-08-28T05:10:20.931Z','Audit AEMU macOS deployment target against current host/toolchain','host_build','Legacy 10.14 deployment target remains valid under Xcode26.6/SDK26.5.','Compiled locked AEMU source using current host adapter while preserving upstream 10.14 target.','Build failed at step 885/9854 because std::filesystem remove/path are unavailable to deployment target 10.14; current Xcode26.6 officially supports deployment targets only from macOS11 upward.','FAIL','Host OS, SDK, and deployment target must be modeled separately. Select a supported minimum target from evidence rather than inheriting upstream constants.');

INSERT OR REPLACE INTO failures(id,experiment_id,symptom,root_cause,owning_layer,workaround,permanent_fix,state) VALUES
('fail_deployment_target_1014','exp_deployment_target_1014','IniFile.cpp std::filesystem operations rejected as unavailable; Ninja stops around step 885/9854','AEMU helper forces MACOSX/OSX deployment target 10.14 while current source uses std::filesystem introduced in macOS10.15 and Xcode26.6 officially supports deployment targets only from macOS11.','host_build','Set a supported deployment target in the TFTMAC host adapter; 12.0 is the strongest current candidate because it matches existing product compatibility evidence.','TFTMAC host adapter owns deployment target selection and verifies it against current Xcode support matrix plus source API availability.','OPEN');

INSERT OR REPLACE INTO unknowns(id,question,owning_layer,blocking,next_probe,status,resolution) VALUES
('unk_phase1_result','Does locked AEMU complete when the host adapter uses macOS 12.0 deployment target instead of stale 10.14?','host_build',1,'Re-run the existing Phase1 build through the owned adapter with deployment target 12.0, preserving all other proven host adaptations and no graphics source mutation.','OPEN',NULL),
('unk_deployment_floor','Is macOS 12.0 the best production minimum, or does an 11.x target materially improve compatibility without cost?','product_compatibility',0,'Build/test 12.0 first because it is already project-proven; only test 11.x if product distribution goals justify it.','OPEN',NULL),
('unk_old_stock_runtime','Can stock Emulator37.1.11 + current API37 Play image satisfy the v2 capability graph without any source-built emulator?','architecture',0,'After Phase1 build parity is understood, run the same host/guest Vulkan and genuine GLES probes against stock37.1.11 as a control.','OPEN',NULL),
('unk_cross_project_aemu35','Does the separate tftmac-runtime project contain a source-built older AEMU/emulator release that is directly reusable here?','donor_analysis',0,'Verify exact emulator release/build, commits, boot proof and host-toolchain evidence in that project before adding it as PROVEN to version_catalog.','OPEN',NULL);

INSERT OR REPLACE INTO decisions(id,decided_at,decision,rationale,state,evidence_id,supersedes) VALUES
('dec_separate_host_sdk_target','2026-08-28T05:19:03.867Z','Model host macOS, Xcode, SDK, and deployment target as four independent compatibility dimensions.','The current host was known but stale AEMU deployment-target assumptions still caused a real compile failure.','ACTIVE','ev_phase1_target1014_fail',NULL),
('dec_target12_first','2026-08-28T05:20:00Z','Use macOS 12.0 as the first deployment-target candidate for Phase1 parity testing; do not set target to current host version by default.','12.0 is inside Xcode26.6 supported range, satisfies std::filesystem availability, and is already proven throughout the historical Apple-Silicon donor build.','ACTIVE','ev_legacy_target12',NULL),
('dec_version_matrix','2026-08-28T05:20:00Z','Maintain older software versions as explicit candidates with provenance, limitations, and revalidation state.','Older stable combinations may be simpler and already compatible; newest-version bias is not an engineering requirement.','ACTIVE',NULL,NULL);

INSERT OR REPLACE INTO constraints(id,category,statement,severity,mutable,rationale) VALUES
('con_version_truth','versioning','Do not equate newest with best. Every version choice must be justified by current-host support, workload capability, security/maintenance needs, and evidence.','HIGH',0,'Older stable versions can reduce compatibility friction; unsupported old versions can also create hidden failures.'),
('con_host_sdk_target_split','host_build','Host macOS version, Xcode version, SDK version, and deployment target must never be collapsed into one version field or inferred from one another.','HARD',0,'The Phase1 10.14 deployment-target failure occurred despite correct host/Xcode/SDK discovery.'),
('con_claim_provenance','knowledge','Every compatibility statement must declare whether it is directly observed, officially documented, project-documented, inferred, or hypothetical.','HIGH',0,'Prevents legacy claims from silently becoming current facts.');

INSERT OR REPLACE INTO architecture_candidates(id,name,summary,status,integration_cost,invention_level,expected_control,expected_risk,rationale) VALUES
('arch_h','Stock Emulator 37.1.11 + API37 capability-first runtime','Use Google stable Emulator37.1.11 as the machine/runtime control and only source-build or patch components if capability probes identify a real gap.','VIABLE',2,2,5,3,'37.1.11 is already pinned and heavily exercised in this repository, is current stable, and explicitly added Vulkan extensions for API37. This may eliminate most source-build maintenance if genuine GLES/Vulkan probes pass.'),
('arch_i','Isolated older macOS/Xcode AEMU build environment','Build locked AEMU in a separate compatible macOS environment using an older helper-friendly Xcode/SDK, then run the produced ARM64 runtime on the current host after parity/signature verification.','RESEARCH',6,3,6,5,'Could avoid continuously adapting stale build helpers, but adds a second build OS and artifact-transfer/signing contract. Current evidence favors the owned adapter first because it already reaches 885/9854 on the host.');

INSERT OR REPLACE INTO candidate_components(candidate_id,component_id,role,required) VALUES
('arch_h','aemu','Stock stable emulator binary',1),
('arch_h','android_guest','Current API37 Play guest',1),
('arch_h','angle','Built-in GuestAngle path',1),
('arch_h','gfxstream','Stock graphics transport',1),
('arch_h','tftmac_shell','Native product surface',1),
('arch_i','aemu','Locked source runtime',1),
('arch_i','tftmac_harness','Artifact verification/runtime integration',1),
('arch_i','xcode','Alternate build-environment compiler',1);

INSERT OR REPLACE INTO table_metadata(table_name,purpose,authority,update_policy,retention_policy,notes) VALUES
('map_meta','Global map schema/process/current-state metadata','engineering map','Update every material truth audit','Permanent','Values with current_* keys must be revised when environment/state changes.'),
('components','Logical system components independent of version','engineering map','Add/update as architecture changes','Permanent',NULL),
('component_versions','Exact frozen versions tied to components','STACK.lock/project evidence','Update when frozen source/tool authority changes','Permanent history',NULL),
('capabilities','Acceptance capabilities and falsifiable rules','SSOT','Change only with SSOT revision','Permanent',NULL),
('component_capabilities','Observed/expected capability state','probe evidence','Update after deterministic probes','Permanent history',NULL),
('interfaces','Component-to-component contracts','architecture evidence','Update when integration boundary changes','Permanent',NULL),
('dependencies','Required provider/consumer relationships','architecture evidence','Update after compatibility evidence','Permanent',NULL),
('constraints','Hard/high/medium/low project constraints','SSOT/user decisions','Update only with explicit architecture/product decision','Permanent',NULL),
('evidence','Atomic factual observations','direct artifacts/source/web authority','Append; do not rewrite history except factual correction','Permanent',NULL),
('experiments','Hypothesis/action/result/lesson records','experiment evidence','Append/update terminal status','Permanent',NULL),
('failures','Causal failure catalog','experiments/compiler/runtime evidence','Update state as fixed/avoided','Permanent',NULL),
('architecture_candidates','Competing solution architectures','engineering analysis','Re-score when evidence changes','Permanent',NULL),
('decisions','Explicit architectural/product decisions','evidence + user authority','Supersede rather than delete','Permanent',NULL),
('unknowns','Unresolved questions with owning layer and next probe','engineering map','Resolve with evidence','Until resolved + historical retention',NULL),
('invention_opportunities','Potential TFTMAC-owned technology boundaries','engineering analysis','Promote/reject with evidence','Permanent',NULL),
('paths','Storage/path authority','SSOT + runtime evidence','Update when storage architecture changes','Permanent',NULL),
('environment_snapshots','Exact host/toolchain observations over time','host probes','Append a new snapshot on environment change','Permanent','Do not overwrite old environment snapshots.'),
('source_documents','Authority/freshness classification of project documents','repository audit','Revalidate on document change','Permanent','Prevents stale docs from acting as current truth.'),
('external_sources','Official external compatibility/release evidence','official vendors/upstreams','Refresh when material version decisions are made','Permanent with freshness label',NULL),
('version_catalog','Current/older software versions and candidate roles','mixed provenance with explicit evidence_class','Update when versions are discovered/revalidated','Permanent','Never promote CLAIMED to PROVEN without direct evidence.'),
('compatibility_claims','Atomic compatibility statements across versions/environments','evidence/external/source docs','Revalidate and supersede explicitly','Permanent',NULL),
('deployment_target_candidates','macOS minimum-target options','Apple matrix + source API + project evidence','Update when Xcode/product floor changes','Permanent',NULL),
('stack_profiles','Whole-stack known-good/historical/candidate bundles','project evidence','Update as bundles are tested','Permanent',NULL),
('stack_profile_members','Version membership for stack bundles','version catalog','Update with stack profile','Permanent',NULL),
('table_metadata','Purpose/authority policy for each SQL table','engineering map schema','Update with schema','Permanent',NULL),
('field_metadata','Structural and semantic metadata for every SQL column','SQLite schema + annotations','Regenerate after schema changes','Permanent','Ensures all fields are queryable/documented structurally.');

-- Structural metadata for every field in every first- and second-generation table.
-- pragma_table_info makes this self-maintaining when executed from a clean DB.
DELETE FROM field_metadata;

INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility)
SELECT 'map_meta',name,type,"notnull",dflt_value,pk,'global metadata field','engineering map','mixed' FROM pragma_table_info('map_meta');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'components',name,type,"notnull",dflt_value,pk,'component field','engineering map','low' FROM pragma_table_info('components');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'component_versions',name,type,"notnull",dflt_value,pk,'version identity field','STACK.lock/evidence','medium' FROM pragma_table_info('component_versions');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'capabilities',name,type,"notnull",dflt_value,pk,'capability contract field','SSOT','low' FROM pragma_table_info('capabilities');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'component_capabilities',name,type,"notnull",dflt_value,pk,'capability observation field','probe evidence','high' FROM pragma_table_info('component_capabilities');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'interfaces',name,type,"notnull",dflt_value,pk,'interface contract field','architecture evidence','medium' FROM pragma_table_info('interfaces');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'dependencies',name,type,"notnull",dflt_value,pk,'dependency relation field','architecture evidence','medium' FROM pragma_table_info('dependencies');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'constraints',name,type,"notnull",dflt_value,pk,'constraint field','SSOT/user authority','low' FROM pragma_table_info('constraints');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'evidence',name,type,"notnull",dflt_value,pk,'evidence provenance field','direct source','append-only' FROM pragma_table_info('evidence');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'experiments',name,type,"notnull",dflt_value,pk,'experiment field','experiment evidence','medium' FROM pragma_table_info('experiments');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'failures',name,type,"notnull",dflt_value,pk,'failure causality field','experiment evidence','medium' FROM pragma_table_info('failures');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'experiment_evidence',name,type,"notnull",dflt_value,pk,'experiment/evidence relation','engineering map','low' FROM pragma_table_info('experiment_evidence');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'architecture_candidates',name,type,"notnull",dflt_value,pk,'architecture scoring field','engineering analysis','medium' FROM pragma_table_info('architecture_candidates');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'candidate_components',name,type,"notnull",dflt_value,pk,'candidate/component relation','engineering map','medium' FROM pragma_table_info('candidate_components');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'decisions',name,type,"notnull",dflt_value,pk,'decision record field','evidence/user authority','low' FROM pragma_table_info('decisions');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'unknowns',name,type,"notnull",dflt_value,pk,'unknown/probe routing field','engineering map','high' FROM pragma_table_info('unknowns');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'invention_opportunities',name,type,"notnull",dflt_value,pk,'invention analysis field','engineering analysis','medium' FROM pragma_table_info('invention_opportunities');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'paths',name,type,"notnull",dflt_value,pk,'filesystem authority field','SSOT/runtime','low' FROM pragma_table_info('paths');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'update_log',name,type,"notnull",dflt_value,pk,'map change-log field','engineering map','append-only' FROM pragma_table_info('update_log');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'environment_snapshots',name,type,"notnull",dflt_value,pk,'host environment observation','host probe','append-only' FROM pragma_table_info('environment_snapshots');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'source_documents',name,type,"notnull",dflt_value,pk,'document authority/freshness field','repository audit','medium' FROM pragma_table_info('source_documents');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'external_sources',name,type,"notnull",dflt_value,pk,'external provenance field','official upstream','medium' FROM pragma_table_info('external_sources');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'version_catalog',name,type,"notnull",dflt_value,pk,'software version/candidate field','mixed explicit provenance','medium' FROM pragma_table_info('version_catalog');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'compatibility_claims',name,type,"notnull",dflt_value,pk,'atomic compatibility claim field','evidence/provenance','high' FROM pragma_table_info('compatibility_claims');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'deployment_target_candidates',name,type,"notnull",dflt_value,pk,'deployment-target option field','Apple/source/project evidence','medium' FROM pragma_table_info('deployment_target_candidates');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'stack_profiles',name,type,"notnull",dflt_value,pk,'whole-stack profile field','project evidence','medium' FROM pragma_table_info('stack_profiles');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'stack_profile_members',name,type,"notnull",dflt_value,pk,'stack/version relation','version catalog','medium' FROM pragma_table_info('stack_profile_members');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'table_metadata',name,type,"notnull",dflt_value,pk,'table semantics field','engineering map schema','low' FROM pragma_table_info('table_metadata');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility) SELECT 'field_metadata',name,type,"notnull",dflt_value,pk,'field metadata self-description','engineering map schema','low' FROM pragma_table_info('field_metadata');

UPDATE field_metadata SET unit='ISO-8601 UTC timestamp', semantic_role='observation timestamp' WHERE column_name IN ('observed_at','decided_at','created_at','retrieved_at','last_verified_at','last_revalidated_at','stale_after','frozen_at');
UPDATE field_metadata SET unit='SHA-256 hex', semantic_role='content integrity identity' WHERE column_name LIKE '%sha256%' OR column_name='artifact_sha256';
UPDATE field_metadata SET semantic_role='foreign-key evidence pointer' WHERE column_name='evidence_id';
UPDATE field_metadata SET semantic_role='stable machine-readable identifier' WHERE column_name='id';
UPDATE field_metadata SET unit='version string', semantic_role='software/platform version' WHERE column_name LIKE '%version%';
UPDATE field_metadata SET unit='GiB', semantic_role='host physical memory' WHERE table_name='environment_snapshots' AND column_name='host_memory_gb';
UPDATE field_metadata SET unit='0-100 score', semantic_role='compatibility prioritization score' WHERE table_name='deployment_target_candidates' AND column_name='compatibility_score';

INSERT INTO update_log(observed_at,subject,change_summary,evidence_id) VALUES
('2026-08-28T05:19:03.867Z','Phase 1 truth correction','Reconciled detached build: no longer running; failed at Ninja step 885/9854 on macOS deployment target 10.14 versus std::filesystem availability.','ev_phase1_target1014_fail'),
('2026-08-28T05:20:00Z','Host compatibility model','Separated current host macOS 26.6.2, Xcode 26.6, SDK 26.5 and deployment target into independent compatibility dimensions.','ev_host_26_6_2'),
('2026-08-28T05:20:00Z','Version strategy','Added current/older Xcode, Emulator, Android guest, retired-donor and historical source-build versions with explicit provenance and limitations.',NULL),
('2026-08-28T05:20:00Z','Document truth model','Classified current authority, legacy donor, historical evidence and stale documents so obsolete claims cannot masquerade as current state.',NULL),
('2026-08-28T05:20:00Z','Deployment target','Promoted macOS 12.0 as first Phase1 parity candidate; rejected inherited 10.14 and unsupported 10.15 targets.','ev_legacy_target12');

-- ---------------------------------------------------------------------------
-- Historical runtime/profile/benchmark coverage
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS runtime_variants (
    id TEXT PRIMARY KEY,
    entrypoint TEXT NOT NULL,
    classification TEXT NOT NULL CHECK (classification IN ('RECOMMENDED','STABLE_FALLBACK','DIAGNOSTIC','PROVISIONAL','EXPERIMENTAL','REJECTED','HISTORICAL')),
    runtime_family TEXT NOT NULL,
    graphics_path TEXT,
    display_profile TEXT,
    resource_profile TEXT,
    exact_result TEXT NOT NULL,
    promotion_state TEXT NOT NULL CHECK (promotion_state IN ('PROMOTED','RETAINED','NOT_PROMOTED','REJECTED','UNKNOWN')),
    source_document_id TEXT REFERENCES source_documents(id),
    current_relevance TEXT NOT NULL,
    notes TEXT
);

CREATE TABLE IF NOT EXISTS benchmark_findings (
    id TEXT PRIMARY KEY,
    classification TEXT NOT NULL CHECK (classification IN ('CONFIRMED','PROVISIONAL','REJECTED','DIAGNOSTIC')),
    environment_id TEXT REFERENCES environment_snapshots(id),
    stack_id TEXT REFERENCES stack_profiles(id),
    workload TEXT NOT NULL,
    metric_summary TEXT NOT NULL,
    causal_interpretation TEXT NOT NULL,
    reproducibility TEXT NOT NULL,
    source_document_id TEXT REFERENCES source_documents(id),
    current_relevance TEXT NOT NULL,
    notes TEXT
);

CREATE TABLE IF NOT EXISTS artifact_registry (
    id TEXT PRIMARY KEY,
    path TEXT NOT NULL UNIQUE,
    artifact_kind TEXT NOT NULL,
    layer TEXT NOT NULL,
    role TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('CURRENT_AUTHORITY','CURRENT_IMPLEMENTATION','DONOR','HISTORICAL','EXPERIMENTAL','REJECTED','STALE')),
    mutation_policy TEXT NOT NULL,
    source_document_id TEXT REFERENCES source_documents(id),
    notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_runtime_variants_classification ON runtime_variants(classification, promotion_state);
CREATE INDEX IF NOT EXISTS idx_benchmark_findings_classification ON benchmark_findings(classification);
CREATE INDEX IF NOT EXISTS idx_artifact_registry_status ON artifact_registry(status, layer);

CREATE VIEW IF NOT EXISTS v_runtime_variant_history AS
SELECT entrypoint, classification, promotion_state, runtime_family, graphics_path,
       exact_result, current_relevance
FROM runtime_variants
ORDER BY CASE classification
           WHEN 'RECOMMENDED' THEN 0
           WHEN 'STABLE_FALLBACK' THEN 1
           WHEN 'PROVISIONAL' THEN 2
           WHEN 'EXPERIMENTAL' THEN 3
           WHEN 'DIAGNOSTIC' THEN 4
           WHEN 'HISTORICAL' THEN 5
           ELSE 6
         END, entrypoint;

CREATE VIEW IF NOT EXISTS v_confirmed_and_rejected_learning AS
SELECT id, classification, workload, metric_summary, causal_interpretation,
       reproducibility, current_relevance
FROM benchmark_findings
ORDER BY CASE classification WHEN 'CONFIRMED' THEN 0 WHEN 'REJECTED' THEN 1 WHEN 'PROVISIONAL' THEN 2 ELSE 3 END, id;

INSERT OR REPLACE INTO source_documents(id,path,sha256,role,authority_rank,temporal_status,scope,last_verified_at,conflicts_with_current_authority,notes) VALUES
('doc_launch_profiles','docs/launch-profiles.md','b3a53fff5c5e8ce37e5f7c0b1bf714e37d8ccead76e09981898934b8baa03524','historical runtime-profile index',55,'HISTORICAL','Explicit promoted/provisional/rejected launcher profiles','2026-08-28T05:31:00Z',0,'Primary source for not repeating rejected graphics profiles.'),
('doc_legacy_architecture','docs/architecture.md','7132bf652fc1d851cf5479f49d9258f9b6e789c6f299db3a868f657515994c2e','Retired donor architecture',45,'DONOR','Legacy launcher/runtime state machine, host/guest boundary, graphics and rollback','2026-08-28T05:31:00Z',1,'Architecture is donor-only; lifecycle/rollback patterns remain useful.'),
('doc_building','docs/building.md','53252cc1b4b364d69e2f0d6f6061d3c90ef246353fa6e4f3e60048e38f977e73','Retired donor build contract',45,'DONOR','macOS12 target, tools, signing, environment variables','2026-08-28T05:31:00Z',0,NULL),
('doc_tftmac_app','tftmac/Sources/TFTMACApp.swift','b92fc0b8b525fca9e77e57633ab7c1939e87c113c7dbaf4aadfa00888ca15a33','pre-v2 TFTMAC app implementation',35,'CURRENT_WITH_LEGACY_CONTENT','Native UI and legacy live-runtime orchestration','2026-08-28T05:31:00Z',1,'Hardcodes old internal SDK/AVD roots and legacy ES3.2 property injection; must not be promoted unchanged.'),
('doc_tftmac_info','tftmac/Info.plist','e1a46f86f6aa748f884314e84ff40518e1ce3b4841708fb7083b62d6cc6b6005','current native-app metadata donor',50,'CURRENT_WITH_LEGACY_CONTENT','Bundle identity/minimum macOS version','2026-08-28T05:31:00Z',0,'LSMinimumSystemVersion 12.0 supports deployment-target candidate.'),
('doc_v2_tool','tools/tftmac-v2.mjs',NULL,'current v2 execution harness',85,'CURRENT','External storage, Phase0, source/build workers, host compatibility and map validation','2026-08-28T05:31:00Z',0,'Self-hash changes during active implementation.');

INSERT OR REPLACE INTO evidence(id,observed_at,kind,source_path,source_sha256,statement,confidence,notes) VALUES
('ev_tftmac_shell_legacy_paths','2026-08-27T01:46:35.223Z','source_audit','tftmac/Sources/TFTMACApp.swift','b92fc0b8b525fca9e77e57633ab7c1939e87c113c7dbaf4aadfa00888ca15a33','Pre-v2 TFTMAC shell hardcodes ~/Library/Application Support/TFTMAC/sdk and avd, AVD TftHighEndTablet, and enhanced renderer property androidboot.opengles.version=196610.','DIRECT','This shell is a presentation/orchestration donor, not compatible unchanged with v2 external Runtime root or no-spoof acceptance.'),
('ev_reference_android36','2026-08-27T01:46:26.989Z','reference_config','reference/avd/config.ini','4432ae12207175e046e943ec60ffd97e1a427dd3c9142a7d1b9495f3ed623d92','Reference TftPBE AVD is Android36 ARM64 Google Play-class configuration with host GPU; generated hardware evidence shows 7 vCPU/6144MB and historical pipe transport.','DIRECT','Reference files capture donor state, not current production v2 state.'),
('ev_reference_rootable36','2026-08-27T01:46:26.989Z','reference_config','reference/rootable-avd/config.ini','095305826c0efe3c8bec12f9926e81672773ceb9deda3594894fb103fafb6977','Reference TftRootAffinity AVD is Android36 ARM64 Google APIs, rootable/no Play Store, 7 vCPU/6144MB, host GPU, 1600x900.','DIRECT','Useful proof of package-authority/execution-guest split patterns.'),
('ev_legacy_min12_plist','2026-08-27T01:46:26.983Z','bundle_metadata','launcher/Info.plist','33f27c2f2b1ee80e0b1d56035fb83002c862d4f6c003083b098303e2eec264ae','Retired donor bundle declared LSMinimumSystemVersion 12.0.','DIRECT',NULL),
('ev_tftmac_min12_plist','2026-08-27T01:46:35.222Z','bundle_metadata','tftmac/Info.plist','e1a46f86f6aa748f884314e84ff40518e1ce3b4841708fb7083b62d6cc6b6005','TFTMAC 1.0.0 native shell also declares LSMinimumSystemVersion 12.0.','DIRECT','Independent second project-local signal supporting macOS12 floor.');

INSERT OR REPLACE INTO compatibility_claims(id,version_id,environment_id,subject,predicate,object,claim_kind,result,evidence_id,external_source_id,source_document_id,observed_at,last_revalidated_at,stale_after,notes) VALUES
('cc_tftmac_shell_paths',NULL,'env_current_m4','Pre-v2 TFTMAC shell','uses runtime storage','internal Application Support sdk/avd paths','OBSERVED','BLOCKS','ev_tftmac_shell_legacy_paths',NULL,'doc_tftmac_app','2026-08-27T01:46:35.223Z','2026-08-28T05:31:00Z',NULL,'Must be refactored to consume v2 external Runtime/SDK/AVD roots before native-shell promotion.'),
('cc_tftmac_shell_spoof',NULL,'env_current_m4','Pre-v2 TFTMAC enhanced renderer','injects','androidboot.opengles.version=196610','OBSERVED','BLOCKS','ev_tftmac_shell_legacy_paths',NULL,'doc_tftmac_app','2026-08-27T01:46:35.223Z','2026-08-28T05:31:00Z',NULL,'Forbidden as v2 capability proof; source remains useful for UI/runtime control structure only.'),
('cc_two_min12_signals','vc_legacy_launcher104','env_current_m4','Retired donor and TFTMAC native bundles','share minimum macOS target','12.0','OBSERVED','SUPPORTS','ev_tftmac_min12_plist',NULL,'doc_tftmac_info','2026-08-27T01:46:35.222Z','2026-08-28T05:31:00Z',NULL,'Two independent project bundles plus build scripts use 12.0.'),
('cc_rootable36_split','vc_android36_r07',NULL,'Android36 userdebug/rootable donor','supports architecture pattern','separate execution guest without Play Store','PROJECT_DOCUMENTED','SUPPORTS','ev_reference_rootable36',NULL,'doc_legacy_architecture','2026-08-27T01:46:26.989Z','2026-08-28T05:31:00Z',NULL,'Useful only if conditional custom-driver execution guest becomes necessary.');

INSERT OR REPLACE INTO runtime_variants(id,entrypoint,classification,runtime_family,graphics_path,display_profile,resource_profile,exact_result,promotion_state,source_document_id,current_relevance,notes) VALUES
('rv_best_verified','run-tft-best-verified.command','RECOMMENDED','retired-donor/PBE Android36','ANGLE/OpenGL -> Vulkan -> gfxstream/MoltenVK -> Metal','1440p historical default',NULL,'Canonical audited legacy source launch; pins selected ASG, ANGLE/OpenGL and MoltenVK settings.','PROMOTED','doc_launch_profiles','Donor baseline only; v2 workload/guest differs.','Historical recommendation does not override v2 no-spoof policy.'),
('rv_fast_quality','run-tft-fast-quality.command','STABLE_FALLBACK','retired-donor/PBE Android36','Same selected legacy graphics stack','configurable',NULL,'Stable fallback without canonical override reset.','RETAINED','doc_launch_profiles','Useful rollback/donor structure.',NULL),
('rv_performance_max','run-tft-performance-max.command','HISTORICAL','retired-donor/PBE Android36','ANGLE/Vulkan/gfxstream/MoltenVK','2560x1440; 67% 3D scale','selected 16KiB ASG write step','Two full transport confirmations retained 34.1-35.1 FPS at stage1-8; app render-base.','PROMOTED','doc_launch_profiles','Performance donor only; not v2 acceptance.',NULL),
('rv_angle_opengl','run-tft-angle-opengl.command','DIAGNOSTIC','retired-donor/PBE Android36','Verified ANGLE/OpenGL overlay',NULL,NULL,'Required lower-level renderer delegate; not complete safety wrapper.','RETAINED','doc_launch_profiles','Useful graphics-control donor.',NULL),
('rv_root_affinity','run-tft-root-affinity.command','DIAGNOSTIC','Android36 rootable execution guest','ANGLE/gfxstream with root scheduling/overlays','1600x900 historical','7 vCPU / 6144MB donor','Owns rootable AVD, overlays, PSO scheduling, HWUI repair and cleanup.','RETAINED','doc_launch_profiles','Important conditional execution-guest donor.',NULL),
('rv_gles32_legacy','run-tft-gles32.command','HISTORICAL','older non-root Android36','legacy pipe-era GLES path','1600x900','6GB','Legacy stable fallback before selected ASG stack.','RETAINED','doc_launch_profiles','Do not infer genuine ES3.2 from name.',NULL),
('rv_mvk128','run-tft-mvk128-experimental.command','EXPERIMENTAL','retired-donor/PBE Android36','MoltenVK 128-buffer candidate',NULL,NULL,'One strong run failed cold and sustained reproducibility.','NOT_PROMOTED','doc_launch_profiles','Do not repeat as default.',NULL),
('rv_no_fbo_submit','run-tft-fast-quality-angle-no-fbo-submit.command','PROVISIONAL','retired-donor/PBE Android36','ANGLE preferSubmitAtFBOBoundary disabled',NULL,NULL,'Promising first run; lacked required cold confirmation.','NOT_PROMOTED','doc_launch_profiles','May be retested only under comparable modern stack evidence.',NULL),
('rv_shader_prewarm','run-tft-fast-quality-shader-prewarm.command','REJECTED','retired-donor/PBE Android36','shader preload candidate',NULL,NULL,'Neutral/rejected by fixed-stage campaign.','REJECTED','doc_launch_profiles','Do not repeat without new causal evidence.',NULL),
('rv_submit_thread','run-tft-fast-quality-submit-thread.command','REJECTED','retired-donor/PBE Android36','guest Vulkan submit/marshalling thread',NULL,NULL,'Regressed to 37.40/32.60/25.80 FPS at fixed stages.','REJECTED','doc_launch_profiles','Negative evidence.',NULL),
('rv_upstream_asg','run-tft-fast-quality-upstream-asg.command','REJECTED','retired-donor/PBE Android36','upstream ASG feature candidate',NULL,NULL,'Failed campaign promotion gates.','REJECTED','doc_launch_profiles','Negative evidence.',NULL),
('rv_asg_active_consumer','run-tft-fast-quality-asg-active-consumer.command','REJECTED','retired-donor/PBE Android36','isolated host active-consumer patch',NULL,NULL,'11.2 FPS / 334ms p95 versus 60 FPS / 18.44ms same-scene control.','REJECTED','doc_launch_profiles','Explicit forensic opt-in only.',NULL),
('rv_native_gles','run-tft-fast-quality-native-gles.command','DIAGNOSTIC','retired-donor/PBE Android36','native gfxstream GLES without guest ANGLE',NULL,NULL,'High-risk diagnostic; no accepted production result.','NOT_PROMOTED','doc_launch_profiles','Protocol/API capability gap proven in native GLES research.',NULL),
('rv_native_gles30','run-tft-fast-quality-native-gles30.command','REJECTED','retired-donor/PBE Android36','native GLES3.0',NULL,NULL,'TFT crashed before first frame because required GLES APIs absent.','REJECTED','doc_launch_profiles','Strong evidence against GLES3.0 shortcut.',NULL),
('rv_native_gles31','run-tft-fast-quality-native-gles31.command','REJECTED','retired-donor/PBE Android36','native GLES3.1 attempt',NULL,NULL,'Host native path exposed only GLES3.0; strict gate failed.','REJECTED','doc_launch_profiles','Strong evidence against shallow native-GLES shortcut.',NULL),
('rv_ubo_direct','run-tft-fast-quality-ubo-direct-write.command','EXPERIMENTAL','retired-donor/PBE Android36','direct UBO writes',NULL,NULL,'Isolated risky profile; no promotion evidence.','NOT_PROMOTED','doc_launch_profiles','Keep only for reproducibility.',NULL),
('rv_ubo_pool','run-tft-fast-quality-ubo-pool.command','EXPERIMENTAL','retired-donor/PBE Android36','larger UBO pool',NULL,NULL,'Isolated risky profile; no promotion evidence.','NOT_PROMOTED','doc_launch_profiles','Keep only for reproducibility.',NULL),
('rv_direct_vulkan','run-tft-direct-vulkan.command','REJECTED','retired-donor/PBE Android36','direct Unreal Vulkan RHI',NULL,NULL,'Selected Shipping device profile disabled direct Vulkan; Vulkan remained below ANGLE.','REJECTED','doc_launch_profiles','Current live client is not proven Unreal anyway.',NULL);

INSERT OR REPLACE INTO benchmark_findings(id,classification,environment_id,stack_id,workload,metric_summary,causal_interpretation,reproducibility,source_document_id,current_relevance,notes) VALUES
('bf_asg_vs_pipe','CONFIRMED','env_benchmark_m1max','stack_m1max_benchmark','Exact stage1-1 battle','ASG 40.1 FPS / 34.85ms p95 vs pipe 29.6 FPS / 49.75ms p95','ASG transport materially outperformed old pipe transport in controlled scene.','Accepted exact-scene A/B','doc_benchmarks','Transport-design donor; do not assume identical delta on API37.',NULL),
('bf_selected_stack','CONFIRMED','env_benchmark_m1max','stack_m1max_benchmark','Later stage1-5','36.0-36.8 FPS, p95 near35ms','Selected legacy stack was CPU/RHI/transport limited, not simply pixel-fill limited.','Confirmed range','doc_benchmarks','Useful bottleneck model.',NULL),
('bf_resolution_ab','CONFIRMED','env_benchmark_m1max','stack_m1max_benchmark','Controlled stage1-5 resolution A/B','2560x1440 31.3 FPS vs 1600x900 30.5 FPS despite 2.56x pixels','Scene was CPU/RHI-bound; lowering resolution was not a universal solution.','Accepted narrow A/B','doc_benchmarks','Avoid reflexive resolution reduction.',NULL),
('bf_effects67','CONFIRMED','env_benchmark_m1max','stack_m1max_benchmark','Tocker Trials stages1-2/1-5/1-8','Mean 45.20 / 38.50 / 33.80 FPS; stage1-8 p95 35.07-35.95ms','Lower-cost effects/LOD at 67% 3D scale improved heavy-scene throughput while preserving more resolution than 50%.','Two complete Trials','doc_benchmarks','Historical performance donor.',NULL),
('bf_asg16k','CONFIRMED','env_benchmark_m1max','stack_m1max_benchmark','Transport candidate','16KiB write step 41.3-43.0 / 34.1-35.1 FPS at stages1-5/1-8; paired4KiB control 38.0/32.8','Moderate ASG write-step increase reduced guest transport overhead without tail regression in selected profile.','Three complete 16KiB Trials plus paired control','doc_benchmarks','Candidate concept only; remeasure on current source/runtime.',NULL),
('bf_mvk128','REJECTED','env_benchmark_m1max','stack_m1max_benchmark','MoltenVK command buffers','Strong 40.20/34.50/32.40 run; cold confirmation 39.5/31.6/23.3','Single favorable run did not reproduce; larger buffer count hurt cold/heavy behavior.','Failed reproducibility','doc_benchmarks','Do not promote 128 buffers by memory.',NULL),
('bf_submit_thread','REJECTED','env_benchmark_m1max','stack_m1max_benchmark','Guest submit thread','37.40/32.60/25.80 FPS','Moving submission/marshalling to forced thread regressed fixed stages.','Rejected fixed-stage campaign','doc_benchmarks','Negative donor evidence.',NULL),
('bf_active_consumer','REJECTED','env_benchmark_m1max','stack_m1max_benchmark','ASG active-consumer host patch','11.2 FPS / 334ms p95 vs 60 FPS / 18.44ms control','Four-byte host patch catastrophically worsened pacing.','Same-scene rejection','doc_benchmarks','Never reapply without new causal reason.',NULL),
('bf_native_gles_capability','REJECTED','env_benchmark_m1max','stack_m1max_benchmark','Native gfxstream GLES shortcut','Native guest exposed ES3.0; ES3.1/3.2 requests failed; gate-relaxed TFT reached protocol validation failures','Shorter path lacks coherent ES3.1/3.2 capability contract; version spoof/alias patches cannot create semantics.','Multiple host/guest probes and game diagnostic','doc_native_gles','Critical architectural negative evidence.',NULL),
('bf_webview_skiagl','CONFIRMED','env_benchmark_m1max','stack_m1max_benchmark','Riot login WebView','Skia OpenGL HWUI avoided verified WebView Vulkan deadlock while TFT ANGLE Vulkan remained enabled','UI renderer and TFT renderer can be separated; Vulkan need not be globally disabled.','Repeated operational fix','doc_research_log','Useful future UI/runtime isolation pattern.',NULL);

INSERT OR REPLACE INTO artifact_registry(id,path,artifact_kind,layer,role,status,mutation_policy,source_document_id,notes) VALUES
('ar_stack','ssot/STACK.lock.yaml','machine_lock','authority','Exact machine/source/version lock','CURRENT_AUTHORITY','Mutate only through deterministic preflight/freeze tooling','doc_stack',NULL),
('ar_ssot','TFTMAC_GPU_RUNTIME_SSOT.md','authority_document','authority','Architecture/product acceptance authority','CURRENT_AUTHORITY','Revise together with implementation plan','doc_ssot',NULL),
('ar_plan','TFTMAC_FULL_IMPLEMENTATION_PLAN.md','authority_document','authority','Execution/phase authority','CURRENT_AUTHORITY','Revise together with SSOT','doc_plan',NULL),
('ar_map','ssot/TFTMAC_ENGINEERING_MAP.sql','knowledge_graph','reasoning','Persistent dependency/version/evidence map','CURRENT_AUTHORITY','Update before architecture-changing action','doc_map',NULL),
('ar_v2tool','tools/tftmac-v2.mjs','orchestration_code','host_build','Phase0/Phase1/external storage/build compatibility/map validation','CURRENT_IMPLEMENTATION','Changes require validation and map evidence','doc_v2_tool',NULL),
('ar_tftmac_shell','tftmac/Sources/TFTMACApp.swift','native_app_source','presentation','Pre-v2 native TFTMAC UI/runtime controller','DONOR','Do not promote unchanged; remove old storage and spoof assumptions first','doc_tftmac_app',NULL),
('ar_legacy_build','historical:removed-build-script','build_script','donor','Proven macOS12 native build/sign/package path','DONOR','Harvest compatibility patterns only','doc_legacy_build',NULL),
('ar_legacy_runtime','historical:removed-runtime-controller','runtime_controller','donor','Legacy process/runtime orchestration and environment injection','DONOR','Harvest state/lifecycle patterns; paths/profiles are legacy','doc_legacy_architecture',NULL),
('ar_legacy_paths','historical:removed-path-model','path_model','donor','Legacy Application Support SDK/AVD layout','HISTORICAL','Do not use for v2 bulk runtime path','doc_legacy_architecture',NULL),
('ar_ref_play36','reference/avd/config.ini','avd_reference','guest','Android36 Play-class AVD donor','HISTORICAL','Read-only evidence','doc_readme_legacy',NULL),
('ar_ref_root36','reference/rootable-avd/config.ini','avd_reference','guest','Android36 rootable execution donor','HISTORICAL','Read-only evidence','doc_readme_legacy',NULL),
('ar_native_gles_host_patch','artifacts/gfxstream-gles32-host-capability-prototype.patch','prototype_patch','graphics_transport','Historical GLES3.2 host capability prototype','EXPERIMENTAL','Do not apply to locked source without fresh causal evidence','doc_native_gles',NULL),
('ar_native_gles_alias_patch','artifacts/gfxstream-gles32-guest-proc-alias-prototype.patch','prototype_patch','guest_graphics','Historical proc-alias prototype','REJECTED','Retain for evidence only; runtime loader already resolved aliases','doc_native_gles',NULL),
('ar_performance_candidates','scripts/performance-candidates.json','experiment_manifest','performance','Historical reproducible performance candidates','HISTORICAL','Do not infer promotion from file presence','doc_benchmarks',NULL);

INSERT OR REPLACE INTO unknowns(id,question,owning_layer,blocking,next_probe,status,resolution) VALUES
('unk_native_shell_v2','Which current TFTMAC native-shell pieces can be retained after replacing legacy internal runtime paths and ES3.2 property injection?','presentation',0,'Defer until runtime capability path is green; then map UI/lifecycle code separately from obsolete runtime constants.','DEFERRED',NULL),
('unk_legacy_performance_transfer','Which confirmed M1 Max/Android36 performance findings remain directionally valid on M4/API37?','performance',0,'Only retest candidates tied to a measured current bottleneck; do not replay the historical campaign wholesale.','OPEN',NULL);

INSERT OR REPLACE INTO table_metadata(table_name,purpose,authority,update_policy,retention_policy,notes) VALUES
('runtime_variants','Historical launcher/profile outcomes and promotion status','launch-profiles/research evidence','Append or reclassify only with new comparable evidence','Permanent','Prevents rejected profile rediscovery.'),
('benchmark_findings','Confirmed/provisional/rejected measured findings','benchmark/research evidence','Append comparable findings; preserve scene/environment limits','Permanent','Performance evidence is environment/workload scoped.'),
('artifact_registry','Critical source/artifact role and mutation policy','repository audit','Update when artifact role/status changes','Permanent','Separates current authority from donor/rejected artifacts.');

INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility)
SELECT 'runtime_variants',name,type,"notnull",dflt_value,pk,'runtime variant/history field','launch-profile evidence','low' FROM pragma_table_info('runtime_variants');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility)
SELECT 'benchmark_findings',name,type,"notnull",dflt_value,pk,'benchmark evidence field','benchmark/research evidence','append-only' FROM pragma_table_info('benchmark_findings');
INSERT OR REPLACE INTO field_metadata(table_name,column_name,declared_type,not_null,default_value,primary_key,semantic_role,source_of_truth,volatility)
SELECT 'artifact_registry',name,type,"notnull",dflt_value,pk,'artifact governance field','repository audit','medium' FROM pragma_table_info('artifact_registry');

INSERT INTO update_log(observed_at,subject,change_summary,evidence_id) VALUES
('2026-08-28T05:31:00Z','Historical runtime coverage','Mapped every indexed legacy launch profile as promoted, provisional, experimental, diagnostic or rejected.',NULL),
('2026-08-28T05:31:00Z','Benchmark memory','Mapped confirmed and rejected transport/renderer findings so known failures are queryable instead of rediscovered.',NULL),
('2026-08-28T05:31:00Z','Native shell truth','Marked current pre-v2 TFTMAC shell as donor until internal runtime paths and GLES property injection are removed.','ev_tftmac_shell_legacy_paths'),
('2026-08-28T05:31:00Z','Artifact governance','Added critical artifact registry with current/donor/historical/experimental/rejected mutation policy.',NULL),
('2026-08-28T05:35:30Z','Version truth correction','Corrected Emulator36.5.10 release attribution and added Emulator36.4.9 as the documented Vulkan-improvement candidate.',NULL);

-- Xcode moving-piece audit for the actual macOS 26.6.2 host.
INSERT OR REPLACE INTO map_meta(key,value) VALUES
('oldest_official_xcode_on_current_host','Xcode 26 / 26.0.1'),
('current_host_xcode_family_span','Xcode 26.6, 26.5, 26.4.1, 26.3, 26.2, 26.1.1, 26.1, 26.0.1, 26'),
('xcode_selection_policy','Choose Xcode independently from host macOS and deployment target. Prefer the oldest/current-host-supported toolchain that reduces upstream friction only when it materially changes compiler/SDK compatibility; do not downgrade merely for age.'),
('legacy_xcode_boundary','Xcode 16.4 is not officially supported on macOS 26.6.2; older Xcodes require a separate compatible build environment if used as supported tooling.');

INSERT OR REPLACE INTO version_catalog(id,component_id,product,version_label,release_date,channel,architecture,host_os_min,host_os_max,guest_api_min,guest_api_max,bundled_sdk_version,deployment_target_min,deployment_target_max,source_kind,source_ref,evidence_class,lifecycle_state,compatibility_state,last_verified_at,exact_claim,limitations,candidate_role) VALUES
('vc_xcode265','xcode','Xcode','26.5',NULL,'stable','arm64','26.2','26.x',NULL,NULL,'26.5','11','26.5','Apple support matrix','ext_apple_xcode_matrix','OFFICIAL_DOCUMENTED','CANDIDATE','CONDITIONAL','2026-08-28T05:38:00Z','Officially supported on current macOS 26.6.2 host and ships macOS SDK26.5.','Same SDK generation as Xcode26.6; does not remove stale AEMU SDK/deployment-target assumptions.','Current-host-supported minor downgrade'),
('vc_xcode2641','xcode','Xcode','26.4.1',NULL,'stable','arm64','26.2','26.x',NULL,NULL,'26.4','11','26.4','Apple support matrix','ext_apple_xcode_matrix','OFFICIAL_DOCUMENTED','CANDIDATE','CONDITIONAL','2026-08-28T05:38:00Z','Officially supported on current macOS 26.6.2 host and ships macOS SDK26.4.','Still a 26.x SDK outside the stale AEMU helper allowlist; adapter still expected.','Current-host-supported older minor'),
('vc_xcode2611','xcode','Xcode','26.1.1',NULL,'stable','arm64','15.6','26.x',NULL,NULL,'26.1','11','26.1','Apple support matrix','ext_apple_xcode_matrix','OFFICIAL_DOCUMENTED','CANDIDATE','CONDITIONAL','2026-08-28T05:38:00Z','Officially supported on current macOS26.6.2 host and ships macOS SDK26.1.','Still a 26.x SDK outside stale helper knowledge.','Current-host-supported older minor'),
('vc_xcode261','xcode','Xcode','26.1',NULL,'stable','arm64','15.6','26.x',NULL,NULL,'26.1','11','26.1','Apple support matrix','ext_apple_xcode_matrix','OFFICIAL_DOCUMENTED','CANDIDATE','CONDITIONAL','2026-08-28T05:38:00Z','Officially supported on current macOS26.6.2 host and ships macOS SDK26.1.','Still a 26.x SDK outside stale helper knowledge.','Current-host-supported older minor'),
('vc_xcode2601','xcode','Xcode','26.0.1',NULL,'stable','arm64','15.6','26.x',NULL,NULL,'26.0','11','26.0','Apple support matrix','ext_apple_xcode_matrix','OFFICIAL_DOCUMENTED','CANDIDATE','CONDITIONAL','2026-08-28T05:38:00Z','Oldest patch release in the Xcode26 family officially supported on current macOS26.6.2 host.','SDK26.0 remains far newer than stale AEMU helper SDK list; does not inherently eliminate compatibility adapter.','Oldest officially supported current-host patch candidate'),
('vc_xcode260','xcode','Xcode','26',NULL,'stable','arm64','15.6','26.x',NULL,NULL,'26.0','11','26.0','Apple support matrix','ext_apple_xcode_matrix','OFFICIAL_DOCUMENTED','CANDIDATE','CONDITIONAL','2026-08-28T05:38:00Z','Oldest Xcode minor family Apple officially lists as supported on current macOS26.6.2 host.','Same fundamental 26.x SDK-era mismatch with stale AEMU helper.','Oldest officially supported current-host minor candidate');

INSERT OR REPLACE INTO compatibility_claims(id,version_id,environment_id,subject,predicate,object,claim_kind,result,evidence_id,external_source_id,source_document_id,observed_at,last_revalidated_at,stale_after,notes) VALUES
('cc_xcode26_family_current_host',NULL,'env_current_m4','Xcode 26 family','officially supports host macOS range including','macOS Tahoe 26.6.2','OFFICIAL_DOCUMENTED','SUPPORTS',NULL,'ext_apple_xcode_matrix',NULL,'2026-08-28T05:38:00Z','2026-08-28T05:38:00Z',NULL,'Apple lists Xcode26,26.0.1,26.1,26.1.1,26.2,26.3,26.4.1,26.5,26.6 as supporting Tahoe26.x; this is the supported local search space.'),
('cc_xcode164_current_host','vc_xcode164','env_current_m4','Xcode 16.4','officially supported on','macOS Tahoe 26.6.2','OFFICIAL_DOCUMENTED','BLOCKS',NULL,'ext_apple_xcode_matrix',NULL,'2026-08-28T05:38:00Z','2026-08-28T05:38:00Z',NULL,'Apple support stops at Tahoe26.1.x; current host is 26.6.2.'),
('cc_xcode26_helper_class',NULL,'env_current_m4','All officially supported Xcode26 local candidates','ship SDK family','26.x','INFERRED','CONDITIONAL',NULL,'ext_apple_xcode_matrix',NULL,'2026-08-28T05:38:00Z','2026-08-28T05:38:00Z',NULL,'Because stale AEMU helper knows SDKs only through15.2, moving within Xcode26 likely changes compiler details but not the need to own SDK/deployment-target compatibility.'),
('cc_google_xcode134','vc_xcode134',NULL,'Current emu-master-dev macOS guide','recommends historical toolchain','Xcode13.4 build13F17a with SDK12.3','OFFICIAL_DOCUMENTED','SUPPORTS',NULL,'ext_aemu_darwin_dev',NULL,'2026-08-28T05:38:00Z','2026-08-28T05:38:00Z',NULL,'This is upstream build guidance, not proof current 2026 source still compiles cleanly with that compiler or that it can run on this M4/macOS26.6.2 host.');

INSERT OR REPLACE INTO stack_profiles(id,name,purpose,status,confidence,environment_id,workload,exact_result,limitations,next_use) VALUES
('stack_xcode26_sweep','Current-host Xcode26 family sweep','Determine whether compiler/SDK minor revision affects locked AEMU host parity without changing macOS','CANDIDATE','STRONG','env_current_m4','AEMU Phase1 build parity','Nine Apple-listed Xcode26 releases are officially within the current host support envelope.','All ship 26.x macOS SDKs, so none is expected to eliminate the stale helper class by itself. Installing multiple huge Xcodes is expensive; test only a strategically selected old endpoint if 26.6+target12 still fails.','First keep Xcode26.6 and test deployment target12.0. If a compiler-specific failure remains, compare one endpoint such as Xcode26.0/26.0.1 rather than every minor.'),
('stack_google_legacy_xcode','Google-recommended historical AEMU Xcode13.4/SDK12.3','Potential isolated legacy build environment','CANDIDATE','STRONG',NULL,'AEMU build only','Current emu-master-dev DARWIN-DEV page explicitly recommends Xcode13.4/SDK12.3 and requires SDK10.15+.','Cannot be treated as supported on macOS26.6.2; current source may have evolved beyond compiler compatibility. Requires separate compatible Apple build environment and artifact verification.','Fallback experiment only if current-host adapter remains costly.');

INSERT OR REPLACE INTO unknowns(id,question,owning_layer,blocking,next_probe,status,resolution) VALUES
('unk_xcode_minor_effect','Does Xcode26.0/26.0.1 materially compile locked AEMU differently from Xcode26.6 after both use deployment target12.0?','host_build',0,'Do not download yet. First test Xcode26.6 + target12.0. Only if a compiler/SDK26.5-specific error remains, install one oldest supported Xcode26 endpoint and run the same bounded build stage.','OPEN',NULL),
('unk_legacy_xcode_build_host','Can current locked 2026 emu-master-dev source compile under Google-recommended Xcode13.4/SDK12.3 or helper-compatible Xcode16.2/SDK15.2 on a separate compatible Apple host?','host_build',0,'Treat as fallback research. Resolve viable hardware/macOS host first, then run configure-only before any full build.','OPEN',NULL);

INSERT INTO update_log(observed_at,subject,change_summary,evidence_id) VALUES
('2026-08-28T05:38:00Z','Xcode compatibility search space','Mapped every Xcode26 release Apple officially supports on current macOS26.6.2 and separated it from unsupported Xcode16.x/legacy isolated-build candidates.',NULL),
('2026-08-28T05:38:00Z','Xcode decision rule','Recorded that local Xcode26 downgrades still use 26.x SDKs, so deployment-target12.0 remains the first experiment before downloading another Xcode.',NULL);

-- ---------------------------------------------------------------------------
-- Schema/current-authority v3: first full official TFT gameplay baseline
-- ---------------------------------------------------------------------------
-- This section intentionally executes last so current measured runtime truth
-- supersedes the earlier source-AEMU/API37 planning state without deleting its
-- historical value.

INSERT OR REPLACE INTO map_meta(key,value) VALUES
('schema_version','3'),
('last_truth_audit_at','2026-08-28T18:30:59Z'),
('current_phase','Playable official TFT baseline -> measured performance optimization'),
('current_runtime','Google Emulator 37.1.11 / Android16 API36 Google Play ARM64 / TFT_Ultra_Tablet'),
('current_workload','Official TFT 18.1-5392842 versionCode 8392842 via com.android.vending'),
('current_renderer','Unreal GameActivity -> ANGLE -> Vulkan/ranchu -> virtio-gpu-asg/gfxstream -> MoltenVK -> Metal'),
('current_result','First full measured gameplay session completed in 1st place'),
('current_game_settings','Graphics=Medium; FPS cap=60; Performance Mode (Beta)=UNKNOWN. Available graphics presets: Low, Medium, High, Ultra High. Available FPS caps: 30, 60, None.'),
('current_performance_priority','Continuous-run telemetry is authoritative. Analyze the full logger capture across emulator/app lifetime; matches and setting changes are annotations for correlation, not mandatory segmentation boundaries. Keep one-variable experiments, but do not require per-match start/stop timing.'),
('current_trace_sources','Perfetto proven available: android.surfaceflinger.frame, android.surfaceflinger.frametimeline, android.surfaceflinger.layers, android.gpu.memory, linux.ftrace, linux.process_stats, linux.sys_stats.'),
('current_trace_collector_smoke','5s raw Perfetto smoke succeeded: 7479 bytes, SHA-256 214dddf456fa94f0ba634dc564f391d576a27bfc6b58610b6e91314376bd9028, zero SurfaceFlinger missed-frame delta during idle smoke.'),
('current_logger_guard','Sampler starts before emulator and must survive startup; TFT launch requires a live logger-growth health check; MATCH_ENTRY/COMBAT_START require fresh process, memory and logcat streams; status reports LOGGER_FAULT when not ready.'),
('current_multi_match_capture','One uninterrupted raw capture may contain multiple games. MATCH_ENTRY/MATCH_RESULT pairs define each match; match 2+ receives a distinct SQL sub-session ID so prior match evidence is never overwritten.'),
('current_performance_truth','User-visible performance was poor/laggy. Resource telemetry shows active memory pressure; gfxinfo cannot quantify native Unreal frame pacing. SurfaceFlinger cumulative counters also nominate GPU-side missed frames, but they are not match-scoped.');

INSERT OR REPLACE INTO components(id,name,kind,layer,ownership,status,purpose,notes) VALUES
('android_guest','Android 16 API36 Google Play ARM64 guest','guest_os','guest','GOOGLE','PROVEN','Official package-authority and gameplay guest','Current playable authority is API36 Play ARM64, not the earlier API37 planning guest.'),
('tft_android','Teamfight Tactics Android client 18.1','workload','application','RIOT','PROVEN','Primary production workload','Current package com.riotgames.league.teamfighttactics launched Unreal SplashActivity/GameActivity and completed a full first-place match.'),
('aemu','Google Android Emulator 37.1.11','hypervisor_runtime','virtualization','UPSTREAM','PROVEN','Current production machine/runtime host','Stock released emulator is now the playable authority; source-built AEMU is not required for the current product path.'),
('perfetto_trace','Android native frame tracing','telemetry','measurement','GOOGLE','AVAILABLE','Capture native Unreal/Vulkan frame pacing and causal graphics timing','Required because gfxinfo produced zero gameplay frames for the native Unreal/Vulkan path.');

INSERT OR REPLACE INTO component_versions(id,component_id,version,commit_sha,artifact_sha256,source_authority,frozen,notes) VALUES
('ver_android_guest','android_guest','Android16 / API36 Play ARM64 rev>=7',NULL,NULL,'direct runtime observation',1,'system-images;android-36;google_apis_playstore;arm64-v8a.'),
('ver_android_emulator_control','aemu','37.1.11 / build 15917651',NULL,NULL,'direct runtime observation',1,'First full official TFT match completed on this released emulator.'),
('ver_tft_current','tft_android','18.1-5392842 / 8392842',NULL,NULL,'Google Play-installed package observation',1,'Installer com.android.vending; signer digest still unresolved.');

INSERT OR REPLACE INTO capabilities(id,name,layer,description,acceptance_rule) VALUES
('cap_full_match_playability','Official TFT full-match playability','application','Official Google Play TFT completes a real match under the TFTMAC runtime.','Full match reaches result screen without device-compatibility rejection or process crash.'),
('cap_native_frame_timing','Native Unreal/Vulkan frame timing','measurement','TFTMAC records real gameplay presentation intervals and correlates stalls to renderer/system boundaries.','Perfetto/SurfaceFlinger/FrameTimeline or equivalent yields continuous native gameplay frame timing aligned to host telemetry.');

INSERT OR REPLACE INTO evidence(id,observed_at,kind,source_path,source_sha256,statement,confidence,notes) VALUES
('ev_first_win_playable','2026-08-28T18:25:16.276Z','gameplay_result','~/Library/Application Support/TFTMAC/Captures/2026-08-28T11-06-18-553Z-e6d3204f-17c2-4b80-9084-e76642089da2/markers.jsonl',NULL,'Official TFT 18.1-5392842 completed a 2152.69-second full match on the current runtime and the user placed 1st.','DIRECT','Functional vertical slice is proven end-to-end.'),
('ev_first_win_renderer','2026-08-28T18:30:59Z','runtime_renderer','~/Library/Application Support/TFTMAC/Captures/2026-08-28T11-06-18-553Z-e6d3204f-17c2-4b80-9084-e76642089da2/gameplay-analysis.json',NULL,'Current runtime is Android16 API36, ro.hardware.egl=angle, ro.hardware.vulkan=ranchu, ro.opengles.version=196610, virtio-gpu-asg/gfxstream host graphics with TFT-specific ANGLE VkInstance creation and MoltenVK/Metal host path.','DIRECT','ES3.2 exposure is an explicit compatibility adapter; this evidence proves workload compatibility, not GLES conformance.'),
('ev_first_win_resources','2026-08-28T18:30:59Z','gameplay_telemetry','~/Library/Application Support/TFTMAC/Captures/2026-08-28T11-06-18-553Z-e6d3204f-17c2-4b80-9084-e76642089da2/gameplay-analysis.json',NULL,'Across 1044-1046 in-match samples, emulator CPU mean=253.87%, p95=330.5%, max=363.2%; RSS mean=5155 MiB, p95=6126 MiB, max=6846 MiB; host compressed memory mean=4.15 GiB and pageouts increased by 12876.','DIRECT','Supports memory pressure as a candidate cause. CPU saturation is not demonstrated by this capture.'),
('ev_native_frame_blindspot','2026-08-28T18:30:59Z','measurement_gap','~/Library/Application Support/TFTMAC/Captures/2026-08-28T11-06-18-553Z-e6d3204f-17c2-4b80-9084-e76642089da2/gameplay-analysis.json',NULL,'gfxinfo produced zero match-window frame samples because the current workload presents through native Unreal/Vulkan rather than Android ViewRoot frame accounting.','DIRECT','Native frame tracing is now blocking before graphics tuning.'),
('ev_trace_capabilities','2026-08-28T18:42:01Z','measurement_capability','~/Library/Application Support/TFTMAC/Captures/2026-08-28T11-06-18-553Z-e6d3204f-17c2-4b80-9084-e76642089da2/trace-capabilities.json',NULL,'The current API36 guest exposes Perfetto android.surfaceflinger.frame, android.surfaceflinger.frametimeline, android.surfaceflinger.layers, android.gpu.memory, linux.ftrace, linux.process_stats and linux.sys_stats data sources.','DIRECT','Exact native frame/presentation telemetry is available without changing the graphics stack.'),
('ev_native_trace_smoke','2026-08-28T18:46:04Z','measurement_capture','~/Library/Application Support/TFTMAC/Captures/2026-08-28T11-06-18-553Z-e6d3204f-17c2-4b80-9084-e76642089da2/perfetto/native-smoke-5s-2026-08-28T18-45-59-859Z.pftrace','214dddf456fa94f0ba634dc564f391d576a27bfc6b58610b6e91314376bd9028','The low-overhead native collector completed a 5-second trace using SurfaceFlinger frame/frametimeline/layers plus GPU memory and produced a 7479-byte raw pftrace.','DIRECT','Collector path is proven. The trace still needs normalization/query support before frame metrics can enter the SQL lab.'),
('ev_sf_cumulative_misses','2026-08-28T18:42:01Z','surfaceflinger_counters','~/Library/Application Support/TFTMAC/Captures/2026-08-28T11-06-18-553Z-e6d3204f-17c2-4b80-9084-e76642089da2/trace-capabilities.json',NULL,'Latest post-match SurfaceFlinger cumulative display counters: renderRate=60 Hz, total missed=2709, GPU missed=2163, HWC missed=546; TFT GameActivity requests 60 Hz.','DIRECT','Counters are cumulative since boot and include non-TFT periods. They nominate a GPU-frame-miss trace but do not attribute the match.'),
('ev_user_first_win_quality','2026-08-28T18:28:00Z','user_observation',NULL,NULL,'User reported graphics and performance during the first full match as very bad, laggy, and low performance despite completing the match in first place.','DIRECT','Subjective quality observation; use as a target signal, not as quantitative FPS evidence.'),
('ev_single_play_avd','2026-08-28T18:25:16.276Z','architecture_result','~/Library/Application Support/TFTMAC/Captures/2026-08-28T11-06-18-553Z-e6d3204f-17c2-4b80-9084-e76642089da2/gameplay-analysis.json',NULL,'One API36 Google Play AVD installed/updated official TFT and executed the same official package through a full match.','DIRECT','No package-authority/execution-guest split is required for the current path.');

INSERT OR REPLACE INTO constraints(id,category,statement,severity,mutable,rationale) VALUES
('con_no_spoof','graphics_truth','Never describe ES3.2 compatibility exposure as genuine conformance. The current explicit nonconformant/testing exposure may be used only as a named workload-compatibility adapter until a conformant path is proven.','HARD',0,'Truthful labeling preserves engineering causality while allowing the currently proven playable path.'),
('con_measure_before_tune','performance','Do not promote graphics, transport, queue, shader, scheduler, or memory tuning without a comparable baseline and measurable result. Native frame timing is mandatory for graphics-performance claims.','HARD',0,'The first match proved that gfxinfo cannot measure this Unreal/Vulkan workload, so blind tuning would recreate the old rabbit hole.'),
('con_one_factor_perf','performance','Performance interventions must change one separable variable at a time and be reversible; KEEP requires measured improvement and confirmation.','HIGH',0,'The historical donor campaign already showed favorable one-off runs can fail cold confirmation.');

INSERT OR REPLACE INTO interfaces(id,from_component,to_component,interface_type,contract,state,notes) VALUES
('if_tft_angle','tft_android','angle','GLES compatibility','Official TFT reaches and uses ANGLE under the explicit ES3.2 compatibility exposure.','PROVEN','TFT-specific ANGLE VkInstance observed during successful full match.'),
('if_angle_vk','angle','gfxstream','Vulkan guest path','ANGLE uses Vulkan/ranchu and submits through gfxstream transport.','PROVEN','Direct runtime properties plus host graphics evidence.'),
('if_gfx_mvk','gfxstream','moltenvk_integrated','host Vulkan','gfxstream host Vulkan reaches MoltenVK/Metal.','PROVEN','Current released emulator successfully renders full TFT match on Apple M4.'),
('if_mvk_metal','moltenvk_integrated','metal','Metal','MoltenVK translates host Vulkan work to Metal on Apple M4.','PROVEN','Current runtime host path completed a full match.');

INSERT OR REPLACE INTO dependencies(id,consumer_component,provider_component,relationship,required,compatibility_state,evidence_id,notes) VALUES
('dep_angle_guestvk','angle','gfxstream','guest Vulkan transport',1,'PASS','ev_first_win_renderer','Current workload path is directly observed.'),
('dep_gfx_mvk','gfxstream','moltenvk_integrated','host Vulkan provider',1,'PASS','ev_first_win_renderer','Current full-match path is directly observed.'),
('dep_mvk_metal','moltenvk_integrated','metal','Apple GPU backend',1,'PASS','ev_first_win_renderer','Current full-match path is directly observed.'),
('dep_tft_gles32','tft_android','angle','ES3.2 workload compatibility',1,'WORKAROUND','ev_first_win_playable','TFT runs only after explicit ANGLE nonconformant/ES3.2 testing exposure. This is a compatibility workaround, not conformance.'),
('dep_tft_play','tft_android','google_play','install/update authority',1,'PASS','ev_single_play_avd','Installer com.android.vending; same AVD executed full match.');

INSERT OR REPLACE INTO component_capabilities(component_id,capability_id,state,evidence_id,notes) VALUES
('tft_android','cap_full_match_playability','PASS','ev_first_win_playable','First full official match completed in 1st place.'),
('angle','cap_guestangle','PASS','ev_first_win_renderer','Runtime workload directly reached ANGLE.'),
('angle','cap_gles32','PARTIAL','ev_first_win_renderer','Workload compatibility is proven only through explicit nonconformant/testing ES3.2 exposure; genuine conformance remains unproven.'),
('perfetto_trace','cap_native_frame_timing','PARTIAL','ev_native_trace_smoke','Required data sources and raw capture path are proven; a TFT-specific combat capture plus trace normalization/query still need validation before performance attribution.');

INSERT OR REPLACE INTO experiments(id,observed_at,title,layer,hypothesis,action,result,status,reusable_lesson) VALUES
('exp_first_win_baseline','2026-08-28T18:30:59Z','First full official TFT gameplay baseline','runtime_performance','The released stock-emulator/API36 compatibility path is sufficiently complete to produce a real gameplay baseline.','Captured full match with append-only host process/memory, clock, logcat, renderer state and result markers.','PASS: 1st place after 2152.69s. Performance was user-reported as poor. Resource telemetry is valid; native frame timing is missing.','PASS','The product path works. Optimize from measured current data; do not resume source-AEMU work unless a future measured capability gap requires it.');

INSERT OR REPLACE INTO experiment_evidence(experiment_id,evidence_id) VALUES
('exp_first_win_baseline','ev_first_win_playable'),
('exp_first_win_baseline','ev_first_win_renderer'),
('exp_first_win_baseline','ev_first_win_resources'),
('exp_first_win_baseline','ev_native_frame_blindspot'),
('exp_first_win_baseline','ev_trace_capabilities'),
('exp_first_win_baseline','ev_native_trace_smoke'),
('exp_first_win_baseline','ev_sf_cumulative_misses'),
('exp_first_win_baseline','ev_user_first_win_quality');

INSERT OR REPLACE INTO failures(id,experiment_id,symptom,root_cause,owning_layer,workaround,permanent_fix,state) VALUES
('fail_native_frame_telemetry','exp_first_win_baseline','Performance felt laggy but gfxinfo recorded zero match-window frames.','Current TFT renders through native Unreal/Vulkan, outside Android ViewRoot/gfxinfo frame accounting.','measurement','Use resource telemetry only for candidate nomination; do not claim frame metrics.','Add low-overhead native Perfetto/SurfaceFlinger/FrameTimeline capture aligned to existing host clock/log streams.','OPEN');

INSERT OR REPLACE INTO decisions(id,decided_at,decision,rationale,state,evidence_id,supersedes) VALUES
('dec_stock_runtime_primary','2026-08-28T18:30:59Z','Use released Google Emulator37.1.11 + API36 Play guest + TFTMAC compatibility adapter as the primary product/runtime path.','The path installed official TFT, passed the ES3.2 device gate after measured ANGLE compatibility exposure, survived Riot patching/login, and completed a full first-place match.','ACTIVE','ev_first_win_playable','dec_locked_aemu'),
('dec_native_trace_before_tuning','2026-08-28T18:30:59Z','Make native Unreal/Vulkan frame timing the next blocking measurement before graphics optimization.','gfxinfo produced zero gameplay frames, so graphics tuning cannot currently be scored honestly.','ACTIVE','ev_native_frame_blindspot',NULL),
('dec_memory_ab_first','2026-08-28T21:31:30Z','Use app-only refresh as immediate low-risk pressure relief, then test guest RAM 6144 -> 5120 MB as the first RAM intervention.','Equal 10/20/30 minute windows around the TFT app restart improved host available memory by ~0.90-0.94 GiB and lowered compressed memory by ~1.83-1.99 GiB despite higher emulator CPU/RSS; live pre-play refresh changed 4.97 -> 2.48 GiB compressed and 4.23 -> 5.59 GiB available. Game 2 guest free-memory minimum ~2.24 GiB makes 4096 MB too aggressive for the first RAM cut.','ACTIVE','ev_first_win_resources',NULL);

INSERT OR REPLACE INTO architecture_candidates(id,name,summary,status,integration_cost,invention_level,expected_control,expected_risk,rationale) VALUES
('arch_a','Locked source AEMU + TFTMAC compatibility/build adapter','Historical source-build path retained only if a future measured runtime capability gap requires source control.','RESEARCH',7,5,9,6,'The released stock emulator now completes official TFT matches; source build adds large failure surface without a current runtime need.'),
('arch_b','Stock Google Emulator37.1.11 + TFTMAC native shell/control','Official released emulator, API36 Play guest, explicit TFT compatibility adapter, native shell and evidence-driven performance lab.','PRIMARY',2,3,8,3,'Directly proven by a full official TFT first-place match on the target Apple M4 host.'),
('arch_h','Stock Emulator37.1.11 capability-first runtime','Earlier stock-control candidate is now subsumed by arch_b and retained for historical traceability.','VIABLE',2,2,6,3,'Its central question is answered: the stock emulator path is playable when paired with the measured compatibility adapter.');

INSERT OR REPLACE INTO unknowns(id,question,owning_layer,blocking,next_probe,status,resolution) VALUES
('unk_stock_capability','Does official Emulator37.1.11 provide the runtime capability needed by current TFT?','graphics_capability',0,'Retain genuine GLES3.2 conformance as a separate research question; product playability is already proven.','RESOLVED','Yes for workload execution when using the explicit ANGLE ES3.2 compatibility exposure; no claim of genuine conformance.'),
('unk_old_stock_runtime','Can stock Emulator37.1.11 + an official Play image run current TFT without a source-built emulator?','architecture',0,'No further probe required unless a future update regresses.','RESOLVED','Yes. Android16 API36 Play ARM64 + Emulator37.1.11 completed a full first-place match.'),
('unk_native_frame_timing','What is the real native Unreal/Vulkan frame-time distribution and which layer owns visible stalls?','measurement',1,'Capture android.surfaceflinger.frame + android.surfaceflinger.frametimeline + android.surfaceflinger.layers + android.gpu.memory during bounded real combat and align it to the existing host clock; add linux.ftrace only in heavier validation.','OPEN',NULL),
('unk_memory_causality','Does reducing guest RAM from 6144 to 5120 MB reduce sustained host compression and improve responsiveness without guest instability?','performance',0,'Run one-factor 5120 MB continuous-run A/B; keep vCPU/display/renderer/transport/package identical and reject if guest headroom approaches LMK/OOM risk.','OPEN',NULL),
('unk_signer_digest','What is the exact SHA-256 signer certificate digest of the current Google-Play-installed TFT base APK?','package_authority',0,'Repair the apksigner capture path and record the actual digest; do not substitute the hard-coded expected value.','OPEN',NULL),
('unk_phase1_result','Does locked source AEMU complete with the host adapter?','host_build',0,'Do not resume unless stock-runtime evidence reveals a source-only blocker.','DEFERRED','No current product need: released Emulator37.1.11 is playable.');

INSERT OR REPLACE INTO invention_opportunities(id,title,problem,tftmac_owned_solution,replaces_or_bypasses,benefit,risk,status) VALUES
('inv_native_frame_logger','TFT Native Frame Telemetry','gfxinfo cannot see Unreal/Vulkan gameplay frames, leaving visible lag unquantified.','Extend the existing append-only logger with bounded android.surfaceflinger.frame + frametimeline + layers + android.gpu.memory capture and clock-aligned stall extraction; add linux.ftrace only for heavier correlation.','ViewRoot/gfxinfo-only frame telemetry','Makes every future optimization scoreable and enables causal stall windows across Unreal/ANGLE/gfxstream/MoltenVK/Metal.','Tracing can perturb workload if configured too heavily; keep bounded/low-overhead and validate observer cost.','RECOMMENDED'),
('inv_memory_ab','Adaptive Guest Memory Profile','Current 6 GiB guest coincides with high host compression/pageouts on a 16 GiB unified-memory host.','Test and, if confirmed, promote a 5 GiB guest profile with automatic rollback when guest memory/instability gates fail.','Fixed donor RAM allocation','Could reduce host compression/swap and improve responsiveness with zero graphics-code changes.','Too little guest RAM may induce Android LMK/OOM or asset churn; requires measured A/B.','RECOMMENDED');

INSERT OR REPLACE INTO version_catalog(id,component_id,product,version_label,release_date,channel,architecture,host_os_min,host_os_max,guest_api_min,guest_api_max,bundled_sdk_version,deployment_target_min,deployment_target_max,source_kind,source_ref,evidence_class,lifecycle_state,compatibility_state,last_verified_at,exact_claim,limitations,candidate_role) VALUES
('vc_android36_play_current','android_guest','Android system image','Android16 API36 Google Play ARM64 rev>=7',NULL,'stable','arm64',NULL,NULL,36,36,NULL,NULL,NULL,'direct runtime observation','gameplay-analysis.json','DIRECT_OBSERVED','CURRENT_AUTHORITY','PROVEN','2026-08-28T18:30:59Z','Official Play guest installed and executed current TFT through a full match.','Compatibility path uses explicit ANGLE ES3.2 exposure.','Current guest'),
('vc_tft_current181','tft_android','TFT Android live','18.1-5392842 / 8392842',NULL,'Google Play','arm64',NULL,NULL,36,36,NULL,NULL,NULL,'direct package observation','gameplay-analysis.json','DIRECT_OBSERVED','CURRENT_AUTHORITY','PROVEN','2026-08-28T18:30:59Z','Installer com.android.vending; Unreal GameActivity; full first-place match completed.','Signer SHA-256 still unresolved.','Current workload');

UPDATE version_catalog SET lifecycle_state='HISTORICAL', candidate_role='Superseded guest planning baseline' WHERE id='vc_android37_r6';
UPDATE version_catalog SET lifecycle_state='HISTORICAL', candidate_role='Superseded workload inspection' WHERE id='vc_tft_live1616';
UPDATE version_catalog SET lifecycle_state='HISTORICAL', candidate_role='Source authority retained only for future blocker research' WHERE id='vc_aemu_locked';

INSERT OR REPLACE INTO stack_profiles(id,name,purpose,status,confidence,environment_id,workload,exact_result,limitations,next_use) VALUES
('stack_first_win','Playable official TFT baseline: API36 + Emulator37.1.11','Current product/performance baseline','CURRENT_AUTHORITY','DIRECT','env_current_m4','TFT 18.1-5392842','Official Google Play package completed a 2152.69s full match in 1st place; ANGLE/Vulkan/gfxstream/MoltenVK/Metal path directly observed.','Performance poor by user observation; gfxinfo has no native Unreal frame samples; signer digest unresolved.','Add native frame tracing, then run RAM 4 GiB one-factor A/B.');

INSERT OR REPLACE INTO stack_profile_members(stack_id,version_id,role,required) VALUES
('stack_first_win','vc_macos_current','host OS',1),
('stack_first_win','vc_emulator37111','stock emulator',1),
('stack_first_win','vc_android36_play_current','official Play guest',1),
('stack_first_win','vc_tft_current181','official workload',1);

INSERT OR REPLACE INTO runtime_variants(id,entrypoint,classification,runtime_family,graphics_path,display_profile,resource_profile,exact_result,promotion_state,source_document_id,current_relevance,notes) VALUES
('rv_current_first_win','TFTMAC start-donor-control','RECOMMENDED','Released Emulator37.1.11 / Android16 API36 Play','TFT -> ANGLE -> Vulkan/ranchu -> virtio-gpu-asg/gfxstream -> MoltenVK -> Metal','1920x1080 / 320 DPI / 60Hz target','6 vCPU / 6144 MB','Official TFT 18.1 completed a full first-place match.','PROMOTED',NULL,'Current product baseline','Compatibility ES3.2 exposure is explicit and nonconformant; performance requires optimization.');

INSERT OR REPLACE INTO benchmark_findings(id,classification,environment_id,stack_id,workload,metric_summary,causal_interpretation,reproducibility,source_document_id,current_relevance,notes) VALUES
('bf_first_win_resources','PROVISIONAL','env_current_m4','stack_first_win','Full first-place TFT match','2152.69s; emulator CPU mean253.87%/p95 330.5%; RSS mean5155MiB/max6846MiB; host compressed mean4.15GiB; pageouts +12876; native gfxinfo frames=0; post-match SF cumulative missed=2709/GPU=2163/HWC=546','Memory pressure is a high-value match-scoped candidate; cumulative SurfaceFlinger counters separately nominate GPU-side frame misses for TFT-specific tracing; aggregate emulator CPU saturation is not demonstrated.','One full match only; SurfaceFlinger counters are since boot; requires controlled A/B and native frametimeline capture.',NULL,'Primary current optimization baseline','User reported laggy/low graphics/performance.');

INSERT INTO update_log(observed_at,subject,change_summary,evidence_id) VALUES
('2026-08-28T18:30:59Z','Playable runtime authority','Promoted released Emulator37.1.11 + API36 Play + explicit TFT compatibility adapter to current product baseline; source-AEMU path moved to research-only.','ev_first_win_playable'),
('2026-08-28T18:30:59Z','Current workload truth','Corrected stale non-Unreal workload claim: current TFT18.1 launches Unreal GameActivity and uses ANGLE/Vulkan path.','ev_first_win_renderer'),
('2026-08-28T18:30:59Z','Performance baseline','Recorded first full-match resource envelope and user-reported poor performance without falsely inventing native frame metrics.','ev_first_win_resources'),
('2026-08-28T18:30:59Z','Optimization order','Made native frame tracing the blocking measurement and guest-RAM 4GiB A/B the first reversible performance intervention.','ev_native_frame_blindspot'),
('2026-08-28T18:42:01Z','Trace capability','Proved current guest exposes SurfaceFlinger frame/frametimeline/layers, GPU memory and Linux tracing data sources; native telemetry no longer requires guessing or external instrumentation.','ev_trace_capabilities'),
('2026-08-28T18:42:01Z','GPU miss nomination','Recorded cumulative SurfaceFlinger missed-frame counters as non-match-scoped nomination evidence only; requires TFT-specific frametimeline correlation before attribution.','ev_sf_cumulative_misses'),
('2026-08-28T18:46:04Z','Native trace collector','Validated a bounded low-overhead Perfetto raw collector using the four required fast-path data sources; combat capture and normalization remain next.','ev_native_trace_smoke'),
('2026-08-28T19:57:30Z','Always-on logger guard','Made telemetry fail-closed for product-controlled gameplay: sampler survival is checked at startup, launch-game runs a growth test, match-entry/combat require fresh streams, and status exposes LOGGER_FAULT.',NULL),
('2026-08-28T19:57:30Z','Multi-match evidence retention','Changed continuous-capture analysis to pair each match independently and ingest later games as separate SQL sub-sessions instead of overwriting the first baseline.',NULL);

-- ---------------------------------------------------------------------------
-- Match 2 observation: second 1st-place result with improved perceived quality
-- ---------------------------------------------------------------------------
INSERT OR REPLACE INTO map_meta(key,value) VALUES
('latest_match_result','Match 2: placement 1 / WIN at 2026-08-28T20:57:14.054Z'),
('latest_match_settings','Medium graphics / 60 FPS cap / Performance Mode Beta OFF'),
('latest_match_quality','User reported gameplay much better and graphics visibly improved versus Game 1.'),
('latest_match_boundary_quality','PARTIAL: exact MATCH_ENTRY was missed; restart-to-result window begins at TFT_APP_RESTART_COMPLETE 2026-08-28T20:17:03.528Z and must not be treated as exact match timing.'),
('latest_match_directional_signal','Compared with Game1, the approximate Match2 window had host compressed-memory mean -0.783 GiB, host available-memory mean +0.443 GiB, and 2236 fewer pageouts, while emulator CPU/RSS were higher. Directional evidence supports host memory pressure as a candidate, not CPU saturation.');

INSERT OR REPLACE INTO evidence(id,observed_at,kind,source_path,source_sha256,statement,confidence,notes) VALUES
('ev_game2_result','2026-08-28T20:57:14.054Z','gameplay_result','~/Library/Application Support/TFTMAC/Captures/2026-08-28T11-06-18-553Z-e6d3204f-17c2-4b80-9084-e76642089da2/markers.jsonl',NULL,'Match 2 completed in 1st place; result marker is exact and logger gate was healthy at the finish.','DIRECT','Second consecutive observed 1st-place result on the TFTMAC runtime.'),
('ev_game2_quality','2026-08-28T20:59:39.181Z','user_observation','~/Library/Application Support/TFTMAC/Captures/2026-08-28T11-06-18-553Z-e6d3204f-17c2-4b80-9084-e76642089da2/markers.jsonl',NULL,'User reported Game 2 gameplay was much better and graphics were visibly improved versus Game 1.','DIRECT','Subjective quality signal; not quantitative FPS evidence.'),
('ev_game2_memory_direction','2026-08-28T21:02:36Z','gameplay_telemetry','~/Library/Application Support/TFTMAC/Captures/2026-08-28T11-06-18-553Z-e6d3204f-17c2-4b80-9084-e76642089da2/gameplay-analysis-match-2-approx.json',NULL,'Approximate app-restart-to-result window: host compressed mean 3.36 GiB and pageout delta 10640; versus Game1 this is -0.783 GiB compressed memory, +0.443 GiB available memory, and -2236 pageouts. Emulator CPU/RSS were higher despite better perceived gameplay.','STRONG','Directional only because Match2 exact entry marker is missing. Supports memory-pressure investigation and argues against aggregate CPU/RSS magnitude alone explaining quality.');

INSERT INTO update_log(observed_at,subject,change_summary,evidence_id) VALUES
('2026-08-28T20:57:14.054Z','Match 2 result','Recorded second 1st-place TFT result with logger healthy at finish.','ev_game2_result'),
('2026-08-28T20:59:39.181Z','Match 2 user quality','Recorded materially better gameplay and graphics versus Game 1.','ev_game2_quality'),
('2026-08-28T21:02:36Z','Match 2 directional resource comparison','Recorded lower host compression/pageouts alongside better perceived quality; exact match timing remains partial because MATCH_ENTRY was missed.','ev_game2_memory_direction');

-- ---------------------------------------------------------------------------
-- Current graphics-pipeline boundary audit: 5 GiB candidate, Medium/60/OFF
-- ---------------------------------------------------------------------------
INSERT OR REPLACE INTO map_meta(key,value) VALUES
('current_graphics_pipeline','TFT Unreal -> Android SurfaceView -> ANGLE GLES compatibility -> guest Vulkan/ranchu -> virtio-gpu-asg/gfxstream -> host Vulkan -> MoltenVK -> Metal -> SurfaceFlinger/HWC -> 1920x1080 display'),
('current_graphics_pipeline_method','Score each connector independently. Measure the first boundary where bounded timing, queue pressure, buffer size, or presentation misses diverge; patch only that connector.'),
('current_game_surface_quality','At Medium/60/Performance OFF the TFT BLAST SurfaceView currently buffers 1280x720 and HWC scales it 1.5x to the 1920x1080 display. This is a proven image-quality boundary and may be an intentional game render-scale tradeoff.'),
('current_connector_state','ANGLE, gfxstream/ASG, MoltenVK and Metal are directly active with no current warning/error signals; their per-frame latency/backpressure is still unmeasured.'),
('current_presentation_state','60Hz exact request, device composition active, client composition inactive. Current boot cumulative counters at audit: 279 total misses, 278 HWC misses, 1 GPU miss; not workload-scoped.'),
('current_pipeline_next_probe','During active combat: pipeline audit immediately before -> 20s native Perfetto frame/frametimeline/layers/GPU-memory trace -> pipeline audit immediately after. Add ftrace only if the bounded frame trace points to scheduling/transport/queue ownership.');

INSERT OR REPLACE INTO evidence(id,observed_at,kind,source_path,source_sha256,statement,confidence,notes) VALUES
('ev_pipeline_audit_5gb','2026-08-28T22:22:43.349Z','graphics_pipeline_audit','~/Library/Application Support/TFTMAC/Captures/2026-08-28T21-40-53-459Z-d6d2f30b-ead9-47b8-8a81-16cc2551bd0e/graphics-pipeline-audit.json',NULL,'Current 5 GiB Medium/60/OFF pipeline audit: TFT SurfaceView render buffer 1280x720 -> display frame 1920x1080 (1.5x scale); ANGLE active with 2 TFT VkInstance creates and 0 ANGLE warning/error signals; virtio-gpu-asg active at 1MiB write buffer / 16KiB write step / 32KiB data ring / drawFlushInterval 800 with 0 gfxstream warning/error signals; MoltenVK native swapchain/composition active with 0 MoltenVK warning/error signals; presentation 60Hz exact with device composition.','DIRECT','The SurfaceView scale is an image-quality fact. Warning absence does not clear latency. Miss counters are cumulative since boot.'),
('ev_pipeline_sf_5gb','2026-08-28T22:17:47.209Z','surfaceflinger_pipeline','~/Library/Application Support/TFTMAC/Captures/2026-08-28T21-40-53-459Z-d6d2f30b-ead9-47b8-8a81-16cc2551bd0e/trace-capabilities.json',NULL,'SurfaceFlinger reports TFT exact 60Hz request and HWC DEVICE composition. The TFT BLAST SurfaceView source crop is 1280x720 into a 1920x1080 display frame. Current boot cumulative misses at this earlier snapshot were 215 total / 214 HWC / 1 GPU.','DIRECT','Use bounded before/after deltas during gameplay before assigning presentation bottleneck ownership.');

INSERT OR REPLACE INTO unknowns(id,question,owning_layer,blocking,next_probe,status,resolution) VALUES
('unk_game_render_surface_scale','Why does Medium/60/OFF produce a 1280x720 TFT SurfaceView on a 1920x1080 guest display, and which in-game preset changes that buffer size?','application_render_surface',0,'Timestamp graphics-preset changes and re-run graphics-pipeline-audit at Medium, High and Ultra High without changing emulator variables. If buffer size stays 1280x720, investigate an owned host-side upscale/presentation adapter rather than forcing the app blindly.','OPEN',NULL),
('unk_current_asg_backpressure','Does the current virtio-gpu-asg ring/decoder path accumulate guest-write/host-consume waits or excessive flushes under heavy TFT combat?','graphics_transport',0,'Use bounded combat trace first. If transport ownership remains plausible, add source-level counters around VirtioGpuAddressSpaceStream/AddressSpaceStream ring waits, bytes, flushes and host-consumed position before changing ring parameters.','OPEN',NULL),
('unk_current_mvk_queue_latency','Does MoltenVK queue-submit/command-buffer processing create significant frame latency on the current Apple M4 path?','host_graphics',0,'Enable bounded MoltenVK performance tracking or equivalent queue timing only after combat frame trace implicates host Vulkan/Metal; compare current async queue submits and 64 active command-buffer limit before changing them.','OPEN',NULL),
('unk_current_hwc_presentation','Are gameplay stalls owned by HWC/device composition, GPU completion, or upstream producer lateness?','presentation',0,'Use pre/post SurfaceFlinger counter deltas plus frametimeline during active combat. Do not infer from cumulative since-boot counters.','OPEN',NULL);

INSERT OR REPLACE INTO invention_opportunities(id,title,problem,tftmac_owned_solution,replaces_or_bypasses,benefit,risk,status) VALUES
('inv_pipeline_boundary_profiler','TFTMAC Graphics Boundary Profiler','The current path is playable but connector latency is opaque; generic CPU/memory metrics cannot identify where a frame waits.','Make the current graphics-pipeline-audit plus bounded Perfetto trace a first-class profiler: record app surface size, ANGLE activity, ASG parameters/waits, host Vulkan/MoltenVK queue statistics and SurfaceFlinger frame ownership into one monotonic timeline.','Broad graphics guessing and per-match manual interpretation','Turns each frame problem into a named connector with evidence, making source patches small and testable.','Some deep counters require a source-built graphics component; instrumentation must remain low overhead.','RECOMMENDED'),
('inv_host_quality_upscaler','TFTMAC Host Quality Upscaler','Current Medium preset feeds a 1280x720 game surface into a 1920x1080 display, so composition enlarges an already lower-detail image.','If higher in-game presets cannot provide acceptable native resolution/performance, intercept the host presentation texture in a source-controlled compositor/native shell and apply a high-quality Metal-side spatial upscaler before final presentation.','Plain HWC 1.5x scaling or forcing the game to render every pixel natively','Could improve perceived image quality while retaining a lower game render cost.','Requires owning the host presentation texture; any upscale adds GPU work/latency and must be A/B measured.','RESEARCH'),
('inv_asg_telemetry_patch','ASG Connector Telemetry Patch','Current stock logs prove ASG is active but expose no ring wait/backpressure timing.','Add low-overhead counters/timestamps at the guest VirtioGpuAddressSpaceStream/AddressSpaceStream ring and host ASG consume/decode boundary: bytes submitted, waits, write/consume distance, flush count and longest blocked interval.','Blind changes to writeStepSize/ring sizes/drawFlushInterval','Lets TFTMAC distinguish transport starvation from ANGLE/MoltenVK/presentation delay before tuning connector parameters.','Requires source-controlled gfxstream/AEMU component and careful observer-overhead validation.','RECOMMENDED'),
('inv_mvk_perf_bridge','MoltenVK Performance Bridge','The host Vulkan -> Metal connector is active but queue-submit and pipeline/command-buffer cost is opaque.','Expose bounded MoltenVK performance statistics/logging through the TFTMAC harness during diagnostic captures, aligned to the same host monotonic clock, without permanently enabling verbose logging.','Guessing from aggregate emulator CPU or one-off queue-setting tweaks','Can separate shader/pipeline compilation, queue submission and Metal command-buffer pressure from upstream transport delay.','Private/performance instrumentation can perturb workload; keep off by default and bounded.','RECOMMENDED');

INSERT INTO update_log(observed_at,subject,change_summary,evidence_id) VALUES
('2026-08-28T22:22:43.349Z','Graphics pipeline audit','Promoted boundary-by-boundary graphics diagnosis. Proven current image path includes 1280x720 TFT SurfaceView scaled 1.5x to 1920x1080; downstream ANGLE/ASG/MoltenVK path is active but latency remains unmeasured.','ev_pipeline_audit_5gb'),
('2026-08-28T22:22:43.349Z','Graphics invention direction','Added owned pipeline-profiler, ASG telemetry, MoltenVK performance bridge and conditional Metal-side quality-upscaler opportunities; patches are gated on bounded connector evidence.','ev_pipeline_audit_5gb');

INSERT OR REPLACE INTO map_meta(key,value) VALUES
('current_idle_native_trace','5s 5GiB lobby/idle trace at 2026-08-28T22:24:18Z: 223409-byte pftrace, SHA-256 2d629585f85649fe6220ffda3efc9c004eebc35a695d367ccab5588cff2cb889, SurfaceFlinger miss delta 0 total / 0 GPU / 0 HWC. This is the quiet baseline for the next combat trace.');

INSERT OR REPLACE INTO evidence(id,observed_at,kind,source_path,source_sha256,statement,confidence,notes) VALUES
('ev_5gb_idle_native_trace','2026-08-28T22:24:23.877Z','native_trace_baseline','~/Library/Application Support/TFTMAC/Captures/2026-08-28T21-40-53-459Z-d6d2f30b-ead9-47b8-8a81-16cc2551bd0e/perfetto/native-smoke-5s-2026-08-28T22-24-18-770Z.pftrace','2d629585f85649fe6220ffda3efc9c004eebc35a695d367ccab5588cff2cb889','Five-second 5 GiB lobby/idle trace captured SurfaceFlinger frame, frametimeline, layers and GPU-memory sources. Miss counters did not change: total=0, GPU=0, HWC=0 during the bounded window.','DIRECT','Quiet baseline only. The raw trace is validated but not yet normalized into per-frame SQL metrics.');

INSERT INTO update_log(observed_at,subject,change_summary,evidence_id) VALUES
('2026-08-28T22:24:23.877Z','Graphics quiet baseline','Captured a bounded five-second 5 GiB idle/lobby native trace with zero SurfaceFlinger miss delta for subtraction against the next active-combat trace.','ev_5gb_idle_native_trace');

-- ---------------------------------------------------------------------------
-- 5 GiB full-run result + audio/network fault isolation
-- ---------------------------------------------------------------------------
INSERT OR REPLACE INTO map_meta(key,value) VALUES
('latest_5gb_result','5 GiB Medium/60/Performance OFF run completed in 1st place; user rated gameplay acceptable overall.'),
('latest_5gb_memory_result','Medium/60/OFF segment: guest available min 1.584 GiB, mean 2.356 GiB; host available mean 5.476 GiB; host compressed mean 2.850 GiB, p95 3.800 GiB; 0 ANR, 0 fatal signal, 0 OOM. 5 GiB is viable for continued testing, not yet promoted as final.'),
('latest_audio_fault','TFT OpenSL ES media track is active at 44.1 kHz stereo, STREAM_MUSIC is unmuted/full-volume, AudioFlinger actively mixes to speaker with zero mixer underruns, but ranchu audio HAL repeatedly fails pcm_writei with I/O error. Fault boundary is AudioFlinger -> ranchu/QEMU/macOS backend.'),
('latest_audio_fix','Controlled emulator boots now request explicit -audio coreaudio instead of leaving macOS backend selection implicit. Requires post-reboot no-I/O-error verification and user audible-sound confirmation before promotion.'),
('latest_disconnect_fault','Late-game disconnect did not change TFT PID 6021 and Android network 101 remained assigned. TFT requested fresh connectivity callbacks at ~18:11:59/18:12:00 and ~18:14:01 and was immediately reassigned to network 101. Treat as Riot/TFT socket/session reconnect, not Android network loss or app crash, until deeper app transport evidence says otherwise.'),
('latest_graphics_run_delta','Pre-game pipeline audit 279 total/278 HWC/1 GPU missed; post-game 803 total/802 HWC/1 GPU. Delta +524 total, +524 HWC, +0 GPU across the broad run interval. Directionally prioritize producer->SurfaceFlinger/HWC pacing and 720p->1080p composition; bounded combat trace still required for causal attribution.');

INSERT OR REPLACE INTO evidence(id,observed_at,kind,source_path,source_sha256,statement,confidence,notes) VALUES
('ev_5gb_full_run','2026-08-28T23:20:34.904Z','continuous_run_telemetry','~/Library/Application Support/TFTMAC/Captures/2026-08-28T21-40-53-459Z-d6d2f30b-ead9-47b8-8a81-16cc2551bd0e/continuous-run-analysis.json',NULL,'5 GiB Medium/60/OFF segment retained at least 1.584 GiB guest available memory, host compressed mean 2.850 GiB/p95 3.800 GiB, and completed with no ANR, fatal signal or OOM.','DIRECT','Supports continued 5 GiB testing; run durations differ from 6 GiB baseline so do not overstate raw pageout or CPU/RSS deltas.'),
('ev_audio_ranchu_io','2026-08-28T23:17:48.393Z','audio_fault','~/Library/Application Support/TFTMAC/Captures/2026-08-28T21-40-53-459Z-d6d2f30b-ead9-47b8-8a81-16cc2551bd0e/runtime-fault-audit.json',NULL,'TFT PID 6021 had a started OpenSL ES media track routed to speaker; AudioFlinger primary mixer was active with zero raw underruns; ranchu audio HAL repeatedly returned pcm_writei I/O error -1.','DIRECT','Fault is below Android mixer and above/inside QEMU host audio output. Explicit CoreAudio backend is the next smallest repair.'),
('ev_disconnect_same_pid','2026-08-28T23:19:31.418Z','network_fault','~/Library/Application Support/TFTMAC/Captures/2026-08-28T21-40-53-459Z-d6d2f30b-ead9-47b8-8a81-16cc2551bd0e/disconnect-window-audit.json',NULL,'TFT PID stayed 6021 across the user-observed disconnect. TFT requested fresh Android network callbacks around 18:11:59-18:12:00 and 18:14:01; each was immediately assigned to existing network 101 with no observed Android network loss.','STRONG','Supports Riot/TFT socket/session reconnect as owning layer; exact remote-side cause remains unresolved.'),
('ev_5gb_presentation_delta','2026-08-28T23:21:18.835Z','graphics_pipeline_audit','~/Library/Application Support/TFTMAC/Captures/2026-08-28T21-40-53-459Z-d6d2f30b-ead9-47b8-8a81-16cc2551bd0e/graphics-pipeline-audit.json',NULL,'Across pre-game to post-game broad interval, SurfaceFlinger cumulative misses rose by 524, entirely HWC misses; GPU missed count stayed 1. TFT surface remained 1280x720 scaled 1.5x to 1920x1080.','STRONG','Broad interval includes non-combat time; use only to prioritize the next bounded combat trace, not to declare HWC root cause.');

INSERT OR REPLACE INTO unknowns(id,question,owning_layer,blocking,next_probe,status,resolution) VALUES
('unk_audio_coreaudio_fix','Does explicit CoreAudio backend eliminate ranchu pcm_writei I/O errors and restore audible TFT sound?','audio_host_backend',1,'Cold-restart the same 5 GiB runtime with -audio coreaudio, launch TFT, confirm no ranchu pcmWrite I/O errors, then obtain user audible confirmation.','TESTING',NULL),
('unk_riot_session_disconnect','Why did TFT request fresh network callbacks and briefly disconnect while Android network 101 remained available?','application_network_session',0,'On next occurrence capture a narrow log window for TFT/Riot socket/Cronet/native transport events; do not change emulator network stack without Android-level loss evidence.','OPEN',NULL);

INSERT OR REPLACE INTO failures(id,experiment_id,symptom,root_cause,owning_layer,workaround,permanent_fix,state) VALUES
('fail_ranchu_audio_output',NULL,'TFT produced no audible sound despite active Android media playback.','Android mixer/routing is healthy, but ranchu virtual audio HAL cannot write PCM to the implicitly selected QEMU host backend and repeatedly reports I/O error -1.','audio_host_backend','Restart controlled emulator with explicit CoreAudio backend.','Pin and validate explicit macOS audio backend in TFTMAC startup; add audio health gate that detects repeated ranchu pcmWrite failures.','WORKAROUND');

INSERT INTO update_log(observed_at,subject,change_summary,evidence_id) VALUES
('2026-08-28T23:20:34.904Z','5 GiB runtime result','Recorded viable 5 GiB run with 1st-place completion, acceptable gameplay and no Android low-memory instability.','ev_5gb_full_run'),
('2026-08-28T23:17:48.393Z','Audio fault isolation','Localized no-sound regression to ranchu/QEMU host audio output after proving TFT OpenSL and AudioFlinger speaker path healthy.','ev_audio_ranchu_io'),
('2026-08-28T23:19:31.418Z','Disconnect isolation','Classified late-game disconnect as same-process app/session reconnect with Android network still available.','ev_disconnect_same_pid'),
('2026-08-28T23:21:18.835Z','Presentation direction','Recorded +524 broad-interval HWC misses with zero additional GPU misses and persistent 720p->1080p scaling.','ev_5gb_presentation_delta');

INSERT OR REPLACE INTO map_meta(key,value) VALUES
('latest_audio_coreaudio_validation','Fresh 5 GiB run launched emulator with explicit -audio coreaudio. With TFT PID 5276 active, audio-health observed an active 44.1 kHz stereo OpenSL ES media track, mixer underruns partial=0/empty=0, ranchu pcm_writei I/O error count=0 and ranchu pcmWrite failure count=0. Machine-side audio path is healthy; user audible confirmation remains the final acceptance check.'),
('latest_lock_screen_repair','Cold boot black screen was Android power/keyguard state, not graphics: mWakefulness=Asleep and SCREEN_STATE_OFF while keyguard was healthy. Auto PIN-entry logic was removed. TFTMAC now wakes via the real power path only when asleep, enables stay-awake for the controlled session, and leaves PIN entry manual. Post-repair state reached mWakefulness=Awake, SCREEN_STATE_ON, then Nexus Launcher after user unlock.'),
('latest_reconnect_pid_policy','Reconnect/fault diagnostics now record and compare the actual TFT launch PID per session instead of hard-coding a historical PID.');

INSERT OR REPLACE INTO evidence(id,observed_at,kind,source_path,source_sha256,statement,confidence,notes) VALUES
('ev_audio_coreaudio_health','2026-08-28T23:40:00.797Z','audio_health','~/Library/Application Support/TFTMAC/Captures/2026-08-28T23-31-16-637Z-df54ebaa-561a-4567-ab20-d94baf0a3619/audio-health.json',NULL,'Explicit CoreAudio run: TFT PID 5276 has active OpenSL ES 44.1 kHz stereo playback; AudioFlinger mixer underruns are 0/0; ranchu pcm_writei I/O errors=0 and pcmWrite failures=0.','DIRECT','Machine-side repair validated. Audible-output acceptance still requires user confirmation.'),
('ev_lock_screen_power_state','2026-08-28T23:37:54.563Z','guest_power_state','~/Library/Application Support/TFTMAC/Captures/2026-08-28T23-31-16-637Z-df54ebaa-561a-4567-ab20-d94baf0a3619/screen-state-probe.json',NULL,'Black emulator window was caused by Android guest being asleep with screenState OFF while keyguard/SystemUI remained healthy; explicit wake changed guest to Awake and SCREEN_STATE_ON.','DIRECT','Not a renderer/gfxstream/MoltenVK failure. Automatic PIN entry was removed; secure unlock remains manual.');

INSERT INTO update_log(observed_at,subject,change_summary,evidence_id) VALUES
('2026-08-28T23:40:00.797Z','CoreAudio repair validation','Validated explicit CoreAudio with active TFT playback and zero ranchu PCM write failures.','ev_audio_coreaudio_health'),
('2026-08-28T23:37:54.563Z','Black-screen repair','Localized black screen to asleep guest display/keyguard state, restored display with power wake, and removed automatic PIN-entry behavior.','ev_lock_screen_power_state');

-- ---------------------------------------------------------------------------
-- Run-trend use, logger hardening, and next presentation experiment
-- ---------------------------------------------------------------------------
INSERT OR REPLACE INTO map_meta(key,value) VALUES
('current_logger_reliability','Raw telemetry is now the authority. Stop seals the raw capture and manifest before SQLite normalization. Normalization failure is written as normalization-error.json and cannot block emulator cleanup, AVD restore, control-state release, or preservation of the long gameplay capture.'),
('current_continuous_run_validity','Continuous official-TFT runs are COMPLETE when process/memory/clock telemetry and Google Play package authority are present. Match-entry and gfxinfo native-frame visibility are no longer prerequisites for a valid run; frame timing remains an independent metric.'),
('current_surfaceflinger_stream','New logger sessions sample SurfaceFlinger total/GPU/HWC missed-frame counters every 10 seconds for correlation against CPU, memory, settings and application events.'),
('latest_5gb_trend','Latest closed 5 GiB run split into 10-minute windows: heavy-gameplay CPU ~245-277%, emulator RSS ~6.1-6.5 GiB, host available ~5.1-5.5 GiB, guest available ~1.64-1.75 GiB. Across the full ~106-minute run compressed memory rose ~2.72 GiB and host available fell ~2.62 GiB. Pressure accumulates over time, but disconnect did not coincide with guest-memory collapse.'),
('latest_5gb_vs_6gb','Directional whole-run comparison: pageout rate 6 GiB ~207.18/min vs 5 GiB ~133.54/min (-35.55%); compressed mean ~0.45 GiB lower and compressed p95 ~1.65 GiB lower on 5 GiB. Workload mixes differ, so 5 GiB is retained but not promoted as a final causal fact.'),
('current_ram_decision','KEEP 5 GiB for continued development; DO NOT cut to 4 GiB now. Heavy-gameplay guest available memory already reaches ~1.64 GiB, so another 1 GiB cut has insufficient safety margin without stronger evidence.'),
('current_presentation_candidate','Stage one-factor gfxstream/ASG candidate tftmac_5gb_flush400_exp_v1: drawFlushInterval 800 -> 400 only. Motivation: broad prior run added +524 HWC misses with +0 GPU misses, and AOSP defines this parameter as balancing host-GPU starvation against notification overhead. Do not combine with RAM, graphics preset, FPS, Performance Mode or other transport changes.'),
('current_preplay_pressure_thresholds','Between-game TFT app refresh threshold tightened to host compressed >=3.75 GiB or host available <=4.75 GiB based on the 5 GiB end-of-run trend; refresh preserves emulator and logger.');

INSERT OR REPLACE INTO evidence(id,observed_at,kind,source_path,source_sha256,statement,confidence,notes) VALUES
('ev_5gb_run_trend','2026-08-28T23:43:51.134Z','continuous_run_trend','~/Library/Application Support/TFTMAC/Captures/2026-08-28T21-40-53-459Z-d6d2f30b-ead9-47b8-8a81-16cc2551bd0e/run-trend-analysis.json',NULL,'Ten-minute trend analysis shows progressive host compression/availability degradation across the 5 GiB run while heavy gameplay retains roughly 1.64-1.75 GiB guest available memory.','DIRECT','Supports between-game process refresh and retaining 5 GiB; does not support a 4 GiB cut.'),
('ev_5gb_6gb_normalized','2026-08-28T23:45:40.943Z','normalized_run_comparison','runtime continuous-run analyses',NULL,'Normalized pageout rate was ~207.18/min on the long 6 GiB run and ~133.54/min on the 5 GiB run, a directional ~35.55% reduction; 5 GiB also reduced compressed-memory mean/p95.','STRONG','Runs differ in duration and workload mix; use directionally, not as a final controlled causal promotion.'),
('ev_logger_raw_seal','2026-08-28T23:47:00Z','logger_design','tools/tftmac-direct-control.mjs',NULL,'Raw capture sealing and cleanup are independent from SQLite normalization; post-processing errors are non-fatal to capture preservation.','DIRECT','Prevents long gameplay sessions from being endangered by DB schema/migration failures.');

INSERT INTO update_log(observed_at,subject,change_summary,evidence_id) VALUES
('2026-08-28T23:43:51.134Z','5 GiB trend analysis','Used the full prior run to identify progressive host pressure, stable heavy-game guest headroom, and no memory-collapse signature at the disconnect.','ev_5gb_run_trend'),
('2026-08-28T23:45:40.943Z','Normalized RAM comparison','Converted raw pageout totals to per-minute rates and retained 5 GiB while rejecting a 4 GiB cut for now.','ev_5gb_6gb_normalized'),
('2026-08-28T23:47:00Z','Logger reliability hardening','Decoupled raw capture sealing and cleanup from SQLite normalization so post-processing cannot strand or invalidate a long run.','ev_logger_raw_seal');

INSERT OR REPLACE INTO map_meta(key,value) VALUES
('latest_closed_run_session','2026-08-28T23-31-16-637Z-df54ebaa-561a-4567-ab20-d94baf0a3619; 3860.24s; tftmac_5gb_baseline_v1; raw capture SEALED; SQLite COMPLETE; 18/18 required artifacts present; manifest f17014ce217742682898a4562aa873a58d8d3fed09b765603c6d4052ea49aa6b.'),
('latest_closed_run_memory','Second sustained 5 GiB run reproduced the operating envelope. Full run weighted means: host available 5.425 GiB, host compressed 2.793 GiB, guest available 2.224 GiB, emulator RSS 5829 MiB. Heavy 10-minute windows reached CPU 229-288%, guest available about 1.70-1.90 GiB, host available about 5.01-5.26 GiB, compressed about 2.97-3.40 GiB. Keep 5120 MB; do not reduce to 4096 MB.'),
('latest_closed_run_pageouts','Current 5 GiB run: 10711 pageouts over 3860.24s = 166.48/min including cold boot. Excluding the first 10-minute cold-boot/startup window, sustained rate is about 127.94/min, close to the prior 5 GiB run about 133.54/min. Old 6 GiB baseline was about 207.18/min. Directional evidence continues to favor 5 GiB.'),
('latest_closed_run_audio','Explicit CoreAudio held through the full run: TFT OpenSL ES 44.1 kHz stereo playback active, ranchu pcm_write I/O failures=0, mixer underruns partial=0 empty=0.'),
('latest_closed_run_network','TFT stayed PID 5276 and Android network 101 remained assigned. End-of-game TFT connectivity callback requests at about 19:30 were immediately assigned to network 101; no Android LOST/UNAVAIL sequence or process restart was observed.'),
('latest_closed_run_presentation','Post-run SurfaceFlinger state: 60 Hz, 1280x720 TFT SurfaceView scaled 1.5x to 1920x1080, total missed=562 and HWC missed=562. The old parser converted an actual zero counter to NULL; parser has been corrected to preserve zero. Current evidence continues to prioritize presentation/HWC pacing over host GPU saturation.'),
('current_graphics_next_action','Proceed with one-factor tftmac_5gb_flush400_exp_v1 experiment: ASG drawFlushInterval 800 -> 400 only, after validating the corrected zero-counter parser and sealed-run comparison. Keep RAM=5120, Medium/60/Performance OFF, CoreAudio, ANGLE/Vulkan/gfxstream/MoltenVK, resolution and all other transport fields fixed.');

COMMIT;

-- Recommended queries during every future work session:
--
--   SELECT * FROM v_open_questions;
--   SELECT * FROM v_failed_or_workaround_dependencies;
--   SELECT * FROM v_architecture_options;
--   SELECT * FROM v_proven_chain;
--   SELECT * FROM experiments ORDER BY observed_at DESC;
--
-- Before an architecture-changing action:
--   1. Insert/update the new evidence.
--   2. Update the experiment or dependency edge it affects.
--   3. Resolve or create the corresponding unknown.
--   4. Re-query v_architecture_options and v_open_questions.
--   5. Only then choose the next mutation.

-- ---------------------------------------------------------------------------
-- 2026-08-30 native full-screen runtime authority
-- ---------------------------------------------------------------------------
UPDATE runtime_variants
SET current_relevance='Historical first-win control receipt; superseded as current launcher identity by rv_current_native_5gb.'
WHERE id='rv_current_first_win';

INSERT OR REPLACE INTO runtime_variants(id,entrypoint,classification,runtime_family,graphics_path,display_profile,resource_profile,exact_result,promotion_state,source_document_id,current_relevance,notes) VALUES
('rv_current_native_5gb','TFTMAC.app','RECOMMENDED','Released Emulator37.1.11 / Android16 API36 Play through packaged macOS app host','TFT Unreal -> ANGLE -> Vulkan/ranchu -> virtio-gpu-asg/gfxstream -> host Vulkan -> MoltenVK -> Metal -> raw gRPC RGBA -> AppKit Metal','1920x1080 / 320 DPI / 60Hz target / native full screen','6 vCPU / 5120 MB','Authenticated controller, ADB5038/emulator-5582 device, official TFT18.1 SplashActivity -> Unreal GameActivity, correctly oriented native frames and input all passed in one live session.','PROMOTED',NULL,'Current native product/runtime authority','Source/presentation FPS are transport metrics, not Unreal FPS. CoreAudio software path passed; user audible confirmation and a full native match remain acceptance gaps.');

INSERT OR REPLACE INTO evidence(id,observed_at,kind,source_path,source_sha256,statement,confidence,notes) VALUES
('ev_native_fullscreen_20260830','2026-08-30T08:41:35Z','native_runtime_acceptance','~/Library/Application Support/TFTMAC/Captures/2026-08-30T08-40-36.792Z-5637b7cf-0c8b-435e-adbb-8f4c0e18de94/TFTMAC_NATIVE_RUNTIME.sqlite',NULL,'Native AppKit TFTMAC authenticated Emulator37.1.11, reached ADB5038/emulator-5582 device, rendered exact 1920x1080 raw RGBA through Metal, accepted mouse input, and launched official TFT18.1 into com.epicgames.unreal.GameActivity.','DIRECT','Live lobby acceptance. Does not claim a completed native match, user-audible sound, or causal graphics-boundary attribution.');

INSERT OR REPLACE INTO map_meta(key,value) VALUES
('current_native_runtime','TFTMAC.app; packaged TFTMAC Emulator Host.app via /usr/bin/open -n -W; ADB5038; emulator-5582; no injected ADB_VENDOR_KEYS; 6 vCPU; 5120 MiB; 1920x1080/320dpi/60Hz; CoreAudio; authenticated gRPC raw RGBA -> AppKit Metal full screen.'),
('current_native_telemetry','Private local SQL plus JSONL/raw sidecars: configuration receipts, events, one-second native-frame interval windows, output presentation, qemu CPU/RSS, guest memory, clock sync, SurfaceFlinger deltas, AudioFlinger health, logcat fault counts, game-process sessions, input counts and manual match/combat/stutter/end markers.'),
('current_native_metric_boundary','gRPC source-window and Metal output rates are transport/presentation observations, not Unreal engine FPS. Use bounded SurfaceFlinger/Perfetto evidence for guest/pipeline attribution.');

INSERT INTO update_log(observed_at,subject,change_summary,evidence_id) VALUES
('2026-08-30T08:41:35Z','Native runtime promotion','Promoted the logged-in-session packaged-host 5038/5582/5120-MiB AppKit/Metal path after live TFT GameActivity acceptance; preserved 5040/5592/6144 evidence as historical only.','ev_native_fullscreen_20260830');

-- ---------------------------------------------------------------------------
-- 2026-08-31 Build 8 current graphics-run authority
-- Historical rows remain evidence of their own timestamps and are not deleted.
-- ---------------------------------------------------------------------------
INSERT OR REPLACE INTO evidence(id,observed_at,kind,source_path,source_sha256,statement,confidence,notes) VALUES
('ev_build8_current_capture_20260831','2026-08-31T23:13:30Z','private_capture_metadata','PRIVATE_LOCAL_ONLY/TFTMAC_NATIVE_RUNTIME.sqlite','c1ef9c9ffe591a297cb86660e3ccfea7e9aeb593f22100e4e732b2fc77d4ee77','Build 8 capture 2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200 is a complete 42m27s automatic TFT PID/layer-lifetime run. Its private SQLite database is 63897600 bytes; it contains 144364 exact-layer intervals, 99.629% exact-layer coverage, weighted FPS 56.98, 1% low 21.49 FPS, p95 21.51 ms, p99 33.434 ms, 6544 jank frames, 144 severe stalls, 7644 missed-vsync equivalents, and 189 degradation incidents.','DIRECT','Raw database excluded from Git; hash and byte count are retained for integrity.'),
('ev_build8_current_stack_20260831','2026-08-31T23:13:30Z','runtime_stack_receipt','PRIVATE_LOCAL_ONLY/TFTMAC_NATIVE_RUNTIME.sqlite','c1ef9c9ffe591a297cb86660e3ccfea7e9aeb593f22100e4e732b2fc77d4ee77','The active TFT path is direct Unreal Vulkan -> gfxstream/ASG -> host Vulkan -> MoltenVK -> Metal. ANGLE is conditional and is not assumed to be the TFT main rendering path. Final Mac presentation is excluded from causal candidates.','DIRECT','Receipt is runtime-specific; it does not expose signed Riot Unreal source lines.'),
('ev_build8_current_root_unknown_20260831','2026-08-31T23:13:30Z','causal_limit','PRIVATE_LOCAL_ONLY/TFTMAC_NATIVE_RUNTIME.sqlite','c1ef9c9ffe591a297cb86660e3ccfea7e9aeb593f22100e4e732b2fc77d4ee77','Current automatic logging verifies degradation but cannot name one internal root component: a shared causal work ID and owned-stage timing are absent. Root attribution is UNKNOWN upstream of or at the guest TFT surface.','DIRECT','No ASG, gfxstream, MoltenVK, Metal, ANGLE, or Unreal cause is inferred from the current capture.'),
('ev_current_host_audit_20260831','2026-08-31T23:13:30Z','host_trust_audit','ssot/runtime-authority.json',NULL,'The current-host audit found release identity hashes matching the historical Build 8 receipt with zero identity findings, while the host trust policy reported CSSMERR_TP_NOT_TRUSTED. This audit is timestamped separately and does not invalidate or rewrite historical signing acceptance.','DIRECT','Trust-policy result is not a release-identity mismatch.');

INSERT OR REPLACE INTO runtime_variants(id,entrypoint,classification,runtime_family,graphics_path,display_profile,resource_profile,exact_result,promotion_state,source_document_id,current_relevance,notes) VALUES
('rv_stock_build8_normal_play','TFTMAC.app','RECOMMENDED','Stock released Emulator37.1.11 / Android16 API36 Play through packaged macOS app host','Unreal direct Vulkan -> gfxstream/ASG -> host Vulkan -> MoltenVK -> Metal','1920x1080 / 320 DPI / 60Hz target / native full screen','6 vCPU / 5120 MiB / CoreAudio / host GPU','Build 8 automatic 42m27s graphics run complete with exact-layer coverage and stack receipts.','PROMOTED',NULL,'Current normal-play authority','Active observed combat_latency_a uses High/60/Performance Mode OFF and is not promoted as a performance result. Markers and battle classification are optional annotations.'),
('rv_tftmac_runtime_diagnostic','isolated source-built emulator','DIAGNOSTIC','tftmac-runtime @ c8aa26ebaa5b977965eb165ad8aac5c98408469f','Planned source-instrumented gfxstream/MoltenVK causal trace','Not applicable until isolated diagnostic acceptance','Not comparable to stock Build 8','Eligible only for the planned advanced causal logger.','NOT_PROMOTED',NULL,'Diagnostic eligibility only','Requires separate parity, correctness, clock, stream-seal, and observer-overhead gates. Never replace normal-play stock authority by implication.');

INSERT OR REPLACE INTO unknowns(id,question,owning_layer,blocking,next_probe,status,resolution) VALUES
('unk_current_internal_root_attribution','Which owned component and source site first diverges before the exact TFT SurfaceFlinger actual-present degradation?','cross_stack_causal_logger',1,'Build the planned isolated source causal logger with explicit work IDs across owned boundaries; require complete joins, clock validity, sealed streams, and observer-overhead <=5% before naming a cause.','OPEN',NULL);

INSERT OR REPLACE INTO decisions(id,decided_at,decision,rationale,state,evidence_id,supersedes) VALUES
('dec_stock_build8_normal_play_authority','2026-08-31T23:13:30Z','Retain stock Build 8 as normal-play authority.','It is the verified automatic logging/control runtime. The advanced source-build path is diagnostic-only and non-comparable until a separate parity gate passes.','ACTIVE','ev_build8_current_capture_20260831',NULL),
('dec_mac_presenter_context_only','2026-08-31T23:13:30Z','Exclude final Mac presenter from causal candidates.','The current capture and user-approved fact establish it as context/correctness telemetry, not the graphics optimization target.','ACTIVE','ev_build8_current_stack_20260831',NULL),
('dec_markers_optional_annotations','2026-08-31T23:13:30Z','Treat match and battle markers as optional annotations.','Automatic TFT process/layer lifetime determines raw capture validity; marker absence cannot invalidate causal analysis.','ACTIVE','ev_build8_current_capture_20260831',NULL);

INSERT OR REPLACE INTO map_meta(key,value) VALUES
('current_phase','Advanced causal graphics logging planned; Build 8 automatic full-run baseline verified.'),
('current_release_gameplay_benchmark','VERIFIED_CAPTURE_ROOT_ATTRIBUTION_UNKNOWN; capture 2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200.'),
('current_runtime_authority','Stock Build 8 packaged macOS-host launcher is normal-play authority. tftmac-runtime@c8aa26e is isolated, diagnostic-only, and non-comparable.'),
('current_observed_configuration','combat_latency_a; High graphics / 60 FPS / Performance Mode OFF; observed active, not performance-promoted.'),
('current_pipeline_receipt','Unreal direct Vulkan -> gfxstream/ASG -> host Vulkan -> MoltenVK -> Metal; ANGLE conditional; final Mac presenter context-only.'),
('current_capture_validity','Automatic PID/layer lifetime logging is verified. Match, battle, combat, and result markers are optional annotations and are not validity or causal gates.'),
('current_root_attribution','UNKNOWN_UPSTREAM_OF_OR_AT_GUEST_SURFACE. Existing telemetry measures degradation but lacks shared owned-stage work IDs for causal naming.'),
('current_advanced_logger_status','PLANNED: isolated source-built runtime instrumentation; do not claim a root component or source line until all causal evidence gates pass.'),
('current_host_audit','Timestamped current-host audit: matching release identity hashes, zero identity findings, CSSMERR_TP_NOT_TRUSTED under current host trust policy; historical release signing acceptance remains distinct.');

INSERT OR REPLACE INTO map_meta(key,value) VALUES
('current_presentation_candidate','RETIRED_AS_CURRENT_ACTION: final Mac presentation is context-only; earlier broad HWC/ASG directional candidates remain historical and cannot name a root cause.'),
('current_graphics_next_action','Plan the isolated source causal logger first. No graphics tuning intervention is current until it identifies an owned first divergent boundary or reports an explicit unowned/missing boundary.');

INSERT INTO update_log(observed_at,subject,change_summary,evidence_id) VALUES
('2026-08-31T23:13:30Z','Build 8 full-run baseline','Recorded the verified automatic 42m27s capture, private integrity metadata, direct Vulkan stack receipt, and explicit UNKNOWN root-attribution boundary.','ev_build8_current_capture_20260831'),
('2026-08-31T23:13:30Z','Causal ownership boundary','Excluded final Mac presentation from causal candidates; made markers/battles optional annotations; retained source-instrumented runtime only as isolated diagnostic eligibility.','ev_build8_current_root_unknown_20260831'),
('2026-08-31T23:13:30Z','Current-host trust audit','Recorded matching release identities and current host CSSMERR_TP_NOT_TRUSTED separately from historical signing acceptance.','ev_current_host_audit_20260831');

-- Reclassify superseded rows without deleting their historical evidence. These
-- exact-key overrides prevent an older INSERT OR REPLACE from acting as current
-- authority when this map is rebuilt from scratch.
UPDATE runtime_variants
SET classification='HISTORICAL',
    promotion_state='RETAINED',
    current_relevance='Historical runtime receipt; superseded by rv_stock_build8_normal_play.',
    notes=COALESCE(notes,'') || ' Reclassified on 2026-08-31; not current renderer or normal-play authority.'
WHERE id IN ('rv_current_first_win','rv_current_native_5gb');

UPDATE stack_profiles
SET status='HISTORICAL',
    next_use='Historical comparison only; Build 8 stock normal-play authority is recorded by rv_stock_build8_normal_play.'
WHERE id='stack_first_win';

UPDATE source_documents
SET path='docs/history/2026-08-31-pre-build8/TFTMAC.md',
    temporal_status='HISTORICAL',
    conflicts_with_current_authority=0,
    notes='Archived pre-Build-8 document. The concise TFTMAC.md replacement points to current authorities.'
WHERE id='doc_tftmac_legacy';

INSERT OR REPLACE INTO source_documents(id,path,sha256,role,authority_rank,temporal_status,scope,last_verified_at,conflicts_with_current_authority,notes) VALUES
('doc_tftmac_build8_current','TFTMAC.md',NULL,'current Build 8 authority pointer',90,'CURRENT','Build 8 normal-play and causal-logging handoff','2026-08-31T23:13:30Z',0,'Defers detailed facts, chronology, engineering status, and formulas to facts.md, project.md, dev.md, and benchmark.md.');

INSERT OR REPLACE INTO map_meta(key,value) VALUES
('current_renderer','Unreal direct Vulkan -> gfxstream/ASG -> host Vulkan -> MoltenVK -> Metal. ANGLE is conditional and is not claimed as the TFT main renderer without a new runtime receipt.'),
('current_logger_guard','Automatic logging follows the TFT process and exact layer from game start until process/app close. Match, combat, battle, quality, and result markers are optional annotations only.'),
('current_multi_match_capture','One uninterrupted automatic capture may contain any number of games. Process/layer lifetime and timestamped samples are authoritative; marker pairing is never required for validity.'),
('current_performance_truth','Build 8 automatic capture verifies sustained frame degradation and exact-layer coverage; the first failing internal component remains UNKNOWN until owned-stage work IDs exist.'),
('current_graphics_pipeline','TFT Unreal direct Vulkan -> gfxstream/ASG -> host Vulkan -> MoltenVK -> Metal. Final Mac presentation is hidden correctness context and excluded from causal ranking.'),
('current_connector_state','The direct-Vulkan stack is receipt-verified. Per-frame ownership below the guest TFT surface remains unmeasured; no internal component is a proven live root cause.'),
('current_native_telemetry','Private local SQL and sealed sidecars are captured automatically across the TFT PID/layer lifetime. Match, combat, battle, stutter, quality, and result markers are optional annotations.'),
('current_native_metric_boundary','Exact TFT SurfaceFlinger actual-present timestamps are FPS authority. Final Mac presentation is hidden correctness context only and cannot be selected as the root cause.'),
('current_game_settings','Observed Build 8 capture: combat_latency_a; High graphics; 60 FPS; Performance Mode OFF. This is an observation, not a promoted tuning result.'),
('current_pipeline_next_probe','Build the isolated source causal logger with owned-stage work IDs, valid clock joins, sealed streams, and <=5% observer-overhead gate before any causal patch.'),
('current_optimization_priority','Use all automatic full-run graphics data. Name or patch a component only after the source causal logger proves the first divergent owned boundary; otherwise report UNKNOWN.');
