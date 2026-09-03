# TFTMAC Project Record

**Project:** native macOS TFT client experience using the official Android TFT package  
**Current development line:** `codex/native-tftmac-2.0.0`  
**Current installed release:** TFTMAC 2.3.0 build 8, installed, live-launched, and automatically logging; release hashes match, while the timestamped current-host signing audit is blocked by the missing local identity
**Project record through:** 2026-08-31 America/Chicago

This is the continuity document for a new developer or a new chat. It records
what TFTMAC is, why the architecture changed, what has been built, what the
evidence says, and what remains unfinished. Immutable/current facts live in
`facts.md`; exact benchmark formulas and current run findings live in
`benchmark.md`; engineering hypotheses and next code work live in `dev.md`.

## 1. Goal

Deliver a premium native Mac application that lets the user launch, log into,
hear, and play official Teamfight Tactics fullscreen on the target M4 Mac mini.
The Android emulator is part of the runtime implementation but is not exposed as
the product UI. The application must also be an engineering laboratory that
captures the complete runtime behavior well enough to make and reject graphics-
pipeline changes based on evidence.

The completion standard is not “the emulator process exists” and not “the lobby
shows 60 FPS.” The user must be able to play through the native Mac window, and
the logger must preserve every under-target period across the complete run. The
graphics target is at least 60 useful FPS throughout, not only during selected
scenes.

## 2. Current architecture

```text
/Applications/TFTMAC.app
  -> AppKit window, menus, fullscreen space, settings and benchmark controls
  -> native Metal presenter and gameplay-cadence overlay
  -> authenticated loopback EmulatorController gRPC
  -> packaged TFTMAC Emulator Host.app
  -> /usr/bin/open -n -W --env ... --args ...
  -> stock Android Emulator 37.1.11 / TFT_Ultra_Tablet
  -> official API 36 Google Play ARM64 guest
  -> official Google Play TFT package
  -> Riot login, Unreal GameActivity, live TFT gameplay
```

Runtime files live on the external volume at
`/Volumes/MAC MINI M4/TFTMAC/Runtime`. Captures and the normalized laboratory
stay under `~/Library/Application Support/TFTMAC`.

The shipping display path is raw authenticated 1920×1080 RGBA from the emulator
controller into a bounded native Metal presentation ring. MMAP/zero-copy remains
a later controlled experiment because readiness fencing, stride/color integrity,
tearing, frame age, and lifetime ownership have not been proven.

## 3. How the project reached this architecture

### Initial working donor

The Mactician donor had already proven that the Android runtime and TFT could
work on this Mac. Its critical behavior was not only its AVD variables. It
launched the emulator through a packaged Mac application host using
`/usr/bin/open -n -W --env ... --args ...`, inside the logged-in user's macOS
session.

The donor contract was:

```text
ADB server 5038
emulator console 5582
serial emulator-5582
no manual ADB_VENDOR_KEYS injection
```

### The ADB regression

An early TFTMAC path bypassed that architecture and directly spawned the
emulator from Node/Clara. It also moved to ports 5040/5592. The changed service
context presented an untrusted ADB host identity to Android, producing:

```text
emulator-5592 unauthorized
Timed out waiting for emulator ADB device.
```

The failure was not proof that the Android runtime, AVD, TFT, GPU, RAM, or CPU
were broken. Returning to the proven packaged host/session architecture and the
5038/5582 identity restored the correct boundary. This is why Node/Clara is not
part of the shipping app.

### Source-build research and retirement

The repository previously developed an AEMU/gfxstream/ANGLE/MoltenVK source
laboratory. That work produced valuable compatibility and performance evidence,
but it was retired as a required product dependency. The released stock emulator
is the normal runtime. Historical source trees, patches, launchers, and campaigns
remain R&D evidence only unless a future experiment explicitly builds an
isolated variant.

### Specialist council and ZoeMC

The project commissioned separate Unreal, ANGLE, gfxstream/ASG, MoltenVK, Metal,
and Fortnite/Unreal research tracks, then used ZoeMC v0.2 to rank 10,000 modeled
architecture worlds. The simulation was useful for ordering tests but used
subjective priors, so it was never treated as a benchmark. Its decisive
recommendation was to prove authenticated native frame delivery before building
a custom zero-copy or driver layer.

That branch is now resolved: raw authenticated gRPC can deliver correct
1920×1080 frames and native input. MMAP remains optional; direct zero-copy
without producer fencing and direct MoltenVK texture handoff without a supported
sharing contract remain invalid. Fortnite/Unreal material is retained as
transferable observability and pipeline-development guidance, not as proof of a
TFT implementation detail.

### Native app pivot

The product moved from “a script that launches an emulator” to one real native
Mac application:

- AppKit owns normal windowing and fullscreen behavior.
- Metal owns the final completed Android-frame presentation.
- EmulatorController owns authenticated local frames and input.
- the emulator stays hidden;
- CoreAudio stays enabled;
- Google Play/Riot own package and authentication flows;
- local SQL starts before gameplay and survives through clean shutdown.

## 4. Chronology and major milestones

| Date | Milestone | Durable outcome |
| --- | --- | --- |
| 2026-08-26 | Repository began from a live high-end tablet/emulator runtime | Preserved a working control instead of treating all earlier work as disposable |
| 2026-08-27 | AEMU/graphics Phase 0 and required-case research | Established component versions, GLES 3.2 compatibility need, and graphics experiment inventory |
| 2026-08-28 | Donor-compatible direct play, sustained telemetry, fixed-stage campaign | Proved ASG over pipe, selected 16 KiB write step, recorded many negative results |
| 2026-08-29 | Native architecture/ownership convergence | Retired Node/source-build production dependency and vendored the exact EmulatorController protocol |
| 2026-08-30 | Native AppKit/Metal runtime became playable | Hidden emulator, authenticated frames, native input, fullscreen, CoreAudio, official TFT, local logging |
| 2026-08-30 | Login/input repair | Primary Mac click became Android touch; WebView updated; credential boundary documented |
| 2026-08-30 | Permission/unlock/icon release work | Stable local signing retained external-volume consent; non-error unlock overlays removed; official icon installed |
| 2026-08-30/31 | Rapid Combat A/B logger | Exact TFT SurfaceFlinger windows, incidents, bounded Perfetto, SQL comparison/decisions implemented |
| 2026-08-31 UTC | Home Run A rejected | Riot Performance Mode Beta experience rejected and made non-selectable |
| 2026-08-31 UTC | Build 7 Combat Latency A | One-factor pre-exec host QoS candidate built, tested, installed, and live-launched; combat gain still unproven |
| 2026-08-31 UTC | Build 8 automatic graphics logger | Signed 2.3.0/8 installed and live-launched; PID 2704 and the exact TFT SurfaceView opened the logger automatically, periodic receipts reached `COMPLETE`, and every observed frame fact resolved through its run, stack hash, window, and receipt |
| 2026-08-31 UTC | Latest automatic graphics run | 42m27s automatic process/layer run recorded 144,364 exact intervals and 189 degradation incidents; it proves the continuous logger and performance deficit, not an internal root cause |

Relevant Git milestones:

```text
8d9ce17  Build native full-screen TFTMAC runtime
558c0ea  Add rapid combat A/B benchmark and telemetry
2123cd0  Add official TFTMAC penguin samurai icon
6bdb188  Add Build 7 combat latency candidate and project handoff
a9192ea  Refocus benchmark analysis on continuous FPS
2889cf0  Finish Build 8 automatic graphics logger
```

Build 7 work was developed after `2123cd0` and includes the candidate, guest
power gate, semantic cross-session layer matching, tests, verifier, and authority
updates.

The first Build 7 candidate attempt correctly failed readiness during a stale
listener/teardown race and auto-restored Control. After ports and lease ownership
were proven free, Control launched, then a clean Combat Latency A relaunch passed.
This was a runtime ownership/transient readiness event, not evidence that the
candidate improved or regressed graphics.

## 5. Native runtime achievements

### Window and presentation

- Native `NSWindow` and macOS fullscreen Space behavior are implemented.
- The emulator's UI is hidden.
- Controller frames are exactly 1920×1080 RGBA8888, 8,294,400 bytes.
- The initial gRPC 4 MiB message ceiling was identified and raised to 16 MiB.
- Earlier live acceptance observed source cadence up to about 61.1 Hz and native
  Metal output about 60.5 Hz. Those are transport/output numbers, not Unreal FPS.
- The final presenter is instrumented for submitted/completed frames, repeated
  source use, drawable errors, command completion latency, and Metal GPU time.

### Runtime control

- The app takes an exclusive runtime lease before touching the shared AVD.
- It fails closed on conflicting AVD/console/controller ownership.
- AVD configuration is backed up and hashed before atomic application.
- Owned-process cleanup checks the unique session marker before termination.
- Clean exit seals telemetry, confirms emulator exit, restores the AVD hash, and
  removes lease/transaction state.

### ADB and controller

- ADB uses the donor-compatible 5038/5582/emulator-5582 identity.
- Live sessions have observed `offline -> unauthorized -> device` and continued
  only after `device` authorization.
- Controller discovery is PID-bound and token-authenticated.
- Tokens are kept in memory and excluded from SQL/log output.

### Input

- Primary pointer input is `EmulatorController.sendTouch`, not a desktop mouse
  assumption.
- Identifier `0` remains stable through down/drag/up; release pressure is zero.
- Keyboard uses the controller's evdev path.
- Input telemetry records coordinates/pressure, counts, and special-key names,
  never typed characters.

### Audio

- Emulator launch uses CoreAudio.
- Earlier live evidence saw active 48 kHz stereo output, an active track, and no
  partial/empty underruns.
- Audible sound at the selected physical output remains a user-level acceptance,
  not something software counters can prove alone.

### Power and unlock

- Secure Android PIN unlock remains manual.
- Non-error text overlays that covered the PIN/TFT display were removed.
- Build 7 now proves virtual AC power, stay-awake, and `Awake` wakefulness before
  proceeding, preventing the avoidable secure-screen sleep state.

### External-volume permission

The original repeated drive-access prompt was addressed through stable local
signing/designated identity rather than changing the proven runtime root. A clean
relaunch retained removable-volume consent. Public Developer ID/notarized
distribution is not yet claimed.

### Official launcher artwork

The official icon is a full-bleed square penguin dressed as a samurai with one
sword and stacked `TFT` / `MAC` text. It has no baked outer gutter or rounded
container; macOS supplies the corner mask. The source and derived artwork hashes
are frozen in the release authority.

## 6. Riot login history

The first native login issue had two separate parts:

1. Primary clicks were being delivered as desktop mouse events to an Android
   WebView that expected touch. Build 4 replaced the primary path with real
   Android touch down/move/up.
2. The login form's `USERNAME` field requires the private Riot account login
   username—not the email address and not the public `Name#Tag` Riot ID.

The Android WebView provider was updated from 133.0.6943.137 to 151.0.7922.199.
The user subsequently logged into the Riot account and played.

The current Build 7 live session later reproduced a Riot
`MobileFREWebViewActivity` input-dispatch ANR. The proven narrow recovery did not
restart TFTMAC or the emulator: it restored
`show_ime_with_hard_keyboard=0`, force-stopped only Riot's failed process, and
reopened the official Splash/Game activity. The mutable WebView/IME dependency
therefore remains a tracked runtime risk.

No username, password, email, PIN, cookie, token, screenshot of the form, or
typed content is retained as project evidence.

## 7. Logger evolution

### Why the early logger was insufficient

The early logger could establish runtime health and rough rates, but it could
not truthfully describe the user's core complaint: large FPS loss during major
fights even when averages or the overlay looked high. Lobby/source/output rates
were too easy to misread as gameplay performance.

### Current logger

Every launch now creates a private session SQLite database plus bounded local
sidecars. It separates:

- exact TFT SurfaceFlinger actual-present frame timing;
- raw gRPC source freshness;
- final Metal presentation;
- QEMU/TFT/host resource state;
- audio, ANR, memory, renderer, shader, fence, and transport signal counts;
- host/guest clock synchronization;
- benchmark boundaries, visible-stutter markers, incident traces, and final
  decisions.

The on-screen `SRC` and `OUT` labels are deliberately not called Unreal FPS.
One-second `game_frame_windows` are the gameplay authority and contain effective
FPS, 1% low, p50/p95/p99/max interval, jank, severe stalls, and missed-vsync
equivalents.

### Combat benchmark

- The user starts it at representative heavy combat.
- Five minutes makes it valid; eight minutes closes it automatically.
- A 20-second start trace and at most two 15-second incident traces are bounded
  to 32 MiB each.
- Incident traces require two adjacent bad windows and a 120-second cooldown.
- SQL rejects invalid duration, layer, clock, history, package/configuration, or
  correctness comparisons.
- The result is `HOME_RUN`, `PROMISING`, `REJECT`, or `INCONCLUSIVE`.
- A winning candidate needs a cold confirmation before promotion.

### Full-run analysis

Complete automatic process/layer runs are the preferred product-performance
record because every frame and resource/pipeline sample participates. Match,
combat, and visible-stutter markers are optional annotations only. The current
UI/source-named Combat Benchmark remains the faster bounded one-factor A/B
screen. Root `benchmark.md` is the shared human/AI contract for exact
raw-interval and continuous-60 deficit metrics, complete-timeline processing,
legal clock-domain correlation, and claim/evidence/unknown records.

## 8. Performance development history

### What was learned from the earlier fixed-stage campaign

The earlier campaign ran on an M1 Max/userdebug environment and is historical,
not current M4 performance. It remains valuable for avoiding repeated failures.

- ASG decisively beat pipe at the same Trial stage.
- 16 KiB ASG write steps beat the paired 4 KiB control.
- 1 MiB ASG write buffer and 32 KiB ring remained the stable choice.
- Async MoltenVK submission and 64 active command buffers were retained.
- Effects/LOD changes at 67% improved the controlled Trial proxy.
- Resolution scaling was not automatically decisive: 2560×1440 versus 1600×900
  barely changed one controlled stage despite 2.56× source pixels.
- The selected historical stack still did not meet the 57 FPS heavy-scene goal
  or reproduce the user's worst approximately 15 FPS gameplay period.

The repository preserves full result tables in `docs/benchmarks.md` and the
technical chronology in `docs/research-log.md`.

### Current native run evidence

The user played games through the native app, including a retained match/lobby
capture. Those sessions established playability, not adequate combat
performance. Heavy fights still visibly drop frames.

The first rapid benchmark using combined Home Run A/Riot Performance Mode Beta
looked respectable by weighted average but was unacceptable in play:

```text
duration                 480.646 s
weighted FPS              56.665
1% low                    17.698 FPS
p95 / p99                 21.760 / 34.335 ms
maximum interval         517.488 ms
incident 1% lows           1.932 and 4.629 FPS
```

The user explicitly rejected that experience. Clock RTT and observer-overhead
gates also made cross-boundary causality invalid. Performance Mode Beta is now
retired and cannot be selected.

## 9. Build 7 history and current Build 8 state

Build 7 replaces the rejected composite with `Combat Latency A`:

- retains 1920×1080, 320 dpi, 60 Hz;
- retains 6 vCPU and 5120 MiB;
- retains host GPU, CoreAudio, ANGLE/ASG/gfxstream/MoltenVK values;
- retains TFT High, 60 FPS, Performance Mode OFF;
- changes only the packaged host's requested pre-exec QoS to
  `user_interactive` and declares Game Mode eligibility.

Implementation additions include:

- exact host QoS requested/set/effective receipt before `execv`;
- fail/rollback if the candidate cannot establish that boundary;
- explicit refusal to claim QEMU child-thread inheritance;
- Android virtual-AC/stay-on/awake gate;
- stale Home Run A preference migration to Control;
- semantic cross-session TFT-layer comparison so dynamic SurfaceFlinger tokens
  do not make every Control/Candidate pair incomparable;
- updated correctness rollback and 40 native tests.

The current live capture is:

```text
~/Library/Application Support/TFTMAC/Captures/
  2026-08-31T02-54-28.329Z-14000b50-bf29-44c6-a963-9203d5313494/
```

Direct evidence from that capture:

- profile `tftmac_5gb_native_v1_preset_combat_latency_a`;
- ADB authorized on 5038 / `emulator-5582`;
- 1920×1080 RGBA first frame;
- host QoS set call returned 0 and read back `user_interactive` before exec;
- guest powered/stay-on/awake;
- official TFT 18.1-5402721 receipt;
- logger health gate passed;
- `TFT_READY_FOR_USER` with Unreal Engine and CoreAudio;
- one-second and resource/clock/pipeline tables continued advancing;
- Riot WebView ANR was recorded and recovered without restarting the emulator.
- the user later marked one full run from `2026-08-31T03:19:25Z` through
  `03:51:00Z` (31m35.054s);
- that match recorded 49.449 weighted FPS, 16.300 FPS 1% low, 33.822 ms p95,
  48.746 ms p99, 1,254.162 ms maximum, 19.110% jank, and 0.610% severe
  intervals from 93,724 exact TFT actual-present intervals;
- 58,925 intervals (62.871%) exceeded the 60 FPS frame budget and 1,599 of
  1,693 complete one-second windows (94.448%) were below 60 FPS;
- all overlapping exact-layer windows were available, the TFT layer was stable,
  and no frame history was truncated;
- final Metal output remained near 60 Hz with zero drawable/command errors while
  reusing 23,231 source frames, showing why OUT cadence cannot stand in for
  useful gameplay cadence;
- clock p95 RTT was 86.757 ms, so this match cannot assign the first upstream
  cause or serve as a formal matched candidate-vs-Control decision.

The Desktop launcher `/Users/flash/Desktop/TFTMAC.app` points to the installed
`/Applications/TFTMAC.app`. Runtime process state is intentionally not frozen
as a durable fact; documentation and Git publication do not restart the app or
its emulator.

What the Build 7 run does **not** prove: a Combat Latency A FPS win. It is one
historical candidate baseline, not a compatible A/B pair.

The current Build 8 full-session authority is capture
`2026-08-31T22-30-26.086Z-8df607d7-a34a-4e2a-b00d-739aa3143200`: a 42m27s
automatic graphics run with 144,364 exact intervals, 99.629% exact-layer
coverage, 189 incidents, 56.98 weighted FPS, 21.49 FPS 1% low, 21.510 ms p95,
and 33.434 ms p99. It observed `combat_latency_a` with High/60/Performance Mode
OFF; that is an observed active preset, not a performance promotion. The run
proves degradation and continuous logging but leaves internal root attribution
`UNKNOWN_UPSTREAM_OF_OR_AT_GUEST_SURFACE`.

The same 2026-08-31 host audit confirmed that the installed main and emulator-
host hashes match the historical Build 8 release receipt. It also found zero
valid local signing identities and a current `CSSMERR_TP_NOT_TRUSTED` result.
Historical signing acceptance and current-host trust are separate facts.

## 10. Current repository state and authority map

Current repository observation:

```text
branch: codex/native-tftmac-2.0.0
HEAD:   2889cf00b54da28ff62e81fd14a6ae892f37d7cf (Build 8)
remote: github -> https://github.com/flashls1/TFTMAC.git
```

The Build 8 line was committed cleanly. Branch/worktree state is mutable and
must be re-observed before it is used as a handoff fact.

Current authority roles:

| File | Role |
| --- | --- |
| `facts.md` | facts, hard boundaries, current observations, explicit unknowns |
| `project.md` | project history, architecture pivots, current state, handoff |
| `benchmark.md` | current full-run/bounded-A/B formulas, validity, AI report contract, and findings |
| `dev.md` | developer map, experiments, hypotheses, next code contracts |
| `ssot/runtime-authority.json` | machine-readable current runtime/release evidence |
| `ssot/STACK.lock.yaml` | frozen stack/profile/toolchain selections |
| `docs/TFTMAC_NATIVE_RUNTIME_KNOWLEDGE_BASE.md` | detailed native outcome and operational knowledge |
| `docs/TFTMAC_UNREAL_PIPELINE_OBSERVABILITY.md` | graphics ownership and attribution rules |
| `docs/benchmarks.md` | historical measured campaign results |
| `docs/research-log.md` | historical R&D chronology and negative results |
| `TFTMACAPP.md` | short current native-app status pointer; historical plan is archived |

The dated archive under `docs/history/2026-08-31-pre-build8/`, retired Node
launch paths, historical source-build directives, and historical Medium-profile
records must not override the current SSOT.

## 11. Decisions that remain locked

- Use the packaged Mac host launch chain and ADB 5038/5582 identity.
- Keep official Google Play/Riot package ownership.
- Keep native AppKit/Metal presentation and hidden emulator.
- Keep raw authenticated gRPC as the working presentation control.
- Keep High/60/Performance Mode OFF as the current in-game control.
- Keep 6 vCPU, 5120 MiB, ASG, 16 KiB write step, 32 KiB ring, 1 MiB buffer,
  800 microsecond flush, async MoltenVK, 64 active command buffers, CoreAudio.
- Keep Riot Performance Mode Beta/Home Run A retired.
- Never record or automate credentials.
- Never call SRC/OUT presentation rates Unreal FPS.
- Never assign a graphics bottleneck without the first valid divergent boundary.
- Treat the final Mac presenter as hidden correctness context only, never as a
  user-facing graphics root-cause candidate.
- Keep base graphics logging automatic from TFT process/layer start through
  process/app close; a controlled Combat Benchmark is optional and never gates
  that logging.
- Keep the current optimization equation graphics-only. CPU/RAM/audio remain
  health and correctness context, not candidate optimization work.

## 12. Next decisive work

1. Preserve the installed Build 8 automatic-graphics logger, its historical
   release hashes, and live acceptance capture
   `2026-08-31T21-39-18.396Z-fe34e3a1-fb91-44eb-804f-4ca8519dfc31`.
2. Treat automatic `graphics_runs`, stack-receipt SHA, direct per-frame stack
   identity, and per-window joins as live-verified Build 8 behavior. The Mac
   presenter is hidden correctness context, not a causal view.
3. Preserve the automatic latest-run receipt; match markers are optional
   annotations, not a condition of valid full-run evidence. A short bounded
   Control/Candidate A/B remains optional screening, not base logging admission.
4. Compare complete graphics timelines, every sustained under-60 episode,
   receipt completeness, and conservative boundary views using `benchmark.md`.
   CPU/RAM/audio remain correctness context only.
5. The latest automatic run confirms an unresolved internal causal gap below
   the SurfaceFlinger authority. Implement the planned source-level work-ID
   instrumentation only in the isolated
   `tftmac-runtime` diagnostic stack at `c8aa26e`; do not replace Build 8.
6. Use that evidence to choose an owned code target. Current TFT is direct
   Unreal Vulkan; ANGLE is second-line only if a run receipt proves it is active.
7. Preserve the recurrent Riot WebView ANR as a separate login reliability issue,
   not as a graphics benchmark result.
8. Measure startup phases if the user's observed slow startup remains after login
   reliability is stable; do not trade away logger-before-runtime, ADB, power,
   package, or controller correctness to make a cosmetic startup number smaller.

The native app is launchable and playable. The remaining project objective is
not another wrapper or another generic FPS counter; it is a measured improvement
that holds at least 60 useful FPS across the complete run without destroying
correctness or the official package boundary.
