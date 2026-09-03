# TFTMAC Clean Ownership, Runtime Convergence, and Storage Reclamation Plan

**Status:** AUTHORITATIVE IMPLEMENTATION PLAN
**Project authority:** `flashls1/TFTMAC`
**Target host:** Apple Silicon Mac mini M4
**Date frozen:** 2026-08-29
**Scope:** source identity, runtime authority, validation/CI, storage reclamation, redundant-project retirement, and safe continuation of the native application build.

**Mandatory execution preflight:** `TFTMAC_CLEAN_OWNERSHIP_PREFLIGHT.md`

> Implementation agents must read the preflight before repository discovery. The preflight contains the exact already-discovered files, symbols, hashes, branch state, storage paths, validation coupling, migration hazards, and KEEP/DELETE/REWRITE/MIGRATE classifications. Do not repeat discovery already recorded there unless its referenced source/hash has changed or the item is explicitly marked REMEASURE.

---

## 0. Executive directive

TFTMAC becomes one independent product and one independent engineering system.

The shipping project must contain only TFTMAC-owned product identity, TFTMAC runtime controls, official Google Android Emulator/Google Play integration, Riot's official TFT package/update path, TFTMAC telemetry, TFTMAC native macOS UI, and the minimum source/evidence required to build and maintain those functions.

The legacy donor product is no longer a runtime dependency, launcher, control application, update authority, branding source, test authority, CI authority, project identity, or installed dependency. Transferable facts that TFTMAC has independently reproduced may remain as TFTMAC facts under TFTMAC naming. Legacy implementation material that is not required by the working architecture is removed.

The abandoned source-built emulator laboratory is also retired from the normal TFTMAC system. The working product uses the released Google Android Emulator and the exact installed EmulatorController protocol. The large development-source tree created by earlier experiments is reclaimed after safety gates prove that nothing in the active product depends on it.

---

# 1. Concrete win condition

The implementation is complete only when all of the following are true:

```text
ONE_ACTIVE_PROJECT = TFTMAC
APP_IDENTITY = TFTMAC
BUNDLE_ID = com.flashls1.tftmac
LEGACY_PRODUCT_UI_REFERENCES = 0
LEGACY_PRODUCT_SOURCE_REFERENCES = 0 in the current tracked tree
LEGACY_LAUNCHERS = 0
LEGACY_UPDATE_FEEDS = 0
LEGACY_RUNTIME_DEPENDENCIES = 0
OFFICIAL_TFT_INSTALLER = com.android.vending
RIOT_PACKAGE_REPACKING = 0
CUSTOM_RIOT_PATCHING = 0
SOURCE_BUILT_AEMU_REQUIRED = NO
WORKING_RUNTIME_ROOT_PRESERVED = YES
WORKING_AVD_PRESERVED = YES
CURRENT_NATIVE_GATE1_WORK_PRESERVED = YES
ABANDONED_BUILD_TREE_RECLAIMED = YES
REDUNDANT_PROJECTS_RETIRED = YES after unique-content gates
NATIVE_TFTMAC_IMPLEMENTATION_CAN_CONTINUE = YES
```

The user must be able to continue building and playing through TFTMAC after cleanup without reinstalling or reconstructing the known-good runtime.

---

# 2. Preflight findings

## 2.1 Current repository authority

Observed current authority:

```text
repository: flashls1/TFTMAC
default branch: master
master SHA: fdfb325100db508f795ed5b83cea48887a88cb71
local/remote: aligned and clean
```

The current native implementation change is:

```text
change: 14d01e7a-b64d-4b7f-b856-e3366885b381
branch: clara/implement-tftmac-native-mac-app-from-tft-14d01e7a
state: active dirty worktree
```

That change contains the new native Xcode/AppKit/Metal work and must be preserved before any destructive cleanup.

Already proven in that change:

- normal `TFTMAC.xcodeproj` exists;
- arm64 Release build passes under Xcode 26.6;
- native unit tests pass;
- Swift 6 concurrency issue found by the compiler was repaired;
- gRPC/SwiftPM dependency graph resolves successfully;
- the installed Android Emulator 37.1.11 controller protocol was frozen directly from the working runtime;
- frozen `emulator_controller.proto` SHA-256 is `1d62c6bcad5f06621f90ec2bf26c661ba769ccd0f1416b5314d25a68e04eee5f`;
- the stock runtime remains the control while the native presentation layer is built.

## 2.2 Legacy identity contamination is broad, not cosmetic

Repository search found hundreds of current-tree references tied to the old donor product. They exist in multiple classes:

```text
README / contribution / support documentation
launcher source and resources
bundle identifiers
application metadata
old icons and social artwork
build scripts
release/update scripts
CI validation
integration tests
runtime-control commands
process detection
profile/config identifiers
performance SQL primary/foreign keys
historical engineering-map rows
old experiment scripts
old updater/feed logic
old keychain/service names
old test names
old package/update terminology
```

Therefore this cannot be implemented as a blind text replacement. Some records are executable behavior, some are SQL identities, some are obsolete code that should be deleted, and some are historical evidence that must be compacted or migrated before removal.

## 2.3 Current validation is still coupled to legacy tests

The registered TFTMAC production validation still executes the old validation script. GitHub CI also invokes that legacy test path.

This must be changed before legacy source is deleted, otherwise a correct cleanup would intentionally break the project's own validation authority.

Final validation authority must be TFTMAC-native and must not depend on a deleted launcher tree.

## 2.4 Abandoned source-build storage is the main reclaim target

The earlier from-source emulator effort created bulk development data under:

```text
/Volumes/MAC MINI M4/TFTMAC/Build
```

Project research recorded the development source/build tree at approximately **131 GB**.

That path includes or historically included:

```text
AEMU multi-repository source checkout
large emulator prebuilts
source-build objects
CMake/Ninja outputs
CTS/reference source trees
host compatibility wrappers
build logs
failed/partial build state
source synchronization metadata
```

The source build reached a real 9,854-step compile and later failed during that obsolete path. Those compiled/source artifacts are no longer required by the working architecture.

The released stock emulator path is already proven and the native project now freezes its protocol from the installed runtime itself. Therefore the large source checkout has no normal product role.

## 2.5 Exact live free-space measurement is a cleanup-time gate

The current Clara registry advertises an external-volume disk probe, but the live allowlist rejected that probe during this preflight. The plan therefore does **not** invent a current free-space number.

Before deletion, implementation must perform one read-only byte inventory through an approved host path and record:

```text
filesystem free bytes before cleanup
size of each candidate directory
protected runtime size
capture size
native DerivedData/build-cache size
redundant project roots/worktrees size
filesystem free bytes after cleanup
exact reclaimed bytes
```

No cleanup acceptance may use an estimated reclaimed figure when an exact post-delete measurement is available.

## 2.6 Redundant Clara project identities

Three TFT-related project identities currently exist:

```text
TFTMAC            -> authoritative project
TFTMAC Runtime    -> older source/runtime project
TFTMAC2           -> essentially empty shell project
```

`TFTMAC2` currently has no active changes, no operations, and only minimal foundation files.

`TFTMAC Runtime` cannot be deleted immediately because it still contains one published but unmerged compatibility-laboratory change:

```text
change: 7c24d6df-bb78-4a4d-9c8f-1b4028871f60
head: 994cf8d8524b87cc03c7decb4b253fc7be2253c7
```

That change must receive a unique-content review before retirement. Any still-useful fact must be reproduced/migrated into TFTMAC or explicitly classified as superseded before the old project is retired.

## 2.7 Licensing boundary

The current repository contains MIT-licensed material with an upstream copyright notice.

Product independence does not authorize false authorship or removal of legally required notices from substantial retained code.

Required rule:

1. Audit which current files, if any, remain copied or substantially derived from the legacy open-source code.
2. Prefer deleting obsolete copied implementation rather than carrying it forward.
3. If substantial licensed portions remain, retain the required copyright and MIT permission notice in a neutral third-party notice location.
4. The old product name is not required by the MIT text and does not need to remain in the product identity.
5. If no substantial licensed portion remains after replacement/removal, update the project's primary licensing/notice structure to accurately describe the resulting TFTMAC codebase.

---

# 3. Non-negotiable implementation rules

1. **TFTMAC is the sole product identity.**
2. **No old launcher ships, starts, or remains callable from TFTMAC.**
3. **No old logo, icon, wordmark, favicon, social artwork, hero image, or fallback icon remains.**
4. **No old hosted game feed or updater remains.**
5. **No third-party Riot APK mirroring, repacking, re-signing, or patching.**
6. **Google Play is package installation/update authority.**
7. **Riot's own application performs its own patch/content initialization.**
8. **The working stock Android Emulator remains runtime authority.**
9. **No source-built AEMU checkout is needed for normal build, launch, test, repair, or release.**
10. **Do not delete the working SDK, AVD, Google account state, TFT install, or active native work during storage cleanup.**
11. **Do not delete a redundant project until unique-source and active-change checks pass.**
12. **Do not rewrite Git history as part of this cleanup.** Current tracked source, artifacts, metadata, and shipping outputs must be clean; destructive historical-object rewriting is not needed for product independence.
13. **Delete recreation paths before deleting large storage.** Old commands must not be able to silently regenerate the 100+ GB source tree.
14. **Every destructive delete requires an exact candidate path and pre-delete classification.** No broad `/Volumes/.../TFTMAC` recursive deletion.
15. **Raw evidence is retained only when it still protects a current decision.** Superseded duplicate experiments are not permanent product assets.

---

# 4. Final TFTMAC architecture after convergence

```text
TFTMAC.app
  -> native AppKit window
  -> Metal presentation
  -> TFTMAC runtime controller
  -> authenticated local EmulatorController
  -> stock Google Android Emulator
  -> official Google Play ARM64 guest
  -> official Google Play TFT package
  -> Riot official authentication/content lifecycle
  -> CoreAudio
  -> TFTMAC raw-first telemetry
```

Development source:

```text
flashls1/TFTMAC
  TFTMAC.xcodeproj
  TFTMAC/
  Vendor/AndroidEmulator/
  Generated/EmulatorController/
  Probes/
  Tests/
  scripts/
  ssot/
```

Normal product development does **not** require:

```text
source-built emulator checkout
legacy launcher tree
legacy application installation
legacy update server/feed
legacy branding tree
legacy release builder
legacy hosted Riot package flow
large CTS/source research checkout
```

---

# 5. Preservation matrix

## 5.1 Protected — never delete during initial cleanup

```text
/Volumes/MAC MINI M4/TFTMAC/Runtime/SDK
/Volumes/MAC MINI M4/TFTMAC/Runtime/AVD
current official Google Play system image
current TFT_Ultra_Tablet userdata
Google Play account/session state inside the AVD
current official TFT package and Riot data inside the AVD
current runtime manifests required by active stock-runtime control
~/Library/Application Support/TFTMAC/Profiles
~/Library/Application Support/TFTMAC/State
current package-authority evidence
current native implementation worktree 14d01e7a...
TFTMAC.xcodeproj source
Vendor/AndroidEmulator frozen protocol
Package.resolved
current source repository and .git
```

## 5.2 Preserve compact evidence, then allow raw-data pruning

Keep a compact canonical record for:

```text
latest known-good playable baseline
latest 5 GB baseline decision
current Medium / 60 / Performance OFF decision
Ultra High rejection
current package identity / installer / signer evidence
current stock-emulator version
current frozen EmulatorController proto hash
current CoreAudio decision
current raw-seal contract
one representative valid performance capture
one representative native trace if still used by an active decision
```

Older duplicate raw captures, abandoned traces, repeated screenshots, rejected experiment runs, and duplicate derived SQL can be deleted only after their decision/result is represented in current TFTMAC SSOT with source hashes where useful.

## 5.3 Disposable after verification

Primary reclaim candidates:

```text
/Volumes/MAC MINI M4/TFTMAC/Build
  including AEMU source checkout
  objects / Ninja / CMake outputs
  large prebuilts downloaded only for source compilation
  CTS/reference source trees used only by abandoned source-build work
  phase-build logs
  compatibility wrappers used only by source compilation

obsolete native DerivedData/build caches
completed obsolete Clara worktrees whose commits already exist on master
old donor checkout directories if present
old installed donor application if present
old donor Application Support/runtime data if present
old external donor runtime directories if present
obsolete launcher dist/DMG/update output
superseded test campaigns and rejected experimental runtime copies
```

The entire `Build` root may be removed only after the recreation-path scan in Gate 3 proves the current native/runtime system no longer references it for required operations.

---

# 6. Source ownership cleanup

## 6.1 Delete obsolete product layers instead of renaming them

Remove the old launcher implementation where TFTMAC no longer uses it:

```text
legacy launcher app source
legacy launcher resources
legacy release manifest for that launcher
legacy updater/feed code
legacy Sparkle integration if TFTMAC does not use it
legacy release builder
legacy update publisher
legacy game-package publisher
legacy launcher integration tests
legacy localization files tied only to the removed launcher
legacy game-host helper app if native TFTMAC no longer requires it
legacy branding source and generated output
```

Do not preserve dead code merely to keep old tests green.

## 6.2 Replace current repository docs with TFTMAC docs

Rewrite or replace:

```text
README.md
CONTRIBUTING.md
SUPPORT.md
SECURITY.md
NOTICE/third-party notices
docs/architecture.md
docs/building.md
docs/releasing.md
docs/reproducibility.md
docs/telemetry.md
docs/troubleshooting.md
GitHub repository metadata
pull-request template
```

These documents describe TFTMAC only.

Historical lessons that still matter are rewritten as independently verified TFTMAC facts. The old product is not treated as continuing architectural authority.

## 6.3 Remove old process/runtime controls

Delete controls whose only purpose is to start, stop, inspect, or compare the old application.

From TFTMAC runtime tooling remove:

```text
legacy-app process classification
legacy-app launch command
legacy-app stop command
legacy-app runtime audit
legacy ADB-port cleanup paths that exist only for that app
legacy Application Support path discovery
legacy installed-app lookup
legacy icon fallback
legacy named compatibility-source labels
```

No command advertised by `tftmac-direct-control.mjs` or other TFTMAC tooling may start the retired application.

## 6.4 Rename TFTMAC runtime identities semantically

Do not carry old names inside data models.

Use TFTMAC-owned identifiers, for example:

```text
tftmac_official_baseline_v1
tftmac_5gb_baseline_v1
tftmac_5gb_flush400_exp_v1
```

Rename code concepts such as:

```text
DONOR_PROFILE -> BASELINE_PROFILE
startDonorControl -> startBaselineControl
prepareDonorAVD -> prepareBaselineAVD
restoreDonorAVD -> restoreBaselineAVD
```

Exact final names should remain short and descriptive.

## 6.5 SQL migration, not destructive string replacement

Performance-lab and engineering-map identifiers are relational keys.

Implement an idempotent migration that:

1. inserts new TFTMAC-owned config IDs;
2. remaps foreign keys in experiments/sessions/evidence;
3. preserves measured values and timestamps;
4. removes superseded old IDs after referential-integrity checks pass;
5. updates lab metadata/current-baseline keys;
6. runs `PRAGMA foreign_key_check`;
7. proves no old identifier remains in active schema/seed data.

Do not destroy useful measurements just to rename their primary key.

## 6.6 Repository-wide forbidden-reference gate

The forbidden legacy product token must be supplied transiently to the validation command and must **not** be committed into the repository solely for the purpose of testing itself.

Validation scans:

```text
tracked file paths
tracked text content
bundle metadata
compiled app strings where practical
CI files
scripts
source code
SQL seed data
assets/resources
project metadata
```

Acceptance: zero current-tree/product matches.

---

# 7. Official update and package authority

TFTMAC's package lifecycle is intentionally simple:

```text
Google Play system image
  -> Google account through official Android UI
  -> Play Store listing for com.riotgames.league.teamfighttactics
  -> Install / Update through com.android.vending
  -> launch official Riot activity
  -> Riot performs its own patch/content initialization
```

Required verification per installed/update state:

```text
package = com.riotgames.league.teamfighttactics
installer = com.android.vending
versionName observed
versionCode observed
signer digest observed
base/split paths observed
launch activity observed
```

Never reintroduce:

```text
hosted APK feed
private updater
bundled game APK
manual Riot patch bundle
re-signing
binary patching
screen-coordinate package install automation
```

If Play requires user authentication, consent, MFA, or CAPTCHA, TFTMAC surfaces the official Play UI and pauses only for that human action.

---

# 8. Validation and CI cutover

## 8.1 Replace legacy validation authority first

Before removing old test source, create TFTMAC-native validation:

```text
scripts/verify-tftmac.command
```

It should run only relevant checks:

```text
repository forbidden-reference scan
TFTMAC Xcode project parse/build
native unit tests
frozen proto SHA verification
Package.resolved presence/pin verification
TFTMAC bundle identity verification
no legacy launcher/update/feed paths
performance-lab schema self-test
engineering-map/SSOT integrity checks still relevant to current architecture
shell/script syntax for retained scripts
```

Do not make normal CI boot Android or require a live game.

## 8.2 GitHub CI

Change CI from legacy launcher validation to:

```text
verify repository ownership
build native TFTMAC
run native unit tests
verify generated/frozen protocol authority
run current SQL/SSOT static checks
reject dirty/generated drift
```

## 8.3 Clara validation

Update the TFTMAC Clara project validation command only after the new verifier passes locally on the exact change.

The production validator must no longer reference a deleted legacy test script.

---

# 9. Safe storage reclamation procedure

Storage cleanup is a controlled effect with evidence before and after.

## 9.1 Freeze active work first

Before any delete:

1. review native change `14d01e7a...`;
2. checkpoint all current native Gate 1 source;
3. ensure `Package.resolved`, frozen proto, Xcode project, tests, and scripts are included;
4. capture current worktree SHA/status;
5. prove the working Runtime root is outside every planned deletion target.

No cleanup starts while unique native source exists only as uncheckpointed local files.

## 9.2 Process quiescence gate

Before deleting build/runtime-adjacent directories:

```text
no source-build worker alive
no repo sync alive
no CMake/Ninja source build alive
no process has an open file under the candidate build tree
no TFTMAC game/emulator process requires the candidate path
```

The working stock emulator may remain installed; cleanup should preferably occur with TFTMAC stopped to reduce ambiguity.

## 9.3 Exact size inventory

Create a machine-readable record such as:

```text
ssot/storage-reclamation-preflight.json
```

For every candidate record:

```text
path
realpath
bytes
classification = PROTECTED | KEEP_EVIDENCE | DISPOSABLE | REVIEW
reason
referenced_by_current_source = true/false
active_process_reference = true/false
planned_action
```

The deletion engine accepts only exact paths classified `DISPOSABLE`.

## 9.4 Remove source-build recreation paths

Before deleting `/Volumes/MAC MINI M4/TFTMAC/Build`:

- remove normal commands that initialize/sync/build AEMU from source;
- remove current product docs instructing source builds;
- remove CI/validation dependence on source-build artifacts;
- remove active SSOT statements that declare the Build tree mandatory;
- retain only compact historical outcome facts if still useful;
- verify current native build and stock-runtime controls do not reference the Build root.

Only then remove the abandoned Build tree.

## 9.5 Tiered deletion order

Recommended order:

```text
Tier 1: obsolete local build caches / DerivedData
Tier 2: closed obsolete TFTMAC worktrees already merged or superseded
Tier 3: old launcher dist/update/build artifacts
Tier 4: abandoned source-build / AEMU / CTS development tree (~131 GB historical footprint)
Tier 5: obsolete donor application/runtime/data installations
Tier 6: superseded raw captures/traces after compact evidence retention
Tier 7: redundant project local roots after retirement gates
```

After each tier, re-measure free space and verify the working stock runtime still resolves.

## 9.6 Runtime smoke after large deletion

Immediately after the abandoned Build tree is removed:

```text
external Runtime root exists
SDK emulator executable exists
ADB exists
TFT_Ultra_Tablet AVD exists
Google Play image exists
frozen proto still matches installed controller proto
native TFTMAC Release build still passes
runtime inventory succeeds
```

Do not wait until the very end to discover that a supposedly disposable path was still referenced.

---

# 10. Capture and diagnostics retention policy

The logger remains valuable, but unlimited raw research growth is not.

Adopt a bounded retention policy:

```text
KEEP:
  latest successful playable baseline raw capture
  latest native-app acceptance capture
  current package-authority evidence
  current promoted A/B evidence
  current crash/failure capture for an unresolved blocker

COMPACT THEN DELETE RAW:
  superseded baseline runs
  rejected experiments already summarized
  duplicate screenshots
  repeated diagnostic dumps
  old traces not tied to an open hypothesis
  abandoned setup/install captures
```

Compact record retains:

```text
session id
dates
runtime config hash
result/verdict
key metrics
manifest/hash references when useful
reason raw data was removed
```

No automated age-based deletion is required in the first cleanup. Use decision relevance, not arbitrary days.

---

# 11. Redundant-project retirement

## 11.1 TFTMAC2

Preflight indicates this project is effectively an empty shell:

```text
no active changes
no operations
no release
minimal foundation files only
```

Retirement procedure:

1. one final unique-file/commit comparison;
2. confirm nothing needs migration;
3. close/remove local worktrees/root;
4. archive remote repository rather than leaving it as an active engineering target;
5. remove or mark retired in Clara so it is no longer selectable as an active TFT project.

## 11.2 TFTMAC Runtime

This project requires a stronger gate because it has an unmerged published change.

Procedure:

1. inspect published head `994cf8d8524b87cc03c7decb4b253fc7be2253c7`;
2. compare its unique files/findings with current TFTMAC master + native implementation branch;
3. for each unique item classify:
   - `MIGRATE_TO_TFTMAC`,
   - `ALREADY_SUPERSEDED`, or
   - `REJECTED/OBSOLETE`;
4. migrate only genuinely useful current facts/code;
5. validate migrated TFTMAC source independently;
6. close the old change;
7. archive the remote project;
8. delete local project/worktree/runtime-local build artifacts;
9. remove or mark retired in Clara.

Final Clara project catalog should present **TFTMAC as the only active TFT engineering authority**.

---

# 12. Implementation sequence and gates

## Gate 0 — preserve current native work

Deliverables:

```text
checkpoint active native Gate 1 work
record exact head and diff
freeze Package.resolved
freeze installed controller proto provenance
```

Exit: no unique active work can be lost by cleanup.

## Gate 1 — ownership inventory

Deliverables:

```text
current-tree legacy-reference inventory
legacy path inventory
legal/code-origin inventory
runtime dependency map
SQL identity migration map
```

Exit: every current reference has one action: DELETE, REWRITE, MIGRATE, or LEGAL_NOTICE.

## Gate 2 — new TFTMAC validation authority

Implement `verify-tftmac.command`, update native tests, and prove it passes before removing old tests.

Exit: TFTMAC can validate itself without the legacy launcher.

## Gate 3 — source/product separation

Delete obsolete launcher/updater/feed/branding code, rename runtime/profile identifiers, migrate SQL, rewrite docs/metadata, remove executable legacy controls.

Exit:

```text
forbidden-reference scan = 0
native Release build = PASS
native tests = PASS
SQL integrity = PASS
```

## Gate 4 — stock-runtime independence proof

Using the current working runtime:

```text
inventory runtime
verify SDK/AVD
verify Google Play package authority
verify installed controller proto
launch/stop control path if safe
```

Exit: no runtime operation requires the abandoned Build tree or retired application.

## Gate 5 — storage preflight and source-build retirement

Produce exact storage inventory and remove all source-build recreation paths.

Exit: `/Volumes/MAC MINI M4/TFTMAC/Build` is classified disposable in full or has explicitly listed small exceptions.

## Gate 6 — reclaim bulk storage

Delete approved candidates by tier and record exact reclaimed bytes.

Exit:

```text
large abandoned source/build tree removed
stock Runtime intact
native source intact
post-delete runtime smoke PASS
```

## Gate 7 — compact/prune superseded telemetry

Retain active evidence, compact obsolete decision evidence, remove no-longer-useful raw bulk.

Exit: captures have a bounded, explainable product role.

## Gate 8 — retire redundant projects

Retire empty project first. Retire old runtime project only after unique-content migration gate.

Exit: TFTMAC is the sole active TFT project in Clara.

## Gate 9 — resume native implementation

Rebase/continue the native implementation on the clean ownership baseline.

Next product gate remains:

```text
hidden stock emulator
authenticated EmulatorController
getStatus
correct PID/AVD proof
clean shutdown
```

The cleanup does not replace or postpone the native-app roadmap; it makes that roadmap operate on the correct clean foundation.

---

# 13. Failure handling and rollback

## Source cleanup failure

If native build/test fails after deleting legacy source:

- restore only the exact deleted source files from Git;
- do not restore old installed applications or large external build trees automatically;
- identify the actual dependency and either migrate it into TFTMAC or remove the dependency.

## SQL migration failure

If foreign-key or semantic checks fail:

- rollback transaction;
- keep the old database untouched;
- repair the migration map;
- never hand-edit primary/foreign IDs in a partially migrated live DB.

## Storage cleanup failure

If a candidate cannot be proven disposable:

```text
classification -> REVIEW
no delete
continue with other proven-disposable candidates
```

If the stock runtime fails after a deletion tier:

- stop further deletion;
- restore only the minimum missing configuration/artifact if it was actually removed;
- never regenerate the full source-build tree unless a current measured blocker specifically requires a new source-build project.

## Redundant-project retirement failure

If unique source is found:

- migrate/reproduce it into TFTMAC first;
- do not delete that old project until the migration commit is validated and durable.

---

# 14. Acceptance tests

Ownership:

```text
[ ] app name is TFTMAC
[ ] bundle id is com.flashls1.tftmac
[ ] only TFTMAC branding/assets exist
[ ] current-tree forbidden legacy product scan has zero matches
[ ] no legacy launcher executable or command exists
[ ] no legacy updater/feed exists
[ ] no legacy hosted game package path exists
[ ] CI does not reference legacy tests
[ ] Clara TFTMAC validation does not reference legacy tests
```

Official package/runtime:

```text
[ ] stock Google Android Emulator is runtime authority
[ ] current SDK/AVD remain on external Runtime root
[ ] EmulatorController proto authority remains installed Emulator 37.1.11
[ ] official TFT package is com.riotgames.league.teamfighttactics
[ ] installer is com.android.vending
[ ] version/signing evidence captured
[ ] Google Play handles app update
[ ] Riot handles Riot content initialization
[ ] no custom Riot binary patch/repack/resign path exists
```

Storage:

```text
[ ] exact pre-clean storage inventory captured
[ ] active processes checked before deletion
[ ] active native work checkpointed
[ ] abandoned source-build recreation paths removed
[ ] abandoned source/build tree removed
[ ] exact reclaimed bytes captured
[ ] protected Runtime root unchanged
[ ] protected AVD unchanged
[ ] native Release build passes after cleanup
[ ] runtime inventory passes after cleanup
```

Project convergence:

```text
[ ] TFTMAC2 unique-content check complete and project retired
[ ] TFTMAC Runtime unique published change reviewed
[ ] useful unique items migrated or proven superseded
[ ] old project retired only after migration gate
[ ] TFTMAC is sole active TFT project authority
```

---

# 15. Required durable cleanup evidence

Implementation should leave small evidence artifacts:

```text
ssot/storage-reclamation-preflight.json
ssot/storage-reclamation-result.json
ssot/ownership-migration.json
ssot/runtime-authority.json
ssot/project-retirement.json
ssot/retained-evidence-index.json
```

`storage-reclamation-result.json` records:

```text
startedAt
completedAt
filesystemFreeBytesBefore
filesystemFreeBytesAfter
reclaimedBytes
removedPaths[]
protectedPathsVerified[]
postCleanupNativeBuild
postCleanupRuntimeInventory
```

Do not keep giant cleanup logs when a compact hash-addressed result is enough.

---

# 16. Zen Gate evaluation

Evaluated using the exact retrieved Zen Gate v2.2 scoring engine.

## Hard gates

```text
H1 Win Condition: PASS
H2 Source of Truth: PASS
H3 Material Ambiguity: PASS
H4 Safety/Reversibility: PASS
H5 Validation Integrity: PASS
Project-specific absolute constraints: PASS
H = 1
```

Material ambiguity is resolved by fail-closed execution gates: exact storage bytes are measured before deletion; redundant projects receive unique-content checks; legal attribution is determined by retained-code audit; no uncertain path is deleted.

## Weighted quality score

| Dimension | Weight | Score / 5 | Contribution |
|---|---:|---:|---:|
| Win Condition Alignment | 15 | 5.0 | 15.0 |
| Source-of-Truth Integrity | 12 | 5.0 | 12.0 |
| Ambiguity Resolution | 13 | 5.0 | 13.0 |
| Simplicity / Minimality | 16 | 4.5 | 14.4 |
| Complexity Justification | 10 | 5.0 | 10.0 |
| Architecture / Boundaries | 9 | 5.0 | 9.0 |
| Failure Handling / Observability | 12 | 5.0 | 12.0 |
| Maintainability / Readability | 6 | 4.5 | 5.4 |
| Practical Shipping Slice | 4 | 5.0 | 4.0 |
| Explainability | 3 | 5.0 | 3.0 |

```text
Q = 97.8
```

Risk penalties:

```text
O overengineering = 1
A unresolved ambiguity = 0
F failure exposure = 2
I irreversibility = 2
R = 5
```

Final:

```text
Z = H × max(0, Q - R)
Z = 1 × (97.8 - 5)
Z = 92.8
PASS threshold = 85
ZEN GATE RESULT = PASS
Remediation mode = NONE
```

Why the remaining penalty exists: bulk storage deletion and project retirement are intentionally irreversible effects. The plan contains explicit preservation, exact-path classification, unique-content, quiescence, checkpoint, and post-delete smoke gates to contain that risk.

---

# 17. Definition of done

This convergence is done when TFTMAC has one clean identity, one native build system, one stock official runtime, one official Google Play/Riot package path, one current validation system, one bounded evidence system, and one active Clara project.

The external drive contains the **working runtime and useful TFTMAC evidence**, not a 100+ GB abandoned source-build laboratory.

After this plan is completed, engineering proceeds directly into the native application's hidden-emulator/EmulatorController gate without bringing any retired launcher, branding, updater, project, or source-build dependency back into the system.
