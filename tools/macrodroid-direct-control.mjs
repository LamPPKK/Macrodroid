#!/usr/bin/env node
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';

const PACKAGE = 'com.riotgames.league.teamfighttactics';
const PLAY_PROBE_PACKAGE = 'com.openai.chatgpt';
const RIOT_SIGNER_SHA256 = '931d969502f3de01a4c239e4199211ebdc57bb9a7526394b9e3e2d1cc079ff0c';
const AVD_NAME = 'TFT_Ultra_Tablet';
const PLAY_DEVICE_ID = '13.5in Freeform';
const PLAY_PROFILE_LABEL = 'TFT Ultra Tablet - 13.5in Freeform / Galaxy Tab S10 Ultra-class';
const PLAY_DISPLAY_WIDTH = 2960;
const PLAY_DISPLAY_HEIGHT = 1848;
const PLAY_DISPLAY_DENSITY = 320;
const PLAY_RAM_MB = 5120;
const BASELINE_PROFILE = Object.freeze({
  id: 'tftmac_5gb_native_v1',
  label: 'TFTMAC native playable 5 GiB baseline',
  width: 1920,
  height: 1080,
  density: 320,
  vcpu: 6,
  ramMB: 5120,
  refreshHz: 60,
  glTransport: 'virtio-gpu-asg',
  asgWriteBufferSize: 1048576,
  asgWriteStepSize: 16384,
  asgDataRingSize: 32768,
  drawFlushInterval: 800,
  featureList: 'GLESDynamicVersion,Vulkan,GuestAngle,-GLPipeChecksum,VulkanBatchedDescriptorSetUpdate,AsyncComposeSupport,VirtioGpuFenceContexts',
  angleEnabledFeatures: 'exposeNonConformantExtensionsAndVersions:exposeES32ForTesting',
  angleDisabledFeatures: 'preferSubmitAtFBOBoundary'
});
// Preserve the donor topology that completed real TFT games in the logged-in
// macOS user session. 5040/5592 was the service-context regression.
const ADB_PORT = '5038';
const SERIAL = 'emulator-5582';
const EMULATOR_PORT = '5582';
const EXTERNAL_ROOT = '/Volumes/MAC MINI M4/TFTMAC/Runtime';
function resolveConsoleUserHome() {
  const userResult = spawnSync('/usr/bin/stat', ['-f', '%Su', '/dev/console'], { encoding: 'utf8' });
  const user = String(userResult.stdout ?? '').trim();
  if (user && user !== 'root' && user !== 'loginwindow') {
    const homeResult = spawnSync('/usr/bin/dscl', ['.', '-read', `/Users/${user}`, 'NFSHomeDirectory'], { encoding: 'utf8' });
    const match = String(homeResult.stdout ?? '').match(/NFSHomeDirectory:\s+(.+)/);
    if (match?.[1]) return match[1].trim();
  }
  return os.homedir();
}

const USER_HOME = resolveConsoleUserHome();
const APP_SUPPORT = path.join(USER_HOME, 'Library', 'Application Support', 'TFTMAC');
const STATE_ROOT = path.join(APP_SUPPORT, 'State');
const CAPTURE_ROOT = path.join(APP_SUPPORT, 'Captures');
const DIAGNOSTICS_ROOT = path.join(APP_SUPPORT, 'Diagnostics');
const CONTROL_STATE = path.join(STATE_ROOT, 'direct-control.json');
const IMAGE_UPGRADE_STATE = path.join(STATE_ROOT, 'image-upgrade.json');
const IMAGE_UPGRADE_STDOUT = path.join(APP_SUPPORT, 'Logs', 'image-upgrade.stdout.log');
const IMAGE_UPGRADE_STDERR = path.join(APP_SUPPORT, 'Logs', 'image-upgrade.stderr.log');
const REQUIRED_IMAGE = 'system-images;android-36;google_apis_playstore;arm64-v8a';
const REQUIRED_IMAGE_MIN_REVISION = 7;
const scriptPath = fileURLToPath(import.meta.url);
const scriptDir = path.dirname(scriptPath);
const repoRoot = process.env.TFTMAC_REPO_ROOT ? path.resolve(process.env.TFTMAC_REPO_ROOT) : path.resolve(scriptDir, '..');

function json(value) { process.stdout.write(`${JSON.stringify(value, null, 2)}\n`); }
function sleep(ms) { return new Promise(resolve => setTimeout(resolve, ms)); }
function nowISO() { return new Date().toISOString(); }
function monoNs() { return process.hrtime.bigint(); }
function exists(p) { try { fs.accessSync(p); return true; } catch { return false; } }
function executable(p) { try { fs.accessSync(p, fs.constants.X_OK); return true; } catch { return false; } }
function ensureDir(p) { fs.mkdirSync(p, { recursive: true }); }
function appendJSONL(file, value) { fs.appendFileSync(file, `${JSON.stringify(value)}\n`); }
function readJSON(file, fallback = null) { try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; } }
function writeJSON(file, value) { ensureDir(path.dirname(file)); fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`); }
function sha256File(file) { const h = crypto.createHash('sha256'); h.update(fs.readFileSync(file)); return h.digest('hex'); }
function matchNumber(text, pattern) { const match = String(text ?? '').match(pattern); return match ? Number(match[1]) : null; }

function bootstrapNativeGate1Authority() {
  const runtime = discover();
  const installedProto = path.join(runtime.sdkRoot, 'emulator', 'lib', 'emulator_controller.proto');
  if (!exists(installedProto)) throw new Error(`INSTALLED_EMULATOR_CONTROLLER_PROTO_MISSING: ${installedProto}`);
  const vendorRoot = path.join(repoRoot, 'Vendor', 'AndroidEmulator');
  const vendoredProto = path.join(vendorRoot, 'emulator_controller.proto');
  const sourcePath = path.join(vendorRoot, 'SOURCE.json');
  ensureDir(vendorRoot);
  const installedSHA256 = sha256File(installedProto);
  if (exists(vendoredProto)) {
    const currentSHA256 = sha256File(vendoredProto);
    if (currentSHA256 !== installedSHA256) {
      throw new Error(`EMULATOR_CONTROLLER_PROTO_DRIFT: vendored=${currentSHA256} installed=${installedSHA256}`);
    }
  } else {
    fs.copyFileSync(installedProto, vendoredProto);
  }
  const phase0 = readJSON(path.join(repoRoot, 'ssot', 'phase0-source.json'), {});
  const source = {
    schema: 1,
    observedAt: nowISO(),
    authority: 'INSTALLED_ANDROID_EMULATOR',
    emulatorVersion: runtime.emulatorVersion,
    emulatorBinary: runtime.emulator,
    installedProtoPath: installedProto,
    installedProtoSHA256: installedSHA256,
    vendoredProtoPath: path.relative(repoRoot, vendoredProto),
    vendoredProtoSHA256: sha256File(vendoredProto),
    aemuAuthority: {
      branch: phase0.aemuBranch ?? null,
      qemuCommit: phase0.commits?.qemu ?? null,
      aemuCommit: phase0.commits?.aemu ?? null,
      manifestSHA256: phase0.manifestSHA256 ?? null
    },
    contract: 'The vendored protocol bytes come directly from the installed stock Android Emulator runtime used by TFTMAC. Build/generation must fail on byte drift until the authority is intentionally refreshed.'
  };
  writeJSON(sourcePath, source);
  return {
    action: 'NATIVE_GATE1_EMULATOR_PROTOCOL_FROZEN',
    emulatorVersion: runtime.emulatorVersion,
    installedProto,
    installedProtoSHA256: installedSHA256,
    vendoredProto: path.relative(repoRoot, vendoredProto),
    source: path.relative(repoRoot, sourcePath),
    sourceSHA256: sha256File(sourcePath)
  };
}

function nativeGate1Script(scriptName, actionName) {
  const script = path.join(repoRoot, 'scripts', scriptName);
  if (!exists(script)) throw new Error(`NATIVE_GATE1_SCRIPT_MISSING: ${script}`);
  const result = command('/bin/zsh', [script], { allowFailure: true, timeout: 3600000, maxBuffer: 128 * 1024 * 1024 });
  if (result.status !== 0) {
    const stdoutTail = result.stdout.slice(-24000);
    const stderrTail = result.stderr.slice(-24000);
    throw new Error(`${actionName}_FAILED\nSTDOUT_TAIL:\n${stdoutTail}\nSTDERR_TAIL:\n${stderrTail}`);
  }
  return { action: actionName, status: result.status, stdout: result.stdout.trim(), stderr: result.stderr.trim() || null };
}

function command(executablePath, args = [], options = {}) {
  const result = spawnSync(executablePath, args, {
    encoding: 'utf8',
    env: options.env ?? process.env,
    cwd: options.cwd ?? repoRoot,
    timeout: options.timeout ?? 120000,
    maxBuffer: options.maxBuffer ?? 32 * 1024 * 1024,
    input: options.input
  });
  if (result.error) throw result.error;
  if (result.status !== 0 && !options.allowFailure) {
    throw new Error(`${executablePath} ${args.join(' ')} failed (${result.status}): ${(result.stderr || result.stdout || '').trim()}`);
  }
  return { status: result.status, stdout: result.stdout ?? '', stderr: result.stderr ?? '' };
}

function resolveReal(p) { try { return fs.realpathSync(p); } catch { return p; } }
function isUnder(child, parent) {
  const c = resolveReal(child);
  const p = resolveReal(parent);
  return c === p || c.startsWith(`${p}${path.sep}`);
}

function walk(root, maxDepth = 4, maxEntries = 12000) {
  const out = [];
  const stack = [{ p: root, depth: 0 }];
  while (stack.length && out.length < maxEntries) {
    const { p, depth } = stack.pop();
    let entries;
    try { entries = fs.readdirSync(p, { withFileTypes: true }); } catch { continue; }
    for (const entry of entries) {
      const full = path.join(p, entry.name);
      out.push(full);
      if (entry.isDirectory() && depth < maxDepth && entry.name !== 'emu-master-dev' && entry.name !== 'src' && entry.name !== '.git') {
        stack.push({ p: full, depth: depth + 1 });
      }
      if (out.length >= maxEntries) break;
    }
  }
  return out;
}

function discover() {
  if (!exists('/Volumes/MAC MINI M4')) throw new Error('External volume /Volumes/MAC MINI M4 is not mounted.');
  if (!exists(EXTERNAL_ROOT)) throw new Error(`Required bulk runtime root does not exist: ${EXTERNAL_ROOT}`);
  const canonicalSdk = path.join(EXTERNAL_ROOT, 'SDK');
  const canonicalAvdIni = path.join(EXTERNAL_ROOT, 'AVD', `${AVD_NAME}.ini`);
  const canonicalComplete = executable(path.join(canonicalSdk, 'platform-tools', 'adb'))
    && executable(path.join(canonicalSdk, 'emulator', 'emulator'))
    && exists(canonicalAvdIni);
  const files = canonicalComplete ? [] : walk(EXTERNAL_ROOT, 5);
  const sdkRoots = new Set();
  for (const file of files) {
    if (file.endsWith(`${path.sep}platform-tools${path.sep}adb`) && executable(file)) {
      const candidate = path.dirname(path.dirname(file));
      if (executable(path.join(candidate, 'emulator', 'emulator'))) sdkRoots.add(candidate);
    }
  }
  for (const candidate of [
    path.join(EXTERNAL_ROOT, 'sdk'),
    path.join(EXTERNAL_ROOT, 'android-sdk'),
    path.join(APP_SUPPORT, 'Runtime', 'sdk'),
    path.join(APP_SUPPORT, 'sdk')
  ]) {
    if (executable(path.join(candidate, 'platform-tools', 'adb')) && executable(path.join(candidate, 'emulator', 'emulator'))) sdkRoots.add(candidate);
  }
  const externalSdkRoots = [...sdkRoots].filter(p => isUnder(p, EXTERNAL_ROOT));
  const sdkRoot = externalSdkRoots[0] ?? [...sdkRoots][0] ?? null;
  if (!sdkRoot) throw new Error(`No complete Google SDK/emulator runtime was found under ${EXTERNAL_ROOT}.`);

  const avdIniCandidates = files.filter(p => p.endsWith(`${AVD_NAME}.ini`));
  for (const candidate of [
    path.join(EXTERNAL_ROOT, 'avd', `${AVD_NAME}.ini`),
    path.join(EXTERNAL_ROOT, '.android', 'avd', `${AVD_NAME}.ini`),
    path.join(APP_SUPPORT, 'Runtime', 'avd', `${AVD_NAME}.ini`),
    path.join(APP_SUPPORT, 'avd', `${AVD_NAME}.ini`)
  ]) if (exists(candidate)) avdIniCandidates.push(candidate);

  let avdIni = [...new Set(avdIniCandidates)].find(p => isUnder(p, EXTERNAL_ROOT)) ?? [...new Set(avdIniCandidates)][0] ?? null;
  let avdHome = avdIni ? path.dirname(avdIni) : null;
  let avdDir = null;
  let avdConfig = null;
  if (avdIni) {
    const ini = fs.readFileSync(avdIni, 'utf8');
    const m = ini.match(/^path=(.+)$/m);
    avdDir = m ? m[1].trim() : path.join(avdHome, `${AVD_NAME}.avd`);
    const configPath = path.join(avdDir, 'config.ini');
    if (exists(configPath)) avdConfig = fs.readFileSync(configPath, 'utf8');
  }

  const imagePkg = path.join(sdkRoot, ...REQUIRED_IMAGE.split(';'));
  const env = {
    ...process.env,
    ANDROID_SDK_ROOT: sdkRoot,
    ANDROID_AVD_HOME: avdHome ?? process.env.ANDROID_AVD_HOME ?? '',
    ANDROID_ADB_SERVER_PORT: ADB_PORT,
    ADB_MDNS_AUTO_CONNECT: ''
  };
  const adb = path.join(sdkRoot, 'platform-tools', 'adb');
  const emulator = path.join(sdkRoot, 'emulator', 'emulator');
  const emulatorVersion = command(emulator, ['-version'], { allowFailure: true, env }).stdout.split('\n').find(l => /Android emulator version/i.test(l))?.trim() ?? null;
  const adbVersion = command(adb, ['version'], { allowFailure: true, env }).stdout.split('\n')[0]?.trim() ?? null;

  return {
    externalRoot: EXTERNAL_ROOT,
    externalRootReal: resolveReal(EXTERNAL_ROOT),
    appSupportRuntime: exists(path.join(APP_SUPPORT, 'Runtime')) ? resolveReal(path.join(APP_SUPPORT, 'Runtime')) : null,
    sdkRoot,
    adb,
    emulator,
    emulatorVersion,
    adbVersion,
    requiredImagePath: imagePkg,
    requiredImagePresent: exists(imagePkg),
    avdIni,
    avdHome,
    avdDir,
    avdConfig,
    env,
    sdkRoots: [...sdkRoots],
    avdIniCandidates: [...new Set(avdIniCandidates)]
  };
}

function adb(runtime, args, options = {}) {
  return command(runtime.adb, ['-P', ADB_PORT, '-s', SERIAL, ...args], { ...options, env: runtime.env });
}
function adbServer(runtime) { command(runtime.adb, ['-P', ADB_PORT, 'start-server'], { env: runtime.env }); }
function deviceReady(runtime) { return adb(runtime, ['get-state'], { allowFailure: true, timeout: 10000 }).stdout.trim() === 'device'; }
async function waitForDevice(runtime, timeoutMs = 180000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (deviceReady(runtime)) return;
    await sleep(1000);
  }
  throw new Error('Timed out waiting for emulator ADB device.');
}
async function waitForBoot(runtime, timeoutMs = 240000) {
  await waitForDevice(runtime, timeoutMs);
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (adb(runtime, ['shell', 'getprop', 'sys.boot_completed'], { allowFailure: true, timeout: 10000 }).stdout.trim() === '1') return;
    await sleep(1000);
  }
  throw new Error('Timed out waiting for Android boot completion.');
}

function guestUserState(runtime) {
  const text = adb(runtime, ['shell', 'dumpsys', 'user'], { allowFailure: true, timeout: 10000 }).stdout;
  const user0Block = text.split(/(?=\n\s*UserInfo\{)/).find(block => /UserInfo\{0:/.test(block)) ?? text;
  const state = user0Block.match(/State:\s*(RUNNING_[A-Z_]+)/)?.[1] ?? null;
  return {
    state,
    unlocked: state === 'RUNNING_UNLOCKED',
    sample: user0Block.split(/\r?\n/).filter(line => /UserInfo\{|State:|Unlock time|Started users state/i.test(line)).slice(0, 40)
  };
}

async function ensureGuestUnlocked(runtime, captureDir = null, timeoutMs = 20000) {
  let observed = guestUserState(runtime);
  if (observed.unlocked) return { action: 'GUEST_ALREADY_UNLOCKED', ...observed };
  const attempts = [];
  const runStep = args => {
    const result = adb(runtime, ['shell', ...args], { allowFailure: true, timeout: 10000 });
    attempts.push({ args, status: result.status, stdout: result.stdout.trim().slice(0, 1000), stderr: result.stderr.trim().slice(0, 1000) });
  };
  runStep(['input', 'keyevent', 'KEYCODE_WAKEUP']);
  runStep(['wm', 'dismiss-keyguard']);
  runStep(['input', 'keyevent', '82']);
  runStep(['input', 'swipe', '960', '900', '960', '250', '250']);
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    observed = guestUserState(runtime);
    if (observed.unlocked) {
      const result = { action: 'GUEST_UNLOCKED', ...observed, attempts };
      if (captureDir) {
        writeJSON(path.join(captureDir, 'guest-unlock.json'), result);
        appendJSONL(path.join(captureDir, 'host-events.jsonl'), { utc: nowISO(), host_mono_ns: monoNs().toString(), event: 'GUEST_UNLOCKED', attempts: attempts.length });
      }
      return result;
    }
    await sleep(500);
  }
  throw new Error(`GUEST_USER_0_REMAINS_LOCKED: ${JSON.stringify({ observed, attempts })}`);
}

function wakeGuestScreen(runtime, captureDir = null) {
  const powerBefore = adb(runtime, ['shell', 'dumpsys', 'power'], { allowFailure: true, timeout: 10000 }).stdout;
  const asleep = /mWakefulness=Asleep|SCREEN_STATE_OFF/i.test(powerBefore);
  adb(runtime, ['shell', 'svc', 'power', 'stayon', 'true'], { allowFailure: true, timeout: 10000 });
  if (asleep) adb(runtime, ['shell', 'input', 'keyevent', 'KEYCODE_POWER'], { allowFailure: true, timeout: 10000 });
  adb(runtime, ['shell', 'input', 'keyevent', 'KEYCODE_WAKEUP'], { allowFailure: true, timeout: 10000 });
  const observed = guestUserState(runtime);
  const result = { action: observed.unlocked ? 'GUEST_AWAKE_UNLOCKED' : 'GUEST_AWAKE_MANUAL_UNLOCK_REQUIRED', wasAsleep: asleep, ...observed };
  if (captureDir) {
    writeJSON(path.join(captureDir, 'guest-unlock.json'), result);
    appendJSONL(path.join(captureDir, 'host-events.jsonl'), { utc: nowISO(), host_mono_ns: monoNs().toString(), event: result.action });
  }
  return result;
}

function wakeGuestScreenAction() {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  if (!deviceReady(runtime)) throw new Error('No active Android device to wake.');
  return wakeGuestScreen(runtime, state?.captureDir ?? null);
}

function screenStateProbe() {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  if (!deviceReady(runtime)) throw new Error('No active Android device for screen-state probe.');
  const shell = args => adb(runtime, ['shell', ...args], { allowFailure: true, timeout: 15000 }).stdout;
  const power = shell(['dumpsys', 'power']);
  const policy = shell(['dumpsys', 'window', 'policy']);
  const windows = shell(['dumpsys', 'window', 'windows']);
  const xml = dumpUI(runtime);
  const result = {
    observedAt: nowISO(),
    guestState: guestUserState(runtime),
    power: power.split(/\r?\n/).filter(line => /Display Power|mWakefulness|mInteractive|screen|display|brightness|doze/i.test(line)).slice(0, 160),
    keyguard: policy.split(/\r?\n/).filter(line => /keyguard|screen|interactive|dream|awake|showing|occluded/i.test(line)).slice(0, 200),
    windows: windows.split(/\r?\n/).filter(line => /mCurrentFocus|mFocusedApp|StatusBar|NotificationShade|Keyguard|Bouncer|SystemUI|Dream|SurfaceView/i.test(line)).slice(0, 220),
    uiText: xml.match(/text="([^"]*)"/g)?.slice(0, 120) ?? []
  };
  if (state?.captureDir) writeJSON(path.join(state.captureDir, 'screen-state-probe.json'), result);
  return result;
}

function revealLockScreen() {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  if (!deviceReady(runtime)) throw new Error('No active Android device to reveal lock screen.');
  wakeGuestScreen(runtime, state?.captureDir ?? null);
  command('/bin/sleep', ['1'], { allowFailure: true, timeout: 3000 });
  adb(runtime, ['shell', 'input', 'swipe', '960', '900', '960', '250', '300'], { allowFailure: true, timeout: 10000 });
  command('/bin/sleep', ['1'], { allowFailure: true, timeout: 3000 });
  const result = screenStateProbe();
  if (state?.captureDir) appendJSONL(path.join(state.captureDir, 'host-events.jsonl'), { utc: nowISO(), host_mono_ns: monoNs().toString(), event: 'LOCK_SCREEN_REVEAL_REQUESTED' });
  return { action: 'LOCK_SCREEN_REVEALED_FOR_MANUAL_PIN', ...result };
}

function hostTimeZoneId() {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || null;
}

function hostUtcOffsetString() {
  const minutesEast = -new Date().getTimezoneOffset();
  const sign = minutesEast >= 0 ? '+' : '-';
  const absolute = Math.abs(minutesEast);
  return `${sign}${String(Math.floor(absolute / 60)).padStart(2, '0')}${String(absolute % 60).padStart(2, '0')}`;
}

async function ensureGuestClock(runtime, captureDir = null) {
  const setAutoTime = adb(runtime, ['shell', 'settings', 'put', 'global', 'auto_time', '1'], { allowFailure: true, timeout: 10000 });
  const setAutoZone = adb(runtime, ['shell', 'settings', 'put', 'global', 'auto_time_zone', '1'], { allowFailure: true, timeout: 10000 });
  await sleep(1500);
  let best = null;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const hostBeforeMs = Date.now();
    const guestEpochRaw = adb(runtime, ['shell', 'date', '+%s'], { allowFailure: true, timeout: 10000 }).stdout.trim();
    const hostAfterMs = Date.now();
    const guestEpochSeconds = Number(guestEpochRaw);
    const hostMidpointSeconds = (hostBeforeMs + hostAfterMs) / 2000;
    const skewSeconds = Number.isFinite(guestEpochSeconds) ? Math.abs(guestEpochSeconds - hostMidpointSeconds) : null;
    const sample = {
      observedAt: nowISO(),
      attempt: attempt + 1,
      hostEpochSeconds: hostMidpointSeconds,
      guestEpochSeconds: Number.isFinite(guestEpochSeconds) ? guestEpochSeconds : null,
      absoluteSkewSeconds: skewSeconds,
      hostTimeZone: hostTimeZoneId(),
      hostUtcOffset: hostUtcOffsetString(),
      guestUtcOffset: adb(runtime, ['shell', 'date', '+%z'], { allowFailure: true, timeout: 10000 }).stdout.trim() || null,
      guestTimeZone: adb(runtime, ['shell', 'getprop', 'persist.sys.timezone'], { allowFailure: true, timeout: 10000 }).stdout.trim() || null,
      autoTime: adb(runtime, ['shell', 'settings', 'get', 'global', 'auto_time'], { allowFailure: true, timeout: 10000 }).stdout.trim(),
      autoTimeZone: adb(runtime, ['shell', 'settings', 'get', 'global', 'auto_time_zone'], { allowFailure: true, timeout: 10000 }).stdout.trim(),
      setAutoTimeStatus: setAutoTime.status,
      setAutoTimeZoneStatus: setAutoZone.status
    };
    if (!best || (sample.absoluteSkewSeconds ?? Number.POSITIVE_INFINITY) < (best.absoluteSkewSeconds ?? Number.POSITIVE_INFINITY)) best = sample;
    if (sample.autoTime === '1' && sample.autoTimeZone === '1' && sample.absoluteSkewSeconds !== null && sample.absoluteSkewSeconds <= 5 && (!sample.guestUtcOffset || sample.guestUtcOffset === sample.hostUtcOffset)) break;
    await sleep(1000);
  }
  if (captureDir && best) {
    writeJSON(path.join(captureDir, 'clock-preflight.json'), best);
    appendJSONL(path.join(captureDir, 'host-events.jsonl'), { utc: nowISO(), event: 'CLOCK_PREFLIGHT', ...best });
  }
  if (!best || best.autoTime !== '1' || best.autoTimeZone !== '1') throw new Error(`PLAY_CLOCK_PREFLIGHT_FAILED: automatic time settings are not enabled (${JSON.stringify(best)}).`);
  if (best.absoluteSkewSeconds === null || best.absoluteSkewSeconds > 5) throw new Error(`PLAY_CLOCK_PREFLIGHT_FAILED: guest clock skew is ${best.absoluteSkewSeconds ?? 'unknown'} seconds.`);
  if (best.guestUtcOffset && best.guestUtcOffset !== best.hostUtcOffset) throw new Error(`PLAY_CLOCK_PREFLIGHT_FAILED: guest UTC offset ${best.guestUtcOffset} does not match host ${best.hostUtcOffset}.`);
  return best;
}

function parseKeyValueLines(text) {
  const out = {};
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^\s*([^:=]+?)\s*[:=]\s*(.*?)\s*$/);
    if (m) out[m[1].trim()] = m[2].trim();
  }
  return out;
}

function captureSigningDigest(runtime, apkPaths, captureDir, versionName, versionCode) {
  if (!captureDir || !apkPaths.length) return { certificateSHA256: null, output: null };
  const previous = readJSON(path.join(captureDir, 'package-state.json'), {});
  if (previous?.versionName === versionName && previous?.versionCode === versionCode && previous?.signerCertificateSHA256) {
    return { certificateSHA256: previous.signerCertificateSHA256, output: exists(path.join(captureDir, 'package-signing.txt')) ? fs.readFileSync(path.join(captureDir, 'package-signing.txt'), 'utf8') : null };
  }
  const buildToolsRoot = path.join(runtime.sdkRoot, 'build-tools');
  let apksigner = null;
  try {
    const versions = fs.readdirSync(buildToolsRoot).sort((a, b) => b.localeCompare(a, undefined, { numeric: true }));
    for (const version of versions) {
      const candidate = path.join(buildToolsRoot, version, 'apksigner');
      if (executable(candidate)) { apksigner = candidate; break; }
    }
  } catch {}
  if (!apksigner) return { certificateSHA256: null, output: 'apksigner unavailable in installed Google build-tools' };
  const baseApk = apkPaths.find(p => /\/base\.apk$/.test(p)) ?? apkPaths[0];
  const tempApk = `/private/tmp/tftmac-signing-${process.pid}-${Date.now()}.apk`;
  try {
    const pull = command(runtime.adb, ['-P', ADB_PORT, '-s', SERIAL, 'pull', baseApk, tempApk], { env: runtime.env, allowFailure: true, timeout: 300000 });
    if (pull.status !== 0 || !exists(tempApk)) return { certificateSHA256: null, output: `adb pull failed: ${pull.stderr || pull.stdout}` };
    const verified = command(apksigner, ['verify', '--print-certs', tempApk], { allowFailure: true, timeout: 120000 });
    const output = `${verified.stdout}${verified.stderr}`.trim();
    const digest = output.match(/Signer #\d+ certificate SHA-256 digest:\s*([0-9a-f:]+)/i)?.[1]?.replace(/:/g, '').toLowerCase() ?? null;
    fs.writeFileSync(path.join(captureDir, 'package-signing.txt'), `${output}\n`);
    return { certificateSHA256: digest, output };
  } finally {
    try { fs.unlinkSync(tempApk); } catch {}
  }
}

function resolvedComponent(text) {
  return String(text ?? '').split(/\r?\n/).map(line => line.trim()).filter(Boolean).findLast(line => /^[^\s/]+\/[^\s]+$/.test(line)) ?? null;
}

function packageState(runtime, captureDir = null, includeSigning = true) {
  const pathsOut = adb(runtime, ['shell', 'pm', 'path', PACKAGE], { allowFailure: true }).stdout.trim();
  if (!pathsOut.includes('package:')) {
    const missing = { observedAt: nowISO(), packageName: PACKAGE, state: 'MISSING', apkPaths: [] };
    if (captureDir) writeJSON(path.join(captureDir, 'package-state.json'), missing);
    return missing;
  }
  const apkPaths = pathsOut.split(/\r?\n/).filter(Boolean).map(l => l.replace(/^package:/, '').trim());
  const dump = adb(runtime, ['shell', 'dumpsys', 'package', PACKAGE], { allowFailure: true, timeout: 30000 }).stdout;
  const versionName = dump.match(/versionName=([^\s]+)/)?.[1] ?? null;
  const versionCode = dump.match(/versionCode=([^\s]+)/)?.[1] ?? null;
  const installer = dump.match(/installerPackageName=([^\s]+)/)?.[1] ?? dump.match(/Installer package name:\s*([^\s]+)/i)?.[1] ?? null;
  const firstInstallTime = dump.match(/firstInstallTime=([^\n]+)/)?.[1]?.trim() ?? null;
  const lastUpdateTime = dump.match(/lastUpdateTime=([^\n]+)/)?.[1]?.trim() ?? null;
  const launchResolveRaw = adb(runtime, ['shell', 'cmd', 'package', 'resolve-activity', '--brief', PACKAGE], { allowFailure: true }).stdout.trim();
  const launchActivity = resolvedComponent(launchResolveRaw);
  const hashes = {};
  const apkBytes = {};
  for (const apkPath of apkPaths) {
    const out = adb(runtime, ['shell', 'sha256sum', apkPath], { allowFailure: true, timeout: 30000 }).stdout.trim();
    const m = out.match(/^([0-9a-f]{64})\s+/i);
    if (m) hashes[apkPath] = m[1].toLowerCase();
    const sizeOut = adb(runtime, ['shell', 'stat', '-c', '%s', apkPath], { allowFailure: true, timeout: 10000 }).stdout.trim();
    if (/^\d+$/.test(sizeOut)) apkBytes[apkPath] = Number(sizeOut);
  }
  const signingLines = dump.split(/\r?\n/).filter(l => /sha-?256|signing|certificate/i.test(l)).slice(0, 80);
  const previousForSigning = captureDir ? readJSON(path.join(captureDir, 'package-state.json'), {}) : {};
  const signing = includeSigning
    ? captureSigningDigest(runtime, apkPaths, captureDir, versionName, versionCode)
    : { certificateSHA256: previousForSigning?.signerCertificateSHA256 ?? null, output: null };
  const previousState = captureDir ? readJSON(path.join(captureDir, 'package-state.json'), {}) : {};
  const currentWasVerified = previousState?.state === 'INSTALLED_CURRENT_OBSERVED'
    && previousState?.versionName === versionName
    && previousState?.versionCode === versionCode;
  const state = {
    observedAt: nowISO(), packageName: PACKAGE, state: currentWasVerified ? 'INSTALLED_CURRENT_OBSERVED' : 'INSTALLED_UNKNOWN_VERSION', versionName, versionCode,
    installerPackage: installer, firstInstallTime, lastUpdateTime, launchActivity, apkPaths, apkSHA256: hashes, apkBytes,
    signerCertificateSHA256: signing.certificateSHA256,
    signingObservation: signingLines
  };
  if (captureDir) {
    writeJSON(path.join(captureDir, 'package-state.json'), state);
    fs.writeFileSync(path.join(captureDir, 'package-dumpsys.txt'), dump);
  }
  return state;
}

function packageLaunchProbe() {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  if (!deviceReady(runtime)) throw new Error('No active Android device for package launch probe.');
  const shell = (args, timeout = 30000) => adb(runtime, ['shell', ...args], { allowFailure: true, timeout });
  const dump = shell(['dumpsys', 'package', PACKAGE], 30000).stdout;
  const launcherResolve = shell(['cmd', 'package', 'resolve-activity', '--brief', '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.LAUNCHER', PACKAGE]);
  const launcherQuery = shell(['cmd', 'package', 'query-activities', '--brief', '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.LAUNCHER', PACKAGE]);
  const packagePath = shell(['pm', 'path', PACKAGE]).stdout.trim();
  const enabledPackages = shell(['pm', 'list', 'packages', '-e', PACKAGE]).stdout.trim();
  const disabledPackages = shell(['pm', 'list', 'packages', '-d', PACKAGE]).stdout.trim();
  const installedPackages = shell(['pm', 'list', 'packages', PACKAGE]).stdout.trim();
  const currentUser = shell(['am', 'get-current-user']).stdout.trim();
  const userState = shell(['dumpsys', 'user']).stdout.split(/\r?\n/).filter(line => /UserInfo\{|state=|RUNNING_|unlock/i.test(line)).slice(0, 120);
  const user0Packages = shell(['pm', 'list', 'packages', '--user', '0', PACKAGE]).stdout.trim();
  const packageLines = dump.split(/\r?\n/).filter(line =>
    /SplashActivity|GameActivity|android\.intent\.action\.MAIN|android\.intent\.category\.LAUNCHER|enabled=|stopped=|suspended=|hidden=|installed=|archiv|pkgFlags|privateFlags/i.test(line)
  ).slice(0, 500);
  const result = {
    observedAt: nowISO(),
    packageName: PACKAGE,
    packagePath,
    installedPackages,
    enabledPackages,
    disabledPackages,
    currentUser,
    userState,
    user0Packages,
    launcherResolve: { status: launcherResolve.status, stdout: launcherResolve.stdout.trim(), stderr: launcherResolve.stderr.trim() },
    launcherQuery: { status: launcherQuery.status, stdout: launcherQuery.stdout.trim(), stderr: launcherQuery.stderr.trim() },
    packageLines
  };
  if (state?.captureDir) writeJSON(path.join(state.captureDir, 'package-launch-probe.json'), result);
  return result;
}

function rendererState(runtime, captureDir) {
  const getprop = adb(runtime, ['shell', 'getprop'], { allowFailure: true, timeout: 30000 }).stdout;
  const sf = adb(runtime, ['shell', 'dumpsys', 'SurfaceFlinger'], { allowFailure: true, timeout: 30000 }).stdout;
  const gfx = adb(runtime, ['shell', 'dumpsys', 'gfxinfo', PACKAGE], { allowFailure: true, timeout: 30000 }).stdout;
  const activity = adb(runtime, ['shell', 'dumpsys', 'activity', 'top'], { allowFailure: true, timeout: 30000 }).stdout;
  const keys = [
    'ro.hardware.egl','ro.hardware.vulkan','ro.opengles.version','ro.boot.qemu.gltransport','ro.boot.qemu.gles','debug.hwui.renderer',
    'ro.kernel.qemu','ro.product.cpu.abi','ro.build.version.release','ro.build.version.sdk'
  ];
  const props = {};
  for (const key of keys) {
    const out = adb(runtime, ['shell', 'getprop', key], { allowFailure: true }).stdout.trim();
    if (out) props[key] = out;
  }
  const settings = {};
  for (const key of ['angle_gl_driver_all_angle','angle_gl_driver_selection_pkgs','angle_gl_driver_selection_values']) {
    settings[key] = adb(runtime, ['shell', 'settings', 'get', 'global', key], { allowFailure: true }).stdout.trim();
  }
  const emulatorLog = captureDir ? path.join(captureDir, 'emulator.stdout.log') : null;
  let hostGraphicsEvidence = [];
  if (emulatorLog && exists(emulatorLog)) {
    hostGraphicsEvidence = fs.readFileSync(emulatorLog, 'utf8').split(/\r?\n/)
      .filter(l => /ANGLE|gfxstream|MoltenVK|Metal|Vulkan|gltransport|virtio-gpu|renderer/i.test(l)).slice(-240);
  }
  const result = { observedAt: nowISO(), properties: props, angleSettings: settings, hostGraphicsEvidence };
  if (captureDir) {
    writeJSON(path.join(captureDir, 'renderer-state.json'), result);
    fs.writeFileSync(path.join(captureDir, 'renderer-getprop.txt'), getprop);
    fs.writeFileSync(path.join(captureDir, 'surfaceflinger', 'surfaceflinger.txt'), sf);
    fs.writeFileSync(path.join(captureDir, 'gfxinfo', 'gfxinfo-snapshot.txt'), gfx);
    fs.writeFileSync(path.join(captureDir, 'activity-top.txt'), activity);
  }
  return result;
}

function currentGitSha() {
  if (process.env.TFTMAC_BUILD_COMMIT) return process.env.TFTMAC_BUILD_COMMIT;
  const bundledCommit = path.join(scriptDir, 'build-commit.txt');
  if (exists(bundledCommit)) return fs.readFileSync(bundledCommit, 'utf8').trim();
  const result = command('/usr/bin/git', ['rev-parse', 'HEAD'], { cwd: repoRoot, allowFailure: true });
  return result.status === 0 ? result.stdout.trim() : 'uncommitted-control';
}

function runtimeState(runtime, captureDir, bootClass) {
  const avdHash = runtime.avdConfig ? crypto.createHash('sha256').update(runtime.avdConfig).digest('hex') : null;
  const display = adb(runtime, ['shell', 'wm', 'size'], { allowFailure: true }).stdout.trim();
  const density = adb(runtime, ['shell', 'wm', 'density'], { allowFailure: true }).stdout.trim();
  const state = {
    observedAt: nowISO(), control: 'control_stock_direct_v0', externalRoot: runtime.externalRoot,
    sdkRoot: runtime.sdkRoot, emulatorVersion: runtime.emulatorVersion, adbVersion: runtime.adbVersion,
    systemImagePackage: REQUIRED_IMAGE, avdName: AVD_NAME, avdHome: runtime.avdHome, avdConfigSHA256: avdHash,
    adbSerial: SERIAL, adbServerPort: Number(ADB_PORT), emulatorConsolePort: Number(EMULATOR_PORT),
    vcpu: 6, ramMB: PLAY_RAM_MB, displayRequested: `${PLAY_DISPLAY_WIDTH}x${PLAY_DISPLAY_HEIGHT}`, densityRequested: PLAY_DISPLAY_DENSITY, refreshTargetHz: 60,
    gpuMode: 'host', audioEnabled: true, audioBackend: 'coreaudio', deviceFrame: false, snapshotsRequired: false, bootClass,
    observedDisplay: display, observedDensity: density
  };
  if (captureDir) writeJSON(path.join(captureDir, 'runtime-state.json'), state);
  return state;
}

function setIniValue(text, key, value) {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const pattern = new RegExp(`^${escaped}=.*$`, 'm');
  return pattern.test(text)
    ? text.replace(pattern, `${key}=${value}`)
    : `${text.replace(/\s*$/, '')}\n${key}=${value}\n`;
}

function prepareAVD() {
  const runtime = discover();
  if (!isUnder(runtime.sdkRoot, EXTERNAL_ROOT)) throw new Error('Selected SDK is not on the required external runtime volume.');
  if (!runtime.requiredImagePresent) throw new Error(`Required official Play image is missing: ${runtime.requiredImagePath}`);
  if (!runtime.avdIni || !runtime.avdDir || !runtime.avdConfig) {
    const avdmanager = path.join(runtime.sdkRoot, 'cmdline-tools', 'latest', 'bin', 'avdmanager');
    if (!executable(avdmanager)) throw new Error(`Required AVD ${AVD_NAME} is missing and avdmanager is unavailable.`);
    ensureDir(path.join(EXTERNAL_ROOT, 'AVD'));
    command(avdmanager, ['create', 'avd', '--name', AVD_NAME, '--package', REQUIRED_IMAGE, '--device', PLAY_DEVICE_ID, '--force'], {
      env: { ...runtime.env, ANDROID_AVD_HOME: path.join(EXTERNAL_ROOT, 'AVD') },
      timeout: 120000
    });
    return prepareAVD();
  }
  if (!isUnder(runtime.avdDir, EXTERNAL_ROOT)) throw new Error('Selected AVD is not on the required external runtime volume.');
  const configPath = path.join(runtime.avdDir, 'config.ini');
  let config = runtime.avdConfig;
  const values = {
    AvdId: AVD_NAME,
     'avd.ini.displayname': 'TFT Ultra Tablet - API36 Google Play',
    'hw.device.manufacturer': 'Google',
    'hw.device.name': PLAY_DEVICE_ID,
    'hw.initialOrientation': 'Landscape',
    'hw.cpu.arch': 'arm64',
    'hw.cpu.ncore': '6',
    'hw.ramSize': String(PLAY_RAM_MB),
    'hw.vmHeapSize': '768',
    'hw.lcd.width': String(PLAY_DISPLAY_WIDTH),
    'hw.lcd.height': String(PLAY_DISPLAY_HEIGHT),
    'hw.lcd.density': String(PLAY_DISPLAY_DENSITY),
    'hw.gpu.enabled': 'yes',
    'hw.gpu.mode': 'host',
    'hw.audioInput': 'yes',
    'hw.keyboard': 'yes',
    'disk.dataPartition.size': '16G',
    'runtime.network.speed': 'full',
    'runtime.network.latency': 'none',
    'PlayStore.enabled': 'true',
    'fastboot.forceColdBoot': 'yes',
    'fastboot.forceFastBoot': 'no'
  };
  for (const [key, value] of Object.entries(values)) config = setIniValue(config, key, value);
  fs.writeFileSync(configPath, config);
  const forbidden = config.split(/\r?\n/).filter(line => /guestangle|opengles\.version|nonconformant|moltenvk|graphics_profile/i.test(line));
  if (forbidden.length) throw new Error(`AVD contains experimental graphics overrides and is not a clean stock control: ${forbidden.join('; ')}`);
  return {
    avdName: AVD_NAME,
    avdHome: runtime.avdHome,
    avdDir: runtime.avdDir,
    configPath,
    configSHA256: sha256File(configPath),
    control: { role: 'PLAY_AUTHORITY', profileLabel: PLAY_PROFILE_LABEL, deviceTemplate: PLAY_DEVICE_ID, vcpu: 6, ramMB: PLAY_RAM_MB, width: PLAY_DISPLAY_WIDTH, height: PLAY_DISPLAY_HEIGHT, densityDpi: PLAY_DISPLAY_DENSITY, gpu: 'host', playStore: true, audio: true },
    imagePackage: REQUIRED_IMAGE,
    emulatorVersion: runtime.emulatorVersion
  };
}

function startSampler(runtime, captureDir, sessionId) {
  const out = fs.openSync(path.join(captureDir, 'sampler.stdout.log'), 'a');
  const err = fs.openSync(path.join(captureDir, 'sampler.stderr.log'), 'a');
  const child = spawn(process.execPath, [scriptPath, 'sampler', '--capture', captureDir, '--session', sessionId], {
    cwd: repoRoot, env: runtime.env, detached: true, stdio: ['ignore', out, err]
  });
  child.unref();
  return child.pid;
}

function startEmulator(runtime, captureDir) {
  if (!runtime.avdHome || !runtime.avdIni || !runtime.avdDir) throw new Error(`Official AVD ${AVD_NAME} is not present under the external runtime.`);
  const out = fs.openSync(path.join(captureDir, 'emulator.stdout.log'), 'a');
  const err = fs.openSync(path.join(captureDir, 'emulator.stderr.log'), 'a');
  const args = [
    `@${AVD_NAME}`, '-id', 'TFTMAC', '-port', EMULATOR_PORT,
    '-gpu', 'host', '-audio', 'coreaudio', '-cores', '6', '-memory', String(PLAY_RAM_MB),
    '-no-snapshot', '-no-metrics', '-no-boot-anim', '-crash-report-mode', 'disabled'
  ];
  const timeZone = hostTimeZoneId();
  if (timeZone) args.push('-timezone', timeZone);
  const env = { ...runtime.env, ANDROID_AVD_HOME: runtime.avdHome, ANDROID_EMULATOR_USE_SYSTEM_LIBS: '0' };
  const child = spawn(runtime.emulator, args, { cwd: repoRoot, env, detached: true, stdio: ['ignore', out, err] });
  child.unref();
  appendJSONL(path.join(captureDir, 'host-events.jsonl'), { utc: nowISO(), event: 'EMULATOR_STARTED', pid: child.pid, args });
  return child.pid;
}

function baselineConfigBackupPath(runtime) {
  if (!runtime.avdDir) throw new Error('Baseline control requires a resolved AVD directory.');
  return path.join(runtime.avdDir, 'config.ini.tftmac-baseline-backup');
}

function prepareBaselineAVD(runtime, drawFlushInterval = BASELINE_PROFILE.drawFlushInterval) {
  if (!runtime.avdDir || !runtime.avdConfig) throw new Error('Baseline control requires an existing official Play AVD.');
  if (!isUnder(runtime.avdDir, EXTERNAL_ROOT)) throw new Error('Baseline control AVD must remain on the external runtime volume.');
  const configPath = path.join(runtime.avdDir, 'config.ini');
  const backupPath = baselineConfigBackupPath(runtime);
  if (exists(backupPath)) {
    const restored = fs.readFileSync(backupPath, 'utf8');
    fs.writeFileSync(configPath, restored);
    fs.unlinkSync(backupPath);
  }
  const baseline = fs.readFileSync(configPath, 'utf8');
  fs.writeFileSync(backupPath, baseline);
  let config = baseline;
  const values = {
    'hw.cpu.ncore': String(BASELINE_PROFILE.vcpu),
    'hw.ramSize': String(BASELINE_PROFILE.ramMB),
    'hw.lcd.width': String(BASELINE_PROFILE.width),
    'hw.lcd.height': String(BASELINE_PROFILE.height),
    'hw.lcd.density': String(BASELINE_PROFILE.density),
    'hw.gpu.enabled': 'yes',
    'hw.gpu.mode': 'host',
    'hw.gltransport': BASELINE_PROFILE.glTransport,
    'hw.gltransport.drawFlushInterval': String(drawFlushInterval),
    'hw.gltransport.asg.writeBufferSize': String(BASELINE_PROFILE.asgWriteBufferSize),
    'hw.gltransport.asg.writeStepSize': String(BASELINE_PROFILE.asgWriteStepSize),
    'hw.gltransport.asg.dataRingSize': String(BASELINE_PROFILE.asgDataRingSize),
    'showDeviceFrame': 'no',
    'skin.name': `${BASELINE_PROFILE.width}x${BASELINE_PROFILE.height}`,
    'fastboot.forceColdBoot': 'yes',
    'fastboot.forceFastBoot': 'no'
  };
  for (const [key, value] of Object.entries(values)) config = setIniValue(config, key, value);
  fs.writeFileSync(configPath, config);
  return {
    profile: BASELINE_PROFILE,
    configPath,
    configSHA256: sha256File(configPath),
    baselineSHA256: crypto.createHash('sha256').update(baseline).digest('hex'),
    backupPath
  };
}

function restoreBaselineAVD(runtime) {
  if (!runtime?.avdDir) return { restored: false, reason: 'AVD_UNRESOLVED' };
  const configPath = path.join(runtime.avdDir, 'config.ini');
  const backupPath = baselineConfigBackupPath(runtime);
  if (!exists(backupPath)) return { restored: false, reason: 'NO_BASELINE_BACKUP' };
  const baseline = fs.readFileSync(backupPath, 'utf8');
  fs.writeFileSync(configPath, baseline);
  fs.unlinkSync(backupPath);
  return { restored: true, configPath, configSHA256: sha256File(configPath) };
}

function startBaselineEmulator(runtime, captureDir, ramMB = BASELINE_PROFILE.ramMB, controlProfileId = BASELINE_PROFILE.id, embeddedControl = false) {
  if (!runtime.avdHome || !runtime.avdIni || !runtime.avdDir) throw new Error(`Official AVD ${AVD_NAME} is not present under the external runtime.`);
  const out = fs.openSync(path.join(captureDir, 'emulator.stdout.log'), 'a');
  const err = fs.openSync(path.join(captureDir, 'emulator.stderr.log'), 'a');
  const args = [
    `@${AVD_NAME}`, '-id', 'TFTMAC', '-port', EMULATOR_PORT,
    '-gpu', 'host', '-audio', 'coreaudio', '-feature', BASELINE_PROFILE.featureList,
    '-append-userspace-opt', 'androidboot.opengles.version=196610',
    '-append-userspace-opt', 'androidboot.tftmac.graphics_profile=tftmac',
    '-skin', `${BASELINE_PROFILE.width}x${BASELINE_PROFILE.height}`,
    '-vsync-rate', String(BASELINE_PROFILE.refreshHz),
    '-dns-server', '1.1.1.1,8.8.8.8',
    '-cores', String(BASELINE_PROFILE.vcpu), '-memory', String(ramMB),
    '-no-hidpi-scaling',
    '-no-snapshot', '-no-metrics', '-no-boot-anim', '-crash-report-mode', 'disabled'
  ];
  if (embeddedControl) args.push('-qt-hide-window', '-grpc-use-token', '-idle-grpc-timeout', '300');
  if (process.env.TFTMAC_NATIVE_FULLSCREEN === '1' && !embeddedControl) {
    const screenWidth = Number(process.env.TFTMAC_HOST_SCREEN_WIDTH ?? 0);
    const screenHeight = Number(process.env.TFTMAC_HOST_SCREEN_HEIGHT ?? 0);
    const controlWidth = Number(process.env.TFTMAC_NATIVE_CONTROL_WIDTH ?? 64);
    const titleChrome = Number(process.env.TFTMAC_NATIVE_TOPBAR_HEIGHT ?? 30);
    const backingScale = Number(process.env.TFTMAC_HOST_BACKING_SCALE ?? 1) || 1;
    const widthScalePoints = screenWidth > controlWidth ? (screenWidth - controlWidth) / BASELINE_PROFILE.width : 1;
    const heightScalePoints = screenHeight > titleChrome ? (screenHeight - titleChrome) / BASELINE_PROFILE.height : 1;
    const logicalScale = Math.max(0.1, Math.min(widthScalePoints, heightScalePoints, 4));
    const scale = logicalScale * backingScale;
    args.push('-scale', scale.toFixed(6));
  }
  const timeZone = hostTimeZoneId();
  if (timeZone) args.push('-timezone', timeZone);
  const env = {
    ...runtime.env,
    ANDROID_AVD_HOME: runtime.avdHome,
    ANDROID_EMULATOR_USE_SYSTEM_LIBS: '0',
    ANGLE_FEATURE_OVERRIDES_ENABLED: BASELINE_PROFILE.angleEnabledFeatures,
    ANGLE_FEATURE_OVERRIDES_DISABLED: BASELINE_PROFILE.angleDisabledFeatures,
    MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS: '0',
    MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE: '64',
    MVK_CONFIG_FAST_MATH_ENABLED: '1'
  };
  delete env.ADB_VENDOR_KEYS;
  const hostApp = path.join(repoRoot, 'dist', 'TFTMAC.app', 'Contents', 'Resources', 'TFTMAC Emulator Host.app');
  if (!exists(hostApp)) throw new Error(`TFTMAC_EMULATOR_HOST_MISSING: build the native app first: ${hostApp}`);
  const openArgs = [
    '-n', '-W',
    '--env', `TFT_EMULATOR=${runtime.emulator}`,
    '--env', `TFT_ADB_SERVER_PORT=${ADB_PORT}`,
    '--env', `ANDROID_ADB_SERVER_PORT=${ADB_PORT}`,
    '--env', 'ADB_MDNS_AUTO_CONNECT=',
    '--env', `ANDROID_SDK_ROOT=${runtime.sdkRoot}`,
    '--env', `ANDROID_AVD_HOME=${runtime.avdHome}`,
    '--env', 'ANDROID_EMULATOR_USE_SYSTEM_LIBS=0',
    '--env', `ANGLE_FEATURE_OVERRIDES_ENABLED=${env.ANGLE_FEATURE_OVERRIDES_ENABLED}`,
    '--env', `ANGLE_FEATURE_OVERRIDES_DISABLED=${env.ANGLE_FEATURE_OVERRIDES_DISABLED}`,
    '--env', `MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=${env.MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS}`,
    '--env', `MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE=${env.MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE}`,
    '--env', `MVK_CONFIG_FAST_MATH_ENABLED=${env.MVK_CONFIG_FAST_MATH_ENABLED}`,
    '--env', `TFT_HOST_STDOUT=${path.join(captureDir, 'emulator.stdout.log')}`,
    '--env', `TFT_HOST_STDERR=${path.join(captureDir, 'emulator.stderr.log')}`,
    hostApp, '--args', ...args
  ];
  const child = spawn('/usr/bin/open', openArgs, { cwd: repoRoot, env, detached: true, stdio: ['ignore', out, err] });
  child.unref();
  appendJSONL(path.join(captureDir, 'host-events.jsonl'), {
    utc: nowISO(), event: 'BASELINE_EMULATOR_STARTED', launcherPid: child.pid, args,
    launcher: '/usr/bin/open -n -W --env ... --args ...', adbVendorKeysPresent: false,
    profile: controlProfileId,
    env: {
      ANGLE_FEATURE_OVERRIDES_ENABLED: env.ANGLE_FEATURE_OVERRIDES_ENABLED,
      ANGLE_FEATURE_OVERRIDES_DISABLED: env.ANGLE_FEATURE_OVERRIDES_DISABLED,
      MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS: env.MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS,
      MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE: env.MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE,
      MVK_CONFIG_FAST_MATH_ENABLED: env.MVK_CONFIG_FAST_MATH_ENABLED
    }
  });
  return child.pid;
}

function baselineRuntimeState(runtime, captureDir, prepared, bootClass, ramMB = BASELINE_PROFILE.ramMB, controlProfileId = BASELINE_PROFILE.id, drawFlushInterval = BASELINE_PROFILE.drawFlushInterval) {
  const display = adb(runtime, ['shell', 'wm', 'size'], { allowFailure: true }).stdout.trim();
  const density = adb(runtime, ['shell', 'wm', 'density'], { allowFailure: true }).stdout.trim();
  const state = {
    observedAt: nowISO(),
    control: controlProfileId,
    compatibilityAdapter: true,
    compatibilitySource: 'TFTMAC measured playable runtime on this host',
    externalRoot: runtime.externalRoot,
    sdkRoot: runtime.sdkRoot,
    emulatorVersion: runtime.emulatorVersion,
    adbVersion: runtime.adbVersion,
    systemImagePackage: REQUIRED_IMAGE,
    avdName: AVD_NAME,
    avdHome: runtime.avdHome,
    avdConfigSHA256: prepared.configSHA256,
    baselineAvdConfigSHA256: prepared.baselineSHA256,
    adbSerial: SERIAL,
    adbServerPort: Number(ADB_PORT),
    emulatorConsolePort: Number(EMULATOR_PORT),
    vcpu: BASELINE_PROFILE.vcpu,
    ramMB,
    ramSource: ramMB === BASELINE_PROFILE.ramMB ? 'profile' : 'emulator-command-line-override',
    displayRequested: `${BASELINE_PROFILE.width}x${BASELINE_PROFILE.height}`,
    densityRequested: BASELINE_PROFILE.density,
    refreshTargetHz: BASELINE_PROFILE.refreshHz,
    gpuMode: 'host',
    graphicsTransportRequested: BASELINE_PROFILE.glTransport,
    guestAngleRequested: true,
    vulkanRequested: true,
    glesCompatibilityExposure: 196610,
    angleDisabledFeatures: BASELINE_PROFILE.angleDisabledFeatures,
    moltenVK: { synchronousQueueSubmits: false, maxActiveMetalCommandBuffersPerQueue: 64, fastMath: true },
    asg: {
      writeBufferSize: BASELINE_PROFILE.asgWriteBufferSize,
      writeStepSize: BASELINE_PROFILE.asgWriteStepSize,
      dataRingSize: BASELINE_PROFILE.asgDataRingSize,
      drawFlushInterval
    },
    audioEnabled: true,
    audioBackend: 'coreaudio',
    deviceFrame: false,
    snapshotsRequired: false,
    bootClass,
    observedDisplay: display,
    observedDensity: density
  };
  writeJSON(path.join(captureDir, 'runtime-state.json'), state);
  return state;
}

async function startBaselineControl(ramMB = BASELINE_PROFILE.ramMB, controlProfileId = BASELINE_PROFILE.id, drawFlushInterval = BASELINE_PROFILE.drawFlushInterval, embeddedControl = false) {
  const preAudit = runtimeProcessAudit();
  const hasEmulator = preAudit.processes.some(item => item.kind === 'ANDROID_EMULATOR');
  if (!hasEmulator) {
    const staleSamplers = preAudit.processes.filter(item => item.kind === 'TFTMAC_SAMPLER');
    for (const sampler of staleSamplers) {
      try { process.kill(sampler.pid, 'SIGTERM'); } catch {}
    }
    if (staleSamplers.length) await sleep(250);
    for (const sampler of staleSamplers) {
      if (processAlive(sampler.pid)) {
        try { process.kill(sampler.pid, 'SIGKILL'); } catch {}
      }
    }
    cleanupTftmacAdbResidue();
    if (staleSamplers.length) await sleep(100);
  }
  singleRuntimePreflight();
  const runtime = discover();
  if (!isUnder(runtime.sdkRoot, EXTERNAL_ROOT)) throw new Error('Selected SDK is not on the required external runtime volume.');
  if (!runtime.requiredImagePresent) throw new Error(`Required official Play image is missing: ${runtime.requiredImagePath}`);
  if (!runtime.avdIni || !runtime.avdConfig || !runtime.avdDir) throw new Error(`Required official Play AVD ${AVD_NAME} was not found.`);
  ensureDir(STATE_ROOT); ensureDir(CAPTURE_ROOT); ensureDir(DIAGNOSTICS_ROOT);
  const prepared = prepareBaselineAVD(runtime, drawFlushInterval);
  const windowFit = embeddedControl ? { prepared: false, reason: 'HIDDEN_EMBEDDED_CONTROL' } : prepareEmulatorWindowFit(runtime, BASELINE_PROFILE.width, BASELINE_PROFILE.height);
  const sessionId = `${new Date().toISOString().replace(/[:.]/g, '-')}-${crypto.randomUUID()}`;
  const captureDir = path.join(CAPTURE_ROOT, sessionId);
  for (const d of [captureDir, path.join(captureDir, 'surfaceflinger'), path.join(captureDir, 'gfxinfo')]) ensureDir(d);
  for (const name of ['clock-sync.jsonl', 'markers.jsonl', 'logcat.raw.txt', 'logcat.filtered.txt', 'host-process.csv', 'host-process.jsonl', 'host-memory.csv', 'host-memory.jsonl']) fs.closeSync(fs.openSync(path.join(captureDir, name), 'a'));
  appendJSONL(path.join(captureDir, 'host-events.jsonl'), { utc: nowISO(), host_mono_ns: monoNs().toString(), event: 'LOGGER_INITIALIZED', sessionId, profile: controlProfileId });
  const session = {
    schema: 1, sessionId, startedUTC: nowISO(), endedUTC: null,
    hostStartMonoNs: monoNs().toString(), hostEndMonoNs: null, captureState: 'CAPTURING',
    workloadLabel: controlProfileId, appCommit: currentGitSha(), runtimeConfig: controlProfileId,
    packageName: PACKAGE, packageUpdatedDuringSession: false, packageAuthorityVerified: false, packageCurrentObservedAt: null,
    matchEntryObserved: false, combatObserved: false
  };
  writeJSON(path.join(captureDir, 'session.json'), session);
  const samplerPid = startSampler(runtime, captureDir, sessionId);
  appendJSONL(path.join(captureDir, 'host-events.jsonl'), { utc: nowISO(), event: 'SAMPLER_STARTED', pid: samplerPid });
  await sleep(350);
  if (!processAlive(samplerPid)) throw new Error(`LOGGER_START_FAILED: sampler PID ${samplerPid} did not remain alive.`);
  let emulatorPid = null;
  try {
    adbServer(runtime);
    const launcherPid = startBaselineEmulator(runtime, captureDir, ramMB, controlProfileId, embeddedControl);
    await waitForBoot(runtime);
    const observedEmulator = runtimeProcessAudit().processes.find(item => item.kind === 'ANDROID_EMULATOR' && item.command.includes(`-port ${EMULATOR_PORT}`));
    if (!observedEmulator) throw new Error(`EMULATOR_PID_NOT_OBSERVED_AFTER_OPEN: console port ${EMULATOR_PORT}`);
    emulatorPid = observedEmulator.pid;
    const guestUnlock = wakeGuestScreen(runtime, captureDir);
    const fullscreenPolicy = prepareGuestFullscreenPolicy(runtime);
    const clockPreflight = await ensureGuestClock(runtime, captureDir);
    const runtimeObserved = baselineRuntimeState(runtime, captureDir, prepared, 'COLD', ramMB, controlProfileId, drawFlushInterval);
    const pkg = packageState(runtime, captureDir, false);
    const renderer = rendererState(runtime, captureDir);
    const state = {
      schema: 1, sessionId, captureDir, samplerPid, emulatorPid, launcherPid, reusedRunningEmulator: false,
      sdkRoot: runtime.sdkRoot, avdHome: runtime.avdHome, startedUTC: session.startedUTC,
      packageState: pkg.state, controlProfile: controlProfileId, baselineConfigBackupPath: prepared.backupPath, embeddedControl
    };
    writeJSON(CONTROL_STATE, state);
    return { ...state, package: pkg, clockPreflight, runtime: runtimeObserved, renderer, next: pkg.state === 'MISSING' ? 'run play-action to install official TFT from Google Play' : 'run play-action to verify/update official TFT, then launch-game' };
  } catch (error) {
    if (processAlive(samplerPid)) { try { process.kill(samplerPid, 'SIGTERM'); } catch {} }
    try { adb(runtime, ['emu', 'kill'], { allowFailure: true, timeout: 10000 }); } catch {}
    restoreBaselineAVD(runtime);
    throw error;
  }
}

async function startControl() {
  const singleRuntime = singleRuntimePreflight();
  const runtime = discover();
  if (!isUnder(runtime.sdkRoot, EXTERNAL_ROOT)) throw new Error('Selected SDK is not on the required external runtime volume.');
  if (!runtime.requiredImagePresent) throw new Error(`Required official Play image is missing: ${runtime.requiredImagePath}`);
  if (!runtime.avdIni || !runtime.avdConfig) throw new Error(`Required AVD ${AVD_NAME} was not found. A clean AVD must be created from the installed official image before launch.`);
  if (!isUnder(runtime.avdDir, EXTERNAL_ROOT)) throw new Error('Selected AVD is not on the required external runtime volume.');
  ensureDir(STATE_ROOT); ensureDir(CAPTURE_ROOT); ensureDir(DIAGNOSTICS_ROOT);
  const windowFit = prepareEmulatorWindowFit(runtime, PLAY_DISPLAY_WIDTH, PLAY_DISPLAY_HEIGHT);
  const sessionId = `${new Date().toISOString().replace(/[:.]/g, '-')}-${crypto.randomUUID()}`;
  const captureDir = path.join(CAPTURE_ROOT, sessionId);
  for (const d of [captureDir, path.join(captureDir, 'surfaceflinger'), path.join(captureDir, 'gfxinfo')]) ensureDir(d);
  for (const name of ['clock-sync.jsonl', 'markers.jsonl', 'logcat.raw.txt', 'logcat.filtered.txt', 'host-process.csv', 'host-process.jsonl', 'host-memory.csv', 'host-memory.jsonl']) {
    fs.closeSync(fs.openSync(path.join(captureDir, name), 'a'));
  }
  appendJSONL(path.join(captureDir, 'host-events.jsonl'), { utc: nowISO(), host_mono_ns: monoNs().toString(), event: 'LOGGER_INITIALIZED', sessionId });
  const session = {
    schema: 1, sessionId, startedUTC: nowISO(), endedUTC: null,
    hostStartMonoNs: monoNs().toString(), hostEndMonoNs: null, captureState: 'CAPTURING',
    workloadLabel: 'first-direct-play-control', appCommit: currentGitSha(), runtimeConfig: 'control_stock_direct_v0',
    packageName: PACKAGE, packageUpdatedDuringSession: false, packageAuthorityVerified: false, packageCurrentObservedAt: null,
    matchEntryObserved: false, combatObserved: false
  };
  writeJSON(path.join(captureDir, 'session.json'), session);
  const samplerPid = startSampler(runtime, captureDir, sessionId);
  appendJSONL(path.join(captureDir, 'host-events.jsonl'), { utc: nowISO(), event: 'SAMPLER_STARTED', pid: samplerPid });
  await sleep(350);
  if (!processAlive(samplerPid)) throw new Error(`LOGGER_START_FAILED: sampler PID ${samplerPid} did not remain alive.`);

  adbServer(runtime);
  const reusedRunningEmulator = deviceReady(runtime);
  const emulatorPid = reusedRunningEmulator ? null : startEmulator(runtime, captureDir);
  await waitForBoot(runtime);
  const guestUnlock = wakeGuestScreen(runtime, captureDir);
  const fullscreenPolicy = prepareGuestFullscreenPolicy(runtime);
  const clockPreflight = await ensureGuestClock(runtime, captureDir);
  runtimeState(runtime, captureDir, reusedRunningEmulator ? 'WARM' : 'COLD');
  const pkg = packageState(runtime, captureDir, false);
  rendererState(runtime, captureDir);
  const state = { schema: 1, sessionId, captureDir, samplerPid, emulatorPid, reusedRunningEmulator, sdkRoot: runtime.sdkRoot, avdHome: runtime.avdHome, startedUTC: session.startedUTC, packageState: pkg.state };
  writeJSON(CONTROL_STATE, state);
  return { ...state, package: pkg, clockPreflight, next: pkg.state === 'MISSING' ? 'run play-action to install official TFT from Google Play' : 'run play-action to verify/update official TFT, then launch-game' };
}

function parseBounds(text) {
  const m = text.match(/bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/);
  if (!m) return null;
  return { x: Math.round((Number(m[1]) + Number(m[3])) / 2), y: Math.round((Number(m[2]) + Number(m[4])) / 2) };
}

function dumpUI(runtime) {
  adb(runtime, ['shell', 'uiautomator', 'dump', '/sdcard/tftmac-window.xml'], { allowFailure: true, timeout: 30000 });
  return adb(runtime, ['shell', 'cat', '/sdcard/tftmac-window.xml'], { allowFailure: true, timeout: 30000 }).stdout;
}

function findNodeByText(xml, wanted) {
  const nodes = xml.match(/<node\b[^>]*\/>/g) ?? [];
  for (const node of nodes) {
    const text = node.match(/text="([^"]*)"/)?.[1] ?? '';
    const desc = node.match(/content-desc="([^"]*)"/)?.[1] ?? '';
    if (wanted.some(rx => rx.test(text) || rx.test(desc))) return { node, text, desc, bounds: parseBounds(node) };
  }
  return null;
}

async function playAction() {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  const captureDir = state?.captureDir ?? null;
  await waitForBoot(runtime, 60000);
  await ensureGuestClock(runtime, captureDir);
  adb(runtime, ['shell', 'am', 'start', '-a', 'android.intent.action.VIEW', '-d', `market://details?id=${PACKAGE}`], { allowFailure: true });
  await sleep(3500);
  const xml = dumpUI(runtime);
  if (captureDir) fs.writeFileSync(path.join(captureDir, 'google-play-ui.xml'), xml);
  const auth = findNodeByText(xml, [/sign in/i, /add account/i, /verify.*account/i, /choose an account/i, /google account/i]);
  if (auth) return { action: 'AUTH_REQUIRED', provider: 'Google', evidence: { text: auth.text, contentDescription: auth.desc }, instruction: 'Authenticate directly in the Google Play UI, then rerun play-action.' };
  const update = findNodeByText(xml, [/^Update$/i]);
  const install = findNodeByText(xml, [/^Install$/i]);
  const open = findNodeByText(xml, [/^Open$/i, /^Play$/i]);
  const target = update ?? install;
  if (target?.bounds) {
    adb(runtime, ['shell', 'input', 'tap', String(target.bounds.x), String(target.bounds.y)]);
    if (captureDir) {
      appendJSONL(path.join(captureDir, 'markers.jsonl'), { utc: nowISO(), host_mono_ns: monoNs().toString(), event: update ? 'PACKAGE_UPDATE' : 'PACKAGE_INSTALL', source: 'Google Play UI' });
      const session = readJSON(path.join(captureDir, 'session.json'), {});
      session.packageUpdatedDuringSession = true;
      writeJSON(path.join(captureDir, 'session.json'), session);
    }
    return { action: update ? 'UPDATE_STARTED' : 'INSTALL_STARTED', instruction: 'Google Play operation started; poll play-action until CURRENT_OBSERVED.' };
  }
  const progress = findNodeByText(xml, [/pending/i, /installing/i, /downloading/i, /%$/i, /^Cancel$/i]);
  if (progress) {
    return { action: 'INSTALL_OR_UPDATE_IN_PROGRESS', evidence: { text: progress.text, contentDescription: progress.desc } };
  }
  const pkg = packageState(runtime, captureDir);
  if (pkg.state !== 'MISSING' && open) {
    if (!/^\d+$/.test(String(pkg.versionCode ?? '')) || Number(pkg.versionCode) <= 0) {
      return { action: 'PACKAGE_VERSION_INVALID', package: pkg, reason: 'Google Play-installed TFT must expose a positive Riot versionCode.' };
    }
    if (pkg.signerCertificateSHA256 && pkg.signerCertificateSHA256 !== RIOT_SIGNER_SHA256) {
      return { action: 'PACKAGE_SIGNER_MISMATCH', package: pkg, expectedSignerCertificateSHA256: RIOT_SIGNER_SHA256 };
    }
    if (pkg.installerPackage !== 'com.android.vending') {
      if (captureDir) appendJSONL(path.join(captureDir, 'host-events.jsonl'), {
        utc: nowISO(), host_mono_ns: monoNs().toString(), event: 'PACKAGE_AUTHORITY_RESET',
        observedInstaller: pkg.installerPackage ?? null, versionName: pkg.versionName ?? null, versionCode: pkg.versionCode ?? null,
        signerCertificateSHA256: pkg.signerCertificateSHA256 ?? null
      });
      const removed = adb(runtime, ['shell', 'pm', 'uninstall', PACKAGE], { allowFailure: true, timeout: 60000 });
      if (!/Success/i.test(`${removed.stdout}${removed.stderr}`)) {
        return { action: 'AUTHORITY_UNRESOLVED', package: pkg, reason: `Existing package is not Google-Play-installed and could not be removed: ${removed.stderr || removed.stdout}` };
      }
      if (captureDir) writeJSON(path.join(captureDir, 'package-state.json'), { observedAt: nowISO(), packageName: PACKAGE, state: 'MISSING', apkPaths: [], authorityReset: true });
      await sleep(1500);
      return await playAction();
    }
    pkg.state = 'INSTALLED_CURRENT_OBSERVED';
    if (captureDir) {
      writeJSON(path.join(captureDir, 'package-state.json'), pkg);
      const session = readJSON(path.join(captureDir, 'session.json'), {});
      session.packageAuthorityVerified = true;
      session.packageCurrentObservedAt = nowISO();
      writeJSON(path.join(captureDir, 'session.json'), session);
    }
    return { action: 'CURRENT_OBSERVED', package: pkg, authority: 'Google Play listing shows Open/Play and no Update action' };
  }
  return { action: 'PLAY_STATE_UNRESOLVED', package: pkg, uiSample: xml.slice(0, 2000) };
}

async function playProbe() {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  const captureDir = state?.captureDir ?? null;
  await waitForBoot(runtime, 60000);
  await ensureGuestClock(runtime, captureDir);
  const shell = (args, timeout = 30000) => adb(runtime, ['shell', ...args], { allowFailure: true, timeout });
  const installedBefore = shell(['pm', 'path', PLAY_PROBE_PACKAGE]).stdout.includes('package:');
  if (installedBefore) return { action: 'PROBE_ALREADY_INSTALLED', packageName: PLAY_PROBE_PACKAGE };
  shell(['am', 'start', '-a', 'android.intent.action.VIEW', '-d', `market://details?id=${PLAY_PROBE_PACKAGE}`]);
  await sleep(3500);
  let xml = dumpUI(runtime);
  const install = findNodeByText(xml, [/^Install$/i]);
  if (!install?.bounds) {
    return { action: 'PROBE_INSTALL_BUTTON_NOT_FOUND', packageName: PLAY_PROBE_PACKAGE, uiTextSample: xml.match(/text="([^"]+)"/g)?.slice(0, 60) ?? [] };
  }
  shell(['input', 'tap', String(install.bounds.x), String(install.bounds.y)]);
  const startedAt = Date.now();
  let installed = false;
  while (Date.now() - startedAt < 45000) {
    await sleep(1500);
    if (shell(['pm', 'path', PLAY_PROBE_PACKAGE], 10000).stdout.includes('package:')) { installed = true; break; }
  }
  xml = dumpUI(runtime);
  const logcat = command(runtime.adb, ['-P', ADB_PORT, '-s', SERIAL, 'logcat', '-d', '-v', 'threadtime', '-t', '6000'], { env: runtime.env, allowFailure: true, timeout: 30000, maxBuffer: 64 * 1024 * 1024 }).stdout;
  const relevant = logcat.split(/\r?\n/).filter(line => line.includes(PLAY_PROBE_PACKAGE) || /statusCode:1010|Delivery received non-OK response|Account .* from AppState|estimated size required|INSTALL_ERROR|DOWNLOAD_PENDING/i.test(line)).slice(-500);
  const result = {
    action: installed ? 'PROBE_INSTALLED' : 'PROBE_FAILED',
    packageName: PLAY_PROBE_PACKAGE,
    installed,
    packagePath: shell(['pm', 'path', PLAY_PROBE_PACKAGE]).stdout.trim() || null,
    uiTextSample: xml.match(/text="([^"]+)"/g)?.slice(0, 60) ?? [],
    relevantLogLines: relevant
  };
  if (captureDir) writeJSON(path.join(captureDir, 'google-play-third-party-probe.json'), result);
  return result;
}

function launchFailureProbe() {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  if (!deviceReady(runtime)) throw new Error('No active Android device for launch failure probe.');
  const logcat = command(runtime.adb, ['-P', ADB_PORT, '-s', SERIAL, 'logcat', '-d', '-v', 'threadtime', '-t', '12000'], { env: runtime.env, allowFailure: true, timeout: 30000, maxBuffer: 96 * 1024 * 1024 }).stdout;
  const lines = logcat.split(/\r?\n/);
  const relevant = lines.filter(line => /teamfighttactics|GameActivity|SplashActivity|AndroidRuntime|FATAL EXCEPTION|Fatal signal|DEBUG\s*:|crash_dump|tombstone|ActivityManager.*(died|killing|crash)|Process .*teamfighttactics|libUnreal|libUE|SIG(SEGV|ABRT|BUS|ILL)|linker|dlopen failed|UnsatisfiedLinkError|abort message|ANR in|am_crash/i.test(line)).slice(-1400);
  const result = { observedAt: nowISO(), sessionId: state?.sessionId ?? null, lines: relevant };
  if (state?.captureDir) writeJSON(path.join(state.captureDir, 'launch-failure-probe.json'), result);
  return result;
}

function glesCapabilityProbe() {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  if (!deviceReady(runtime)) throw new Error('No active Android device for GLES capability probe.');
  const shell = (args, timeout = 30000) => adb(runtime, ['shell', ...args], { allowFailure: true, timeout });
  const sf = shell(['dumpsys', 'SurfaceFlinger']).stdout;
  const gfx = shell(['dumpsys', 'gfxinfo', PACKAGE]).stdout;
  const props = {};
  for (const key of ['ro.opengles.version','ro.hardware.egl','ro.hardware.vulkan','ro.boot.hardwareegl','ro.boot.hardware.vulkan','ro.boot.hardware.gltransport','ro.boot.qemu.gltransport.name']) {
    props[key] = shell(['getprop', key]).stdout.trim() || null;
  }
  const logcat = command(runtime.adb, ['-P', ADB_PORT, '-s', SERIAL, 'logcat', '-d', '-v', 'threadtime', '-t', '4000'], { env: runtime.env, allowFailure: true, timeout: 30000, maxBuffer: 64 * 1024 * 1024 }).stdout;
  const relevant = logcat.split(/\r?\n/).filter(line => /teamfighttactics|GameActivity|Unreal|OpenGL ES|GLES|GL_VERSION|ANGLE|EGL|unable to run on this device|not supported|ES 3\.2|ES3_2|FeatureLevel/i.test(line)).slice(-500);
  const result = {
    observedAt: nowISO(),
    sessionId: state?.sessionId ?? null,
    properties: props,
    surfaceFlingerGraphics: sf.split(/\r?\n/).filter(line => /GLES|GL_VERSION|OpenGL|EGL|ANGLE|Vulkan|renderer/i.test(line)).slice(0, 240),
    gfxInfoGraphics: gfx.split(/\r?\n/).filter(line => /GLES|OpenGL|EGL|renderer|driver|version/i.test(line)).slice(0, 160),
    relevantLogLines: relevant
  };
  if (state?.captureDir) writeJSON(path.join(state.captureDir, 'gles-capability-probe.json'), result);
  return result;
}

function latestMemoryPressure(captureDir) {
  const rows = readJSONL(path.join(captureDir, 'host-memory.jsonl'));
  const row = rows.at(-1) ?? null;
  if (!row) return null;
  const gib = 1024 ** 3;
  return {
    utc: row.utc ?? null,
    hostMonoNs: row.host_mono_ns ?? null,
    hostAvailableGiB: Number(row.host_available_bytes) / gib,
    hostCompressedGiB: Number(row.host_compressed_bytes) / gib,
    hostSwapUsedGiB: Number(row.host_swap_used_bytes) / gib,
    guestAvailableGiB: Number(row.guest_available_bytes) / gib,
    pageoutCount: Number(row.pageout_count)
  };
}

async function preplayOptimize() {
  const state = readJSON(CONTROL_STATE);
  if (!state?.captureDir) throw new Error('No active direct-control session. Run start first.');
  const loggerGate = await loggerHealth();
  if (!loggerGate.healthy) throw new Error(`LOGGER_REQUIRED_BEFORE_PREPLAY_OPTIMIZE: ${JSON.stringify(loggerGate)}`);
  const before = latestMemoryPressure(state.captureDir);
  if (!before) throw new Error('PREPLAY_MEMORY_SAMPLE_UNAVAILABLE');
  const compressionThresholdGiB = 3.75;
  const availableThresholdGiB = 4.75;
  const shouldRefresh = before.hostCompressedGiB >= compressionThresholdGiB || before.hostAvailableGiB <= availableThresholdGiB;
  let restart = null;
  if (shouldRefresh) {
    restart = await restartGame();
    await sleep(8000);
  }
  const after = latestMemoryPressure(state.captureDir);
  const result = {
    action: shouldRefresh ? 'PREPLAY_TFT_REFRESHED' : 'PREPLAY_NO_REFRESH_NEEDED',
    thresholds: { compressionGiB: compressionThresholdGiB, hostAvailableGiB: availableThresholdGiB },
    reason: shouldRefresh
      ? `Host pressure exceeded hygiene threshold: compressed=${before.hostCompressedGiB.toFixed(2)} GiB, available=${before.hostAvailableGiB.toFixed(2)} GiB.`
      : `Host pressure within hygiene envelope: compressed=${before.hostCompressedGiB.toFixed(2)} GiB, available=${before.hostAvailableGiB.toFixed(2)} GiB.`,
    before,
    after,
    delta: after ? {
      hostAvailableGiB: after.hostAvailableGiB - before.hostAvailableGiB,
      hostCompressedGiB: after.hostCompressedGiB - before.hostCompressedGiB,
      hostSwapUsedGiB: after.hostSwapUsedGiB - before.hostSwapUsedGiB,
      guestAvailableGiB: after.guestAvailableGiB - before.guestAvailableGiB
    } : null,
    restart,
    loggerGate
  };
  appendJSONL(path.join(state.captureDir, 'host-events.jsonl'), {
    utc: nowISO(), host_mono_ns: monoNs().toString(), event: 'PREPLAY_MEMORY_HYGIENE',
    decision: result.action, thresholds: result.thresholds, before, after, delta: result.delta
  });
  writeJSON(path.join(state.captureDir, 'preplay-memory-hygiene.json'), result);
  return result;
}

async function restartGame() {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  if (!state?.captureDir) throw new Error('No active direct-control session. Run start first.');
  const loggerGate = await loggerHealth();
  if (!loggerGate.healthy) throw new Error(`LOGGER_REQUIRED_BEFORE_TFT_RESTART: ${JSON.stringify(loggerGate)}`);
  const oldPid = adb(runtime, ['shell', 'pidof', PACKAGE], { allowFailure: true, timeout: 10000 }).stdout.trim() || null;
  appendJSONL(path.join(state.captureDir, 'host-events.jsonl'), { utc: nowISO(), host_mono_ns: monoNs().toString(), event: 'TFT_APP_RESTART_REQUESTED', oldPid });
  adb(runtime, ['shell', 'am', 'force-stop', PACKAGE], { allowFailure: true, timeout: 15000 });
  const deadline = Date.now() + 15000;
  while (Date.now() < deadline) {
    const pid = adb(runtime, ['shell', 'pidof', PACKAGE], { allowFailure: true, timeout: 10000 }).stdout.trim();
    if (!pid) break;
    await sleep(250);
  }
  await sleep(500);
  const result = await launchGame();
  appendJSONL(path.join(state.captureDir, 'host-events.jsonl'), { utc: nowISO(), host_mono_ns: monoNs().toString(), event: 'TFT_APP_RESTART_COMPLETE', oldPid, newPid: result.pid ?? null, action: result.action });
  return { action: 'TFT_APP_RESTARTED', oldPid, newPid: result.pid ?? null, launch: result, loggerGate };
}

async function launchGame() {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  if (!state?.captureDir) throw new Error('No active direct-control session. Run start first.');
  const captureDir = state.captureDir;
  const loggerGate = await loggerHealth();
  if (!loggerGate.healthy) throw new Error(`LOGGER_REQUIRED_BEFORE_TFT_LAUNCH: ${JSON.stringify(loggerGate)}`);
  await waitForBoot(runtime, 60000);
  await ensureGuestUnlocked(runtime, captureDir);
  await ensureGuestClock(runtime, captureDir);
  const pkg = packageState(runtime, captureDir, false);
  if (pkg.state === 'MISSING') throw new Error('Official TFT package is not installed. Run play-action first.');
  rendererState(runtime, captureDir);
  adb(runtime, ['shell', 'dumpsys', 'gfxinfo', PACKAGE, 'reset'], { allowFailure: true, timeout: 30000 });
  appendJSONL(path.join(captureDir, 'host-events.jsonl'), { utc: nowISO(), host_mono_ns: monoNs().toString(), event: 'GFXINFO_RESET_BEFORE_TFT_LAUNCH' });
  const resolvedRaw = adb(runtime, ['shell', 'cmd', 'package', 'resolve-activity', '--brief', PACKAGE], { allowFailure: true }).stdout.trim();
  const resolved = resolvedComponent(resolvedRaw);
  const verifiedSplashActivity = `${PACKAGE}/com.epicgames.unreal.SplashActivity`;
  const verifiedGameActivity = `${PACKAGE}/com.epicgames.unreal.GameActivity`;
  const launchCandidates = [...new Set([resolved, verifiedSplashActivity, verifiedGameActivity].filter(Boolean))];
  let launchResult = null;
  let launchedComponent = null;
  for (const component of launchCandidates) {
    const attempt = adb(runtime, ['shell', 'am', 'start', '--user', '0', '-n', component], { allowFailure: true, timeout: 10000 });
    appendJSONL(path.join(captureDir, 'host-events.jsonl'), {
      utc: nowISO(), host_mono_ns: monoNs().toString(), event: 'TFT_LAUNCH_ATTEMPT', component,
      status: attempt.status, stdout: attempt.stdout.trim().slice(0, 1000), stderr: attempt.stderr.trim().slice(0, 1000)
    });
    if (attempt.status === 0 && !/Error:|does not exist|not exported|unable to resolve/i.test(`${attempt.stdout}\n${attempt.stderr}`)) {
      launchResult = attempt;
      launchedComponent = component;
      break;
    }
    launchResult = attempt;
  }
  appendJSONL(path.join(captureDir, 'markers.jsonl'), { utc: nowISO(), host_mono_ns: monoNs().toString(), event: 'TFT_LAUNCH', resolvedActivity: resolved ?? null, launchedComponent });
  const deadline = Date.now() + 45000;
  let pid = '';
  while (Date.now() < deadline) {
    pid = adb(runtime, ['shell', 'pidof', PACKAGE], { allowFailure: true }).stdout.trim();
    if (pid) break;
    await sleep(1000);
  }
  if (!pid) throw new Error(`TFT did not remain running. component=${resolved ?? 'unresolved'} launch=${(launchResult.stderr || launchResult.stdout || '').trim()}`);
  const sessionPath = path.join(captureDir, 'session.json');
  const launchSession = readJSON(sessionPath, {});
  launchSession.lastTftLaunchPid = pid;
  launchSession.lastTftLaunchObservedAt = nowISO();
  writeJSON(sessionPath, launchSession);
  appendJSONL(path.join(captureDir, 'host-events.jsonl'), { utc: nowISO(), host_mono_ns: monoNs().toString(), event: 'TFT_PROCESS_RUNNING', pid });
  await sleep(8000);
  const renderer = rendererState(runtime, captureDir);
  const xml = dumpUI(runtime);
  fs.writeFileSync(path.join(captureDir, 'tft-ui.xml'), xml);
  const screencap = spawnSync(runtime.adb, ['-P', ADB_PORT, '-s', SERIAL, 'exec-out', 'screencap', '-p'], { env: runtime.env, encoding: null, maxBuffer: 32 * 1024 * 1024, timeout: 30000 });
  if (screencap.status === 0 && screencap.stdout) fs.writeFileSync(path.join(captureDir, 'tft-launch.png'), screencap.stdout);
  const riotAuth = findNodeByText(xml, [/sign in/i, /log in/i, /riot account/i]);
  return { action: riotAuth ? 'RIOT_AUTH_POSSIBLE' : 'TFT_RUNNING', pid, resolvedActivity: resolved || null, renderer, riotAuthEvidence: riotAuth ? { text: riotAuth.text, contentDescription: riotAuth.desc } : null, captureDir, loggerGate };
}

function processAlive(pid) { if (!pid) return false; try { process.kill(pid, 0); return true; } catch { return false; } }

function loggerGameplayGate(state = readJSON(CONTROL_STATE)) {
  if (!state?.captureDir) return { ready: false, reason: 'NO_ACTIVE_CAPTURE' };
  const snapshot = telemetrySnapshot(state.captureDir);
  const now = Date.now();
  const ageMs = rel => snapshot[rel]?.mtimeMs ? Math.max(0, now - snapshot[rel].mtimeMs) : null;
  const processAgeMs = ageMs('host-process.jsonl');
  const memoryAgeMs = ageMs('host-memory.jsonl');
  const logBytes = snapshot['logcat.raw.txt']?.bytes ?? 0;
  const logcatAgeMs = ageMs('logcat.raw.txt');
  const samplerAlive = processAlive(state.samplerPid);
  const processFresh = processAgeMs !== null && processAgeMs <= 10000;
  const memoryFresh = memoryAgeMs !== null && memoryAgeMs <= 10000;
  const logcatPresent = logBytes > 0;
  const logcatFresh = logcatAgeMs !== null && logcatAgeMs <= 15000;
  return {
    ready: samplerAlive && processFresh && memoryFresh && logcatPresent && logcatFresh,
    samplerAlive,
    processFresh,
    memoryFresh,
    logcatPresent,
    logcatFresh,
    processAgeMs,
    memoryAgeMs,
    logcatAgeMs,
    logcatBytes: logBytes,
    sessionId: state.sessionId,
    captureDir: state.captureDir
  };
}

function gameSettings(graphicsPreset = 'UNKNOWN', fpsCap = 'UNKNOWN', performanceMode = 'UNKNOWN') {
  const state = readJSON(CONTROL_STATE);
  if (!state?.captureDir) throw new Error('No active direct-control session.');
  const presetMap = new Map([
    ['low','Low'], ['medium','Medium'], ['high','High'], ['ultra-high','Ultra High'], ['ultrahigh','Ultra High'], ['ultra high','Ultra High'], ['unknown','UNKNOWN']
  ]);
  const preset = presetMap.get(String(graphicsPreset).trim().toLowerCase());
  const fpsRaw = String(fpsCap).trim().toLowerCase();
  const fps = fpsRaw === '30' ? '30' : fpsRaw === '60' ? '60' : ['none','no-cap','no cap','uncapped'].includes(fpsRaw) ? 'None' : fpsRaw === 'unknown' ? 'UNKNOWN' : null;
  const perfRaw = String(performanceMode).trim().toLowerCase();
  const perf = ['on','enabled','true','1'].includes(perfRaw) ? 'ON' : ['off','disabled','false','0'].includes(perfRaw) ? 'OFF' : perfRaw === 'unknown' ? 'UNKNOWN' : null;
  if (!preset) throw new Error(`GAME_SETTINGS_PRESET_INVALID: ${graphicsPreset}`);
  if (!fps) throw new Error(`GAME_SETTINGS_FPS_INVALID: ${fpsCap}`);
  if (!perf) throw new Error(`GAME_SETTINGS_PERFORMANCE_MODE_INVALID: ${performanceMode}`);
  const event = {
    utc: nowISO(), host_mono_ns: monoNs().toString(), event: 'GAME_SETTINGS', source: 'user-observation',
    graphicsPreset: preset, fpsCap: fps, performanceModeBeta: perf
  };
  appendJSONL(path.join(state.captureDir, 'markers.jsonl'), event);
  const sessionPath = path.join(state.captureDir, 'session.json');
  const session = readJSON(sessionPath, {});
  session.currentGameSettings = { graphicsPreset: preset, fpsCap: fps, performanceModeBeta: perf, observedAt: event.utc };
  writeJSON(sessionPath, session);
  return { action: 'GAME_SETTINGS_RECORDED', captureDir: state.captureDir, settings: event };
}

function qualityReport(summary = 'Gameplay quality improved', comparison = 'previous match') {
  const state = readJSON(CONTROL_STATE);
  if (!state?.captureDir) throw new Error('No active direct-control session.');
  const markersPath = path.join(state.captureDir, 'markers.jsonl');
  const markers = readJSONL(markersPath);
  const matchOrdinal = Math.max(1, markers.filter(row => row.event === 'MATCH_RESULT').length);
  const event = {
    utc: nowISO(),
    host_mono_ns: monoNs().toString(),
    event: 'USER_QUALITY_REPORT',
    source: 'user-observation',
    matchOrdinal,
    summary: String(summary),
    comparison: String(comparison)
  };
  appendJSONL(markersPath, event);
  return { action: 'USER_QUALITY_REPORT_RECORDED', captureDir: state.captureDir, report: event };
}

function matchBoundaryProbe() {
  const state = readJSON(CONTROL_STATE);
  if (!state?.captureDir) throw new Error('No active direct-control session.');
  const file = path.join(state.captureDir, 'logcat.raw.txt');
  if (!exists(file)) return { action: 'MATCH_BOUNDARY_PROBE', candidates: [], reason: 'logcat missing' };
  const stat = fs.statSync(file);
  const maxBytes = 32 * 1024 * 1024;
  const start = Math.max(0, stat.size - maxBytes);
  const length = stat.size - start;
  const fd = fs.openSync(file, 'r');
  let text = '';
  try {
    const buffer = Buffer.alloc(length);
    fs.readSync(fd, buffer, 0, length, start);
    text = buffer.toString('utf8');
  } finally {
    fs.closeSync(fd);
  }
  const lifecycle = /(match|game.?start|game.?end|round|stage|combat|battle|loading|lobby|queue|reconnect|player.*ready|activity.*resum|foreground|session)/i;
  const owner = /(teamfighttactics|riotgames|unreal|gameactivity|tft)/i;
  const candidates = text.split(/\r?\n/)
    .filter(line => owner.test(line) && lifecycle.test(line))
    .slice(-800);
  const result = { action: 'MATCH_BOUNDARY_PROBE', observedAt: nowISO(), bytesScanned: length, candidates };
  writeJSON(path.join(state.captureDir, 'match-boundary-probe.json'), result);
  return result;
}

function analyzeApproximateLatestMatch() {
  const state = readJSON(CONTROL_STATE);
  if (!state?.captureDir) throw new Error('No active direct-control session.');
  const captureDir = state.captureDir;
  const markers = readJSONL(path.join(captureDir, 'markers.jsonl'));
  const hostEvents = readJSONL(path.join(captureDir, 'host-events.jsonl'));
  const result = [...markers].reverse().find(row => row.event === 'MATCH_RESULT' && Number(row.matchOrdinal ?? 0) >= 2);
  if (!result) throw new Error('No later MATCH_RESULT is available for approximate analysis.');
  const endHostNs = Number(result.host_mono_ns);
  const startEvent = [...hostEvents].reverse().find(row => row.event === 'TFT_APP_RESTART_COMPLETE' && Number(row.host_mono_ns) < endHostNs);
  if (!startEvent) throw new Error('No TFT_APP_RESTART_COMPLETE boundary exists before the latest match result.');
  const startHostNs = Number(startEvent.host_mono_ns);
  if (!Number.isFinite(startHostNs) || !Number.isFinite(endHostNs) || endHostNs <= startHostNs) throw new Error('Approximate match boundary is invalid.');

  const processRows = readJSONL(path.join(captureDir, 'host-process.jsonl')).filter(row => {
    const mono = Number(row.host_mono_ns);
    return Number.isFinite(mono) && mono >= startHostNs && mono <= endHostNs;
  });
  const emulatorRows = processRows.filter(row => /qemu-system-aarch64|\/emulator(?:\s|$)/i.test(String(row.command ?? '')));
  const cpuPercent = summarizeNumbers(emulatorRows.map(row => Number(row.cpu_pct)));
  const rssMiB = summarizeNumbers(emulatorRows.map(row => Number(row.rss_kb) / 1024));

  const memoryRows = readJSONL(path.join(captureDir, 'host-memory.jsonl')).filter(row => {
    const mono = Number(row.host_mono_ns);
    return Number.isFinite(mono) && mono >= startHostNs && mono <= endHostNs;
  });
  const gib = 1024 ** 3;
  const hostAvailableGiB = summarizeNumbers(memoryRows.map(row => Number(row.host_available_bytes) / gib));
  const hostCompressedGiB = summarizeNumbers(memoryRows.map(row => Number(row.host_compressed_bytes) / gib));
  const hostSwapUsedGiB = summarizeNumbers(memoryRows.map(row => Number(row.host_swap_used_bytes) / gib));
  const guestAvailableGiB = summarizeNumbers(memoryRows.map(row => Number(row.guest_available_bytes) / gib));
  const pageouts = memoryRows.map(row => Number(row.pageout_count)).filter(Number.isFinite);
  const pageoutDelta = pageouts.length > 1 ? pageouts.at(-1) - pageouts[0] : null;

  const settings = [...markers].reverse().find(row => row.event === 'GAME_SETTINGS' && Number(row.host_mono_ns) <= endHostNs) ?? null;
  const qualityReports = markers.filter(row => row.event === 'USER_QUALITY_REPORT' && Number(row.matchOrdinal) === Number(result.matchOrdinal));
  const game1 = readJSON(path.join(captureDir, 'gameplay-analysis-match-1.json'), readJSON(path.join(captureDir, 'gameplay-analysis.json'), null));
  const delta = (candidate, baseline) => Number.isFinite(candidate) && Number.isFinite(baseline) ? candidate - baseline : null;
  const comparison = game1 ? {
    emulatorCpuMeanDeltaPctPoints: delta(cpuPercent.mean, game1.hostEmulator?.cpuPercent?.mean),
    emulatorCpuP95DeltaPctPoints: delta(cpuPercent.p95, game1.hostEmulator?.cpuPercent?.p95),
    emulatorRssMeanDeltaMiB: delta(rssMiB.mean, game1.hostEmulator?.rssMiB?.mean),
    emulatorRssP95DeltaMiB: delta(rssMiB.p95, game1.hostEmulator?.rssMiB?.p95),
    hostCompressedMeanDeltaGiB: delta(hostCompressedGiB.mean, game1.memory?.hostCompressedGiB?.mean),
    hostAvailableMeanDeltaGiB: delta(hostAvailableGiB.mean, game1.memory?.hostAvailableGiB?.mean),
    pageoutDeltaDifference: delta(pageoutDelta, game1.memory?.pageoutDelta)
  } : null;

  const analysis = {
    schema: 1,
    observedAt: nowISO(),
    sessionId: state.sessionId,
    matchOrdinal: Number(result.matchOrdinal ?? 2),
    placement: result.placement ?? null,
    result: result.result ?? null,
    boundaryAuthority: 'APP_RESTART_PROXY_NOT_MATCH_ENTRY',
    semanticValidForExactMatchTiming: false,
    startProxy: startEvent,
    matchResult: result,
    windowSeconds: (endHostNs - startHostNs) / 1e9,
    gameSettings: settings ? { graphicsPreset: settings.graphicsPreset, fpsCap: settings.fpsCap, performanceModeBeta: settings.performanceModeBeta, observedAt: settings.utc } : null,
    qualityReports,
    hostEmulator: { sampleCount: emulatorRows.length, cpuPercent, rssMiB },
    memory: { sampleCount: memoryRows.length, hostAvailableGiB, hostCompressedGiB, hostSwapUsedGiB, guestAvailableGiB, pageoutDelta },
    comparisonToGame1: comparison,
    caution: 'Start boundary is the TFT app-only restart, not a proven match-entry event. Use resource deltas as directional evidence only.'
  };
  writeJSON(path.join(captureDir, `gameplay-analysis-match-${analysis.matchOrdinal}-approx.json`), analysis);
  return analysis;
}

function ingestApproximateLatestMatch() {
  const analysis = analyzeApproximateLatestMatch();
  const captureDir = readJSON(CONTROL_STATE)?.captureDir;
  const databasePath = path.join(DIAGNOSTICS_ROOT, 'TFTMAC_PERFORMANCE_LAB.sqlite');
  const schemaPath = labSchemaPath();
  if (!schemaPath) throw new Error('TFTMAC performance-lab schema is unavailable.');
  ensureDir(DIAGNOSTICS_ROOT);
  const initialize = !exists(databasePath) || fs.statSync(databasePath).size === 0;
  const db = new DatabaseSync(databasePath);
  try {
    if (initialize) db.exec(fs.readFileSync(schemaPath, 'utf8'));
    db.exec('PRAGMA foreign_keys = ON;');
    const configId = BASELINE_PROFILE.id;
    const labSessionId = `${analysis.sessionId}-match-${analysis.matchOrdinal}-approx`;
    const packageInfo = readJSON(path.join(captureDir, 'package-state.json'), {});
    const packageFile = path.join(captureDir, 'package-state.json');
    const rendererFile = path.join(captureDir, 'renderer-state.json');
    const summaryText = analysis.qualityReports.map(row => row.summary).join(' | ') || 'No user quality report';
    db.exec('BEGIN IMMEDIATE;');
    try {
      db.prepare(`INSERT INTO sessions(
        id,runtime_config_id,started_utc,ended_utc,host_start_mono_ns,host_end_mono_ns,boot_class,workload_class,
        package_name,package_version_name,package_version_code,package_state_sha256,renderer_state_sha256,session_manifest_sha256,
        package_updated_during_session,capture_state,semantic_valid,invalid_reason,notes
      ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET ended_utc=excluded.ended_utc,host_end_mono_ns=excluded.host_end_mono_ns,
        capture_state=excluded.capture_state,semantic_valid=excluded.semantic_valid,invalid_reason=excluded.invalid_reason,notes=excluded.notes`)
        .run(labSessionId,configId,analysis.startProxy.utc,analysis.matchResult.utc,Number(analysis.startProxy.host_mono_ns),Number(analysis.matchResult.host_mono_ns),
          'WARM','MIXED',PACKAGE,packageInfo.versionName ?? null,packageInfo.versionCode ?? null,
          exists(packageFile) ? sha256File(packageFile) : null,exists(rendererFile) ? sha256File(rendererFile) : null,null,
          0,'PARTIAL',0,'Exact MATCH_ENTRY was not recorded; start boundary is TFT_APP_RESTART_COMPLETE.',
          `Match ${analysis.matchOrdinal} placement=${analysis.placement}; settings=${analysis.gameSettings?.graphicsPreset ?? 'UNKNOWN'}/${analysis.gameSettings?.fpsCap ?? 'UNKNOWN'}/performance-${analysis.gameSettings?.performanceModeBeta ?? 'UNKNOWN'}; user=${summaryText}`);

      db.prepare('DELETE FROM metrics WHERE session_id=?').run(labSessionId);
      const metric = db.prepare('INSERT INTO metrics(session_id,experiment_id,metric_scope,metric_name,metric_value,unit,source_artifact_id,semantic_valid,notes) VALUES(?,?,?,?,?,?,?,?,?)');
      const add = (scope,name,value,unit,valid=0,notes='Approximate restart-to-result window; exact match entry missing.') => { if (Number.isFinite(Number(value))) metric.run(labSessionId,null,scope,name,Number(value),unit,null,valid,notes); };
      add('MATCH','placement',analysis.placement,'rank',1,'Exact user-observed match result.');
      add('WINDOW','restart_to_result_duration',analysis.windowSeconds,'seconds');
      add('HOST_CPU','emulator_cpu_mean',analysis.hostEmulator.cpuPercent.mean,'percent');
      add('HOST_CPU','emulator_cpu_p95',analysis.hostEmulator.cpuPercent.p95,'percent');
      add('MEMORY','emulator_rss_mean',analysis.hostEmulator.rssMiB.mean,'MiB');
      add('MEMORY','emulator_rss_p95',analysis.hostEmulator.rssMiB.p95,'MiB');
      add('MEMORY','host_available_mean',analysis.memory.hostAvailableGiB.mean,'GiB');
      add('MEMORY','host_compressed_mean',analysis.memory.hostCompressedGiB.mean,'GiB');
      add('MEMORY','pageout_delta',analysis.memory.pageoutDelta,'pages');
      add('COMPARISON','host_compressed_mean_delta_vs_game1',analysis.comparisonToGame1?.hostCompressedMeanDeltaGiB,'GiB');
      add('COMPARISON','host_available_mean_delta_vs_game1',analysis.comparisonToGame1?.hostAvailableMeanDeltaGiB,'GiB');
      add('COMPARISON','pageout_delta_difference_vs_game1',analysis.comparisonToGame1?.pageoutDeltaDifference,'pages');

      const evidence = db.prepare('INSERT OR REPLACE INTO evidence(id,hypothesis_id,session_id,experiment_id,evidence_type,claim,relation,strength,source_artifact_id,created_at,notes) VALUES(?,?,?,?,?,?,?,?,?,?,?)');
      evidence.run(`ev_match_${analysis.matchOrdinal}_user_quality`,null,labSessionId,null,'CONFIG_OBSERVATION',summaryText,'NEUTRAL','MODERATE',null,nowISO(),'Direct user observation; subjective quality signal, not quantitative FPS evidence.');
      evidence.run(`ev_match_${analysis.matchOrdinal}_memory_direction`,'h_memory_pressure',labSessionId,null,'DIRECT_MEASUREMENT',
        `Approximate restart-to-result window had host compressed mean ${analysis.memory.hostCompressedGiB.mean?.toFixed(2)} GiB and pageout delta ${analysis.memory.pageoutDelta}; vs Game1 deltas were ${analysis.comparisonToGame1?.hostCompressedMeanDeltaGiB?.toFixed(2)} GiB compressed and ${analysis.comparisonToGame1?.pageoutDeltaDifference} pageouts while user reported better gameplay.`,
        'SUPPORTS','WEAK',null,nowISO(),'Directional only because exact Match2 entry marker is missing.');
      db.prepare('INSERT OR REPLACE INTO lab_meta(key,value) VALUES(?,?)').run('latest_partial_match_session', labSessionId);
      db.exec('COMMIT;');
    } catch (error) {
      try { db.exec('ROLLBACK;'); } catch {}
      throw error;
    }
    const summary = {
      databasePath,
      databaseSHA256: sha256File(databasePath),
      session: db.prepare('SELECT id,capture_state,semantic_valid,invalid_reason,notes FROM sessions WHERE id=?').get(labSessionId),
      metrics: db.prepare('SELECT metric_scope,metric_name,metric_value,unit,semantic_valid FROM metrics WHERE session_id=? ORDER BY metric_scope,metric_name').all(labSessionId),
      evidence: db.prepare('SELECT id,hypothesis_id,claim,relation,strength FROM evidence WHERE session_id=? ORDER BY id').all(labSessionId)
    };
    writeJSON(path.join(captureDir, `lab-ingest-match-${analysis.matchOrdinal}-approx.json`), summary);
    return summary;
  } finally {
    try { db.close(); } catch {}
  }
}

function marker(kind = 'stutter') {
  const state = readJSON(CONTROL_STATE);
  if (!state?.captureDir) throw new Error('No active direct-control session.');
  const placementMatch = String(kind).match(/^placement-([1-8])$/);
  const definitions = {
    stutter: { event: 'MANUAL_STUTTER_MARKER', source: 'F8' },
    'match-entry': { event: 'MATCH_ENTRY', source: 'control-observation' },
    'combat-start': { event: 'COMBAT_START', source: 'control-observation' },
    'first-place': { event: 'MATCH_RESULT', source: 'user-observation', placement: 1, result: 'WIN' }
  };
  const definition = placementMatch
    ? { event: 'MATCH_RESULT', source: 'user-observation', placement: Number(placementMatch[1]), result: Number(placementMatch[1]) === 1 ? 'WIN' : 'PLACED' }
    : definitions[kind];
  if (!definition) throw new Error(`Unsupported marker kind: ${kind}`);
  const gateRequired = kind === 'match-entry' || kind === 'combat-start';
  const loggerGate = loggerGameplayGate(state);
  if (gateRequired && !loggerGate.ready) throw new Error(`LOGGER_REQUIRED_BEFORE_GAMEPLAY_MARKER: ${JSON.stringify(loggerGate)}`);
  const existingMarkers = readJSONL(path.join(state.captureDir, 'markers.jsonl'));
  const matchOrdinal = definition.event === 'MATCH_ENTRY'
    ? existingMarkers.filter(row => row.event === 'MATCH_ENTRY').length + 1
    : definition.event === 'MATCH_RESULT'
      ? existingMarkers.filter(row => row.event === 'MATCH_RESULT').length + 1
      : null;
  const event = { utc: nowISO(), host_mono_ns: monoNs().toString(), ...definition, ...(matchOrdinal ? { matchOrdinal } : {}) };
  appendJSONL(path.join(state.captureDir, 'markers.jsonl'), event);
  if (kind !== 'stutter') {
    const sessionPath = path.join(state.captureDir, 'session.json');
    const session = readJSON(sessionPath, {});
    if (kind === 'match-entry') session.matchEntryObserved = true;
    if (kind === 'combat-start') session.combatObserved = true;
    if (definition.event === 'MATCH_RESULT') {
      session.matchResultObserved = true;
      session.placement = definition.placement;
      session.result = definition.result;
      session.completedMatchCount = Math.max(Number(session.completedMatchCount ?? 0), matchOrdinal ?? 1);
    }
    writeJSON(sessionPath, session);
  }
  return { action: 'MARKER_RECORDED', kind, captureDir: state.captureDir, marker: event, loggerGate };
}

async function recoverAnrWait() {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  if (!deviceReady(runtime)) throw new Error('No active Android device for ANR recovery.');
  const xml = dumpUI(runtime);
  const waitNode = findNodeByText(xml, [/^Wait$/i]);
  const anrText = findNodeByText(xml, [/isn['’]?t responding/i, /not responding/i]);
  if (!waitNode?.bounds) {
    return { action: 'ANR_WAIT_NOT_PRESENT', anrVisible: Boolean(anrText), postStatus: await status() };
  }
  adb(runtime, ['shell', 'input', 'tap', String(waitNode.bounds.x), String(waitNode.bounds.y)], { allowFailure: true, timeout: 10000 });
  if (state?.captureDir) {
    appendJSONL(path.join(state.captureDir, 'host-events.jsonl'), { utc: nowISO(), host_mono_ns: monoNs().toString(), event: 'ANR_WAIT_SELECTED', activity: 'MobileFREWebViewActivity' });
  }
  await sleep(2500);
  return { action: 'ANR_WAIT_SELECTED', postStatus: await status() };
}

function riotPatchState(runtime) {
  if (!deviceReady(runtime)) return { state: 'DEVICE_UNAVAILABLE', serviceActive: false, evidence: [] };
  const services = adb(runtime, ['shell', 'dumpsys', 'activity', 'services', PACKAGE], { allowFailure: true, timeout: 30000 }).stdout;
  const serviceLines = services.split(/\r?\n/).filter(line => /TFTPatchingFGService|com\.riotgames\.mobile/i.test(line)).slice(0, 80);
  const serviceActive = serviceLines.some(line => /TFTPatchingFGService/.test(line));
  const logcat = command(runtime.adb, ['-P', ADB_PORT, '-s', SERIAL, 'logcat', '-d', '-v', 'threadtime', '-t', '1800'], { env: runtime.env, allowFailure: true, timeout: 30000, maxBuffer: 32 * 1024 * 1024 }).stdout;
  const evidence = logcat.split(/\r?\n/).filter(line => /TFTPatchingFGService|teamfighttactics.*(patch|download|asset|content)|riotgames.*(patch|download|asset|content)/i.test(line)).slice(-120);
  return {
    state: serviceActive ? 'PATCHING_OR_INITIALIZING' : 'NO_ACTIVE_PATCH_SERVICE',
    serviceActive,
    serviceLines,
    evidence
  };
}

function telemetrySnapshot(captureDir) {
  const tracked = [
    'host-events.jsonl', 'host-process.jsonl', 'host-memory.jsonl', 'clock-sync.jsonl',
    'logcat.raw.txt', 'gfxinfo/framestats.raw.txt'
  ];
  const files = {};
  for (const rel of tracked) {
    const file = path.join(captureDir, rel);
    try {
      const stat = fs.statSync(file);
      files[rel] = { bytes: stat.size, mtimeMs: stat.mtimeMs };
    } catch {
      files[rel] = { bytes: null, mtimeMs: null };
    }
  }
  return files;
}

async function loggerHealth() {
  const state = readJSON(CONTROL_STATE);
  if (!state?.captureDir) throw new Error('No active direct-control session.');
  const before = telemetrySnapshot(state.captureDir);
  await sleep(2600);
  const after = telemetrySnapshot(state.captureDir);
  const growth = {};
  for (const [rel, current] of Object.entries(after)) {
    const prior = before[rel] ?? {};
    growth[rel] = current.bytes !== null && prior.bytes !== null
      ? { bytesAdded: current.bytes - prior.bytes, mtimeAdvanced: (current.mtimeMs ?? 0) > (prior.mtimeMs ?? 0) }
      : { bytesAdded: null, mtimeAdvanced: false };
  }
  const expectedStreams = ['host-process.jsonl', 'host-memory.jsonl', 'logcat.raw.txt', 'gfxinfo/framestats.raw.txt'];
  const activeStreams = expectedStreams.filter(rel => (growth[rel]?.bytesAdded ?? 0) > 0 || growth[rel]?.mtimeAdvanced);
  const samplerAlive = processAlive(state.samplerPid);
  const processAdvancing = (growth['host-process.jsonl']?.bytesAdded ?? 0) > 0 || growth['host-process.jsonl']?.mtimeAdvanced;
  const memoryAdvancing = (growth['host-memory.jsonl']?.bytesAdded ?? 0) > 0 || growth['host-memory.jsonl']?.mtimeAdvanced;
  const logcatBytes = after['logcat.raw.txt']?.bytes ?? 0;
  const logcatAgeMs = after['logcat.raw.txt']?.mtimeMs ? Math.max(0, Date.now() - after['logcat.raw.txt'].mtimeMs) : null;
  const logcatPresent = logcatBytes > 0;
  const logcatFresh = logcatAgeMs !== null && logcatAgeMs <= 15000;
  const result = {
    observedAt: nowISO(),
    sessionId: state.sessionId,
    captureDir: state.captureDir,
    samplerAlive,
    emulatorProcessAlive: processAlive(state.emulatorPid),
    activeStreams,
    expectedStreams,
    processAdvancing,
    memoryAdvancing,
    logcatPresent,
    logcatFresh,
    logcatAgeMs,
    gfxinfoRequiredForHealth: false,
    healthy: samplerAlive && processAdvancing && memoryAdvancing && logcatPresent && logcatFresh,
    before,
    after,
    growth
  };
  writeJSON(path.join(state.captureDir, 'logger-health.json'), result);
  return result;
}

function percentileNumber(values, p) {
  const finite = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (!finite.length) return null;
  const index = Math.min(finite.length - 1, Math.max(0, Math.ceil(finite.length * p) - 1));
  return finite[index];
}

function summarizeNumbers(values) {
  const finite = values.filter(Number.isFinite);
  if (!finite.length) return { count: 0, min: null, mean: null, p50: null, p95: null, p99: null, max: null };
  return {
    count: finite.length,
    min: Math.min(...finite),
    mean: finite.reduce((sum, value) => sum + value, 0) / finite.length,
    p50: percentileNumber(finite, 0.50),
    p95: percentileNumber(finite, 0.95),
    p99: percentileNumber(finite, 0.99),
    max: Math.max(...finite)
  };
}

function matchWindowFromMarkers(markers) {
  const ordered = markers
    .filter(row => row?.event === 'MATCH_ENTRY' || row?.event === 'MATCH_RESULT')
    .sort((a, b) => Number(a.host_mono_ns ?? 0) - Number(b.host_mono_ns ?? 0));
  const completed = [];
  let start = null;
  for (const row of ordered) {
    if (row.event === 'MATCH_ENTRY') {
      start = row;
      continue;
    }
    if (row.event !== 'MATCH_RESULT' || !start) continue;
    const startHostNs = Number(start.host_mono_ns);
    const endHostNs = Number(row.host_mono_ns);
    if (Number.isFinite(startHostNs) && Number.isFinite(endHostNs) && endHostNs > startHostNs) {
      completed.push({ start, result: row, matchOrdinal: completed.length + 1, startHostNs, endHostNs, durationSeconds: (endHostNs - startHostNs) / 1e9 });
    }
    start = null;
  }
  return completed.at(-1) ?? null;
}

function sessionLogSignals(captureDir) {
  const logPath = path.join(captureDir, 'logcat.raw.txt');
  const emulatorPath = path.join(captureDir, 'emulator.stdout.log');
  const androidText = exists(logPath) ? fs.readFileSync(logPath, 'utf8') : '';
  const emulatorText = exists(emulatorPath) ? fs.readFileSync(emulatorPath, 'utf8') : '';
  const count = (text, rx) => (text.match(rx) ?? []).length;
  const samples = (text, rx, maximum = 20) => text.split(/\r?\n/).filter(line => rx.test(line)).slice(-maximum);
  return {
    scope: 'whole capture; startup/patch/login lines may precede match-entry',
    android: {
      tftAnrCount: count(androidText, /ANR in com\.riotgames\.league\.teamfighttactics/g),
      inputDispatchTimeoutCount: count(androidText, /teamfighttactics.*Input dispatching timed out/gi),
      fatalSignalCount: count(androidText, /teamfighttactics.*Fatal signal|Fatal signal.*teamfighttactics/gi),
      outOfMemoryCount: count(androidText, /teamfighttactics.*(?:OutOfMemory|low memory|lmkd)|(?:OutOfMemory|low memory|lmkd).*teamfighttactics/gi),
      choreographerSkippedFrameEvents: count(androidText, /Choreographer.*Skipped\s+\d+\s+frames/gi),
      patchServiceMentions: count(androidText, /TFTPatchingFGService/g),
      angleWarningOrErrorCount: count(androidText, /ANGLE.*(?:warn|error|fail|unsupported)/gi),
      vulkanWarningOrErrorCount: count(androidText, /Vulkan.*(?:warn|error|fail|unsupported)/gi),
      relevantSamples: samples(androidText, /teamfighttactics.*(?:ANR|timeout|Fatal signal|OutOfMemory|low memory)|ANGLE.*(?:warn|error|fail|unsupported)|Vulkan.*(?:warn|error|fail|unsupported)/i)
    },
    emulator: {
      graphicsWarningOrErrorCount: count(emulatorText, /(?:ANGLE|gfxstream|MoltenVK|Vulkan|Metal).*(?:warn|error|fail|stall|timeout|unsupported)/gi),
      relevantSamples: samples(emulatorText, /(?:ANGLE|gfxstream|MoltenVK|Vulkan|Metal).*(?:warn|error|fail|stall|timeout|unsupported)/i)
    }
  };
}

function analyzeRestartEffect() {
  const state = readJSON(CONTROL_STATE);
  if (!state?.captureDir) throw new Error('No active direct-control session.');
  const captureDir = state.captureDir;
  const hostEvents = readJSONL(path.join(captureDir, 'host-events.jsonl'));
  const restart = [...hostEvents].reverse().find(row => row.event === 'TFT_APP_RESTART_COMPLETE');
  if (!restart?.host_mono_ns) throw new Error('No TFT_APP_RESTART_COMPLETE event is available.');
  const restartNs = Number(restart.host_mono_ns);
  const processRows = readJSONL(path.join(captureDir, 'host-process.jsonl'));
  const memoryRows = readJSONL(path.join(captureDir, 'host-memory.jsonl'));
  const gib = 1024 ** 3;
  const select = (rows, startNs, endNs) => rows.filter(row => {
    const mono = Number(row.host_mono_ns);
    return Number.isFinite(mono) && mono >= startNs && mono < endNs;
  });
  const procSummary = rows => {
    const emulatorRows = rows.filter(row => /qemu-system-aarch64|\/emulator(?:\s|$)/i.test(String(row.command ?? '')));
    return {
      sampleCount: emulatorRows.length,
      cpuPercent: summarizeNumbers(emulatorRows.map(row => Number(row.cpu_pct))),
      rssMiB: summarizeNumbers(emulatorRows.map(row => Number(row.rss_kb) / 1024))
    };
  };
  const memSummary = rows => {
    const pageouts = rows.map(row => Number(row.pageout_count)).filter(Number.isFinite);
    return {
      sampleCount: rows.length,
      hostAvailableGiB: summarizeNumbers(rows.map(row => Number(row.host_available_bytes) / gib)),
      hostCompressedGiB: summarizeNumbers(rows.map(row => Number(row.host_compressed_bytes) / gib)),
      hostSwapUsedGiB: summarizeNumbers(rows.map(row => Number(row.host_swap_used_bytes) / gib)),
      guestAvailableGiB: summarizeNumbers(rows.map(row => Number(row.guest_available_bytes) / gib)),
      pageoutDelta: pageouts.length > 1 ? pageouts.at(-1) - pageouts[0] : null
    };
  };
  const delta = (post, pre) => Number.isFinite(post) && Number.isFinite(pre) ? post - pre : null;
  const windows = {};
  for (const seconds of [600, 1200, 1800]) {
    const span = seconds * 1e9;
    const preProc = procSummary(select(processRows, restartNs - span, restartNs));
    const postProc = procSummary(select(processRows, restartNs, restartNs + span));
    const preMem = memSummary(select(memoryRows, restartNs - span, restartNs));
    const postMem = memSummary(select(memoryRows, restartNs, restartNs + span));
    windows[String(seconds)] = {
      seconds,
      pre: { hostEmulator: preProc, memory: preMem },
      post: { hostEmulator: postProc, memory: postMem },
      delta: {
        emulatorCpuMeanPctPoints: delta(postProc.cpuPercent.mean, preProc.cpuPercent.mean),
        emulatorCpuP95PctPoints: delta(postProc.cpuPercent.p95, preProc.cpuPercent.p95),
        emulatorRssMeanMiB: delta(postProc.rssMiB.mean, preProc.rssMiB.mean),
        hostAvailableMeanGiB: delta(postMem.hostAvailableGiB.mean, preMem.hostAvailableGiB.mean),
        hostCompressedMeanGiB: delta(postMem.hostCompressedGiB.mean, preMem.hostCompressedGiB.mean),
        hostSwapMeanGiB: delta(postMem.hostSwapUsedGiB.mean, preMem.hostSwapUsedGiB.mean),
        guestAvailableMeanGiB: delta(postMem.guestAvailableGiB.mean, preMem.guestAvailableGiB.mean),
        pageoutDeltaDifference: delta(postMem.pageoutDelta, preMem.pageoutDelta)
      }
    };
  }
  const result = {
    schema: 1,
    observedAt: nowISO(),
    sessionId: state.sessionId,
    restart,
    windows,
    interpretationRule: 'Equal-duration pre/post app-restart windows. Positive host-available and negative compressed/pageout deltas support restart-related pressure relief; CPU/RSS changes alone do not establish causality.'
  };
  writeJSON(path.join(captureDir, 'restart-effect-analysis.json'), result);
  return result;
}

function analyzeContinuousRun() {
  const state = readJSON(CONTROL_STATE);
  if (!state?.captureDir) throw new Error('No active direct-control session.');
  const captureDir = state.captureDir;
  const session = readJSON(path.join(captureDir, 'session.json'), {});
  const markers = readJSONL(path.join(captureDir, 'markers.jsonl'));
  const hostEvents = readJSONL(path.join(captureDir, 'host-events.jsonl'));
  const allProcessRows = readJSONL(path.join(captureDir, 'host-process.jsonl'));
  const allMemoryRows = readJSONL(path.join(captureDir, 'host-memory.jsonl'));

  const observedMonos = [
    ...allProcessRows.map(row => Number(row.host_mono_ns)),
    ...allMemoryRows.map(row => Number(row.host_mono_ns)),
    ...markers.map(row => Number(row.host_mono_ns)),
    ...hostEvents.map(row => Number(row.host_mono_ns))
  ].filter(Number.isFinite);
  const sessionStartNs = session.hostStartMonoNs === null || session.hostStartMonoNs === undefined || session.hostStartMonoNs === '' ? NaN : Number(session.hostStartMonoNs);
  const sessionEndNs = session.hostEndMonoNs === null || session.hostEndMonoNs === undefined || session.hostEndMonoNs === '' ? NaN : Number(session.hostEndMonoNs);
  const startHostNs = Number.isFinite(sessionStartNs) ? sessionStartNs : (observedMonos.length ? Math.min(...observedMonos) : Number(monoNs()));
  const endHostNs = Number.isFinite(sessionEndNs) ? sessionEndNs : (observedMonos.length ? Math.max(...observedMonos) : Number(monoNs()));
  if (!(endHostNs >= startHostNs)) throw new Error('CONTINUOUS_RUN_WINDOW_INVALID');

  const processRows = allProcessRows.filter(row => {
    const mono = Number(row.host_mono_ns);
    return Number.isFinite(mono) && mono >= startHostNs && mono <= endHostNs;
  });
  const emulatorRows = processRows.filter(row => /qemu-system-aarch64|\/emulator(?:\s|$)/i.test(String(row.command ?? '')));
  const memoryRows = allMemoryRows.filter(row => {
    const mono = Number(row.host_mono_ns);
    return Number.isFinite(mono) && mono >= startHostNs && mono <= endHostNs;
  });
  const gib = 1024 ** 3;
  const pageouts = memoryRows.map(row => Number(row.pageout_count)).filter(Number.isFinite);
  const runMetrics = {
    hostEmulator: {
      sampleCount: emulatorRows.length,
      cpuPercent: summarizeNumbers(emulatorRows.map(row => Number(row.cpu_pct))),
      rssMiB: summarizeNumbers(emulatorRows.map(row => Number(row.rss_kb) / 1024))
    },
    memory: {
      sampleCount: memoryRows.length,
      hostAvailableGiB: summarizeNumbers(memoryRows.map(row => Number(row.host_available_bytes) / gib)),
      hostCompressedGiB: summarizeNumbers(memoryRows.map(row => Number(row.host_compressed_bytes) / gib)),
      hostSwapUsedGiB: summarizeNumbers(memoryRows.map(row => Number(row.host_swap_used_bytes) / gib)),
      guestAvailableGiB: summarizeNumbers(memoryRows.map(row => Number(row.guest_available_bytes) / gib)),
      pageoutDelta: pageouts.length > 1 ? pageouts.at(-1) - pageouts[0] : null
    }
  };

  const settingsTimeline = markers
    .filter(row => row.event === 'GAME_SETTINGS')
    .filter(row => Number.isFinite(Number(row.host_mono_ns)))
    .sort((a, b) => Number(a.host_mono_ns) - Number(b.host_mono_ns));
  const matchResults = markers.filter(row => row.event === 'MATCH_RESULT').sort((a, b) => Number(a.host_mono_ns ?? 0) - Number(b.host_mono_ns ?? 0));
  const qualityReports = markers.filter(row => row.event === 'USER_QUALITY_REPORT').sort((a, b) => Number(a.host_mono_ns ?? 0) - Number(b.host_mono_ns ?? 0));
  const manualStutters = markers.filter(row => row.event === 'MANUAL_STUTTER_MARKER');
  const appRestarts = hostEvents.filter(row => row.event === 'TFT_APP_RESTART_COMPLETE');
  const logSignals = sessionLogSignals(captureDir);

  const segmentStarts = [
    { host_mono_ns: String(startHostNs), utc: session.startedUTC ?? state.startedUTC ?? null, graphicsPreset: 'UNKNOWN', fpsCap: 'UNKNOWN', performanceModeBeta: 'UNKNOWN', source: 'run-start' },
    ...settingsTimeline.filter(row => Number(row.host_mono_ns) > startHostNs && Number(row.host_mono_ns) < endHostNs)
  ];
  const settingsSegments = segmentStarts.map((setting, index) => {
    const segmentStartNs = Math.max(startHostNs, Number(setting.host_mono_ns));
    const next = segmentStarts[index + 1];
    const segmentEndNs = next ? Math.min(endHostNs, Number(next.host_mono_ns)) : endHostNs;
    const pRows = emulatorRows.filter(row => Number(row.host_mono_ns) >= segmentStartNs && Number(row.host_mono_ns) < segmentEndNs);
    const mRows = memoryRows.filter(row => Number(row.host_mono_ns) >= segmentStartNs && Number(row.host_mono_ns) < segmentEndNs);
    const segmentPageouts = mRows.map(row => Number(row.pageout_count)).filter(Number.isFinite);
    return {
      index: index + 1,
      startedAt: setting.utc ?? null,
      startHostNs: segmentStartNs,
      endHostNs: segmentEndNs,
      durationSeconds: Math.max(0, (segmentEndNs - segmentStartNs) / 1e9),
      settings: {
        graphicsPreset: setting.graphicsPreset ?? 'UNKNOWN',
        fpsCap: setting.fpsCap ?? 'UNKNOWN',
        performanceModeBeta: setting.performanceModeBeta ?? 'UNKNOWN'
      },
      hostEmulator: {
        sampleCount: pRows.length,
        cpuPercent: summarizeNumbers(pRows.map(row => Number(row.cpu_pct))),
        rssMiB: summarizeNumbers(pRows.map(row => Number(row.rss_kb) / 1024))
      },
      memory: {
        sampleCount: mRows.length,
        hostAvailableGiB: summarizeNumbers(mRows.map(row => Number(row.host_available_bytes) / gib)),
        hostCompressedGiB: summarizeNumbers(mRows.map(row => Number(row.host_compressed_bytes) / gib)),
        hostSwapUsedGiB: summarizeNumbers(mRows.map(row => Number(row.host_swap_used_bytes) / gib)),
        guestAvailableGiB: summarizeNumbers(mRows.map(row => Number(row.guest_available_bytes) / gib)),
        pageoutDelta: segmentPageouts.length > 1 ? segmentPageouts.at(-1) - segmentPageouts[0] : null
      }
    };
  }).filter(segment => segment.durationSeconds > 0);

  const analysis = {
    schema: 2,
    analysisModel: 'CONTINUOUS_RUN_PRIMARY',
    observedAt: nowISO(),
    sessionId: state.sessionId,
    captureDir,
    run: {
      startedUTC: session.startedUTC ?? state.startedUTC ?? null,
      snapshotUTC: nowISO(),
      endedUTC: session.endedUTC ?? null,
      startHostNs,
      endHostNs,
      durationSeconds: (endHostNs - startHostNs) / 1e9,
      captureState: session.captureState ?? 'CAPTURING',
      loggerStillActive: processAlive(state.samplerPid)
    },
    annotations: {
      completedMatches: matchResults.length,
      wins: matchResults.filter(row => Number(row.placement) === 1 || row.result === 'WIN').length,
      placements: matchResults.map(row => ({ utc: row.utc ?? null, placement: row.placement ?? null, result: row.result ?? null, matchOrdinal: row.matchOrdinal ?? null })),
      settingsTimeline: settingsTimeline.map(row => ({ utc: row.utc ?? null, graphicsPreset: row.graphicsPreset ?? 'UNKNOWN', fpsCap: row.fpsCap ?? 'UNKNOWN', performanceModeBeta: row.performanceModeBeta ?? 'UNKNOWN' })),
      qualityReports: qualityReports.map(row => ({ utc: row.utc ?? null, summary: row.summary ?? null, comparison: row.comparison ?? null, matchOrdinal: row.matchOrdinal ?? null })),
      appRestartCount: appRestarts.length,
      manualStutterCount: manualStutters.length,
      matchEntryMarkersPresent: markers.filter(row => row.event === 'MATCH_ENTRY').length
    },
    hostEmulator: runMetrics.hostEmulator,
    memory: runMetrics.memory,
    settingsSegments,
    logSignals,
    interpretationRule: 'The continuous logger run is authoritative. Match boundaries are optional annotations; setting-change timestamps and other events are used for correlation without requiring per-game segmentation.'
  };
  writeJSON(path.join(captureDir, 'continuous-run-analysis.json'), analysis);
  return analysis;
}

function ingestContinuousRunIntoLab() {
  const analysis = analyzeContinuousRun();
  const captureDir = analysis.captureDir;
  const labSessionId = `${analysis.sessionId}-continuous-run`;
  const databasePath = path.join(DIAGNOSTICS_ROOT, 'TFTMAC_PERFORMANCE_LAB.sqlite');
  const schemaPath = labSchemaPath();
  if (!schemaPath) throw new Error('TFTMAC performance-lab schema is unavailable.');
  ensureDir(DIAGNOSTICS_ROOT);
  const initialize = !exists(databasePath) || fs.statSync(databasePath).size === 0;
  const db = new DatabaseSync(databasePath);
  try {
    if (initialize) db.exec(fs.readFileSync(schemaPath, 'utf8'));
    db.exec('PRAGMA foreign_keys = ON;');
    const packageInfo = readJSON(path.join(captureDir, 'package-state.json'), {});
    const sessionFile = readJSON(path.join(captureDir, 'session.json'), {});
    const packageFile = path.join(captureDir, 'package-state.json');
    const rendererFile = path.join(captureDir, 'renderer-state.json');
    const currentConfigId = BASELINE_PROFILE.id;
    const now = nowISO();
    db.exec('BEGIN IMMEDIATE;');
    try {
      db.prepare('INSERT OR REPLACE INTO lab_meta(key,value) VALUES(?,?)').run('analysis_model', 'CONTINUOUS_RUN_PRIMARY');
      db.prepare('INSERT OR REPLACE INTO lab_meta(key,value) VALUES(?,?)').run('current_continuous_run_session', labSessionId);
      db.prepare('INSERT OR REPLACE INTO lab_meta(key,value) VALUES(?,?)').run('last_continuous_run_ingest_at', now);
      db.prepare('INSERT OR REPLACE INTO lab_meta(key,value) VALUES(?,?)').run('current_optimization_priority', 'Analyze the continuous logger run as the primary performance record. Matches and setting changes are annotations for correlation; do not require per-match start/stop boundaries.');
      db.prepare(`INSERT INTO sessions(
        id,runtime_config_id,started_utc,ended_utc,host_start_mono_ns,host_end_mono_ns,boot_class,workload_class,
        package_name,package_version_name,package_version_code,package_state_sha256,renderer_state_sha256,session_manifest_sha256,
        package_updated_during_session,capture_state,semantic_valid,invalid_reason,notes
      ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET ended_utc=excluded.ended_utc,host_end_mono_ns=excluded.host_end_mono_ns,
        capture_state=excluded.capture_state,semantic_valid=excluded.semantic_valid,invalid_reason=excluded.invalid_reason,notes=excluded.notes`)
        .run(labSessionId,currentConfigId,analysis.run.startedUTC,analysis.run.snapshotUTC,analysis.run.startHostNs,analysis.run.endHostNs,
          'UNKNOWN','MIXED',PACKAGE,packageInfo.versionName ?? null,packageInfo.versionCode ?? null,
          exists(packageFile) ? sha256File(packageFile) : null,exists(rendererFile) ? sha256File(rendererFile) : null,null,
          sessionFile.packageUpdatedDuringSession ? 1 : 0,analysis.run.endedUTC ? 'COMPLETE' : 'CAPTURING',1,null,
          `Continuous-run aggregate; ${analysis.annotations.completedMatches} completed match annotation(s), ${analysis.annotations.wins} win(s), ${analysis.settingsSegments.length} settings segment(s).`);

      db.prepare('DELETE FROM metrics WHERE session_id=?').run(labSessionId);
      const metric = db.prepare('INSERT INTO metrics(session_id,experiment_id,metric_scope,metric_name,metric_value,unit,source_artifact_id,semantic_valid,notes) VALUES(?,?,?,?,?,?,?,?,?)');
      const add = (scope,name,value,unit,notes=null) => { if (Number.isFinite(Number(value))) metric.run(labSessionId,null,scope,name,Number(value),unit,null,1,notes); };
      add('RUN','duration',analysis.run.durationSeconds,'seconds');
      add('RUN','completed_matches',analysis.annotations.completedMatches,'count');
      add('RUN','wins',analysis.annotations.wins,'count');
      add('HOST_CPU','emulator_cpu_mean',analysis.hostEmulator.cpuPercent.mean,'percent');
      add('HOST_CPU','emulator_cpu_p95',analysis.hostEmulator.cpuPercent.p95,'percent');
      add('HOST_CPU','emulator_cpu_max',analysis.hostEmulator.cpuPercent.max,'percent');
      add('MEMORY','emulator_rss_mean',analysis.hostEmulator.rssMiB.mean,'MiB');
      add('MEMORY','emulator_rss_p95',analysis.hostEmulator.rssMiB.p95,'MiB');
      add('MEMORY','emulator_rss_max',analysis.hostEmulator.rssMiB.max,'MiB');
      add('MEMORY','host_available_mean',analysis.memory.hostAvailableGiB.mean,'GiB');
      add('MEMORY','host_available_min',analysis.memory.hostAvailableGiB.min,'GiB');
      add('MEMORY','host_compressed_mean',analysis.memory.hostCompressedGiB.mean,'GiB');
      add('MEMORY','host_compressed_p95',analysis.memory.hostCompressedGiB.p95,'GiB');
      add('MEMORY','host_compressed_max',analysis.memory.hostCompressedGiB.max,'GiB');
      add('MEMORY','host_swap_mean',analysis.memory.hostSwapUsedGiB.mean,'GiB');
      add('MEMORY','host_swap_max',analysis.memory.hostSwapUsedGiB.max,'GiB');
      add('MEMORY','guest_available_min',analysis.memory.guestAvailableGiB.min,'GiB');
      add('MEMORY','pageout_delta',analysis.memory.pageoutDelta,'pages');
      add('EVENTS','app_restart_count',analysis.annotations.appRestartCount,'count');
      add('EVENTS','manual_stutter_count',analysis.annotations.manualStutterCount,'count');
      add('EVENTS','tft_anr_count',analysis.logSignals.android.tftAnrCount,'count');

      for (const segment of analysis.settingsSegments) {
        const scope = `SETTINGS_SEGMENT_${segment.index}`;
        const note = JSON.stringify({ settings: segment.settings, startedAt: segment.startedAt, durationSeconds: segment.durationSeconds });
        add(scope,'duration',segment.durationSeconds,'seconds',note);
        add(scope,'emulator_cpu_mean',segment.hostEmulator.cpuPercent.mean,'percent',note);
        add(scope,'emulator_rss_mean',segment.hostEmulator.rssMiB.mean,'MiB',note);
        add(scope,'host_available_mean',segment.memory.hostAvailableGiB.mean,'GiB',note);
        add(scope,'host_compressed_mean',segment.memory.hostCompressedGiB.mean,'GiB',note);
        add(scope,'pageout_delta',segment.memory.pageoutDelta,'pages',note);
      }

      const evidence = db.prepare('INSERT OR REPLACE INTO evidence(id,hypothesis_id,session_id,experiment_id,evidence_type,claim,relation,strength,source_artifact_id,created_at,notes) VALUES(?,?,?,?,?,?,?,?,?,?,?)');
      evidence.run('ev_continuous_run_model',null,labSessionId,null,'CONFIG_OBSERVATION','Continuous-run telemetry is the primary performance record; match and settings events are annotations used for correlation rather than mandatory segmentation boundaries.','NEUTRAL','DECISIVE',null,now,'User-directed measurement model.');
      if (Number(analysis.memory.pageoutDelta ?? 0) > 0) {
        evidence.run('ev_continuous_run_memory','h_memory_pressure',labSessionId,null,'DIRECT_MEASUREMENT',`Across the continuous run, host pageouts increased by ${analysis.memory.pageoutDelta}; compressed memory mean=${analysis.memory.hostCompressedGiB.mean?.toFixed(2)} GiB and max=${analysis.memory.hostCompressedGiB.max?.toFixed(2)} GiB.`,'SUPPORTS','MODERATE',null,now,'Run-level resource envelope; setting segments provide finer correlation without requiring match boundaries.');
      }
      const quality = analysis.annotations.qualityReports.map(row => row.summary).filter(Boolean).join(' | ');
      if (quality) evidence.run('ev_continuous_run_user_quality',null,labSessionId,null,'CONFIG_OBSERVATION',quality,'NEUTRAL','MODERATE',null,now,'Timestamped user quality observations inside the continuous run.');
      db.exec('COMMIT;');
    } catch (error) {
      try { db.exec('ROLLBACK;'); } catch {}
      throw error;
    }
    const summary = {
      databasePath,
      databaseSHA256: sha256File(databasePath),
      session: db.prepare('SELECT id,capture_state,semantic_valid,notes FROM sessions WHERE id=?').get(labSessionId),
      metrics: db.prepare('SELECT metric_scope,metric_name,metric_value,unit,semantic_valid,notes FROM metrics WHERE session_id=? ORDER BY metric_scope,metric_name').all(labSessionId),
      evidence: db.prepare('SELECT id,hypothesis_id,claim,relation,strength FROM evidence WHERE session_id=? ORDER BY id').all(labSessionId),
      settingsSegments: analysis.settingsSegments
    };
    writeJSON(path.join(captureDir, 'continuous-run-lab-ingest.json'), summary);
    return summary;
  } finally {
    try { db.close(); } catch {}
  }
}

function analyzeSession() {
  const state = readJSON(CONTROL_STATE);
  if (!state?.captureDir) throw new Error('No active direct-control session.');
  const captureDir = state.captureDir;
  const markers = readJSONL(path.join(captureDir, 'markers.jsonl'));
  const clocks = readJSONL(path.join(captureDir, 'clock-sync.jsonl'));
  const window = matchWindowFromMarkers(markers);
  if (!window) throw new Error('A complete MATCH_ENTRY -> MATCH_RESULT window is required before gameplay analysis.');

  const framePath = path.join(captureDir, 'gfxinfo', 'framestats.raw.txt');
  const frameText = exists(framePath) ? fs.readFileSync(framePath, 'utf8') : '';
  const frames = parseFrameStats(frameText);
  const relevantClocks = clocks.filter(row => {
    const midpoint = Number(row.host_midpoint_ns);
    return Number.isFinite(midpoint) && midpoint >= window.startHostNs - 30e9 && midpoint <= window.endHostNs + 30e9;
  });
  const offsets = relevantClocks.map(row => Number(row.estimated_offset_ns)).filter(Number.isFinite);
  const estimatedOffsetNs = percentileNumber(offsets, 0.50);
  const matchedFrames = estimatedOffsetNs === null ? [] : frames.filter(frame => {
    const hostNs = Number(frame.completedNs) + estimatedOffsetNs;
    return hostNs >= window.startHostNs && hostNs <= window.endHostNs;
  });
  const frameIntervalsMs = matchedFrames
    .map(frame => frame.intervalNs === null ? null : Number(frame.intervalNs) / 1e6)
    .filter(value => Number.isFinite(value) && value > 0 && value < 10000);
  const frameSummary = summarizeNumbers(frameIntervalsMs);
  const frameMetrics = {
    ...frameSummary,
    fpsFromMeanInterval: frameSummary.mean ? 1000 / frameSummary.mean : null,
    jankFramesOver33_334ms: frameIntervalsMs.filter(value => value > 33.334).length,
    jankPercentOver33_334ms: frameIntervalsMs.length ? 100 * frameIntervalsMs.filter(value => value > 33.334).length / frameIntervalsMs.length : null,
    severeFramesOver100ms: frameIntervalsMs.filter(value => value > 100).length,
    stallsOver250ms: frameIntervalsMs.filter(value => value > 250).length,
    stallsOver500ms: frameIntervalsMs.filter(value => value > 500).length,
    stallsOver1000ms: frameIntervalsMs.filter(value => value > 1000).length,
    estimatedClockOffsetNs: estimatedOffsetNs,
    clockSamplesInWindow: relevantClocks.length,
    coverageSeconds: matchedFrames.length > 1 ? (Number(matchedFrames.at(-1).completedNs) - Number(matchedFrames[0].completedNs)) / 1e9 : 0,
    caution: 'gfxinfo framestats is a presentation proxy; native Unreal/Vulkan GPU timing still requires Perfetto/AGI or equivalent tracing.'
  };

  const processRows = readJSONL(path.join(captureDir, 'host-process.jsonl')).filter(row => {
    const mono = Number(row.host_mono_ns);
    return Number.isFinite(mono) && mono >= window.startHostNs && mono <= window.endHostNs;
  });
  const emulatorRows = processRows.filter(row => /qemu-system-aarch64|\/emulator(?:\s|$)/i.test(String(row.command ?? '')));
  const emulatorCpu = summarizeNumbers(emulatorRows.map(row => Number(row.cpu_pct)));
  const emulatorRssMiB = summarizeNumbers(emulatorRows.map(row => Number(row.rss_kb) / 1024));

  const memoryRows = readJSONL(path.join(captureDir, 'host-memory.jsonl')).filter(row => {
    const mono = Number(row.host_mono_ns);
    return Number.isFinite(mono) && mono >= window.startHostNs && mono <= window.endHostNs;
  });
  const gib = 1024 ** 3;
  const hostAvailableGiB = memoryRows.map(row => Number(row.host_available_bytes) / gib);
  const hostCompressedGiB = memoryRows.map(row => Number(row.host_compressed_bytes) / gib);
  const hostSwapGiB = memoryRows.map(row => Number(row.host_swap_used_bytes) / gib);
  const guestAvailableGiB = memoryRows.map(row => Number(row.guest_available_bytes) / gib);
  const pageouts = memoryRows.map(row => Number(row.pageout_count)).filter(Number.isFinite);
  const memoryMetrics = {
    sampleCount: memoryRows.length,
    hostAvailableGiB: summarizeNumbers(hostAvailableGiB),
    hostCompressedGiB: summarizeNumbers(hostCompressedGiB),
    hostSwapUsedGiB: summarizeNumbers(hostSwapGiB),
    guestAvailableGiB: summarizeNumbers(guestAvailableGiB),
    pageoutDelta: pageouts.length > 1 ? pageouts.at(-1) - pageouts[0] : null,
    activeMemoryPressureObserved: pageouts.length > 1 ? pageouts.at(-1) > pageouts[0] : null
  };

  const gameSettingsMarker = markers
    .filter(row => row?.event === 'GAME_SETTINGS' && Number(row.host_mono_ns ?? 0) <= window.startHostNs)
    .sort((a, b) => Number(a.host_mono_ns ?? 0) - Number(b.host_mono_ns ?? 0))
    .at(-1) ?? null;
  const logSignals = sessionLogSignals(captureDir);
  const renderer = readJSON(path.join(captureDir, 'renderer-state.json'), {});
  const runtime = readJSON(path.join(captureDir, 'runtime-state.json'), {});
  const packageInfo = readJSON(path.join(captureDir, 'package-state.json'), {});
  const session = readJSON(path.join(captureDir, 'session.json'), {});
  const findings = [];
  if ((frameMetrics.jankPercentOver33_334ms ?? 0) > 10) findings.push({ severity: 'HIGH', boundary: 'FRAME_PACING', finding: `Measured jank exceeds 10% of captured gameplay frames (${frameMetrics.jankPercentOver33_334ms.toFixed(2)}%).` });
  if ((frameMetrics.p95 ?? 0) > 33.334) findings.push({ severity: 'HIGH', boundary: 'FRAME_PACING', finding: `Gameplay p95 frame interval is ${frameMetrics.p95.toFixed(2)} ms, beyond a smooth 30 FPS cadence.` });
  if ((memoryMetrics.pageoutDelta ?? 0) > 0) findings.push({ severity: 'MEDIUM', boundary: 'MEMORY', finding: `Host pageouts increased by ${memoryMetrics.pageoutDelta} during the match; memory pressure is a live candidate, not yet proven causal.` });
  if ((emulatorCpu.p95 ?? 0) >= 500) findings.push({ severity: 'MEDIUM', boundary: 'HOST_CPU', finding: `Emulator p95 CPU reached ${emulatorCpu.p95.toFixed(1)}% across macOS cores; CPU scheduling/translation overhead deserves controlled testing.` });
  if (logSignals.android.tftAnrCount > 0) findings.push({ severity: 'MEDIUM', boundary: 'ANDROID_UI', finding: `${logSignals.android.tftAnrCount} TFT ANR event(s) occurred in the full capture, including startup/WebView behavior; isolate from gameplay before attributing.` });
  if (!findings.length) findings.push({ severity: 'INFO', boundary: 'MEASUREMENT', finding: 'No single dominant cause is proven by the current low-overhead capture. Use one-factor experiments plus deeper tracing.' });

  const analysis = {
    schema: 1,
    observedAt: nowISO(),
    sessionId: state.sessionId,
    captureDir,
    match: {
      matchOrdinal: window.matchOrdinal ?? window.result.matchOrdinal ?? window.start.matchOrdinal ?? 1,
      placement: window.result.placement ?? session.matchPlacement ?? null,
      result: window.result.result ?? session.matchResult ?? null,
      durationSeconds: window.durationSeconds,
      matchEntryMarker: window.start,
      matchResultMarker: window.result,
      gameSettings: gameSettingsMarker ? {
        graphicsPreset: gameSettingsMarker.graphicsPreset ?? 'UNKNOWN',
        fpsCap: gameSettingsMarker.fpsCap ?? 'UNKNOWN',
        performanceModeBeta: gameSettingsMarker.performanceModeBeta ?? 'UNKNOWN',
        observedAt: gameSettingsMarker.utc ?? null
      } : { graphicsPreset: 'UNKNOWN', fpsCap: 'UNKNOWN', performanceModeBeta: 'UNKNOWN', observedAt: null }
    },
    package: { versionName: packageInfo.versionName ?? null, versionCode: packageInfo.versionCode ?? null, installerPackage: packageInfo.installerPackage ?? null },
    runtime: {
      control: runtime.control ?? state.controlProfile ?? null,
      display: runtime.observedDisplay ?? null,
      density: runtime.observedDensity ?? null,
      vcpu: runtime.vcpu ?? null,
      ramMB: runtime.ramMB ?? null,
      graphicsTransport: runtime.graphicsTransportRequested ?? runtime.observedGraphicsTransport ?? null
    },
    renderer: {
      properties: renderer.properties ?? {},
      angleSettings: renderer.angleSettings ?? {},
      hostGraphicsEvidenceTail: (renderer.hostGraphicsEvidence ?? []).slice(-30)
    },
    frameMetrics,
    hostEmulator: { sampleCount: emulatorRows.length, cpuPercent: emulatorCpu, rssMiB: emulatorRssMiB },
    memory: memoryMetrics,
    logSignals,
    findings,
    nextExperimentRule: 'Change one reversible variable at a time; compare against this match baseline; KEEP only measured improvements that survive confirmation.'
  };
  writeJSON(path.join(captureDir, `gameplay-analysis-match-${analysis.match.matchOrdinal}.json`), analysis);
  writeJSON(path.join(captureDir, 'gameplay-analysis.json'), analysis);
  return analysis;
}

function ingestAnalysisIntoLab() {
  const analysis = analyzeSession();
  const captureDir = analysis.captureDir;
  const labSessionId = analysis.match.matchOrdinal > 1 ? `${analysis.sessionId}-match-${analysis.match.matchOrdinal}` : analysis.sessionId;
  const databasePath = path.join(DIAGNOSTICS_ROOT, 'TFTMAC_PERFORMANCE_LAB.sqlite');
  const schemaPath = labSchemaPath();
  if (!schemaPath) throw new Error('TFTMAC performance-lab schema is unavailable.');
  ensureDir(DIAGNOSTICS_ROOT);
  const initialize = !exists(databasePath) || fs.statSync(databasePath).size === 0;
  const db = new DatabaseSync(databasePath);
  try {
    if (initialize) db.exec(fs.readFileSync(schemaPath, 'utf8'));
    db.exec('PRAGMA foreign_keys = ON;');
    db.exec('BEGIN IMMEDIATE;');
    try {
      const now = nowISO();
      const sessionFile = readJSON(path.join(captureDir, 'session.json'), {});
      const packageFile = path.join(captureDir, 'package-state.json');
      const rendererFile = path.join(captureDir, 'renderer-state.json');
      const traceCaps = readJSON(path.join(captureDir, 'trace-capabilities.json'), {});
      const sfCounters = traceCaps?.surfaceFlingerCounters ?? {};
      const perfettoDir = path.join(captureDir, 'perfetto');
      let latestTraceMetadata = null;
      try {
        const metas = fs.readdirSync(perfettoDir)
          .filter(name => name.endsWith('.pftrace.json'))
          .map(name => ({ name, path: path.join(perfettoDir, name), mtimeMs: fs.statSync(path.join(perfettoDir, name)).mtimeMs }))
          .sort((a, b) => b.mtimeMs - a.mtimeMs);
        if (metas[0]) latestTraceMetadata = readJSON(metas[0].path, null);
      } catch {}
      const currentConfigId = BASELINE_PROFILE.id;
      const candidateConfigId = 'tftmac_5gb_baseline_v1';

      db.prepare('INSERT OR REPLACE INTO lab_meta(key,value) VALUES(?,?)').run('last_gameplay_ingest_at', now);
      db.prepare('INSERT OR REPLACE INTO lab_meta(key,value) VALUES(?,?)').run('current_gameplay_baseline_session', labSessionId);
      db.prepare('INSERT OR REPLACE INTO lab_meta(key,value) VALUES(?,?)').run('current_optimization_priority', 'Hold the proven 5120-MiB native baseline; correlate native frame windows, SurfaceFlinger deltas, memory, audio and explicit setting markers; change one restart-bound variable at a time.');
      db.prepare('INSERT OR REPLACE INTO lab_meta(key,value) VALUES(?,?)').run('current_game_settings', JSON.stringify(analysis.match.gameSettings));
      if (latestTraceMetadata) db.prepare('INSERT OR REPLACE INTO lab_meta(key,value) VALUES(?,?)').run('native_trace_collector_smoke', JSON.stringify({ label: latestTraceMetadata.label, durationSeconds: latestTraceMetadata.durationSeconds, byteCount: latestTraceMetadata.byteCount, sha256: latestTraceMetadata.sha256, dataSources: latestTraceMetadata.dataSources, parseState: latestTraceMetadata.parseState }));

      const configStmt = db.prepare(`INSERT INTO runtime_configs(
        id,parent_config_id,name,config_sha256,emulator_version,platform_tools_version,system_image_package,system_image_revision,
        avd_name,adb_serial,adb_server_port,emulator_console_port,vcpu,ram_mb,display_width,display_height,density_dpi,refresh_hz,
        gpu_mode,audio_enabled,graphics_transport,angle_mode,vulkan_mode,moltenvk_mode,presentation_mode,state,created_at,notes
      ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET
        parent_config_id=excluded.parent_config_id,name=excluded.name,emulator_version=excluded.emulator_version,
        platform_tools_version=excluded.platform_tools_version,system_image_package=excluded.system_image_package,
        avd_name=excluded.avd_name,adb_serial=excluded.adb_serial,adb_server_port=excluded.adb_server_port,
        emulator_console_port=excluded.emulator_console_port,vcpu=excluded.vcpu,ram_mb=excluded.ram_mb,
        display_width=excluded.display_width,display_height=excluded.display_height,density_dpi=excluded.density_dpi,
        refresh_hz=excluded.refresh_hz,gpu_mode=excluded.gpu_mode,audio_enabled=excluded.audio_enabled,
        graphics_transport=excluded.graphics_transport,angle_mode=excluded.angle_mode,vulkan_mode=excluded.vulkan_mode,
        moltenvk_mode=excluded.moltenvk_mode,presentation_mode=excluded.presentation_mode,state=excluded.state,notes=excluded.notes`);
      const currentNotes = 'Current native baseline: API36 Play ARM64, 5038/5582 donor identity, 5 GiB, authenticated gRPC raw frames, AppKit/Metal presentation, ANGLE ES3.2 compatibility exposure, Vulkan/ranchu, virtio-gpu-asg, gfxstream and MoltenVK/Metal.';
      configStmt.run(currentConfigId,null,'TFTMAC native playable 5 GiB baseline',null,'37.1.11','37.0.1',REQUIRED_IMAGE,REQUIRED_IMAGE_MIN_REVISION,AVD_NAME,SERIAL,Number(ADB_PORT),Number(EMULATOR_PORT),BASELINE_PROFILE.vcpu,BASELINE_PROFILE.ramMB,BASELINE_PROFILE.width,BASELINE_PROFILE.height,BASELINE_PROFILE.density,BASELINE_PROFILE.refreshHz,'host',1,BASELINE_PROFILE.glTransport,'GuestAngle + explicit ES3.2 compatibility exposure','ranchu / guest Vulkan','gfxstream host Vulkan -> MoltenVK/Metal','native AppKit Metal embedded','CONTROL',sessionFile.startedUTC ?? now,currentNotes);
      configStmt.run(candidateConfigId,'tftmac_official_baseline_v1','RAM 5 GiB candidate (historical)',null,'37.1.11','37.0.1',REQUIRED_IMAGE,REQUIRED_IMAGE_MIN_REVISION,AVD_NAME,SERIAL,Number(ADB_PORT),Number(EMULATOR_PORT),6,5120,1920,1080,320,60,'host',1,'virtio-gpu-asg','same as historical 6 GiB baseline','same as historical baseline','same as historical baseline','same as historical baseline','HISTORICAL',now,'Preserved historical 6144 -> 5120 MiB experiment receipt; current authority is tftmac_5gb_native_v1.');

      db.prepare(`INSERT INTO sessions(
        id,runtime_config_id,started_utc,ended_utc,host_start_mono_ns,host_end_mono_ns,boot_class,workload_class,
        package_name,package_version_name,package_version_code,package_state_sha256,renderer_state_sha256,session_manifest_sha256,
        package_updated_during_session,capture_state,semantic_valid,invalid_reason,notes
      ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET runtime_config_id=excluded.runtime_config_id,ended_utc=excluded.ended_utc,
        host_end_mono_ns=excluded.host_end_mono_ns,workload_class=excluded.workload_class,package_version_name=excluded.package_version_name,
        package_version_code=excluded.package_version_code,package_state_sha256=excluded.package_state_sha256,
        renderer_state_sha256=excluded.renderer_state_sha256,capture_state=excluded.capture_state,semantic_valid=excluded.semantic_valid,
        invalid_reason=excluded.invalid_reason,notes=excluded.notes`)
        .run(labSessionId,currentConfigId,analysis.match.matchEntryMarker.utc,analysis.match.matchResultMarker.utc,
          asNumber(analysis.match.matchEntryMarker.host_mono_ns),asNumber(analysis.match.matchResultMarker.host_mono_ns),
          'COLD','MIXED',PACKAGE,analysis.package.versionName,analysis.package.versionCode,
          exists(packageFile) ? sha256File(packageFile) : null,exists(rendererFile) ? sha256File(rendererFile) : null,null,
          sessionFile.packageUpdatedDuringSession ? 1 : 0,'PARTIAL',1,
          'Native Unreal/Vulkan frame timing is not visible through gfxinfo; resource-envelope baseline is valid but frame-pacing attribution is not yet measurable.',
          `Gameplay match ${analysis.match.matchOrdinal}; placement=${analysis.match.placement ?? 'unknown'}; duration=${analysis.match.durationSeconds.toFixed(1)}s; installer=${analysis.package.installerPackage}.`);

      db.prepare('DELETE FROM metrics WHERE session_id=?').run(labSessionId);
      const metricStmt = db.prepare('INSERT INTO metrics(session_id,experiment_id,metric_scope,metric_name,metric_value,unit,source_artifact_id,semantic_valid,notes) VALUES(?,?,?,?,?,?,?,?,?)');
      const addMetric = (scope,name,value,unit,semanticValid=1,notes=null) => { if (Number.isFinite(Number(value))) metricStmt.run(labSessionId,null,scope,name,Number(value),unit,null,semanticValid,notes); };
      addMetric('MATCH','duration',analysis.match.durationSeconds,'seconds');
      addMetric('MATCH','placement',analysis.match.placement,'rank');
      addMetric('HOST_CPU','emulator_cpu_mean',analysis.hostEmulator.cpuPercent.mean,'percent');
      addMetric('HOST_CPU','emulator_cpu_p95',analysis.hostEmulator.cpuPercent.p95,'percent');
      addMetric('HOST_CPU','emulator_cpu_max',analysis.hostEmulator.cpuPercent.max,'percent');
      addMetric('MEMORY','emulator_rss_mean',analysis.hostEmulator.rssMiB.mean,'MiB');
      addMetric('MEMORY','emulator_rss_p95',analysis.hostEmulator.rssMiB.p95,'MiB');
      addMetric('MEMORY','emulator_rss_max',analysis.hostEmulator.rssMiB.max,'MiB');
      addMetric('MEMORY','host_available_min',analysis.memory.hostAvailableGiB.min,'GiB');
      addMetric('MEMORY','host_compressed_mean',analysis.memory.hostCompressedGiB.mean,'GiB');
      addMetric('MEMORY','host_compressed_p95',analysis.memory.hostCompressedGiB.p95,'GiB');
      addMetric('MEMORY','host_compressed_max',analysis.memory.hostCompressedGiB.max,'GiB');
      addMetric('MEMORY','host_swap_mean',analysis.memory.hostSwapUsedGiB.mean,'GiB');
      addMetric('MEMORY','host_swap_max',analysis.memory.hostSwapUsedGiB.max,'GiB');
      addMetric('MEMORY','guest_available_min',analysis.memory.guestAvailableGiB.min,'GiB');
      addMetric('MEMORY','pageout_delta',analysis.memory.pageoutDelta,'pages');
      addMetric('FRAME','native_frame_samples',analysis.frameMetrics.count,'count',0,'gfxinfo does not observe the Unreal native Vulkan presentation path.');
      addMetric('ANDROID_UI','tft_anr_count_full_capture',analysis.logSignals.android.tftAnrCount,'count',1,'Includes startup/login/patch period, not attributed to match rendering.');
      addMetric('SURFACEFLINGER','cumulative_total_missed_frames',sfCounters.totalMissedFrames,'count',0,'Cumulative display counter since boot; not match-scoped.');
      addMetric('SURFACEFLINGER','cumulative_gpu_missed_frames',sfCounters.gpuMissedFrames,'count',0,'Cumulative display counter since boot; not match-scoped.');
      addMetric('SURFACEFLINGER','cumulative_hwc_missed_frames',sfCounters.hwcMissedFrames,'count',0,'Cumulative display counter since boot; not match-scoped.');
      addMetric('SURFACEFLINGER','render_rate_hz',sfCounters.renderRateHz,'Hz',0,'Observed after match; validates 60 Hz display target but is not a match-window statistic.');

      db.prepare(`INSERT INTO hypotheses(id,title,boundary,statement,predicted_signature,falsification_condition,status,confidence,nominated_from_session_id,created_at,notes)
        VALUES(?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET status=excluded.status,confidence=excluded.confidence,nominated_from_session_id=excluded.nominated_from_session_id,notes=excluded.notes`)
        .run('h_guest_ram_host_pressure','Guest RAM allocation amplifies host memory pressure','MEMORY','The 6144 MB Android guest contributes enough host RSS/compression/pageout pressure to worsen gameplay responsiveness on the 16 GiB M4 host.','A 5120 MB one-factor run materially lowers emulator RSS/host compression while preserving adequate guest headroom without OOM/LMK instability.','5120 MB does not reduce memory pressure, materially degrades guest headroom, or worsens stability/performance under comparable gameplay.','QUEUED',0.60,labSessionId,now,`Baseline: RSS mean ${analysis.hostEmulator.rssMiB.mean.toFixed(0)} MiB, max ${analysis.hostEmulator.rssMiB.max.toFixed(0)} MiB; host compressed mean ${analysis.memory.hostCompressedGiB.mean.toFixed(2)} GiB; pageout delta ${analysis.memory.pageoutDelta}.`);
      db.prepare(`UPDATE hypotheses SET status='TESTING',confidence=?,nominated_from_session_id=?,notes=? WHERE id='h_memory_pressure'`)
        .run(0.60,labSessionId,`Match ${analysis.match.matchOrdinal} showed active host pageouts (+${analysis.memory.pageoutDelta}) with compressed memory mean ${analysis.memory.hostCompressedGiB.mean.toFixed(2)} GiB; causal attribution still requires A/B.`);
      db.prepare(`INSERT INTO hypotheses(id,title,boundary,statement,predicted_signature,falsification_condition,status,confidence,nominated_from_session_id,created_at,notes)
        VALUES(?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET status=excluded.status,confidence=excluded.confidence,nominated_from_session_id=excluded.nominated_from_session_id,notes=excluded.notes`)
        .run('h_gpu_frame_miss','GPU-side presentation misses contribute to visible lag','SURFACEFLINGER','A meaningful portion of visible gameplay lag is caused by GPU/presentation misses somewhere in the Unreal -> ANGLE -> Vulkan -> gfxstream -> MoltenVK -> Metal path.','TFT-specific android.surfaceflinger.frametimeline traces show GPU-missed or late frames correlated with visible stalls while host memory state is controlled.','TFT-specific frametimeline remains healthy during visible stalls, or misses disappear without improving perceived performance.','QUEUED',0.35,labSessionId,now,`SurfaceFlinger cumulative counters after the match: total=${sfCounters.totalMissedFrames ?? 'unknown'}, GPU=${sfCounters.gpuMissedFrames ?? 'unknown'}, HWC=${sfCounters.hwcMissedFrames ?? 'unknown'}. Counters are since boot and therefore only nomination evidence.`);

      const evidenceStmt = db.prepare(`INSERT OR REPLACE INTO evidence(id,hypothesis_id,session_id,experiment_id,evidence_type,claim,relation,strength,source_artifact_id,created_at,notes) VALUES(?,?,?,?,?,?,?,?,?,?,?)`);
      evidenceStmt.run(`ev_match_${analysis.match.matchOrdinal}_runtime`,null,labSessionId,null,'CONFIG_OBSERVATION',`Official TFT ${analysis.package.versionName} (${analysis.package.versionCode}) completed match ${analysis.match.matchOrdinal} with placement ${analysis.match.placement ?? 'unknown'} on Emulator37.1.11 / Android16 API36 using ANGLE -> Vulkan/ranchu -> virtio-gpu-asg/gfxstream -> MoltenVK/Metal.`,'NEUTRAL','DECISIVE',null,now,'Functional playability is proven; graphics conformance is not claimed because ES3.2 exposure is an explicit compatibility adapter.');
      evidenceStmt.run(`ev_match_${analysis.match.matchOrdinal}_memory`,'h_memory_pressure',labSessionId,null,'DIRECT_MEASUREMENT',`During the ${analysis.match.durationSeconds.toFixed(0)}s match, emulator RSS averaged ${analysis.hostEmulator.rssMiB.mean.toFixed(0)} MiB and peaked ${analysis.hostEmulator.rssMiB.max.toFixed(0)} MiB; host compressed memory averaged ${analysis.memory.hostCompressedGiB.mean.toFixed(2)} GiB and pageouts increased by ${analysis.memory.pageoutDelta}.`,'SUPPORTS','MODERATE',null,now,'Supports memory pressure as a candidate cause; does not prove causality.');
      evidenceStmt.run(`ev_match_${analysis.match.matchOrdinal}_cpu`,null,labSessionId,null,'DIRECT_MEASUREMENT',`Emulator host CPU averaged ${analysis.hostEmulator.cpuPercent.mean.toFixed(1)}% with p95 ${analysis.hostEmulator.cpuPercent.p95.toFixed(1)}% and max ${analysis.hostEmulator.cpuPercent.max.toFixed(1)}% during the match.`,'NEUTRAL','STRONG',null,now,'Does not show aggregate host-emulator CPU saturation; guest-thread scheduling remains unmeasured.');
      evidenceStmt.run(`ev_match_${analysis.match.matchOrdinal}_frame_blindspot`,null,labSessionId,null,'NEGATIVE_RESULT','gfxinfo produced zero native gameplay frame samples for the Unreal/Vulkan match window.','NEUTRAL','DECISIVE',null,now,'Future optimization decisions require Perfetto/SurfaceFlinger/AGI-class native frame timing; do not infer FPS from gfxinfo for this workload.');
      if (traceCaps?.perfettoAvailable) {
        evidenceStmt.run(`ev_match_${analysis.match.matchOrdinal}_trace_capabilities`,null,labSessionId,null,'CONFIG_OBSERVATION','The API36 guest exposes Perfetto android.surfaceflinger.frame, android.surfaceflinger.frametimeline, android.surfaceflinger.layers, android.gpu.memory, linux.ftrace, linux.process_stats and linux.sys_stats data sources.','SUPPORTS','DECISIVE',null,now,'These are the authoritative next-run native telemetry sources.');
      }
      if (Number.isFinite(Number(sfCounters.totalMissedFrames))) {
        evidenceStmt.run(`ev_match_${analysis.match.matchOrdinal}_sf_cumulative`,'h_gpu_frame_miss',labSessionId,null,'CONFIG_OBSERVATION',`SurfaceFlinger cumulative display counters observed after the match: total missed=${sfCounters.totalMissedFrames}, GPU missed=${sfCounters.gpuMissedFrames}, HWC missed=${sfCounters.hwcMissedFrames}, render rate=${sfCounters.renderRateHz} Hz, TFT requested 60 Hz=${sfCounters.gameRequested60Hz}.`,'SUPPORTS','WEAK',null,now,'Counters are cumulative since boot and include non-TFT periods; use only to nominate GPU-frame tracing, not to attribute the match.');
      }
      if (latestTraceMetadata?.sha256) {
        evidenceStmt.run(`ev_match_${analysis.match.matchOrdinal}_native_trace`,null,labSessionId,null,'CONFIG_OBSERVATION',`Bounded Perfetto collector produced a ${latestTraceMetadata.durationSeconds}s raw trace (${latestTraceMetadata.byteCount} bytes, SHA-256 ${latestTraceMetadata.sha256}) using ${latestTraceMetadata.dataSources.join(', ')}.`,'SUPPORTS','STRONG',null,now,`Collector smoke succeeded; parse state=${latestTraceMetadata.parseState}. Counter delta=${JSON.stringify(latestTraceMetadata.counterDelta ?? {})}.`);
      }

      db.prepare(`INSERT INTO unknowns(id,question,boundary,status,blocking,resolution_evidence_id,opened_at,resolved_at,notes)
        VALUES(?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET status=excluded.status,blocking=excluded.blocking,resolution_evidence_id=excluded.resolution_evidence_id,notes=excluded.notes`)
        .run('u_native_frame_timing','What is the real Unreal/Vulkan frame-time distribution and which boundary owns the visible stalls?','FRAME_TIMING','OPEN',1,`ev_match_${analysis.match.matchOrdinal}_frame_blindspot`,now,null,'Blocking for graphics/performance tuning. Exact available sources are android.surfaceflinger.frame + frametimeline + layers, android.gpu.memory, linux.ftrace/process_stats/sys_stats. Capture them during real combat.');
      db.prepare(`UPDATE unknowns SET status='RESOLVED',resolved_at=?,notes=? WHERE id='u_observed_renderer_path'`)
        .run(now,'Observed path: TFT -> ANGLE -> Vulkan/ranchu -> virtio-gpu-asg/gfxstream -> MoltenVK/Metal.');
      db.prepare(`UPDATE unknowns SET status='RESOLVED',resolved_at=?,notes=? WHERE id='u_one_guest_controls'`)
        .run(now,'One official API36 Google Play AVD installed/updated official TFT and completed a full match using the TFTMAC compatibility profile.');

      db.prepare(`INSERT INTO experiments(id,hypothesis_id,name,experiment_type,baseline_config_id,candidate_config_id,run_class,one_factor,state,required_cold_confirmation,semantic_gate,created_at,completed_at,notes)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET baseline_config_id=excluded.baseline_config_id,candidate_config_id=excluded.candidate_config_id,state=excluded.state,semantic_gate=excluded.semantic_gate,notes=excluded.notes`)
        .run('exp_ram_5gb_ab','h_guest_ram_host_pressure','Guest RAM 6144 -> 5120 MB A/B','INTERVENTION','tftmac_official_baseline_v1',candidateConfigId,'HEAVY',1,'COMPLETE',1,'Historical one-factor experiment preserved; current native runs hold 5120 MiB unless a new explicit experiment is selected.',now,now,'Historical RAM experiment closed by promotion of the 5120-MiB native baseline.');
      db.prepare(`INSERT INTO experiments(id,hypothesis_id,name,experiment_type,baseline_config_id,candidate_config_id,run_class,one_factor,state,required_cold_confirmation,semantic_gate,created_at,completed_at,notes)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET baseline_config_id=excluded.baseline_config_id,state=excluded.state,semantic_gate=excluded.semantic_gate,notes=excluded.notes`)
        .run('exp_native_frame_trace',null,'Native Unreal/Vulkan frame-timing capture','OBSERVATION',currentConfigId,null,'HEAVY',0,'PLANNED',0,'Capture android.surfaceflinger.frame + android.surfaceflinger.frametimeline + android.surfaceflinger.layers + android.gpu.memory during real TFT combat; align to existing host monotonic clock and optionally add linux.ftrace only in the heavier validation run.',now,null,'Measurement experiment; must precede graphics transport/queue tuning. Available Perfetto sources were proven directly on the current guest.');
      db.prepare(`UPDATE experiments SET state='COMPLETE',baseline_config_id=?,completed_at=?,notes=? WHERE id='exp_control_direct_play'`)
        .run(currentConfigId,now,`First official full match completed with placement ${analysis.match.placement}; resource telemetry valid; native frame timing unavailable through gfxinfo.`);
      db.prepare(`UPDATE experiments SET state='CANCELLED',notes=COALESCE(notes,'') || ? WHERE id IN ('exp_control_repeat_warm','exp_transition_capture','exp_heavy_capture') AND baseline_config_id='control_stock_direct_v0'`)
        .run(' Superseded by the proven tftmac_official_baseline_v1 baseline and native Perfetto trace experiment.');
      db.prepare('INSERT OR REPLACE INTO experiment_sessions(experiment_id,session_id,role) VALUES(?,?,?)').run('exp_control_direct_play',labSessionId,analysis.match.matchOrdinal === 1 ? 'BASELINE' : 'DIAGNOSTIC');

      db.exec('COMMIT;');
    } catch (error) {
      try { db.exec('ROLLBACK;'); } catch {}
      throw error;
    }
    const summary = {
      databasePath,
      databaseSHA256: sha256File(databasePath),
      session: db.prepare('SELECT id,runtime_config_id,workload_class,capture_state,semantic_valid,notes FROM sessions WHERE id=?').get(labSessionId),
      metrics: db.prepare('SELECT metric_scope,metric_name,metric_value,unit,semantic_valid FROM metrics WHERE session_id=? ORDER BY metric_scope,metric_name').all(labSessionId),
      openHypotheses: db.prepare("SELECT id,title,status,confidence FROM hypotheses WHERE status IN ('QUEUED','TESTING','SUPPORTED') ORDER BY confidence DESC,id").all(),
      plannedExperiments: db.prepare("SELECT id,name,state,one_factor,baseline_config_id,candidate_config_id FROM experiments WHERE state='PLANNED' ORDER BY id").all(),
      blockingUnknowns: db.prepare("SELECT id,question,boundary,status FROM unknowns WHERE blocking=1 AND status='OPEN' ORDER BY id").all()
    };
    writeJSON(path.join(captureDir, `lab-ingest-match-${analysis.match.matchOrdinal}.json`), summary);
    writeJSON(path.join(captureDir, 'lab-ingest.json'), summary);
    return summary;
  } finally {
    try { db.close(); } catch {}
  }
}

function surfaceFlingerCounters(runtime) {
  const dump = adb(runtime, ['shell', 'dumpsys', 'SurfaceFlinger', '--help'], { allowFailure: true, timeout: 30000, maxBuffer: 32 * 1024 * 1024 });
  const text = `${dump.stdout}\n${dump.stderr}`;
  return {
    observedAt: nowISO(),
    status: dump.status,
    renderRateHz: Number(text.match(/renderRate=([0-9.]+) Hz/)?.[1] ?? NaN) || null,
    totalMissedFrames: matchNumber(text, /Total missed frame count:\s*(\d+)/),
    hwcMissedFrames: matchNumber(text, /HWC missed frame count:\s*(\d+)/),
    gpuMissedFrames: matchNumber(text, /GPU missed frame count:\s*(\d+)/),
    gameRequested60Hz: /GameFrameRateOverrides=[\s\S]*\{10215,\s*0\s+60\}/.test(text) || /GameActivity[^\n]*requestedFrameRate:\s*\{60\.00 Hz/.test(text)
  };
}

function nativeTraceConfig(durationSeconds) {
  const durationMs = Math.max(1000, Math.round(durationSeconds * 1000));
  return `buffers { size_kb: 16384 fill_policy: RING_BUFFER }

data_sources { config { name: "android.surfaceflinger.frame" target_buffer: 0 } }
data_sources { config { name: "android.surfaceflinger.frametimeline" target_buffer: 0 } }
data_sources { config { name: "android.surfaceflinger.layers" target_buffer: 0 } }
data_sources { config { name: "android.gpu.memory" target_buffer: 0 } }
duration_ms: ${durationMs}
`;
}

async function analyzeLatestClosedRunFast() {
  ensureDir(CAPTURE_ROOT);
  const candidates = fs.readdirSync(CAPTURE_ROOT, { withFileTypes: true })
    .filter(entry => entry.isDirectory())
    .map(entry => {
      const dir = path.join(CAPTURE_ROOT, entry.name);
      return { id: entry.name, dir, session: readJSON(path.join(dir, 'session.json'), null) };
    })
    .filter(row => row.session?.endedUTC)
    .sort((a, b) => a.id.localeCompare(b.id));
  const target = candidates.at(-1);
  if (!target) throw new Error('NO_CLOSED_RUN_AVAILABLE_FOR_FAST_ANALYSIS');
  const startNs = Number(target.session.hostStartMonoNs);
  const endNs = Number(target.session.hostEndMonoNs);
  if (!Number.isFinite(startNs) || !Number.isFinite(endNs) || endNs <= startNs) throw new Error('CLOSED_RUN_WINDOW_INVALID');

  const binSeconds = 600;
  const binNs = binSeconds * 1e9;
  const binCount = Math.max(1, Math.ceil((endNs - startNs) / binNs));
  const bins = Array.from({ length: binCount }, (_, index) => ({
    index: index + 1,
    startSeconds: index * binSeconds,
    durationSeconds: Math.min(binSeconds, Math.max(0, (endNs - (startNs + index * binNs)) / 1e9)),
    cpu: [], rss: [], hostAvailable: [], hostCompressed: [], guestAvailable: [], swap: [],
    pageoutFirst: null, pageoutLast: null,
    sfFirst: null, sfLast: null
  }));
  const overall = { cpu: [], rss: [], hostAvailable: [], hostCompressed: [], guestAvailable: [], swap: [], pageoutFirst: null, pageoutLast: null };
  const gib = 1024 ** 3;
  const binFor = mono => {
    const index = Math.floor((mono - startNs) / binNs);
    return index >= 0 && index < bins.length ? bins[index] : null;
  };

  const streamJsonl = async (file, consume) => {
    if (!exists(file)) return;
    const readline = await import('node:readline');
    const input = fs.createReadStream(file, { encoding: 'utf8' });
    const rl = readline.createInterface({ input, crlfDelay: Infinity });
    for await (const line of rl) {
      if (!line.trim()) continue;
      let row;
      try { row = JSON.parse(line); } catch { continue; }
      consume(row);
    }
  };

  await streamJsonl(path.join(target.dir, 'host-process.jsonl'), row => {
    if (!/qemu-system-aarch64|\/emulator(?:\s|$)/i.test(String(row.command ?? ''))) return;
    const mono = Number(row.host_mono_ns);
    if (!Number.isFinite(mono) || mono < startNs || mono > endNs) return;
    const cpu = Number(row.cpu_pct);
    const rss = Number(row.rss_kb) / 1024;
    const bin = binFor(mono);
    if (Number.isFinite(cpu)) { overall.cpu.push(cpu); bin?.cpu.push(cpu); }
    if (Number.isFinite(rss)) { overall.rss.push(rss); bin?.rss.push(rss); }
  });

  await streamJsonl(path.join(target.dir, 'host-memory.jsonl'), row => {
    const mono = Number(row.host_mono_ns);
    if (!Number.isFinite(mono) || mono < startNs || mono > endNs) return;
    const values = {
      hostAvailable: Number(row.host_available_bytes) / gib,
      hostCompressed: Number(row.host_compressed_bytes) / gib,
      guestAvailable: Number(row.guest_available_bytes) / gib,
      swap: Number(row.host_swap_used_bytes) / gib
    };
    const pageout = Number(row.pageout_count);
    const bin = binFor(mono);
    for (const key of Object.keys(values)) {
      if (!Number.isFinite(values[key])) continue;
      overall[key].push(values[key]);
      bin?.[key].push(values[key]);
    }
    if (Number.isFinite(pageout)) {
      if (overall.pageoutFirst === null) overall.pageoutFirst = pageout;
      overall.pageoutLast = pageout;
      if (bin) {
        if (bin.pageoutFirst === null) bin.pageoutFirst = pageout;
        bin.pageoutLast = pageout;
      }
    }
  });

  await streamJsonl(path.join(target.dir, 'surfaceflinger', 'counters.jsonl'), row => {
    const mono = Number(row.host_mono_ns);
    if (!Number.isFinite(mono) || mono < startNs || mono > endNs) return;
    const bin = binFor(mono);
    if (!bin) return;
    if (!bin.sfFirst) bin.sfFirst = row;
    bin.sfLast = row;
  });

  const deltaCounter = (first, last, key) => {
    const a = Number(first?.[key]);
    const b = Number(last?.[key]);
    return Number.isFinite(a) && Number.isFinite(b) ? b - a : null;
  };
  const summarizeBin = bin => {
    const pageoutDelta = Number.isFinite(bin.pageoutFirst) && Number.isFinite(bin.pageoutLast) ? bin.pageoutLast - bin.pageoutFirst : null;
    const minutes = bin.durationSeconds / 60;
    return {
      index: bin.index,
      startSeconds: bin.startSeconds,
      durationSeconds: bin.durationSeconds,
      emulatorCpuMeanPct: summarizeNumbers(bin.cpu).mean,
      emulatorCpuP95Pct: summarizeNumbers(bin.cpu).p95,
      emulatorRssMeanMiB: summarizeNumbers(bin.rss).mean,
      hostAvailableMeanGiB: summarizeNumbers(bin.hostAvailable).mean,
      hostCompressedMeanGiB: summarizeNumbers(bin.hostCompressed).mean,
      guestAvailableMeanGiB: summarizeNumbers(bin.guestAvailable).mean,
      guestAvailableMinGiB: summarizeNumbers(bin.guestAvailable).min,
      pageoutDelta,
      pageoutsPerMinute: Number.isFinite(pageoutDelta) && minutes > 0 ? pageoutDelta / minutes : null,
      surfaceFlinger: {
        samples: bin.sfFirst ? 1 + (bin.sfLast && bin.sfLast !== bin.sfFirst ? 1 : 0) : 0,
        totalMissDelta: deltaCounter(bin.sfFirst, bin.sfLast, 'totalMissedFrames'),
        gpuMissDelta: deltaCounter(bin.sfFirst, bin.sfLast, 'gpuMissedFrames'),
        hwcMissDelta: deltaCounter(bin.sfFirst, bin.sfLast, 'hwcMissedFrames')
      }
    };
  };
  const summarizedBins = bins.map(summarizeBin).filter(bin => bin.durationSeconds > 0);
  const pageoutDelta = Number.isFinite(overall.pageoutFirst) && Number.isFinite(overall.pageoutLast) ? overall.pageoutLast - overall.pageoutFirst : null;
  const durationSeconds = (endNs - startNs) / 1e9;
  const markers = readJSONL(path.join(target.dir, 'markers.jsonl'));
  const seal = readJSON(path.join(target.dir, 'capture-seal.json'), null);
  const result = {
    schema: 1,
    observedAt: nowISO(),
    sessionId: target.id,
    captureDir: target.dir,
    session: {
      startedUTC: target.session.startedUTC,
      endedUTC: target.session.endedUTC,
      captureState: target.session.captureState ?? null,
      rawCaptureState: target.session.rawCaptureState ?? null,
      durationSeconds
    },
    seal: seal ? {
      rawCaptureState: seal.rawCaptureState ?? null,
      rawManifestSHA256: seal.rawManifestSHA256 ?? null,
      manifestSHA256: seal.finalManifestSHA256 ?? seal.manifestSHA256 ?? null,
      semanticValid: seal.semanticValid ?? null
    } : null,
    wholeRun: {
      emulatorCpuPercent: summarizeNumbers(overall.cpu),
      emulatorRssMiB: summarizeNumbers(overall.rss),
      hostAvailableGiB: summarizeNumbers(overall.hostAvailable),
      hostCompressedGiB: summarizeNumbers(overall.hostCompressed),
      guestAvailableGiB: summarizeNumbers(overall.guestAvailable),
      hostSwapUsedGiB: summarizeNumbers(overall.swap),
      pageoutDelta,
      pageoutsPerMinute: Number.isFinite(pageoutDelta) && durationSeconds > 0 ? pageoutDelta / (durationSeconds / 60) : null
    },
    bins: summarizedBins,
    annotations: {
      gameSettings: markers.filter(row => row.event === 'GAME_SETTINGS'),
      qualityReports: markers.filter(row => row.event === 'USER_QUALITY_REPORT'),
      matchResults: markers.filter(row => row.event === 'MATCH_RESULT')
    },
    attributionRule: 'Only explicit GAME_SETTINGS timestamps define exact preset windows. User-observed Ultra High lag without a switch timestamp is decisive usability evidence but not assigned to an arbitrary telemetry bin.'
  };
  writeJSON(path.join(target.dir, 'closed-run-fast-analysis.json'), result);
  return result;
}

function latestClosedRunFastResult() {
  ensureDir(CAPTURE_ROOT);
  const candidates = fs.readdirSync(CAPTURE_ROOT, { withFileTypes: true })
    .filter(entry => entry.isDirectory())
    .map(entry => {
      const dir = path.join(CAPTURE_ROOT, entry.name);
      return { id: entry.name, dir, session: readJSON(path.join(dir, 'session.json'), null) };
    })
    .filter(row => row.session?.endedUTC)
    .sort((a, b) => a.id.localeCompare(b.id));
  const target = candidates.at(-1);
  if (!target) throw new Error('NO_CLOSED_RUN_AVAILABLE');
  const analysis = readJSON(path.join(target.dir, 'closed-run-fast-analysis.json'), null);
  if (!analysis) throw new Error(`FAST_ANALYSIS_RESULT_MISSING: ${target.id}`);
  return {
    sessionId: analysis.sessionId,
    session: analysis.session,
    seal: analysis.seal,
    wholeRun: analysis.wholeRun,
    bins: analysis.bins,
    annotations: analysis.annotations,
    attributionRule: analysis.attributionRule
  };
}

function analyzeLatestClosedRunTrends() {
  ensureDir(CAPTURE_ROOT);
  const candidates = fs.readdirSync(CAPTURE_ROOT, { withFileTypes: true })
    .filter(entry => entry.isDirectory())
    .map(entry => {
      const dir = path.join(CAPTURE_ROOT, entry.name);
      const session = readJSON(path.join(dir, 'session.json'), null);
      return { id: entry.name, dir, session };
    })
    .filter(row => row.session?.endedUTC && exists(path.join(row.dir, 'host-memory.jsonl')) && exists(path.join(row.dir, 'host-process.jsonl')))
    .sort((a, b) => a.id.localeCompare(b.id));
  const target = candidates.at(-1);
  if (!target) throw new Error('NO_CLOSED_RUN_AVAILABLE_FOR_TREND_ANALYSIS');
  const startNs = Number(target.session.hostStartMonoNs);
  const endNs = Number(target.session.hostEndMonoNs);
  if (!Number.isFinite(startNs) || !Number.isFinite(endNs) || endNs <= startNs) throw new Error('CLOSED_RUN_WINDOW_INVALID');
  const processRows = readJSONL(path.join(target.dir, 'host-process.jsonl'));
  const memoryRows = readJSONL(path.join(target.dir, 'host-memory.jsonl'));
  const sfRows = readJSONL(path.join(target.dir, 'surfaceflinger', 'counters.jsonl'));
  const emulatorRows = processRows.filter(row => /qemu-system-aarch64|\/emulator(?:\s|$)/i.test(String(row.command ?? '')));
  const gib = 1024 ** 3;
  const binSeconds = 600;
  const binNs = binSeconds * 1e9;
  const bins = [];
  for (let binStart = startNs, index = 1; binStart < endNs; binStart += binNs, index += 1) {
    const binEnd = Math.min(endNs, binStart + binNs);
    const p = emulatorRows.filter(row => { const n = Number(row.host_mono_ns); return Number.isFinite(n) && n >= binStart && n < binEnd; });
    const m = memoryRows.filter(row => { const n = Number(row.host_mono_ns); return Number.isFinite(n) && n >= binStart && n < binEnd; });
    const s = sfRows.filter(row => { const n = Number(row.host_mono_ns); return Number.isFinite(n) && n >= binStart && n < binEnd; });
    const pageouts = m.map(row => Number(row.pageout_count)).filter(Number.isFinite);
    const sfDelta = key => s.length > 1 && Number.isFinite(Number(s[0][key])) && Number.isFinite(Number(s.at(-1)[key])) ? Number(s.at(-1)[key]) - Number(s[0][key]) : null;
    const durationMinutes = (binEnd - binStart) / 1e9 / 60;
    const pageoutDelta = pageouts.length > 1 ? pageouts.at(-1) - pageouts[0] : null;
    bins.push({
      index,
      startSeconds: (binStart - startNs) / 1e9,
      durationSeconds: (binEnd - binStart) / 1e9,
      emulatorCpuMeanPct: summarizeNumbers(p.map(row => Number(row.cpu_pct))).mean,
      emulatorCpuP95Pct: summarizeNumbers(p.map(row => Number(row.cpu_pct))).p95,
      emulatorRssMeanMiB: summarizeNumbers(p.map(row => Number(row.rss_kb) / 1024)).mean,
      hostAvailableMeanGiB: summarizeNumbers(m.map(row => Number(row.host_available_bytes) / gib)).mean,
      hostCompressedMeanGiB: summarizeNumbers(m.map(row => Number(row.host_compressed_bytes) / gib)).mean,
      guestAvailableMeanGiB: summarizeNumbers(m.map(row => Number(row.guest_available_bytes) / gib)).mean,
      pageoutDelta,
      pageoutsPerMinute: Number.isFinite(pageoutDelta) && durationMinutes > 0 ? pageoutDelta / durationMinutes : null,
      surfaceFlinger: {
        samples: s.length,
        totalMissDelta: sfDelta('totalMissedFrames'),
        gpuMissDelta: sfDelta('gpuMissedFrames'),
        hwcMissDelta: sfDelta('hwcMissedFrames')
      }
    });
  }
  const validBins = bins.filter(bin => Number.isFinite(bin.hostCompressedMeanGiB));
  const first = validBins[0] ?? null;
  const last = validBins.at(-1) ?? null;
  const delta = (a, b) => Number.isFinite(a) && Number.isFinite(b) ? a - b : null;
  const result = {
    observedAt: nowISO(),
    sessionId: target.id,
    runDurationSeconds: (endNs - startNs) / 1e9,
    binSeconds,
    bins,
    firstToLast: first && last ? {
      emulatorCpuMeanPct: delta(last.emulatorCpuMeanPct, first.emulatorCpuMeanPct),
      emulatorRssMeanMiB: delta(last.emulatorRssMeanMiB, first.emulatorRssMeanMiB),
      hostAvailableMeanGiB: delta(last.hostAvailableMeanGiB, first.hostAvailableMeanGiB),
      hostCompressedMeanGiB: delta(last.hostCompressedMeanGiB, first.hostCompressedMeanGiB),
      guestAvailableMeanGiB: delta(last.guestAvailableMeanGiB, first.guestAvailableMeanGiB),
      pageoutsPerMinute: delta(last.pageoutsPerMinute, first.pageoutsPerMinute)
    } : null,
    note: 'Ten-minute windows over the latest closed raw run. Use trends to identify progressive pressure; different workload intensity between windows can still affect CPU/RSS.'
  };
  writeJSON(path.join(target.dir, 'run-trend-analysis.json'), result);
  return result;
}

function compareLatestRuns() {
  ensureDir(CAPTURE_ROOT);
  const rows = fs.readdirSync(CAPTURE_ROOT, { withFileTypes: true })
    .filter(entry => entry.isDirectory())
    .map(entry => {
      const dir = path.join(CAPTURE_ROOT, entry.name);
      const continuous = path.join(dir, 'continuous-run-analysis.json');
      const gameplay = path.join(dir, 'gameplay-analysis.json');
      const trend = path.join(dir, 'run-trend-analysis.json');
      return { id: entry.name, dir, analysisPath: exists(continuous) ? continuous : (exists(gameplay) ? gameplay : (exists(trend) ? trend : null)) };
    })
    .filter(row => row.analysisPath)
    .sort((a, b) => a.id.localeCompare(b.id))
    .slice(-4)
    .map(row => {
      const analysis = readJSON(row.analysisPath, {});
      const runtimeInfo = readJSON(path.join(row.dir, 'runtime-state.json'), {});
      const trendBins = Array.isArray(analysis.bins) ? analysis.bins : [];
      const trendDuration = trendBins.reduce((sum, bin) => sum + (Number(bin.durationSeconds) || 0), 0);
      const weightedTrend = key => trendDuration > 0
        ? trendBins.reduce((sum, bin) => sum + (Number(bin.durationSeconds) || 0) * (Number(bin[key]) || 0), 0) / trendDuration
        : null;
      const trendPageoutDelta = trendBins.length ? trendBins.reduce((sum, bin) => sum + (Number(bin.pageoutDelta) || 0), 0) : null;
      const mem = analysis.memory ?? (trendBins.length ? {
        hostAvailableGiB: { mean: weightedTrend('hostAvailableMeanGiB') },
        hostCompressedGiB: { mean: weightedTrend('hostCompressedMeanGiB'), p95: null },
        hostSwapUsedGiB: { mean: null },
        guestAvailableGiB: { mean: weightedTrend('guestAvailableMeanGiB'), min: null },
        pageoutDelta: trendPageoutDelta
      } : {});
      const cpu = analysis.hostEmulator?.cpuPercent ?? (trendBins.length ? { mean: weightedTrend('emulatorCpuMeanPct'), p95: null } : {});
      const rss = analysis.hostEmulator?.rssMiB ?? (trendBins.length ? { mean: weightedTrend('emulatorRssMeanMiB'), p95: null } : {});
      return {
        sessionId: row.id,
        control: runtimeInfo.control ?? analysis.runtimeConfig ?? null,
        ramMB: runtimeInfo.ramMB ?? null,
        durationSeconds: analysis.run?.durationSeconds ?? analysis.match?.durationSeconds ?? analysis.runDurationSeconds ?? null,
        captureState: analysis.run?.captureState ?? analysis.captureState ?? readJSON(path.join(row.dir, 'session.json'), {})?.captureState ?? null,
        completedMatches: analysis.annotations?.completedMatches ?? (analysis.match ? 1 : 0),
        wins: analysis.annotations?.wins ?? (analysis.match?.placement === 1 ? 1 : 0),
        emulatorCpuMeanPct: cpu.mean ?? null,
        emulatorCpuP95Pct: cpu.p95 ?? null,
        emulatorRssMeanMiB: rss.mean ?? null,
        emulatorRssP95MiB: rss.p95 ?? null,
        hostAvailableMeanGiB: mem.hostAvailableGiB?.mean ?? null,
        hostCompressedMeanGiB: mem.hostCompressedGiB?.mean ?? null,
        hostCompressedP95GiB: mem.hostCompressedGiB?.p95 ?? null,
        hostSwapMeanGiB: mem.hostSwapUsedGiB?.mean ?? null,
        guestAvailableMeanGiB: mem.guestAvailableGiB?.mean ?? null,
        guestAvailableMinGiB: mem.guestAvailableGiB?.min ?? null,
        pageoutDelta: mem.pageoutDelta ?? null,
        pageoutsPerMinute: Number.isFinite(Number(mem.pageoutDelta)) && Number(analysis.run?.durationSeconds ?? analysis.match?.durationSeconds ?? analysis.runDurationSeconds) > 0
          ? Number(mem.pageoutDelta) / (Number(analysis.run?.durationSeconds ?? analysis.match?.durationSeconds ?? analysis.runDurationSeconds) / 60)
          : null,
        qualityReports: analysis.annotations?.qualityReports ?? []
      };
    });
  const baseline6 = [...rows].reverse().find(row => Number(row.ramMB) === 6144) ?? null;
  const candidate5 = [...rows].reverse().find(row => Number(row.ramMB) === 5120) ?? null;
  const safeDiff = (candidate, baseline) => Number.isFinite(candidate) && Number.isFinite(baseline) ? candidate - baseline : null;
  const delta = baseline6 && candidate5 ? {
    hostAvailableMeanGiB: safeDiff(candidate5.hostAvailableMeanGiB, baseline6.hostAvailableMeanGiB),
    hostCompressedMeanGiB: safeDiff(candidate5.hostCompressedMeanGiB, baseline6.hostCompressedMeanGiB),
    hostCompressedP95GiB: safeDiff(candidate5.hostCompressedP95GiB, baseline6.hostCompressedP95GiB),
    hostSwapMeanGiB: safeDiff(candidate5.hostSwapMeanGiB, baseline6.hostSwapMeanGiB),
    guestAvailableMeanGiB: safeDiff(candidate5.guestAvailableMeanGiB, baseline6.guestAvailableMeanGiB),
    pageoutDelta: safeDiff(candidate5.pageoutDelta, baseline6.pageoutDelta),
    pageoutsPerMinute: safeDiff(candidate5.pageoutsPerMinute, baseline6.pageoutsPerMinute),
    pageoutsPerMinutePercent: Number.isFinite(candidate5.pageoutsPerMinute) && Number.isFinite(baseline6.pageoutsPerMinute) && baseline6.pageoutsPerMinute !== 0
      ? 100 * (candidate5.pageoutsPerMinute - baseline6.pageoutsPerMinute) / baseline6.pageoutsPerMinute
      : null,
    emulatorCpuMeanPct: safeDiff(candidate5.emulatorCpuMeanPct, baseline6.emulatorCpuMeanPct),
    emulatorRssMeanMiB: safeDiff(candidate5.emulatorRssMeanMiB, baseline6.emulatorRssMeanMiB)
  } : null;
  return { observedAt: nowISO(), runs: rows, baseline6GiB: baseline6, candidate5GiB: candidate5, candidateMinusBaseline: delta };
}

function audioHealthCheck() {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  if (!state?.captureDir) throw new Error('No active direct-control session.');
  if (!deviceReady(runtime)) throw new Error('No active Android device for audio health check.');
  const captureDir = state.captureDir;
  const logPath = path.join(captureDir, 'logcat.raw.txt');
  const text = exists(logPath) ? fs.readFileSync(logPath, 'utf8') : '';
  const pcmWriteIoErrorCount = (text.match(/android\.hardware\.audio@7\.1-impl\.ranchu: pcmWrite:259 pcm_writei failed with 'cannot read\/write stream data: I\/O error'/g) ?? []).length;
  const pcmWriteFailureCount = (text.match(/android\.hardware\.audio@7\.1-impl\.ranchu: pcmWrite:260 failure: -1/g) ?? []).length;
  const audioDump = adb(runtime, ['shell', 'dumpsys', 'audio'], { allowFailure: true, timeout: 30000 }).stdout;
  const audioFlinger = adb(runtime, ['shell', 'dumpsys', 'media.audio_flinger'], { allowFailure: true, timeout: 30000 }).stdout;
  const pid = adb(runtime, ['shell', 'pidof', PACKAGE], { allowFailure: true, timeout: 10000 }).stdout.trim() || null;
  const tftPlayback = audioDump.split(/\r?\n/).filter(line => pid && line.includes(`/${pid}`) && /AudioPlaybackConfiguration/.test(line)).slice(-20);
  const activeTftPlayback = tftPlayback.some(line => /state:started/.test(line));
  const mixerUnderruns = audioFlinger.split(/\r?\n/).filter(line => /Normal mixer raw underrun counters/.test(line)).slice(-10);
  const ps = state.emulatorPid ? command('/bin/ps', ['-p', String(state.emulatorPid), '-ww', '-o', 'command='], { allowFailure: true, timeout: 10000 }).stdout.trim() : '';
  const explicitCoreAudio = /(?:^|\s)-audio\s+coreaudio(?:\s|$)/.test(ps);
  const result = {
    observedAt: nowISO(),
    sessionId: state.sessionId,
    tftPid: pid,
    explicitCoreAudio,
    pcmWriteIoErrorCount,
    pcmWriteFailureCount,
    activeTftPlayback,
    tftPlayback,
    mixerUnderruns,
    healthy: explicitCoreAudio && pcmWriteIoErrorCount === 0 && pcmWriteFailureCount === 0
  };
  writeJSON(path.join(captureDir, 'audio-health.json'), result);
  return result;
}

function emulatorScaleProbe() {
  const runtime = discover();
  const help = command(runtime.emulator, ['-help'], { allowFailure: true, env: runtime.env, timeout: 30000, maxBuffer: 16 * 1024 * 1024 });
  const lines = `${help.stdout}\n${help.stderr}`.split(/\r?\n/).filter(line => /scale|window|zoom|dpi|skin/i.test(line)).slice(0, 240);
  return { observedAt: nowISO(), status: help.status, lines };
}

function audioBackendProbe() {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  const helpAudio = command(runtime.emulator, ['-help-audio'], { allowFailure: true, env: runtime.env, timeout: 30000 });
  const helpAll = command(runtime.emulator, ['-help'], { allowFailure: true, env: runtime.env, timeout: 30000, maxBuffer: 16 * 1024 * 1024 });
  const hostAudio = command('/usr/sbin/system_profiler', ['SPAudioDataType'], { allowFailure: true, timeout: 30000, maxBuffer: 8 * 1024 * 1024 });
  const emulatorPs = state?.emulatorPid ? command('/bin/ps', ['-p', String(state.emulatorPid), '-ww', '-o', 'command='], { allowFailure: true, timeout: 10000 }) : { status: 1, stdout: '', stderr: '' };
  const select = text => String(text ?? '').split(/\r?\n/).filter(line => /audio|coreaudio|sound|speaker|backend|out=|in=|no-audio/i.test(line)).slice(0, 240);
  return {
    observedAt: nowISO(),
    emulatorPid: state?.emulatorPid ?? null,
    emulatorCommand: emulatorPs.stdout.trim() || null,
    helpAudio: { status: helpAudio.status, lines: select(`${helpAudio.stdout}\n${helpAudio.stderr}`) },
    helpAudioRaw: `${helpAudio.stdout}${helpAudio.stderr}`.trim().slice(0, 16000),
    helpRelevant: select(`${helpAll.stdout}\n${helpAll.stderr}`),
    hostAudioProfile: select(`${hostAudio.stdout}\n${hostAudio.stderr}`)
  };
}

function disconnectWindowAudit() {
  const state = readJSON(CONTROL_STATE);
  if (!state?.captureDir) throw new Error('No active direct-control session.');
  const captureDir = state.captureDir;
  const logPath = path.join(captureDir, 'logcat.raw.txt');
  const text = exists(logPath) ? fs.readFileSync(logPath, 'utf8').slice(-24 * 1024 * 1024) : '';
  const lines = text.split(/\r?\n/);
  const sessionInfo = readJSON(path.join(captureDir, 'session.json'), {});
  const expectedPid = String(sessionInfo.lastTftLaunchPid ?? '').trim() || null;
  const pidRx = expectedPid ? new RegExp(`\\b${expectedPid.replace(/[^0-9]/g, '')}\\b`) : null;
  const tftLines = lines.filter(line => !/\bartd\b/.test(line) && (
    /com\.riotgames\.league\.teamfighttactics/.test(line) ||
    (pidRx ? pidRx.test(line) : false) ||
    (/ConnectivityService/.test(line) && /(?:10215|RequestorPkg: com\.riotgames\.league\.teamfighttactics|LOST|UNAVAIL|NetReassign)/.test(line)) ||
    (/(?:ActivityTaskManager|ActivityManager|WindowManager)/.test(line) && /teamfighttactics|GameActivity|SplashActivity/.test(line))
  ));
  const highSignal = tftLines.filter(line => /disconnect|reconnect|LOST|UNAVAIL|timeout|timed out|connection|NetReassign|requestNetwork|destroy|stop|start|resume|pause|GameActivity|SplashActivity|network/i.test(line)).slice(-300);
  const networkRequests = highSignal.filter(line => /ConnectivityService.*(?:requestNetwork|NetReassign|LOST|UNAVAIL)/.test(line));
  const activityTransitions = highSignal.filter(line => /ActivityTaskManager|ActivityManager|WindowManager/.test(line));
  const result = {
    observedAt: nowISO(),
    sessionId: state.sessionId,
    currentTftPid: (() => { try { const runtime = discover(); return adb(runtime, ['shell', 'pidof', PACKAGE], { allowFailure: true, timeout: 10000 }).stdout.trim() || null; } catch { return null; } })(),
    networkRequests: networkRequests.slice(-120),
    activityTransitions: activityTransitions.slice(-120),
    highSignal: highSignal.slice(-220)
  };
  writeJSON(path.join(captureDir, 'disconnect-window-audit.json'), result);
  return result;
}

function runtimeFaultAudit() {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  if (!state?.captureDir) throw new Error('No active direct-control session.');
  if (!deviceReady(runtime)) throw new Error('No active Android device for runtime fault audit.');
  const captureDir = state.captureDir;
  const sessionInfo = readJSON(path.join(captureDir, 'session.json'), {});
  const knownLaunchPid = String(sessionInfo.lastTftLaunchPid ?? '').trim() || null;
  const currentPid = adb(runtime, ['shell', 'pidof', PACKAGE], { allowFailure: true, timeout: 10000 }).stdout.trim() || null;
  const audioDump = adb(runtime, ['shell', 'dumpsys', 'audio'], { allowFailure: true, timeout: 30000 }).stdout;
  const audioFlinger = adb(runtime, ['shell', 'dumpsys', 'media.audio_flinger'], { allowFailure: true, timeout: 30000 }).stdout;
  const audioPolicy = adb(runtime, ['shell', 'dumpsys', 'media.audio_policy'], { allowFailure: true, timeout: 30000 }).stdout;
  const musicVolume = adb(runtime, ['shell', 'media', 'volume', '--stream', '3', '--get'], { allowFailure: true, timeout: 10000 });
  const zenMode = adb(runtime, ['shell', 'settings', 'get', 'global', 'zen_mode'], { allowFailure: true, timeout: 10000 }).stdout.trim() || null;
  const logPath = path.join(captureDir, 'logcat.raw.txt');
  const hostLogPath = path.join(captureDir, 'emulator.stdout.log');
  const logText = exists(logPath) ? fs.readFileSync(logPath, 'utf8').slice(-20 * 1024 * 1024) : '';
  const hostLog = exists(hostLogPath) ? fs.readFileSync(hostLogPath, 'utf8') : '';
  const lines = logText.split(/\r?\n/);
  const networkRx = /disconnect|reconnect|connection\s+(?:lost|closed|reset|failed|failure)|network\s+(?:lost|unavailable|disconnect|failed|failure)|socket.*(?:closed|reset|timeout|failed)|timed?\s*out|ECONN|ENET|ETIMEDOUT|UnknownHost|DNS|ConnectivityService|NetworkMonitor|Cronet|WebSocket|libcurl|curl.*error|ssl.*(?:error|fail)|tls.*(?:error|fail)/i;
  const riotRx = /riotgames|teamfighttactics|riotclient|riot|league/i;
  const audioRx = /AudioTrack|AudioFlinger|AudioPolicy|AAudio|OpenSL|audio.*(?:error|fail|underrun|dead|disconnect|mute)|CoreAudio|qemu.*audio/i;
  const networkEvidence = lines.filter(line => networkRx.test(line) && (riotRx.test(line) || /ConnectivityService|NetworkMonitor|netd|Cronet|DNS|ssl|tls/i.test(line))).slice(-240);
  const audioLogEvidence = lines.filter(line => audioRx.test(line)).slice(-180);
  const hostAudioEvidence = hostLog.split(/\r?\n/).filter(line => /audio|coreaudio|sound|speaker/i.test(line)).slice(-120);
  const pickLines = (text, rx, limit = 160) => text.split(/\r?\n/).filter(line => rx.test(line)).slice(-limit);
  const result = {
    schema: 1,
    observedAt: nowISO(),
    sessionId: state.sessionId,
    controlProfile: state.controlProfile ?? null,
    process: {
      currentTftPid: currentPid,
      knownLaunchPid,
      pidUnchangedFromPreGameObservation: Boolean(knownLaunchPid && currentPid === knownLaunchPid)
    },
    audio: {
      runtimeDeclaresAudioEnabled: readJSON(path.join(captureDir, 'runtime-state.json'), {})?.audioEnabled ?? null,
      musicVolume: { status: musicVolume.status, text: `${musicVolume.stdout}${musicVolume.stderr}`.trim() },
      zenMode,
      audioService: pickLines(audioDump, /STREAM_MUSIC|speaker|device|mute|volume|AudioDevice|AUDIO_DEVICE_OUT|active/i, 180),
      audioFlinger: pickLines(audioFlinger, /output|mixer|track|active|standby|device|underrun|sample rate|frame/i, 180),
      audioPolicy: pickLines(audioPolicy, /output|speaker|device|route|active|strategy|AUDIO_DEVICE_OUT/i, 180),
      logEvidence: audioLogEvidence,
      hostBackendEvidence: hostAudioEvidence
    },
    network: {
      evidence: networkEvidence,
      tftProcessStayedAlive: Boolean(knownLaunchPid && currentPid === knownLaunchPid),
      interpretation: knownLaunchPid && currentPid === knownLaunchPid
        ? 'The observed late-game disconnect did not restart the TFT process; investigate Riot/session/network transport and Android connectivity before app-crash recovery.'
        : 'TFT PID changed; process-level restart may have contributed and needs timeline reconstruction.'
    }
  };
  writeJSON(path.join(captureDir, 'runtime-fault-audit.json'), result);
  return result;
}

function graphicsPipelineAudit() {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  if (!state?.captureDir) throw new Error('No active direct-control session.');
  if (!deviceReady(runtime)) throw new Error('No active Android device for graphics pipeline audit.');
  const captureDir = state.captureDir;
  const sf = adb(runtime, ['shell', 'dumpsys', 'SurfaceFlinger'], { allowFailure: true, timeout: 30000 }).stdout;
  const counters = surfaceFlingerCounters(runtime);
  const runtimeInfo = readJSON(path.join(captureDir, 'runtime-state.json'), {});
  const session = readJSON(path.join(captureDir, 'session.json'), {});
  const emulatorLogPath = path.join(captureDir, 'emulator.stdout.log');
  const emulatorText = exists(emulatorLogPath) ? fs.readFileSync(emulatorLogPath, 'utf8') : '';
  const cropMatches = [...sf.matchAll(/sourceCrop=\[\s*([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\]/gi)]
    .map(match => ({ width: Math.max(0, Number(match[3]) - Number(match[1])), height: Math.max(0, Number(match[4]) - Number(match[2])) }))
    .filter(item => item.width > 0 && item.height > 0)
    .sort((a, b) => (a.width * a.height) - (b.width * b.height));
  const frameMatches = [...sf.matchAll(/displayFrame=\[\s*([0-9.-]+)\s+([0-9.-]+)\s+([0-9.-]+)\s+([0-9.-]+)\]/gi)]
    .map(match => ({ width: Math.max(0, Number(match[3]) - Number(match[1])), height: Math.max(0, Number(match[4]) - Number(match[2])) }))
    .filter(item => item.width > 0 && item.height > 0)
    .sort((a, b) => (b.width * b.height) - (a.width * a.height));
  const renderWidth = cropMatches[0]?.width ?? null;
  const renderHeight = cropMatches[0]?.height ?? null;
  const displayWidth = frameMatches[0]?.width ?? null;
  const displayHeight = frameMatches[0]?.height ?? null;
  const scaleX = renderWidth && displayWidth ? displayWidth / renderWidth : null;
  const scaleY = renderHeight && displayHeight ? displayHeight / renderHeight : null;
  const count = rx => (emulatorText.match(rx) ?? []).length;
  const recentWarnings = emulatorText.split(/\r?\n/).filter(line => /(?:ANGLE|gfxstream|MoltenVK|Vulkan|Metal|virtio-gpu|ASG).*(?:warn|error|fail|stall|timeout|unsupported)/i.test(line)).slice(-80);
  const pipeline = [
    {
      boundary: 'UNREAL_TO_ANDROID_SURFACE',
      state: renderWidth && displayWidth && (renderWidth < displayWidth || renderHeight < displayHeight) ? 'ATTENTION' : 'OBSERVED',
      evidence: { renderBuffer: renderWidth && renderHeight ? `${renderWidth}x${renderHeight}` : null, displayFrame: displayWidth && displayHeight ? `${displayWidth}x${displayHeight}` : null, scaleX, scaleY },
      interpretation: renderWidth && displayWidth && renderWidth < displayWidth ? 'TFT is producing a lower-resolution game SurfaceView that Android composition scales to the display. This is an image-quality boundary and may also be an intentional performance tradeoff.' : 'No lower-resolution game-surface upscale was proven in this snapshot.'
    },
    {
      boundary: 'ANGLE_TO_GUEST_VULKAN',
      state: /Created VkInstance:.*com\.riotgames\.league\.teamfighttactics.*ANGLE/i.test(emulatorText) ? 'PROVEN_ACTIVE' : 'UNKNOWN',
      evidence: { tftAngleVkInstanceCreates: count(/Created VkInstance:.*com\.riotgames\.league\.teamfighttactics.*ANGLE/gi), angleWarningsOrErrors: count(/ANGLE.*(?:warn|error|fail|stall|timeout|unsupported)/gi), glesCompatibilityExposure: runtimeInfo.glesCompatibilityExposure ?? null },
      interpretation: 'ANGLE is active for TFT. Translation cost is not yet measured per frame; absence of warnings does not prove zero overhead.'
    },
    {
      boundary: 'GUEST_VULKAN_TO_GFXSTREAM_ASG',
      state: /Gfxstream initialized successfully!/i.test(emulatorText) ? 'PROVEN_ACTIVE' : 'UNKNOWN',
      evidence: { graphicsTransport: runtimeInfo.graphicsTransportRequested ?? null, asg: runtimeInfo.asg ?? null, gfxstreamWarningsOrErrors: count(/gfxstream.*(?:warn|error|fail|stall|timeout|unsupported)/gi), virtualQueueGuestFlagIgnored: count(/Guest usage of host flag 'VulkanVirtualQueue' will be ignored/gi) },
      interpretation: 'virtio-gpu-asg/gfxstream is active. Current logs do not expose queue/ring wait time, so transport backpressure remains unmeasured rather than cleared.'
    },
    {
      boundary: 'HOST_VULKAN_TO_MOLTENVK',
      state: /Selecting Vulkan device:\s*Apple M4/i.test(emulatorText) ? 'PROVEN_ACTIVE' : 'UNKNOWN',
      evidence: { vulkanComposition: /useVulkanComposition:\s*true/i.test(emulatorText), nativeSwapchain: /useVulkanNativeSwapchain:\s*true/i.test(emulatorText), moltenVkWarningsOrErrors: count(/MoltenVK.*(?:warn|error|fail|stall|timeout|unsupported)/gi) },
      interpretation: 'gfxstream host Vulkan is reaching MoltenVK on Apple M4. Queue-submit and command-buffer latency are not yet measured.'
    },
    {
      boundary: 'METAL_TO_SURFACEFLINGER_PRESENT',
      state: 'OBSERVED',
      evidence: { renderRateHz: counters.renderRateHz ?? null, totalMissedFrames: counters.totalMissedFrames ?? null, gpuMissedFrames: counters.gpuMissedFrames ?? null, hwcMissedFrames: counters.hwcMissedFrames ?? null, gameRequested60Hz: counters.gameRequested60Hz ?? null, usesDeviceComposition: /usesDeviceComposition=true/i.test(sf), usesClientComposition: /usesClientComposition=true/i.test(sf) },
      interpretation: 'Presentation is 60 Hz and currently uses device composition. Missed-frame counters are cumulative since boot; only bounded deltas during gameplay can assign a bottleneck.'
    }
  ];
  const result = {
    schema: 1,
    observedAt: nowISO(),
    sessionId: state.sessionId,
    controlProfile: state.controlProfile ?? runtimeInfo.control ?? null,
    gameSettings: session.currentGameSettings ?? null,
    pipeline,
    recentGraphicsWarnings: recentWarnings,
    nextProbe: 'Run native-trace-combat during active combat and take graphics-pipeline-audit immediately before/after. Attribute the first boundary whose bounded timing/miss counters diverge; patch only that connector.'
  };
  writeJSON(path.join(captureDir, 'graphics-pipeline-audit.json'), result);
  return result;
}

async function captureNativeTrace(durationSeconds = 5, label = 'smoke') {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  if (!state?.captureDir) throw new Error('No active direct-control session.');
  if (!deviceReady(runtime)) throw new Error('No active emulator available for native trace capture.');
  const traceDir = path.join(state.captureDir, 'perfetto');
  ensureDir(traceDir);
  const safeLabel = String(label).replace(/[^a-z0-9_-]+/gi, '-').replace(/^-+|-+$/g, '') || 'trace';
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const fileName = `native-${safeLabel}-${durationSeconds}s-${stamp}.pftrace`;
  const hostPath = path.join(traceDir, fileName);
  const remotePath = `/data/misc/perfetto-traces/tftmac-${process.pid}-${Date.now()}.pftrace`;
  const config = nativeTraceConfig(durationSeconds);
  const before = surfaceFlingerCounters(runtime);
  const startEvent = { utc: nowISO(), host_mono_ns: monoNs().toString(), event: 'NATIVE_TRACE_START', label: safeLabel, durationSeconds, dataSources: ['android.surfaceflinger.frame','android.surfaceflinger.frametimeline','android.surfaceflinger.layers','android.gpu.memory'] };
  appendJSONL(path.join(state.captureDir, 'markers.jsonl'), startEvent);
  const trace = adb(runtime, ['shell', 'perfetto', '--txt', '-c', '-', '-o', remotePath], {
    allowFailure: true,
    timeout: Math.max(30000, (durationSeconds + 20) * 1000),
    maxBuffer: 32 * 1024 * 1024,
    input: config
  });
  if (trace.status !== 0) {
    adb(runtime, ['shell', 'rm', '-f', remotePath], { allowFailure: true, timeout: 10000 });
    throw new Error(`NATIVE_TRACE_CAPTURE_FAILED: ${(trace.stderr || trace.stdout || '').trim()}`);
  }
  const pull = adb(runtime, ['pull', remotePath, hostPath], { allowFailure: true, timeout: 120000, maxBuffer: 32 * 1024 * 1024 });
  adb(runtime, ['shell', 'rm', '-f', remotePath], { allowFailure: true, timeout: 10000 });
  if (pull.status !== 0 || !exists(hostPath) || fs.statSync(hostPath).size <= 0) {
    throw new Error(`NATIVE_TRACE_PULL_FAILED: ${(pull.stderr || pull.stdout || '').trim()}`);
  }
  const after = surfaceFlingerCounters(runtime);
  const metadata = {
    schema: 1,
    observedAt: nowISO(),
    sessionId: state.sessionId,
    label: safeLabel,
    durationSeconds,
    tracePath: hostPath,
    traceFileName: fileName,
    byteCount: fs.statSync(hostPath).size,
    sha256: sha256File(hostPath),
    dataSources: ['android.surfaceflinger.frame','android.surfaceflinger.frametimeline','android.surfaceflinger.layers','android.gpu.memory'],
    surfaceFlingerBefore: before,
    surfaceFlingerAfter: after,
    counterDelta: {
      totalMissedFrames: Number.isFinite(before.totalMissedFrames) && Number.isFinite(after.totalMissedFrames) ? after.totalMissedFrames - before.totalMissedFrames : null,
      gpuMissedFrames: Number.isFinite(before.gpuMissedFrames) && Number.isFinite(after.gpuMissedFrames) ? after.gpuMissedFrames - before.gpuMissedFrames : null,
      hwcMissedFrames: Number.isFinite(before.hwcMissedFrames) && Number.isFinite(after.hwcMissedFrames) ? after.hwcMissedFrames - before.hwcMissedFrames : null
    },
    parseState: 'RAW_CAPTURE_VALIDATED_NOT_YET_NORMALIZED'
  };
  const metaPath = `${hostPath}.json`;
  writeJSON(metaPath, metadata);
  appendJSONL(path.join(state.captureDir, 'markers.jsonl'), { utc: nowISO(), host_mono_ns: monoNs().toString(), event: 'NATIVE_TRACE_END', label: safeLabel, durationSeconds, traceFileName: fileName, sha256: metadata.sha256, counterDelta: metadata.counterDelta });
  return metadata;
}

function hostDesktopBounds() {
  const result = command('/usr/bin/osascript', ['-e', 'tell application "Finder" to get bounds of window of desktop'], { allowFailure: true, timeout: 10000 });
  const values = result.stdout.trim().split(/\s*,\s*/).map(Number);
  if (result.status !== 0 || values.length < 4 || values.some(value => !Number.isFinite(value))) return null;
  return { x: values[0], y: values[1], width: values[2] - values[0], height: values[3] - values[1] };
}

function setUserIniValue(text, key, value) {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const pattern = new RegExp(`^\\s*${escaped}\\s*=.*$`, 'm');
  return pattern.test(text)
    ? text.replace(pattern, `${key} = ${value}`)
    : `${text.replace(/\s*$/, '')}${text.trim() ? '\n' : ''}${key} = ${value}\n`;
}

function prepareEmulatorWindowFit(runtime, contentWidth, contentHeight) {
  if (!runtime.avdDir) return { prepared: false, reason: 'AVD_UNRESOLVED' };

  // The native TFTMAC shell owns live fullscreen sizing with NSScreen. Seed the
  // emulator at 1:1 guest scale and move only the Qt title chrome above the
  // screen; do not use Finder's combined multi-monitor desktop bounds here.
  if (process.env.TFTMAC_NATIVE_FULLSCREEN === '1') {
    const screenWidth = Number(process.env.TFTMAC_HOST_SCREEN_WIDTH ?? 0);
    const screenHeight = Number(process.env.TFTMAC_HOST_SCREEN_HEIGHT ?? 0);
    const controlWidth = Number(process.env.TFTMAC_NATIVE_CONTROL_WIDTH ?? 64);
    const titleChrome = Number(process.env.TFTMAC_NATIVE_TOPBAR_HEIGHT ?? 30);
    const backingScale = Number(process.env.TFTMAC_HOST_BACKING_SCALE ?? 1) || 1;
    const widthScalePoints = screenWidth > controlWidth ? (screenWidth - controlWidth) / contentWidth : 1;
    const heightScalePoints = screenHeight > titleChrome ? (screenHeight - titleChrome) / contentHeight : 1;
    const logicalScale = Math.max(0.1, Math.min(widthScalePoints, heightScalePoints, 4));
    const scale = logicalScale * backingScale;
    const userIniPath = path.join(runtime.avdDir, 'emulator-user.ini');
    let text = exists(userIniPath) ? fs.readFileSync(userIniPath, 'utf8') : '[General]\n';
    text = setUserIniValue(text, 'window.x', 0);
    text = setUserIniValue(text, 'window.y', 0);
    text = setUserIniValue(text, 'window.scale', scale.toFixed(6));
    fs.writeFileSync(userIniPath, text);
    return {
      prepared: true,
      mode: 'NATIVE_SHELL_SCALE',
      userIniPath,
      host: { width: screenWidth || null, height: screenHeight || null, controlWidth, titleChrome },
      content: { width: contentWidth, height: contentHeight },
      window: { x: 0, y: 0, scale },
      guestResolutionPreserved: true,
      liveSizingAuthority: 'TFTMAC native shell; explicit emulator -scale'
    };
  }

  const bounds = hostDesktopBounds();
  if (!bounds) return { prepared: false, reason: 'HOST_DESKTOP_BOUNDS_UNRESOLVED' };

  // TFTMAC immersive mode keeps the Android guest at its authoritative
  // 1920x1080 resolution while scaling the host Qt canvas to cover the Mac
  // display. Google Emulator chrome is deliberately placed outside the visible
  // desktop: title bar above the screen and stock toolbar beyond the right edge.
  // This replaces the old inset/margin behavior that made the game appear as a
  // smaller screen inside the native wrapper.
  const chromeHeight = 38;
  const scale = Math.max(0.1, Math.max(bounds.width / contentWidth, bounds.height / contentHeight));
  const scaledWidth = contentWidth * scale;
  const scaledHeight = contentHeight * scale;
  const cropX = Math.max(0, (scaledWidth - bounds.width) / 2);
  const cropY = Math.max(0, (scaledHeight - bounds.height) / 2);
  const windowX = Math.round(-cropX);
  const windowY = Math.round(-chromeHeight - cropY);

  const userIniPath = path.join(runtime.avdDir, 'emulator-user.ini');
  let text = exists(userIniPath) ? fs.readFileSync(userIniPath, 'utf8') : '[General]\n';
  text = setUserIniValue(text, 'window.x', windowX);
  text = setUserIniValue(text, 'window.y', windowY);
  text = setUserIniValue(text, 'window.scale', scale.toFixed(6));
  fs.writeFileSync(userIniPath, text);
  return {
    prepared: true,
    mode: 'IMMERSIVE_COVER',
    userIniPath,
    desktop: bounds,
    content: { width: contentWidth, height: contentHeight },
    scaledContent: { width: scaledWidth, height: scaledHeight },
    window: { x: windowX, y: windowY, scale },
    crop: { x: cropX, y: cropY },
    guestResolutionPreserved: true
  };
}

function prepareGuestFullscreenPolicy(runtime) {
  if (!deviceReady(runtime)) return { prepared: false, reason: 'DEVICE_NOT_READY' };
  const keys = {
    override_desktop_mode_features: '0',
    enable_freeform_support: '0',
    force_desktop_mode_on_external_displays: '0'
  };
  const before = {};
  const after = {};
  for (const [key, value] of Object.entries(keys)) {
    before[key] = adb(runtime, ['shell', 'settings', 'get', 'global', key], { allowFailure: true, timeout: 10000 }).stdout.trim() || null;
    adb(runtime, ['shell', 'settings', 'put', 'global', key, value], { allowFailure: true, timeout: 10000 });
    after[key] = adb(runtime, ['shell', 'settings', 'get', 'global', key], { allowFailure: true, timeout: 10000 }).stdout.trim() || null;
  }
  return { prepared: Object.entries(keys).every(([key, value]) => after[key] === value), rebootRequiredForDesktopModeOverride: before.override_desktop_mode_features !== '0', before, after };
}

function traceCapabilities() {
  const runtime = discover();
  if (!deviceReady(runtime)) throw new Error('No active emulator available for trace capability discovery.');
  const runShell = (args, timeout = 30000, maxBuffer = 32 * 1024 * 1024) => adb(runtime, ['shell', ...args], { allowFailure: true, timeout, maxBuffer });
  const perfettoHelp = runShell(['perfetto', '--help']);
  const perfettoQuery = runShell(['perfetto', '--query'], 30000, 64 * 1024 * 1024);
  const sfList = runShell(['dumpsys', 'SurfaceFlinger', '--list']);
  const sfHelp = runShell(['dumpsys', 'SurfaceFlinger', '--help']);
  const queryText = `${perfettoQuery.stdout}\n${perfettoQuery.stderr}`;
  const interestingDataSources = queryText.split(/\r?\n/)
    .filter(line => /android\.(surfaceflinger|frame|gpu|memory|power)|linux\.(ftrace|process|sys_stats)|track_event|gpu|frame|surface|sched|freq|memory/i.test(line))
    .slice(0, 600);
  const tftSurfaces = sfList.stdout.split(/\r?\n/)
    .filter(line => /teamfighttactics|GameActivity|SurfaceView|BLAST|Surface/i.test(line))
    .slice(0, 300);
  const sfText = `${sfHelp.stdout}\n${sfHelp.stderr}`;
  const result = {
    observedAt: nowISO(),
    perfettoAvailable: perfettoHelp.status === 0 || perfettoQuery.status === 0,
    nativeFrameDataSources: {
      surfaceFlingerFrame: interestingDataSources.some(line => /android\.surfaceflinger\.frame\b/.test(line)),
      surfaceFlingerFrameTimeline: interestingDataSources.some(line => /android\.surfaceflinger\.frametimeline\b/.test(line)),
      surfaceFlingerLayers: interestingDataSources.some(line => /android\.surfaceflinger\.layers\b/.test(line)),
      gpuMemory: interestingDataSources.some(line => /android\.gpu\.memory\b/.test(line)),
      ftrace: interestingDataSources.some(line => /linux\.ftrace\b/.test(line)),
      processStats: interestingDataSources.some(line => /linux\.process_stats\b/.test(line)),
      sysStats: interestingDataSources.some(line => /linux\.sys_stats\b/.test(line))
    },
    surfaceFlingerCounters: {
      renderRateHz: Number(sfText.match(/renderRate=([0-9.]+) Hz/)?.[1] ?? NaN) || null,
      totalMissedFrames: matchNumber(sfText, /Total missed frame count:\s*(\d+)/),
      hwcMissedFrames: matchNumber(sfText, /HWC missed frame count:\s*(\d+)/),
      gpuMissedFrames: matchNumber(sfText, /GPU missed frame count:\s*(\d+)/),
      gameRequested60Hz: /GameFrameRateOverrides=[\s\S]*\{10215,\s*0\s+60\}/.test(sfText) || /GameActivity[^\n]*requestedFrameRate:\s*\{60\.00 Hz/.test(sfText),
      scope: 'cumulative display counters since boot; not match-scoped'
    },
    perfettoHelpStatus: perfettoHelp.status,
    perfettoQueryStatus: perfettoQuery.status,
    perfettoHelp: `${perfettoHelp.stdout}${perfettoHelp.stderr}`.trim().slice(0, 24000),
    interestingDataSources,
    surfaceFlingerListStatus: sfList.status,
    tftSurfaces,
    surfaceFlingerHelpStatus: sfHelp.status,
    surfaceFlingerHelp: `${sfHelp.stdout}${sfHelp.stderr}`.trim().slice(0, 24000)
  };
  const state = readJSON(CONTROL_STATE);
  if (state?.captureDir) writeJSON(path.join(state.captureDir, 'trace-capabilities.json'), result);
  return result;
}

function presentationProbe() {
  const runtime = discover();
  if (!deviceReady(runtime)) throw new Error('No active emulator available.');
  const shell = (args, timeout = 30000) => adb(runtime, ['shell', ...args], { allowFailure: true, timeout }).stdout;
  const windowDump = shell(['dumpsys', 'window', 'displays']);
  const activityDump = shell(['dumpsys', 'activity', 'top']);
  return {
    action: 'PRESENTATION_PROBE',
    wmSize: shell(['wm', 'size']).trim(),
    wmDensity: shell(['wm', 'density']).trim(),
    orientation: shell(['settings', 'get', 'system', 'user_rotation']).trim(),
    windowEvidence: windowDump.split(/\r?\n/).filter(line => /DisplayFrames|DisplayCutout|InsetsState|statusBars|navigationBars|mCurrentFocus|mFocusedApp|GameActivity|teamfighttactics|frame=|displayFrame=/i.test(line)).slice(0, 320),
    activityEvidence: activityDump.split(/\r?\n/).filter(line => /ACTIVITY|GameActivity|teamfighttactics|bounds|appBounds|mResumedActivity|topResumedActivity/i.test(line)).slice(0, 220)
  };
}

function androidControl(control) {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  if (!deviceReady(runtime)) throw new Error('TFTMAC Android runtime is not ready.');
  const shell = (...args) => adb(runtime, ['shell', ...args], { allowFailure: true, timeout: 15000 });
  let result = null;
  switch (control) {
    case 'back': result = shell('input', 'keyevent', '4'); break;
    case 'home': result = shell('input', 'keyevent', '3'); break;
    case 'overview': result = shell('input', 'keyevent', '187'); break;
    case 'power': result = shell('input', 'keyevent', '26'); break;
    case 'volume-up': result = shell('input', 'keyevent', '24'); break;
    case 'volume-down': result = shell('input', 'keyevent', '25'); break;
    case 'rotate': {
      const current = Number(shell('settings', 'get', 'system', 'user_rotation').stdout.trim() || 0);
      const next = current === 1 ? 0 : 1;
      shell('settings', 'put', 'system', 'accelerometer_rotation', '0');
      result = shell('settings', 'put', 'system', 'user_rotation', String(next));
      break;
    }
    case 'screenshot': {
      const captureDir = state?.captureDir ?? path.join(APP_SUPPORT, 'Screenshots');
      ensureDir(captureDir);
      const guestPath = '/sdcard/tftmac-screenshot.png';
      shell('screencap', '-p', guestPath);
      const hostPath = path.join(captureDir, `screenshot-${nowISO().replace(/[:.]/g, '-')}.png`);
      const pull = adb(runtime, ['pull', guestPath, hostPath], { allowFailure: true, timeout: 30000 });
      shell('rm', '-f', guestPath);
      if (pull.status !== 0 || !exists(hostPath)) throw new Error(`TFTMAC screenshot failed: ${(pull.stderr || pull.stdout || '').trim()}`);
      if (state?.captureDir) appendJSONL(path.join(state.captureDir, 'host-events.jsonl'), { utc: nowISO(), host_mono_ns: monoNs().toString(), event: 'SCREENSHOT', path: hostPath });
      return { action: 'ANDROID_CONTROL', control, screenshot: hostPath };
    }
    default: throw new Error(`Unknown TFTMAC Android control: ${control}`);
  }
  if (state?.captureDir) appendJSONL(path.join(state.captureDir, 'host-events.jsonl'), { utc: nowISO(), host_mono_ns: monoNs().toString(), event: 'ANDROID_CONTROL', control });
  return { action: 'ANDROID_CONTROL', control, status: result?.status ?? 0 };
}

function emulatorWindowInventory() {
  const runtime = discover();
  if (!deviceReady(runtime)) throw new Error('No active emulator available.');
  const state = readJSON(CONTROL_STATE);
  const ps = command('/bin/ps', ['axo', 'pid=,command='], { allowFailure: true, timeout: 10000 }).stdout;
  const observedPid = state?.emulatorPid && processAlive(state.emulatorPid)
    ? Number(state.emulatorPid)
    : Number(ps.split(/\r?\n/).map(line => line.trim()).map(line => line.match(/^(\d+)\s+(.+)$/)).find(match => match && /qemu-system-aarch64/.test(match[2]) && new RegExp(`@${AVD_NAME}\\b`).test(match[2]))?.[1] ?? 0);
  if (!observedPid) throw new Error('Active emulator host PID could not be resolved.');
  const script = `
    tell application "System Events"
      set targetProcess to first application process whose unix id is ${observedPid}
      set outputText to ""
      set windowCount to count of windows of targetProcess
      repeat with i from 1 to windowCount
        set w to window i of targetProcess
        set n to name of w
        set s to size of w
        set p to position of w
        set outputText to outputText & i & "|" & n & "|" & (item 1 of s) & "x" & (item 2 of s) & "|" & (item 1 of p) & "," & (item 2 of p) & linefeed
      end repeat
    end tell
    return outputText
  `;
  const result = command('/usr/bin/osascript', ['-e', script], { allowFailure: true, timeout: 10000 });
  if (result.status !== 0) throw new Error(`EMULATOR_WINDOW_INVENTORY_FAILED: ${(result.stderr || result.stdout || '').trim()}`);
  return { action: 'EMULATOR_WINDOW_INVENTORY', emulatorPid: observedPid, windows: result.stdout.trim().split(/\r?\n/).filter(Boolean) };
}

function fitEmulatorWindow() {
  const runtime = discover();
  if (!deviceReady(runtime)) throw new Error('No active emulator available to fit.');
  const state = readJSON(CONTROL_STATE);
  const nextBootGuestPolicy = prepareGuestFullscreenPolicy(runtime);
  const ps = command('/bin/ps', ['axo', 'pid=,command='], { allowFailure: true, timeout: 10000 }).stdout;
  const observedPid = state?.emulatorPid && processAlive(state.emulatorPid)
    ? Number(state.emulatorPid)
    : Number(ps.split(/\r?\n/).map(line => line.trim()).map(line => line.match(/^(\d+)\s+(.+)$/)).find(match => match && /qemu-system-aarch64/.test(match[2]) && new RegExp(`@${AVD_NAME}\\b`).test(match[2]))?.[1] ?? 0);
  if (!observedPid) throw new Error('Active emulator host PID could not be resolved.');
  const script = `
    tell application "Finder" to set desktopBounds to bounds of window of desktop
    set screenWidth to item 3 of desktopBounds
    set screenHeight to item 4 of desktopBounds
    set chromeWidth to 72
    set chromeHeight to 38
    -- Preserve the Android guest at 1920x1080.  The host window is deliberately
    -- oversized so the Qt title bar is above the visible display and the stock
    -- emulator toolbar is beyond the right edge. TFTMAC supplies its own native
    -- control strip on that edge instead of adding a streamed rendering layer.
    set targetWidth to (screenWidth + chromeWidth) as integer
    set targetHeight to (screenHeight + chromeHeight) as integer
    tell application "System Events"
      set targetProcess to first application process whose unix id is ${observedPid}
      set targetWindow to missing value
      repeat with w in windows of targetProcess
        try
          if name of w starts with "Android Emulator - " then
            set targetWindow to w
            exit repeat
          end if
        end try
      end repeat
      if targetWindow is missing value then error "TFTMAC game canvas window not found"
      set frontmost of targetProcess to true
      delay 0.1
      set position of targetWindow to {0, -chromeHeight}
      set size of targetWindow to {targetWidth, targetHeight}
      delay 0.15
      set finalPosition to position of targetWindow
      set finalSize to size of targetWindow
    end tell
    return (screenWidth as text) & "x" & (screenHeight as text) & " -> TFTMAC " & (item 1 of finalSize as text) & "x" & (item 2 of finalSize as text) & " @ " & (item 1 of finalPosition as text) & "," & (item 2 of finalPosition as text)
  `;
  const result = command('/usr/bin/osascript', ['-e', script], { allowFailure: true, timeout: 10000 });
  const output = `${result.stdout}${result.stderr}`.trim();
  if (result.status !== 0) {
    const nextLaunch = prepareEmulatorWindowFit(runtime, BASELINE_PROFILE.width, BASELINE_PROFILE.height);
    return { action: 'EMULATOR_WINDOW_FIT_LIVE_PERMISSION_REQUIRED', output, emulatorPid: observedPid, guestResolutionPreserved: true, guestResolution: `${BASELINE_PROFILE.width}x${BASELINE_PROFILE.height}`, nextLaunch, nextBootGuestPolicy, manualLiveAction: 'Use macOS fullscreen (Control-Command-F) or resize the emulator window smaller.' };
  }
  const nextLaunch = prepareEmulatorWindowFit(runtime, BASELINE_PROFILE.width, BASELINE_PROFILE.height);
  if (state?.captureDir) appendJSONL(path.join(state.captureDir, 'host-events.jsonl'), { utc: nowISO(), event: 'EMULATOR_WINDOW_FIT_HOST', source: 'macOS window resize', emulatorPid: observedPid, result: output, nextLaunch });
  return { action: 'EMULATOR_WINDOW_FIT_HOST', output, emulatorPid: observedPid, guestResolutionPreserved: true, guestResolution: `${BASELINE_PROFILE.width}x${BASELINE_PROFILE.height}`, nextLaunch, nextBootGuestPolicy };
}

async function status() {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  const ready = deviceReady(runtime);
  const pkg = ready ? packageState(runtime, state?.captureDir ?? null, false) : null;
  const pid = ready ? adb(runtime, ['shell', 'pidof', PACKAGE], { allowFailure: true }).stdout.trim() : '';
  const top = ready ? adb(runtime, ['shell', 'dumpsys', 'activity', 'activities'], { allowFailure: true }).stdout.split(/\r?\n/).filter(l => /mResumedActivity|topResumedActivity/i.test(l)).slice(0, 4) : [];
  const xml = ready ? dumpUI(runtime) : '';
  const googleAuth = xml ? findNodeByText(xml, [/sign in/i, /add account/i, /choose an account/i]) : null;
  const riotAuth = xml ? findNodeByText(xml, [/sign in/i, /log in/i, /riot account/i]) : null;
  const anrWait = xml ? findNodeByText(xml, [/^Wait$/i]) : null;
  const anrText = xml ? findNodeByText(xml, [/isn['’]?t responding/i, /not responding/i]) : null;
  const riotPatch = ready && pid ? riotPatchState(runtime) : { state: 'NOT_RUNNING', serviceActive: false, evidence: [] };
  const loggerGate = state?.captureDir ? loggerGameplayGate(state) : { ready: false, reason: 'NO_ACTIVE_CAPTURE' };
  const gameState = state?.captureDir && !loggerGate.ready
    ? 'LOGGER_FAULT'
    : anrWait
    ? 'ANR_WAIT_REQUIRED'
    : riotPatch.serviceActive
    ? 'PATCHING_OR_INITIALIZING'
    : pid && top.some(line => /teamfighttactics\/com\.epicgames\.unreal\.GameActivity/.test(line))
      ? 'RUNNING_POST_PATCH_OR_LOBBY'
      : pid ? 'RUNNING' : 'NOT_RUNNING';
  return { activeSession: state, deviceReady: ready, samplerAlive: processAlive(state?.samplerPid), emulatorProcessAlive: processAlive(state?.emulatorPid), loggerGate, package: pkg, tftPid: pid || null, gameState, riotPatch, anr: { visible: Boolean(anrText || anrWait), waitAvailable: Boolean(anrWait) }, resumedActivity: top, googleAuthPossible: Boolean(googleAuth), riotAuthPossible: Boolean(pid && riotAuth), uiTextSample: xml.match(/text="([^"]+)"/g)?.slice(0, 20) ?? [] };
}

function androidToolEnv(runtime) {
  const javaHomes = [
    process.env.JAVA_HOME,
    '/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home',
    '/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home',
    '/Applications/Android Studio.app/Contents/jbr/Contents/Home'
  ].filter(Boolean);
  const javaHome = javaHomes.find(home => executable(path.join(home, 'bin', 'java'))) ?? null;
  const env = { ...runtime.env };
  if (javaHome) {
    env.JAVA_HOME = javaHome;
    env.PATH = `${path.join(javaHome, 'bin')}:${env.PATH ?? ''}`;
  }
  return { env, javaHome };
}

function imageRevision(runtime, imagePackage = REQUIRED_IMAGE) {
  const properties = path.join(runtime.sdkRoot, ...imagePackage.split(';'), 'source.properties');
  if (!exists(properties)) return null;
  return parseKeyValueLines(fs.readFileSync(properties, 'utf8'))['Pkg.Revision'] ?? null;
}

async function imageUpgradeWorker() {
  ensureDir(path.dirname(IMAGE_UPGRADE_STATE));
  ensureDir(path.dirname(IMAGE_UPGRADE_STDOUT));
  const base = {
    schema: 1,
    pid: process.pid,
    targetPackage: REQUIRED_IMAGE,
    minimumRevision: REQUIRED_IMAGE_MIN_REVISION,
    startedAt: nowISO()
  };
  const record = extra => writeJSON(IMAGE_UPGRADE_STATE, { ...base, ...extra });
  try {
    const runtime = discover();
    const { env, javaHome } = androidToolEnv(runtime);
    const sdkmanager = path.join(runtime.sdkRoot, 'cmdline-tools', 'latest', 'bin', 'sdkmanager');
    const avdmanager = path.join(runtime.sdkRoot, 'cmdline-tools', 'latest', 'bin', 'avdmanager');
    if (!executable(sdkmanager)) throw new Error(`sdkmanager unavailable: ${sdkmanager}`);
    if (!executable(avdmanager)) throw new Error(`avdmanager unavailable: ${avdmanager}`);

    record({ status: 'RUNNING', stage: 'INSTALLING_IMAGE', javaHome });
    const install = command(sdkmanager, ['--install', REQUIRED_IMAGE, '--channel=3'], {
      env,
      timeout: 30 * 60 * 1000,
      maxBuffer: 128 * 1024 * 1024
    });
    const revision = imageRevision(runtime);
    if (!revision || Number.parseInt(revision, 10) < REQUIRED_IMAGE_MIN_REVISION) {
      throw new Error(`Image install completed but revision ${revision ?? 'unknown'} is below ${REQUIRED_IMAGE_MIN_REVISION}.`);
    }

    record({ status: 'RUNNING', stage: 'RECREATING_AVD', installedRevision: revision });
    for (const target of [runtime.avdIni, runtime.avdDir]) {
      if (!target) continue;
      if (!isUnder(target, EXTERNAL_ROOT)) throw new Error(`Refusing to remove AVD path outside external runtime: ${target}`);
      fs.rmSync(target, { recursive: true, force: true });
    }
    ensureDir(runtime.avdHome ?? path.join(EXTERNAL_ROOT, 'AVD'));
    const avdHome = runtime.avdHome ?? path.join(EXTERNAL_ROOT, 'AVD');
    command(avdmanager, [
      'create', 'avd', '--name', AVD_NAME,
      '--package', REQUIRED_IMAGE,
      '--device', PLAY_DEVICE_ID, '--force'
    ], {
      env: { ...env, ANDROID_AVD_HOME: avdHome },
      input: 'no\n',
      timeout: 120000,
      maxBuffer: 32 * 1024 * 1024
    });
    const prepared = prepareAVD();
    const completed = {
      status: 'SUCCEEDED',
      stage: 'COMPLETE',
      installedRevision: revision,
      endedAt: nowISO(),
      prepared,
      sdkmanagerOutputTail: install.stdout.slice(-6000)
    };
    record(completed);
    return completed;
  } catch (error) {
    const failure = {
      status: 'FAILED',
      stage: 'FAILED',
      endedAt: nowISO(),
      error: error instanceof Error ? error.message : String(error)
    };
    record(failure);
    throw error;
  }
}

function imageUpgradeStart() {
  const existing = readJSON(IMAGE_UPGRADE_STATE);
  if (existing?.status === 'RUNNING' && processAlive(existing.pid)) {
    return { launched: false, alreadyRunning: true, worker: existing };
  }
  ensureDir(path.dirname(IMAGE_UPGRADE_STDOUT));
  const out = fs.openSync(IMAGE_UPGRADE_STDOUT, 'a');
  const err = fs.openSync(IMAGE_UPGRADE_STDERR, 'a');
  try {
    const child = spawn(process.execPath, [scriptPath, 'image-upgrade-worker'], {
      cwd: repoRoot,
      env: process.env,
      detached: true,
      stdio: ['ignore', out, err]
    });
    child.unref();
    return {
      launched: true,
      pid: child.pid,
      targetPackage: REQUIRED_IMAGE,
      minimumRevision: REQUIRED_IMAGE_MIN_REVISION,
      statePath: IMAGE_UPGRADE_STATE,
      stdoutPath: IMAGE_UPGRADE_STDOUT,
      stderrPath: IMAGE_UPGRADE_STDERR
    };
  } finally {
    fs.closeSync(out);
    fs.closeSync(err);
  }
}

function imageUpgradeStatus() {
  const state = readJSON(IMAGE_UPGRADE_STATE, { status: 'NOT_STARTED' });
  const tail = file => {
    if (!exists(file)) return null;
    const text = fs.readFileSync(file, 'utf8');
    return text.slice(-6000);
  };
  return {
    ...state,
    alive: Boolean(state?.pid && processAlive(state.pid)),
    stdoutTail: tail(IMAGE_UPGRADE_STDOUT),
    stderrTail: tail(IMAGE_UPGRADE_STDERR)
  };
}

function imageCheck() {
  const runtime = discover();
  const sourceProperties = path.join(runtime.requiredImagePath, 'source.properties');
  const installedProperties = exists(sourceProperties) ? parseKeyValueLines(fs.readFileSync(sourceProperties, 'utf8')) : {};
  const javaHomes = [
    process.env.JAVA_HOME,
    '/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home',
    '/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home',
    '/Applications/Android Studio.app/Contents/jbr/Contents/Home'
  ].filter(Boolean);
  const javaHome = javaHomes.find(home => executable(path.join(home, 'bin', 'java'))) ?? null;
  const env = { ...runtime.env };
  if (javaHome) {
    env.JAVA_HOME = javaHome;
    env.PATH = `${path.join(javaHome, 'bin')}:${env.PATH ?? ''}`;
  }
  const sdkmanager = path.join(runtime.sdkRoot, 'cmdline-tools', 'latest', 'bin', 'sdkmanager');
  const androidCli = path.join(runtime.sdkRoot, 'cmdline-tools', 'latest', 'bin', 'android');
  let listing = { status: -1, stdout: '', stderr: 'No Android SDK package-list tool found' };
  if (executable(sdkmanager)) {
    listing = command(sdkmanager, ['--list', '--channel=3'], { env, allowFailure: true, timeout: 120000, maxBuffer: 64 * 1024 * 1024 });
  } else if (executable(androidCli)) {
    listing = command(androidCli, [`--sdk=${runtime.sdkRoot}`, 'sdk', 'list', '.*(android-3[67]).*playstore.*arm64.*', '--all', '--all-versions', '--canary'], { env, allowFailure: true, timeout: 120000, maxBuffer: 64 * 1024 * 1024 });
  }
  const lines = `${listing.stdout}\n${listing.stderr}`.split(/\r?\n/)
    .filter(line => /system-images.*android-3[67].*(google_apis_playstore|playstore).*arm64/i.test(line));
  return {
    installedPackage: REQUIRED_IMAGE,
    installedRevision: installedProperties['Pkg.Revision'] ?? null,
    installedDescription: installedProperties['Pkg.Desc'] ?? null,
    packageToolStatus: listing.status,
    javaHome,
    matchingAvailableLines: lines.slice(0, 120)
  };
}

function deviceProfiles() {
  const runtime = discover();
  const { env, javaHome } = androidToolEnv(runtime);
  const avdmanager = path.join(runtime.sdkRoot, 'cmdline-tools', 'latest', 'bin', 'avdmanager');
  if (!executable(avdmanager)) throw new Error(`avdmanager unavailable: ${avdmanager}`);
  const result = command(avdmanager, ['list', 'device'], { env, allowFailure: true, timeout: 120000, maxBuffer: 32 * 1024 * 1024 });
  const blocks = result.stdout.split(/---------/).map(block => block.trim()).filter(Boolean);
  const profiles = blocks.map(block => {
    const id = block.match(/id:\s*\d+\s+or\s+"([^"]+)"/)?.[1] ?? null;
    const name = block.match(/Name:\s*(.+)/)?.[1]?.trim() ?? null;
    const oem = block.match(/OEM\s*:\s*(.+)/)?.[1]?.trim() ?? null;
    const tag = block.match(/Tag\s*:\s*(.+)/)?.[1]?.trim() ?? null;
    return { id, name, oem, tag, raw: block };
  }).filter(p => p.id);
  return { javaHome, status: result.status, profiles };
}

async function googleAccountUI() {
  const runtime = discover();
  await waitForBoot(runtime, 60000);
  const before = adb(runtime, ['shell', 'dumpsys', 'account'], { allowFailure: true, timeout: 30000 }).stdout;
  const launch = adb(runtime, [
    'shell', 'am', 'start', '-W',
    '-a', 'android.settings.ADD_ACCOUNT_SETTINGS',
    '--esa', 'account_types', 'com.google'
  ], { allowFailure: true, timeout: 30000 });
  await sleep(1800);
  const xml = dumpUI(runtime);
  const state = readJSON(CONTROL_STATE);
  if (state?.captureDir) {
    fs.writeFileSync(path.join(state.captureDir, 'google-account-ui.xml'), xml);
    appendJSONL(path.join(state.captureDir, 'host-events.jsonl'), { utc: nowISO(), event: 'GOOGLE_ACCOUNT_UI_OPENED', launchStatus: launch.status });
  }
  return {
    action: 'GOOGLE_ACCOUNT_UI_OPEN',
    launchStatus: launch.status,
    launchOutput: `${launch.stdout}${launch.stderr}`.trim(),
    accountsBefore: before.match(/Accounts:\s*(\d+)/)?.[1] ?? null,
    uiTextSample: xml.match(/text="([^"]+)"/g)?.slice(0, 40) ?? []
  };
}

async function playStoreRepair() {
  const runtime = discover();
  await waitForBoot(runtime, 60000);
  const state = readJSON(CONTROL_STATE);
  const captureDir = state?.captureDir ?? null;
  const shell = (args, timeout = 30000) => adb(runtime, ['shell', ...args], { allowFailure: true, timeout });
  const accountsBefore = shell(['dumpsys', 'account']).stdout;
  const countBefore = Number(accountsBefore.match(/Accounts:\s*(\d+)/)?.[1] ?? 0);
  const clear = shell(['pm', 'clear', 'com.android.vending'], 60000);
  shell(['am', 'force-stop', 'com.android.vending']);
  await sleep(1200);
  const launch = shell(['am', 'start', '-W', '-a', 'android.intent.action.VIEW', '-d', `market://details?id=${PACKAGE}`], 30000);
  await sleep(5000);
  const accountsAfter = shell(['dumpsys', 'account']).stdout;
  const countAfter = Number(accountsAfter.match(/Accounts:\s*(\d+)/)?.[1] ?? 0);
  const xml = dumpUI(runtime);
  const result = {
    action: 'PLAY_STORE_STATE_REPAIRED',
    clearStatus: clear.status,
    clearOutput: `${clear.stdout}${clear.stderr}`.trim(),
    launchStatus: launch.status,
    accountCountBefore: countBefore,
    accountCountAfter: countAfter,
    googleAccountPreserved: /type=com\.google|Account \{.*com\.google/i.test(accountsAfter),
    uiTextSample: xml.match(/text="([^"]+)"/g)?.slice(0, 60) ?? []
  };
  if (captureDir) {
    appendJSONL(path.join(captureDir, 'host-events.jsonl'), { utc: nowISO(), event: 'PLAY_STORE_STATE_REPAIR', accountCountBefore: countBefore, accountCountAfter: countAfter, clearStatus: clear.status });
    writeJSON(path.join(captureDir, 'play-store-repair.json'), result);
  }
  return result;
}

async function playInstallBrief() {
  const runtime = discover();
  await waitForBoot(runtime, 60000);
  const state = readJSON(CONTROL_STATE);
  const captureDir = state?.captureDir ?? null;
  const logcat = command(runtime.adb, ['-P', ADB_PORT, '-s', SERIAL, 'logcat', '-d', '-v', 'threadtime', '-t', '15000'], { env: runtime.env, allowFailure: true, timeout: 30000, maxBuffer: 64 * 1024 * 1024 }).stdout;
  const lines = logcat.split(/\r?\n/);
  const focus = lines.filter(line => /(com\.riotgames\.league\.teamfighttactics|Finsky.*(tos|install|acqui|download|deliver|session|offer|eligible|account|library|purchase|error|fail|abandon|device)|PackageInstaller.*(teamfight|riot|abandon|fail|error)|Phonesky.*(tos|install|fail|error)|Installer.*teamfight|Session.*teamfight)/i.test(line)).slice(-800);
  const shell = (args, timeout = 30000) => adb(runtime, ['shell', ...args], { allowFailure: true, timeout });
  const vendingPrefs = shell(['dumpsys', 'package', 'com.android.vending']).stdout;
  const accounts = shell(['dumpsys', 'account']).stdout;
  const result = {
    observedAt: nowISO(),
    accountCount: Number(accounts.match(/Accounts:\s*(\d+)/)?.[1] ?? 0),
    googleAccountPresent: /type=com\.google|Account \{.*com\.google/i.test(accounts),
    playVersionName: vendingPrefs.match(/versionName=([^\s]+)/)?.[1] ?? null,
    tosTokenEmptySeen: focus.some(line => /tosToken is empty/i.test(line)),
    tftMentionCount: focus.filter(line => /com\.riotgames\.league\.teamfighttactics/i.test(line)).length,
    focusLines: focus
  };
  if (captureDir) writeJSON(path.join(captureDir, 'google-play-install-brief.json'), result);
  return result;
}

async function installDiagnose() {
  const runtime = discover();
  await waitForBoot(runtime, 60000);
  const state = readJSON(CONTROL_STATE);
  const captureDir = state?.captureDir ?? null;
  const shell = (args, timeout = 30000) => adb(runtime, ['shell', ...args], { allowFailure: true, timeout });
  const logcat = command(runtime.adb, ['-P', ADB_PORT, '-s', SERIAL, 'logcat', '-d', '-v', 'threadtime', '-t', '12000'], { env: runtime.env, allowFailure: true, timeout: 30000, maxBuffer: 64 * 1024 * 1024 }).stdout;
  const rx = /(INSTALL_FAILED|PackageInstaller|PackageManager|PackageInstallerSession|Finsky|Phonesky|installd|dex2oat|AppIntegrity|PlayProtect|Verifier|install[^ ]*.*fail|fail[^ ]*.*install|insufficient|not enough|storage|native librar|ABI|split|session.*(fail|abandon)|download.*(fail|error)|asset.*(fail|error)|fs-verity|parse.*package|incompatible)/i;
  const lines = logcat.split(/\r?\n/).filter(line => rx.test(line)).slice(-1800);
  const vendingDump = shell(['dumpsys', 'package', 'com.android.vending']).stdout;
  const sessions = shell(['dumpsys', 'package', 'installer']).stdout;
  const staged = shell(['cmd', 'package', 'list', 'staged-sessions']).stdout;
  const result = {
    observedAt: nowISO(),
    sessionId: state?.sessionId ?? null,
    tftPackage: packageState(runtime, captureDir, false),
    guest: {
      sdk: shell(['getprop', 'ro.build.version.sdk']).stdout.trim(),
      release: shell(['getprop', 'ro.build.version.release']).stdout.trim(),
      fingerprint: shell(['getprop', 'ro.build.fingerprint']).stdout.trim(),
      abi: shell(['getprop', 'ro.product.cpu.abi']).stdout.trim(),
      abiList: shell(['getprop', 'ro.product.cpu.abilist']).stdout.trim(),
      pageSize: shell(['getconf', 'PAGESIZE']).stdout.trim(),
      dataFilesystem: shell(['df', '-h', '/data']).stdout.trim(),
      dataBytes: shell(['df', '-B1', '/data']).stdout.trim()
    },
    playStore: {
      versionName: vendingDump.match(/versionName=([^\s]+)/)?.[1] ?? null,
      versionCode: vendingDump.match(/versionCode=([^\s]+)/)?.[1] ?? null,
      installerSessions: sessions.split(/\r?\n/).filter(line => /Session|install|failure|error|stage|package/i.test(line)).slice(-500),
      stagedSessions: staged.trim() || null
    },
    foreground: shell(['dumpsys', 'activity', 'top']).stdout.split(/\r?\n/).filter(line => /ACTIVITY|topResumedActivity|mResumedActivity|com\.android\.vending/.test(line)).slice(0, 50),
    relevantLogLines: lines
  };
  if (captureDir) {
    writeJSON(path.join(captureDir, 'google-play-install-diagnostic.json'), result);
    fs.writeFileSync(path.join(captureDir, 'google-play-install-logcat.txt'), `${lines.join('\n')}\n`);
  }
  return result;
}

async function authBrief() {
  const runtime = discover();
  await waitForBoot(runtime, 60000);
  const logcat = command(runtime.adb, ['-P', ADB_PORT, '-s', SERIAL, 'logcat', '-d', '-v', 'threadtime', '-t', '5000'], { env: runtime.env, allowFailure: true, timeout: 30000 }).stdout;
  const rx = /(MinuteMaid|PreAddAccount|GLSUser|DeviceKeyStore|crashpad|FATAL EXCEPTION|Force finishing activity.*google|Process .*com\.google\.android\.gms.*died|POST_PRE_ADD_ACCOUNT|auth\.uiflows|Protocol message end-group|Account.*error)/i;
  const lines = logcat.split(/\r?\n/).filter(line => rx.test(line)).slice(-500);
  const accounts = adb(runtime, ['shell', 'dumpsys', 'account'], { allowFailure: true, timeout: 30000 }).stdout;
  const top = adb(runtime, ['shell', 'dumpsys', 'activity', 'top'], { allowFailure: true, timeout: 30000 }).stdout;
  const result = {
    observedAt: nowISO(),
    accountCount: Number(accounts.match(/Accounts:\s*(\d+)/)?.[1] ?? 0),
    foreground: top.split(/\r?\n/).filter(line => /ACTIVITY|topResumedActivity|mResumedActivity/.test(line)).slice(0, 30),
    minuteMaidCrash: lines.some(line => /Force finishing activity.*MinuteMaid|crashpad|FATAL EXCEPTION.*google|Process .*com\.google\.android\.gms.*died/i.test(line)),
    glsProtocolError: lines.some(line => /Protocol message end-group tag did not match expected tag/i.test(line)),
    deviceKeyMissing: lines.some(line => /Device key file not found/i.test(line)),
    relevantLines: lines
  };
  const state = readJSON(CONTROL_STATE);
  if (state?.captureDir) writeJSON(path.join(state.captureDir, 'google-auth-brief.json'), result);
  return result;
}

async function playCertification() {
  const runtime = discover();
  await waitForBoot(runtime, 60000);
  const state = readJSON(CONTROL_STATE);
  const captureDir = state?.captureDir ?? null;
  await ensureGuestClock(runtime, captureDir);
  const shell = (args, timeout = 30000) => adb(runtime, ['shell', ...args], { allowFailure: true, timeout });
  const prop = key => shell(['getprop', key]).stdout.trim() || null;
  const features = shell(['pm', 'list', 'features']).stdout.split(/\r?\n/).filter(Boolean);
  const gsfQuery = shell(['content', 'query', '--uri', 'content://com.google.android.gsf.gservices', '--projection', 'name:value', '--where', "name='android_id'"]).stdout.trim();
  const packageDump = name => shell(['dumpsys', 'package', name]).stdout;
  const vendingDump = packageDump('com.android.vending');
  const gmsDump = packageDump('com.google.android.gms');
  const gsfDump = packageDump('com.google.android.gsf');

  const activityCandidates = [
    'com.android.vending/com.google.android.finsky.activities.SettingsActivity',
    'com.android.vending/com.google.android.finsky.settings.SettingsActivity'
  ];
  let settingsLaunch = null;
  let xml = '';
  for (const component of activityCandidates) {
    const launch = shell(['am', 'start', '-W', '-n', component]);
    if (launch.status === 0 && !/Error|Exception|does not exist|not exported/i.test(`${launch.stdout}${launch.stderr}`)) {
      settingsLaunch = component;
      await sleep(1800);
      xml = dumpUI(runtime);
      break;
    }
  }
  if (!xml) {
    shell(['am', 'force-stop', 'com.android.vending']);
    shell(['am', 'start', '-W', '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.LAUNCHER', '-n', 'com.android.vending/com.google.android.finsky.activities.MainActivity']);
    await sleep(2200);
    xml = dumpUI(runtime);
    const account = findNodeByText(xml, [/account and settings/i, /settings and account/i, /profile/i]);
    if (account?.bounds) {
      shell(['input', 'tap', String(account.bounds.x), String(account.bounds.y)]);
      await sleep(900);
      xml = dumpUI(runtime);
      const settings = findNodeByText(xml, [/^Settings$/i]);
      if (settings?.bounds) {
        shell(['input', 'tap', String(settings.bounds.x), String(settings.bounds.y)]);
        await sleep(1000);
        xml = dumpUI(runtime);
      }
    }
  }
  const about = findNodeByText(xml, [/^About$/i]);
  if (about?.bounds) {
    shell(['input', 'tap', String(about.bounds.x), String(about.bounds.y)]);
    await sleep(1000);
    xml = dumpUI(runtime);
  }
  const nodes = xml.match(/<node\b[^>]*\/>/g) ?? [];
  const visibleText = nodes.flatMap(node => {
    const text = node.match(/text="([^"]*)"/)?.[1] ?? '';
    const desc = node.match(/content-desc="([^"]*)"/)?.[1] ?? '';
    return [text, desc].filter(Boolean);
  });
  const certificationText = visibleText.filter(value => /play protect certification|device is (?:not )?certified|certification/i.test(value));
  const sanitizedUiText = visibleText.filter(value => !/@/.test(value)).filter(value => /play protect|certif|about|play store version|update play store|device/i.test(value)).slice(0, 80);
  const clickableNodes = nodes.filter(node => /clickable="true"/.test(node)).flatMap(node => {
    const text = node.match(/text="([^"]*)"/)?.[1] ?? '';
    const desc = node.match(/content-desc="([^"]*)"/)?.[1] ?? '';
    const bounds = parseBounds(node);
    if ((text && /@/.test(text)) || (desc && /@/.test(desc))) return [];
    if (!bounds) return [];
    return [{ text: text || null, contentDescription: desc || null, bounds }];
  }).slice(0, 120);
  const allSanitizedText = visibleText.filter(value => value && !/@/.test(value)).slice(0, 160);
  const result = {
    observedAt: nowISO(),
    imagePackage: REQUIRED_IMAGE,
    playStoreEnabledInAvd: parseKeyValueLines(runtime.avdConfig ?? '')['PlayStore.enabled'] ?? null,
    settingsLaunch,
    certificationText,
    certificationState: certificationText.some(value => /not certified/i.test(value)) ? 'NOT_CERTIFIED'
      : certificationText.some(value => /device is certified|play protect certified/i.test(value)) ? 'CERTIFIED'
      : 'UNRESOLVED',
    device: {
      fingerprint: prop('ro.build.fingerprint'),
      brand: prop('ro.product.brand'),
      manufacturer: prop('ro.product.manufacturer'),
      model: prop('ro.product.model'),
      device: prop('ro.product.device'),
      buildType: prop('ro.build.type'),
      buildTags: prop('ro.build.tags'),
      debuggable: prop('ro.debuggable'),
      secure: prop('ro.secure'),
      verifiedBootState: prop('ro.boot.verifiedbootstate'),
      flashLocked: prop('ro.boot.flash.locked'),
      vbmetaDeviceState: prop('ro.boot.vbmeta.device_state'),
      sdk: prop('ro.build.version.sdk'),
      release: prop('ro.build.version.release'),
      abi: prop('ro.product.cpu.abi')
    },
    graphicsEligibility: {
      roOpenGLESVersion: prop('ro.opengles.version'),
      hardwareEGL: prop('ro.hardware.egl'),
      hardwareVulkan: prop('ro.hardware.vulkan'),
      vulkanVersionFeature: features.find(line => /android\.hardware\.vulkan\.version/i.test(line)) ?? null,
      vulkanLevelFeature: features.find(line => /android\.hardware\.vulkan\.level/i.test(line)) ?? null,
      glesVersionFeature: features.find(line => /reqGlEsVersion|opengles/i.test(line)) ?? null,
      relevantFeatures: features.filter(line => /vulkan|opengl|gles|texture|screen\.landscape|touchscreen|ram\.(normal|low)/i.test(line)).slice(0, 120)
    },
    registration: {
      androidIdPresent: Boolean(shell(['settings', 'get', 'secure', 'android_id']).stdout.trim()),
      gsfAndroidIdQuerySucceeded: Boolean(gsfQuery && !/Permission Denial|SecurityException|No result/i.test(gsfQuery)),
      gsfAndroidIdPresent: /value=\d+|android_id/i.test(gsfQuery),
      playStoreVersionName: vendingDump.match(/versionName=([^\s]+)/)?.[1] ?? null,
      playServicesVersionName: gmsDump.match(/versionName=([^\s]+)/)?.[1] ?? null,
      gsfVersionName: gsfDump.match(/versionName=([^\s]+)/)?.[1] ?? null
    },
    uiEvidence: sanitizedUiText,
    allSanitizedText,
    clickableNodes
  };
  if (captureDir) writeJSON(path.join(captureDir, 'google-play-certification.json'), result);
  return result;
}

async function playDiagnose() {
  const runtime = discover();
  await waitForBoot(runtime, 60000);
  const state = readJSON(CONTROL_STATE);
  const captureDir = state?.captureDir ?? null;
  const shell = (args, timeout = 30000) => adb(runtime, ['shell', ...args], { allowFailure: true, timeout });
  const pkg = name => {
    const dump = shell(['dumpsys', 'package', name]).stdout;
    return {
      installed: /Package \[|versionCode=|versionName=/.test(dump),
      versionName: dump.match(/versionName=([^\s]+)/)?.[1] ?? null,
      versionCode: dump.match(/versionCode=([^\s]+)/)?.[1] ?? null,
      firstInstallTime: dump.match(/firstInstallTime=([^\n]+)/)?.[1]?.trim() ?? null,
      lastUpdateTime: dump.match(/lastUpdateTime=([^\n]+)/)?.[1]?.trim() ?? null,
      enabled: dump.match(/enabled=([^\s]+)/)?.[1] ?? null
    };
  };
  const props = {};
  for (const key of [
    'ro.build.version.release','ro.build.version.sdk','ro.build.version.security_patch','ro.build.fingerprint',
    'ro.product.model','ro.product.manufacturer','ro.product.device','ro.product.cpu.abi',
    'ro.boot.verifiedbootstate','ro.boot.flash.locked','ro.kernel.qemu','ro.boot.qemu.avd_name',
    'ro.build.tags','ro.build.type','ro.debuggable','ro.secure','persist.sys.timezone'
  ]) props[key] = shell(['getprop', key]).stdout.trim() || null;
  const epoch = shell(['date', '+%s']).stdout.trim();
  const utcDate = shell(['date', '-u']).stdout.trim();
  const autoTime = shell(['settings', 'get', 'global', 'auto_time']).stdout.trim();
  const autoZone = shell(['settings', 'get', 'global', 'auto_time_zone']).stdout.trim();
  const androidId = shell(['settings', 'get', 'secure', 'android_id']).stdout.trim();
  const accounts = shell(['dumpsys', 'account']).stdout;
  const connectivity = shell(['dumpsys', 'connectivity']).stdout;
  const dnsProbe = shell(['ping', '-c', '1', '-W', '3', 'connectivitycheck.gstatic.com'], 10000);
  const playCheck = shell(['pm', 'list', 'packages', '-i']).stdout.split(/\r?\n/)
    .filter(line => /com\.android\.vending|com\.google\.android\.gms|com\.google\.android\.gsf/.test(line));
  const logcat = command(runtime.adb, ['-P', ADB_PORT, '-s', SERIAL, 'logcat', '-d', '-v', 'threadtime', '-t', '6000'], { env: runtime.env, allowFailure: true, timeout: 30000 }).stdout;
  const authRx = /(Finsky|Vending|GoogleLogin|GoogleAuth|AuthManager|AccountManager|GLS|GmsAuth|GmsCore|Google Play services|checkin|Checkin|DroidGuard|SafetyNet|Integrity|PlayIntegrity|device.?cert|certification|OAuth|token|Token|signin|SignIn|auth|Auth|phenotype|conscrypt|SSL|TLS|network|Network)/i;
  const authLines = logcat.split(/\r?\n/).filter(line => authRx.test(line)).slice(-1200);
  const result = {
    observedAt: nowISO(),
    sessionId: state?.sessionId ?? null,
    foreground: shell(['dumpsys', 'activity', 'top']).stdout.split(/\r?\n/).filter(line => /ACTIVITY|mResumedActivity|topResumedActivity|com\.android\.vending/.test(line)).slice(0, 40),
    clock: { hostEpochSeconds: Math.floor(Date.now() / 1000), guestEpochSeconds: Number(epoch) || null, guestUTC: utcDate || null, autoTime, autoTimeZone: autoZone },
    network: { dnsProbeStatus: dnsProbe.status, dnsProbe: `${dnsProbe.stdout}${dnsProbe.stderr}`.trim(), connectivityMentions: connectivity.split(/\r?\n/).filter(line => /VALIDATED|INTERNET|WIFI|NetworkAgentInfo|Dns|dns/i.test(line)).slice(0, 120) },
    properties: props,
    androidId: androidId || null,
    packages: {
      playStore: pkg('com.android.vending'),
      playServices: pkg('com.google.android.gms'),
      googleServicesFramework: pkg('com.google.android.gsf')
    },
    packageInstallers: playCheck,
    accountsSummary: accounts.split(/\r?\n/).filter(line => /Account \{|type=com\.google|Accounts:|User UserInfo|AuthenticatorDescription/i.test(line)).slice(0, 160),
    authLogLines: authLines
  };
  if (captureDir) {
    writeJSON(path.join(captureDir, 'google-play-auth-diagnostic.json'), result);
    fs.writeFileSync(path.join(captureDir, 'google-play-auth-logcat.txt'), `${authLines.join('\n')}\n`);
  }
  return result;
}

function recursiveSize(root) {
  let total = 0;
  const stack = [root];
  while (stack.length) {
    const p = stack.pop();
    let st; try { st = fs.lstatSync(p); } catch { continue; }
    if (st.isFile()) total += st.size;
    else if (st.isDirectory()) { try { for (const e of fs.readdirSync(p)) stack.push(path.join(p, e)); } catch {} }
  }
  return total;
}

function parseFrameStats(text) {
  const byIntended = new Map();
  let header = null;
  for (const line of text.split(/\r?\n/)) {
    if (line.startsWith('Flags,IntendedVsync')) { header = line.split(','); continue; }
    if (!header || !/^\d+,/.test(line)) continue;
    const parts = line.split(',');
    if (parts.length < header.length) continue;
    const rec = Object.fromEntries(header.map((h, i) => [h, parts[i]]));
    let intended, completed;
    try {
      intended = BigInt(rec.IntendedVsync || '0');
      completed = BigInt(rec.FrameCompleted || '0');
    } catch { continue; }
    if (intended <= 0n || completed <= 0n || completed < intended || completed >= 9000000000000000000n) continue;
    byIntended.set(intended.toString(), {
      intendedNs: intended,
      completedNs: completed,
      renderLatencyNs: completed - intended
    });
  }
  const rows = [...byIntended.values()].sort((a, b) => a.completedNs < b.completedNs ? -1 : a.completedNs > b.completedNs ? 1 : 0);
  let previous = null;
  for (let i = 0; i < rows.length; i += 1) {
    rows[i].frameNumber = i + 1;
    rows[i].intervalNs = previous === null ? null : rows[i].completedNs - previous;
    previous = rows[i].completedNs;
  }
  return rows;
}

function readJSONL(file) {
  if (!exists(file)) return [];
  return fs.readFileSync(file, 'utf8').split(/\r?\n/).filter(Boolean).flatMap(line => {
    try { return [JSON.parse(line)]; } catch { return []; }
  });
}

function csvEscape(value) {
  if (value === null || value === undefined) return '';
  const s = String(value);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

function percentile(values, p) {
  if (!values.length) return null;
  const a = [...values].sort((x, y) => x - y);
  const idx = Math.min(a.length - 1, Math.max(0, Math.ceil(p * a.length) - 1));
  return a[idx];
}

function finalizeRawManifest(captureDir) {
  const rawRelativePaths = [
    'session.json',
    'runtime-state.json',
    'package-state.json',
    'renderer-state.json',
    'host-events.jsonl',
    'clock-sync.jsonl',
    'markers.jsonl',
    'emulator.stdout.log',
    'emulator.stderr.log',
    'logcat.raw.txt',
    'host-process.csv',
    'host-process.jsonl',
    'host-memory.csv',
    'host-memory.jsonl',
    'surfaceflinger/counters.jsonl',
    'gfxinfo/framestats.raw.txt'
  ];
  const lines = [];
  for (const rel of rawRelativePaths) {
    const file = path.join(captureDir, rel);
    if (!exists(file)) continue;
    try {
      if (fs.statSync(file).isFile()) lines.push(`${sha256File(file)}  ${rel}`);
    } catch {}
  }
  const manifestPath = path.join(captureDir, 'manifest.raw.sha256');
  fs.writeFileSync(manifestPath, `${lines.join('\n')}${lines.length ? '\n' : ''}`);
  return { path: manifestPath, sha256: sha256File(manifestPath), artifactCount: lines.length };
}

function finalizeManifest(captureDir) {
  const entries = [];
  for (const file of walk(captureDir, 12, 50000)) {
    try { if (fs.statSync(file).isFile() && !['manifest.sha256'].includes(path.basename(file))) entries.push(file); } catch {}
  }
  entries.sort();
  const lines = entries.map(file => `${sha256File(file)}  ${path.relative(captureDir, file)}`);
  fs.writeFileSync(path.join(captureDir, 'manifest.sha256'), `${lines.join('\n')}\n`);
  return sha256File(path.join(captureDir, 'manifest.sha256'));
}

function filterLogcat(captureDir) {
  const raw = path.join(captureDir, 'logcat.raw.txt');
  const filtered = path.join(captureDir, 'logcat.filtered.txt');
  if (!exists(raw)) { fs.writeFileSync(filtered, ''); return 0; }
  const matcher = /riot|teamfight|leagueoflegends|unreal|\bUE[45]\b|angle|gfxstream|moltenvk|vulkan|metal|surfaceflinger|choreographer|openglrenderer|\bEGL\b|graphicsenv|activitymanager|packagemanager|fatal exception|\bANR\b/i;
  const lines = fs.readFileSync(raw, 'utf8').split(/\r?\n/).filter(line => matcher.test(line));
  fs.writeFileSync(filtered, `${lines.join('\n')}${lines.length ? '\n' : ''}`);
  return lines.length;
}

function artifactId(sessionId, relativePath) {
  return `artifact_${crypto.createHash('sha256').update(`${sessionId}\0${relativePath}`).digest('hex').slice(0, 28)}`;
}

function asNumber(value) {
  if (value === null || value === undefined || value === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function labSchemaPath() {
  const candidates = [
    path.join(scriptDir, 'TFTMAC_PERFORMANCE_LAB.sql'),
    path.join(repoRoot, 'ssot', 'TFTMAC_PERFORMANCE_LAB.sql')
  ];
  return candidates.find(exists) ?? null;
}

function engineeringMapSelfTest() {
  const schemaPath = path.join(repoRoot, 'ssot', 'TFTMAC_ENGINEERING_MAP.sql');
  if (!exists(schemaPath)) throw new Error('TFTMAC engineering-map SQL is unavailable.');
  const tempPath = `/private/tmp/tftmac-map-selftest-${process.pid}-${Date.now()}.sqlite`;
  const db = new DatabaseSync(tempPath);
  try {
    db.exec(fs.readFileSync(schemaPath, 'utf8'));
    const foreignKeyProblems = db.prepare('PRAGMA foreign_key_check').all();
    const tableCount = db.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table'").get()?.n ?? 0;
    const viewCount = db.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE type='view'").get()?.n ?? 0;
    const currentLoggerReliability = db.prepare("SELECT value FROM map_meta WHERE key='current_logger_reliability'").get()?.value ?? null;
    const currentPresentationCandidate = db.prepare("SELECT value FROM map_meta WHERE key='current_presentation_candidate'").get()?.value ?? null;
    if (foreignKeyProblems.length) throw new Error(`ENGINEERING_MAP_FOREIGN_KEY_FAILURE: ${JSON.stringify(foreignKeyProblems)}`);
    if (!currentLoggerReliability) throw new Error('ENGINEERING_MAP_LOGGER_POLICY_MISSING');
    return { schemaPath, tableCount, viewCount, foreignKeyProblems, currentLoggerReliability, currentPresentationCandidate };
  } finally {
    try { db.close(); } catch {}
    try { fs.unlinkSync(tempPath); } catch {}
  }
}

function labSelfTest() {
  const schemaPath = labSchemaPath();
  if (!schemaPath) throw new Error('TFTMAC performance-lab schema is unavailable.');
  const tempPath = `/private/tmp/tftmac-lab-selftest-${process.pid}-${Date.now()}.sqlite`;
  const db = new DatabaseSync(tempPath);
  try {
    db.exec(fs.readFileSync(schemaPath, 'utf8'));
    const currentBaseline = db.prepare("SELECT value FROM lab_meta WHERE key='current_playable_baseline'").get()?.value ?? 'control_stock_direct_v0';
    const control = db.prepare('SELECT id,vcpu,ram_mb,display_width,display_height,density_dpi,state FROM runtime_configs WHERE id=?').get(currentBaseline);
    const experiment = db.prepare("SELECT id,state,baseline_config_id FROM experiments WHERE id='exp_control_direct_play'").get();
    const plannedExperiments = db.prepare("SELECT id,name,baseline_config_id,candidate_config_id,one_factor FROM experiments WHERE state='PLANNED' ORDER BY id").all();
    const foreignKeyProblems = db.prepare('PRAGMA foreign_key_check').all();
    const syntheticLatestMatch = matchWindowFromMarkers([
      { event: 'MATCH_ENTRY', host_mono_ns: '100' },
      { event: 'MATCH_RESULT', host_mono_ns: '200', placement: 1 },
      { event: 'MATCH_ENTRY', host_mono_ns: '300' },
      { event: 'MATCH_RESULT', host_mono_ns: '450', placement: 4 }
    ]);
    if (!control) throw new Error(`PERFORMANCE_LAB_CURRENT_BASELINE_MISSING: ${currentBaseline}`);
    if (foreignKeyProblems.length) throw new Error(`PERFORMANCE_LAB_FOREIGN_KEY_FAILURE: ${JSON.stringify(foreignKeyProblems)}`);
    if (syntheticLatestMatch?.matchOrdinal !== 2 || syntheticLatestMatch?.result?.placement !== 4) throw new Error(`MULTI_MATCH_SEGMENTATION_FAILED: ${JSON.stringify(syntheticLatestMatch)}`);
    return { schemaPath, currentBaseline, control, experiment, plannedExperiments, foreignKeyProblems, multiMatchSegmentation: { pass: true, latestMatchOrdinal: syntheticLatestMatch.matchOrdinal, latestPlacement: syntheticLatestMatch.result.placement } };
  } finally {
    try { db.close(); } catch {}
    try { fs.unlinkSync(tempPath); } catch {}
  }
}

function normalizePerformanceLab(captureDir, frames, metrics, storage, manifestSHA256) {
  ensureDir(DIAGNOSTICS_ROOT);
  const schemaPath = labSchemaPath();
  if (!schemaPath) throw new Error('TFTMAC performance-lab schema is unavailable.');
  const databasePath = path.join(DIAGNOSTICS_ROOT, 'TFTMAC_PERFORMANCE_LAB.sqlite');
  const initialize = !exists(databasePath) || fs.statSync(databasePath).size === 0;
  const db = new DatabaseSync(databasePath);
  try {
    if (initialize) db.exec(fs.readFileSync(schemaPath, 'utf8'));
    db.exec('PRAGMA foreign_keys = ON;');

    const session = readJSON(path.join(captureDir, 'session.json'), {});
    const runtime = readJSON(path.join(captureDir, 'runtime-state.json'), {});
    const pkg = readJSON(path.join(captureDir, 'package-state.json'), {});
    const renderer = readJSON(path.join(captureDir, 'renderer-state.json'), {});
    const markers = readJSONL(path.join(captureDir, 'markers.jsonl'));
    const clocks = readJSONL(path.join(captureDir, 'clock-sync.jsonl'));
    const processes = readJSONL(path.join(captureDir, 'host-process.jsonl'));
    const memories = readJSONL(path.join(captureDir, 'host-memory.jsonl'));
    const sessionId = session.sessionId;
    const runtimeConfigId = session.runtimeConfig ?? runtime.control ?? 'control_stock_direct_v0';
    const matchResultObserved = session.matchResultObserved === true || markers.some(row => row.event === 'MATCH_RESULT');
    const gameplayOutcomeObserved = matchResultObserved && pkg.installerPackage === 'com.android.vending';
    const rawTelemetryValid = clocks.length > 0 && processes.length > 0 && memories.length > 0;
    const officialRuntimeValid = pkg.installerPackage === 'com.android.vending';
    const nativeFrameTimingValid = frames.some(frame => frame.intervalNs !== null);
    const semanticValid = rawTelemetryValid && officialRuntimeValid;
    const captureState = semanticValid ? 'COMPLETE' : 'PARTIAL';
    const workloadClass = session.lastTftLaunchPid || matchResultObserved ? 'MIXED' : 'UNKNOWN';
    const packageStatePath = path.join(captureDir, 'package-state.json');
    const rendererStatePath = path.join(captureDir, 'renderer-state.json');

    db.exec('BEGIN IMMEDIATE;');
    try {
      const observedConfigHash = runtime.avdConfigSHA256 ?? null;
      const hashOwner = observedConfigHash ? db.prepare('SELECT id FROM runtime_configs WHERE config_sha256=?').get(observedConfigHash)?.id ?? null : null;
      const safeConfigHash = !hashOwner || hashOwner === runtimeConfigId ? observedConfigHash : null;
      const runtimeConfigExists = Boolean(db.prepare('SELECT 1 AS ok FROM runtime_configs WHERE id=?').get(runtimeConfigId));
      if (!runtimeConfigExists) {
        const baselineId = BASELINE_PROFILE.id;
        const baselineExists = Boolean(db.prepare('SELECT 1 AS ok FROM runtime_configs WHERE id=?').get(baselineId));
        const parentConfigId = runtimeConfigId !== baselineId && baselineExists ? baselineId : null;
        db.prepare(`INSERT INTO runtime_configs(
          id,parent_config_id,name,config_sha256,emulator_version,platform_tools_version,system_image_package,system_image_revision,
          avd_name,adb_serial,adb_server_port,emulator_console_port,vcpu,ram_mb,display_width,display_height,density_dpi,refresh_hz,
          gpu_mode,audio_enabled,graphics_transport,angle_mode,vulkan_mode,moltenvk_mode,presentation_mode,state,created_at,notes
        ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`)
          .run(runtimeConfigId,parentConfigId,`Observed runtime ${runtimeConfigId}`,safeConfigHash,
            '37.1.11','37.0.1',REQUIRED_IMAGE,REQUIRED_IMAGE_MIN_REVISION,AVD_NAME,SERIAL,Number(ADB_PORT),Number(EMULATOR_PORT),
            asNumber(runtime.vcpu),asNumber(runtime.ramMB),1920,1080,320,60,'host',runtime.audioEnabled === false ? 0 : 1,
            runtime.graphicsTransportRequested ?? null,renderer?.angleSettings ? JSON.stringify(renderer.angleSettings) : null,
            renderer?.properties?.['ro.hardware.vulkan'] ?? null,
            (renderer?.hostGraphicsEvidence ?? []).some(line => /MoltenVK/i.test(line)) ? 'OBSERVED_IN_HOST_LOG' : null,
            'direct emulator window',runtimeConfigId === baselineId ? 'CONTROL' : 'CANDIDATE',session.startedUTC ?? nowISO(),
            `Auto-registered from runtime-state during normalization; audioBackend=${runtime.audioBackend ?? 'implicit'}.`);
      }
      db.prepare("UPDATE runtime_configs SET config_sha256=COALESCE(config_sha256, ?), graphics_transport=COALESCE(graphics_transport, ?), angle_mode=COALESCE(angle_mode, ?), vulkan_mode=COALESCE(vulkan_mode, ?), moltenvk_mode=COALESCE(moltenvk_mode, ?) WHERE id=?")
        .run(safeConfigHash,
          runtime.graphicsTransportRequested ?? runtime.observedGraphicsTransport ?? null,
          renderer?.angleSettings ? JSON.stringify(renderer.angleSettings) : null,
          renderer?.properties?.['ro.hardware.vulkan'] ?? null,
          (renderer?.hostGraphicsEvidence ?? []).some(line => /MoltenVK/i.test(line)) ? 'OBSERVED_IN_HOST_LOG' : null,
          runtimeConfigId);

      db.prepare(`INSERT INTO sessions (
        id,runtime_config_id,started_utc,ended_utc,host_start_mono_ns,host_end_mono_ns,boot_class,workload_class,
        package_name,package_version_name,package_version_code,package_state_sha256,renderer_state_sha256,session_manifest_sha256,
        package_updated_during_session,capture_state,semantic_valid,invalid_reason,notes
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET
        ended_utc=excluded.ended_utc,host_end_mono_ns=excluded.host_end_mono_ns,boot_class=excluded.boot_class,workload_class=excluded.workload_class,
        package_version_name=excluded.package_version_name,package_version_code=excluded.package_version_code,package_state_sha256=excluded.package_state_sha256,
        renderer_state_sha256=excluded.renderer_state_sha256,session_manifest_sha256=excluded.session_manifest_sha256,
        package_updated_during_session=excluded.package_updated_during_session,capture_state=excluded.capture_state,semantic_valid=excluded.semantic_valid,
        invalid_reason=excluded.invalid_reason,notes=excluded.notes`)
        .run(sessionId, runtimeConfigId, session.startedUTC ?? null, session.endedUTC ?? null,
          asNumber(session.hostStartMonoNs), asNumber(session.hostEndMonoNs), runtime.bootClass ?? 'UNKNOWN', workloadClass,
          PACKAGE, pkg.versionName ?? null, pkg.versionCode ?? null,
          exists(packageStatePath) ? sha256File(packageStatePath) : null,
          exists(rendererStatePath) ? sha256File(rendererStatePath) : null,
          manifestSHA256, session.packageUpdatedDuringSession ? 1 : 0, captureState, semanticValid ? 1 : 0,
          semanticValid ? (nativeFrameTimingValid ? null : 'Continuous raw run is valid; native Unreal/Vulkan frame timing remains a separate unresolved metric.') : 'Continuous run is missing required raw telemetry or official Google Play package authority.',
          `model=CONTINUOUS_RUN_PRIMARY; Google Play installer=${pkg.installerPackage ?? 'unknown'}; rawTelemetry=${rawTelemetryValid}; matchResult=${matchResultObserved}; nativeFrameTiming=${nativeFrameTimingValid}; signer=${pkg.signerCertificateSHA256 ?? 'unavailable'}`);

      db.prepare("DELETE FROM evidence WHERE session_id=? AND id LIKE 'evidence_%'").run(sessionId);
      db.prepare('DELETE FROM experiment_sessions WHERE experiment_id=? AND session_id=?').run('exp_control_direct_play', sessionId);
      db.prepare(`DELETE FROM metrics WHERE session_id=? AND metric_name IN (
        'frame_sample_count','presented_fps_approx','mean_frame_interval_ms','p50_frame_interval_ms','p95_frame_interval_ms','p99_frame_interval_ms','jank_pct','severe_stall_count',
        'sdk_bytes','avd_bytes','capture_bytes'
      )`).run(sessionId);
      for (const table of ['frame_samples','process_samples','memory_samples','markers','clock_sync','artifacts']) {
        db.prepare(`DELETE FROM ${table} WHERE session_id=?`).run(sessionId);
      }

      const requiredArtifacts = new Set([
        'session.json','runtime-state.json','package-state.json','renderer-state.json','host-events.jsonl','clock-sync.jsonl','markers.jsonl',
        'emulator.stdout.log','emulator.stderr.log','logcat.raw.txt','logcat.filtered.txt','host-process.csv','host-process.jsonl','host-memory.csv','host-memory.jsonl',
        'surfaceflinger/surfaceflinger.txt','gfxinfo/framestats.raw.txt','manifest.sha256'
      ]);
      const artifactByPath = new Map();
      const files = walk(captureDir, 12, 50000).filter(file => { try { return fs.statSync(file).isFile(); } catch { return false; } });
      const observedRel = new Set(files.map(file => path.relative(captureDir, file)));
      const artifactStmt = db.prepare('INSERT INTO artifacts(id,session_id,experiment_id,artifact_kind,path,sha256,byte_count,required,state,created_at,notes) VALUES(?,?,?,?,?,?,?,?,?,?,?)');
      for (const file of files) {
        const rel = path.relative(captureDir, file);
        const id = artifactId(sessionId, rel);
        artifactByPath.set(rel, id);
        const stat = fs.statSync(file);
        artifactStmt.run(id, sessionId, null, path.extname(rel).replace(/^\./, '').toUpperCase() || 'FILE', rel, sha256File(file), stat.size, requiredArtifacts.has(rel) ? 1 : 0, 'PRESENT', session.endedUTC ?? nowISO(), null);
      }
      for (const rel of requiredArtifacts) {
        if (observedRel.has(rel)) continue;
        const id = artifactId(sessionId, rel);
        artifactByPath.set(rel, id);
        artifactStmt.run(id, sessionId, null, 'REQUIRED_CONTROL_ARTIFACT', rel, null, null, 1, 'MISSING', session.endedUTC ?? nowISO(), 'Required by TFTMAC_DIRECT_PLAY_CONTROL_BUILD.md');
      }

      const clockStmt = db.prepare('INSERT INTO clock_sync(session_id,host_t0_ns,guest_mono_ns,host_t1_ns,host_midpoint_ns,rtt_ns,estimated_offset_ns,source) VALUES(?,?,?,?,?,?,?,?)');
      for (const row of clocks) {
        if ([row.host_t0_ns,row.guest_mono_ns,row.host_t1_ns,row.host_midpoint_ns,row.rtt_ns,row.estimated_offset_ns].some(v => asNumber(v) === null)) continue;
        clockStmt.run(sessionId, asNumber(row.host_t0_ns), asNumber(row.guest_mono_ns), asNumber(row.host_t1_ns), asNumber(row.host_midpoint_ns), asNumber(row.rtt_ns), asNumber(row.estimated_offset_ns), row.source ?? '/proc/uptime');
      }

      const markerTableSql = String(db.prepare("SELECT sql FROM sqlite_master WHERE type='table' AND name='markers'").get()?.sql ?? '');
      const markerTypeSupported = type => markerTableSql.includes(`'${type}'`);
      const markerStmt = db.prepare('INSERT INTO markers(session_id,host_mono_ns,guest_mono_ns,marker_type,label,payload_json) VALUES(?,?,?,?,?,?)');
      for (const row of markers) {
        const type = row.event === 'MANUAL_STUTTER_MARKER' ? 'USER_STUTTER'
          : row.event === 'MATCH_ENTRY' ? 'MATCH_ENTRY'
          : row.event === 'MATCH_RESULT' ? 'MATCH_RESULT'
          : row.event === 'COMBAT_START' ? 'COMBAT_START'
          : row.event === 'PACKAGE_UPDATE' ? 'PACKAGE_UPDATE'
          : row.event === 'GAME_SETTINGS' ? 'GAME_SETTINGS'
          : 'CUSTOM';
        const normalizedType = markerTypeSupported(type) ? type : 'CUSTOM';
        markerStmt.run(sessionId, asNumber(row.host_mono_ns) ?? asNumber(session.hostStartMonoNs) ?? 0, null, normalizedType, row.event ?? null, JSON.stringify({ ...row, normalizedMarkerType: normalizedType, originalMarkerType: type }));
      }

      const frameArtifact = artifactByPath.get('gfxinfo/framestats.raw.txt') ?? null;
      const frameStmt = db.prepare('INSERT INTO frame_samples(session_id,source,surface_name,frame_number,presentation_host_ns,presentation_guest_ns,frame_interval_ns,classification,raw_artifact_id) VALUES(?,?,?,?,?,?,?,?,?)');
      for (const row of frames) {
        const interval = row.intervalNs === null ? null : Number(row.intervalNs);
        const classification = interval === null ? 'UNKNOWN' : interval > 100000000 ? 'SEVERE_STALL' : interval > 33334000 ? 'JANK' : 'NORMAL';
        frameStmt.run(sessionId, 'gfxinfo_framestats', null, row.frameNumber, null, Number(row.completedNs), interval, classification, frameArtifact);
      }

      const processArtifact = artifactByPath.get('host-process.jsonl') ?? null;
      const processStmt = db.prepare('INSERT INTO process_samples(session_id,host_mono_ns,scope,process_name,pid,tid,cpu_pct,cpu_time_ns,rss_bytes,thread_count,nice_value,process_state,raw_artifact_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)');
      const emulatorRSSByMono = new Map();
      for (const row of processes) {
        const mono = asNumber(row.host_mono_ns);
        if (mono === null) continue;
        const rssBytes = asNumber(row.rss_kb) === null ? null : Number(row.rss_kb) * 1024;
        processStmt.run(sessionId, mono, 'HOST', path.basename(row.command ?? 'unknown'), asNumber(row.pid), null, asNumber(row.cpu_pct), null, rssBytes, null, asNumber(row.nice), row.state ?? null, processArtifact);
        if (/emulator|qemu/i.test(row.command ?? '') && rssBytes !== null) emulatorRSSByMono.set(String(row.host_mono_ns), Math.max(emulatorRSSByMono.get(String(row.host_mono_ns)) ?? 0, rssBytes));
      }

      const memoryArtifact = artifactByPath.get('host-memory.jsonl') ?? null;
      const memoryStmt = db.prepare('INSERT INTO memory_samples(session_id,host_mono_ns,host_used_bytes,host_available_bytes,host_compressed_bytes,host_swap_used_bytes,host_pressure_state,guest_total_bytes,guest_available_bytes,emulator_rss_bytes,pagein_count,pageout_count,raw_artifact_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)');
      for (const row of memories) {
        const mono = asNumber(row.host_mono_ns);
        if (mono === null) continue;
        memoryStmt.run(sessionId, mono, asNumber(row.host_used_bytes), asNumber(row.host_available_bytes), asNumber(row.host_compressed_bytes), asNumber(row.host_swap_used_bytes), null,
          asNumber(row.guest_total_bytes), asNumber(row.guest_available_bytes), emulatorRSSByMono.get(String(row.host_mono_ns)) ?? null,
          asNumber(row.pagein_count), asNumber(row.pageout_count), memoryArtifact);
      }

      const metricStmt = db.prepare('INSERT INTO metrics(session_id,experiment_id,metric_scope,metric_name,metric_value,unit,source_artifact_id,semantic_valid,notes) VALUES(?,?,?,?,?,?,?,?,?)');
      const metricRows = [
        ['FRAME','frame_sample_count',metrics.frameSampleCount,'count'],
        ['FRAME','presented_fps_approx',metrics.presentedFPSApprox,'fps'],
        ['FRAME','mean_frame_interval_ms',metrics.meanFrameMs,'ms'],
        ['FRAME','p50_frame_interval_ms',metrics.p50FrameMs,'ms'],
        ['FRAME','p95_frame_interval_ms',metrics.p95FrameMs,'ms'],
        ['FRAME','p99_frame_interval_ms',metrics.p99FrameMs,'ms'],
        ['FRAME','jank_pct',metrics.jankPct,'percent'],
        ['FRAME','severe_stall_count',metrics.severeStallCount,'count'],
        ['STORAGE','sdk_bytes',storage.sdkBytes,'bytes'],
        ['STORAGE','avd_bytes',storage.avdBytes,'bytes'],
        ['STORAGE','capture_bytes',storage.captureBytes,'bytes']
      ];
      for (const [scope,name,value,unit] of metricRows) {
        if (value === null || value === undefined || !Number.isFinite(Number(value))) continue;
        const metricSemanticValid = scope === 'FRAME' ? (nativeFrameTimingValid ? 1 : 0) : (semanticValid ? 1 : 0);
        metricStmt.run(sessionId, null, scope, name, Number(value), unit, scope === 'FRAME' ? (artifactByPath.get('frame-metrics.json') ?? frameArtifact) : (artifactByPath.get('storage-bom.json') ?? null), metricSemanticValid, scope === 'FRAME' && !nativeFrameTimingValid ? 'gfxinfo is not a valid native Unreal/Vulkan frame source for this session.' : null);
      }

      const packageArtifact = artifactByPath.get('package-state.json') ?? null;
      const rendererArtifact = artifactByPath.get('renderer-state.json') ?? null;
      if (session.packageAuthorityVerified === true && pkg.versionName) {
        db.prepare('INSERT INTO evidence(id,hypothesis_id,session_id,experiment_id,evidence_type,claim,relation,strength,source_artifact_id,created_at,notes) VALUES(?,?,?,?,?,?,?,?,?,?,?)')
          .run(`evidence_pkg_${sessionId}`, null, sessionId, null, 'CONFIG_OBSERVATION', `Google Play authority observed official TFT ${pkg.versionName} (${pkg.versionCode ?? 'unknown code'}).`, 'SUPPORTS', 'STRONG', packageArtifact, session.endedUTC ?? nowISO(), `Signer SHA-256: ${pkg.signerCertificateSHA256 ?? 'unavailable'}`);
        db.prepare("UPDATE unknowns SET status='RESOLVED', resolved_at=?, notes=? WHERE id='u_current_tft_version'")
          .run(session.endedUTC ?? nowISO(), `${pkg.versionName} / ${pkg.versionCode ?? 'unknown code'} / signer ${pkg.signerCertificateSHA256 ?? 'unavailable'}`);
      }
      if (exists(rendererStatePath)) {
        db.prepare('INSERT INTO evidence(id,hypothesis_id,session_id,experiment_id,evidence_type,claim,relation,strength,source_artifact_id,created_at,notes) VALUES(?,?,?,?,?,?,?,?,?,?,?)')
          .run(`evidence_renderer_${sessionId}`, null, sessionId, null, 'CONFIG_OBSERVATION', 'Renderer state was captured directly from the current stock control.', 'SUPPORTS', 'STRONG', rendererArtifact, session.endedUTC ?? nowISO(), JSON.stringify(renderer.properties ?? {}));
        db.prepare("UPDATE unknowns SET status='RESOLVED', resolved_at=?, notes=? WHERE id='u_observed_renderer_path'")
          .run(session.endedUTC ?? nowISO(), JSON.stringify({ properties: renderer.properties ?? {}, hostGraphicsEvidence: (renderer.hostGraphicsEvidence ?? []).slice(-20) }));
      }
      db.prepare("UPDATE unknowns SET status='RESOLVED', resolved_at=?, notes=? WHERE id='u_storage_bom'")
        .run(session.endedUTC ?? nowISO(), JSON.stringify(storage));

      if (gameplayOutcomeObserved) {
        db.prepare("INSERT OR REPLACE INTO experiment_sessions(experiment_id,session_id,role) VALUES('exp_control_direct_play',?,'BASELINE')").run(sessionId);
        db.prepare("UPDATE experiments SET state='COMPLETE', completed_at=?, notes=? WHERE id='exp_control_direct_play'")
          .run(session.endedUTC ?? nowISO(), `Completed official Google-Play-installed live-match control session ${sessionId}; native frame timing available=${nativeFrameTimingValid}.`);
      }
      db.exec('COMMIT;');
    } catch (error) {
      try { db.exec('ROLLBACK;'); } catch {}
      throw error;
    }

    const quality = db.prepare('SELECT * FROM v_session_quality WHERE session_id=?').get(session.sessionId);
    const stall = db.prepare('SELECT * FROM v_stall_summary WHERE session_id=?').get(session.sessionId);
    db.close();
    const result = {
      databasePath,
      databaseSHA256: sha256File(databasePath),
      initializedFromSchema: initialize,
      semanticValid,
      captureState,
      quality: quality ?? null,
      stallSummary: stall ?? null
    };
    writeJSON(path.join(captureDir, 'normalization.json'), result);
    return result;
  } catch (error) {
    try { db.close(); } catch {}
    throw error;
  }
}

async function stopControl() {
  const runtime = discover();
  const state = readJSON(CONTROL_STATE);
  if (!state?.captureDir) throw new Error('No active direct-control session.');
  const captureDir = state.captureDir;

  // CRITICAL SHUTDOWN CONTRACT: stop producers and seal raw evidence first.
  // No SDK/AVD inventory, package-signing pull, SQL work, or expensive derived
  // analysis is allowed to sit between sampler shutdown and the raw seal.
  if (processAlive(state.samplerPid)) { try { process.kill(state.samplerPid, 'SIGTERM'); } catch {} }
  for (let i = 0; i < 10 && processAlive(state.samplerPid); i += 1) await sleep(500);

  const sessionPath = path.join(captureDir, 'session.json');
  const session = readJSON(sessionPath, {});
  const pkg = readJSON(path.join(captureDir, 'package-state.json'), {});
  session.endedUTC = nowISO();
  session.hostEndMonoNs = monoNs().toString();
  session.rawCaptureState = 'SEALED';
  session.semanticValid = pkg.installerPackage === 'com.android.vending'
    && exists(path.join(captureDir, 'host-process.jsonl'))
    && exists(path.join(captureDir, 'host-memory.jsonl'))
    && exists(path.join(captureDir, 'logcat.raw.txt'));
  session.captureState = session.semanticValid ? 'COMPLETE' : 'PARTIAL';
  writeJSON(sessionPath, session);

  const rawManifest = finalizeRawManifest(captureDir);
  writeJSON(path.join(captureDir, 'capture-seal.json'), {
    sessionId: state.sessionId,
    sealedAt: nowISO(),
    rawCaptureState: 'SEALED',
    rawManifestSHA256: rawManifest.sha256,
    rawArtifactCount: rawManifest.artifactCount,
    semanticValid: session.semanticValid,
    note: 'Raw capture was sealed immediately after telemetry producers stopped. All derived analysis, inventory, and SQLite work is post-seal and cannot invalidate this capture.'
  });

  // Everything below this line is post-seal derived work. It may fail without
  // compromising the completed game capture.
  const filteredLogLines = filterLogcat(captureDir);
  const frameText = exists(path.join(captureDir, 'gfxinfo', 'framestats.raw.txt')) ? fs.readFileSync(path.join(captureDir, 'gfxinfo', 'framestats.raw.txt'), 'utf8') : '';
  const frames = parseFrameStats(frameText);
  const frameMs = frames.flatMap(row => row.intervalNs === null ? [] : [Number(row.intervalNs) / 1e6]).filter(v => Number.isFinite(v) && v > 0 && v < 10000);
  const renderLatencyMs = frames.map(row => Number(row.renderLatencyNs) / 1e6).filter(v => Number.isFinite(v) && v >= 0 && v < 10000);
  const metrics = {
    frameSampleCount: frameMs.length,
    meanFrameMs: frameMs.length ? frameMs.reduce((a, b) => a + b, 0) / frameMs.length : null,
    p50FrameMs: percentile(frameMs, 0.50),
    p95FrameMs: percentile(frameMs, 0.95),
    p99FrameMs: percentile(frameMs, 0.99),
    maxFrameMs: frameMs.length ? Math.max(...frameMs) : null,
    meanRenderLatencyMs: renderLatencyMs.length ? renderLatencyMs.reduce((a, b) => a + b, 0) / renderLatencyMs.length : null,
    jankCount: frameMs.filter(v => v > 33.334).length,
    severeStallCount: frameMs.filter(v => v > 100).length,
    filteredLogLines
  };
  metrics.jankPct = frameMs.length ? metrics.jankCount * 100 / frameMs.length : null;
  metrics.presentedFPSApprox = metrics.meanFrameMs && metrics.meanFrameMs > 0 ? 1000 / metrics.meanFrameMs : null;
  session.nativeFrameTimingValid = frameMs.length > 0;
  writeJSON(sessionPath, session);
  writeJSON(path.join(captureDir, 'frame-metrics.json'), metrics);

  // Runtime/AVD size is configuration inventory, not per-game shutdown work.
  // Keep it out of the critical path; a dedicated inventory action can refresh
  // those values when the runtime actually changes.
  const previousStorage = readJSON(path.join(captureDir, 'storage-bom.json'), {});
  const packageGuestBytes = Object.values(pkg.apkBytes ?? {}).reduce((sum, value) => sum + (Number(value) || 0), 0) || null;
  const storage = {
    observedAt: nowISO(),
    sdkBytes: previousStorage.sdkBytes ?? null,
    avdBytes: previousStorage.avdBytes ?? null,
    packageGuestBytes,
    captureBytes: recursiveSize(captureDir),
    inventoryDeferred: true,
    provisionalCeilingBytes: 35 * 1024 ** 3
  };
  writeJSON(path.join(captureDir, 'storage-bom.json'), storage);

  const manifestSHA256 = finalizeManifest(captureDir);
  const seal = readJSON(path.join(captureDir, 'capture-seal.json'), {});
  writeJSON(path.join(captureDir, 'capture-seal.json'), {
    ...seal,
    finalizedAt: nowISO(),
    finalManifestSHA256: manifestSHA256,
    nativeFrameTimingValid: session.nativeFrameTimingValid
  });

  let normalization = null;
  let normalizationError = null;
  try {
    normalization = normalizePerformanceLab(captureDir, frames, metrics, storage, manifestSHA256);
  } catch (error) {
    normalizationError = {
      observedAt: nowISO(),
      error: error instanceof Error ? error.message : String(error),
      rawCapturePreserved: true,
      rawManifestSHA256: rawManifest.sha256,
      manifestSHA256
    };
    writeJSON(path.join(captureDir, 'normalization-error.json'), normalizationError);
  }
  const controlResult = { sessionId: state.sessionId, rawManifestSHA256: rawManifest.sha256, manifestSHA256, rawCaptureState: 'SEALED', metrics, storage, normalization, normalizationError };
  writeJSON(path.join(captureDir, 'control-result.json'), controlResult);
  const result = { sessionId: state.sessionId, captureDir, ...controlResult };
  try { adb(runtime, ['emu', 'kill'], { allowFailure: true, timeout: 10000 }); } catch {}
  if (state.controlProfile === BASELINE_PROFILE.id || String(state.controlProfile ?? '').startsWith('tftmac_')) {
    try { result.baselineAvdRestore = restoreBaselineAVD(runtime); } catch (error) { result.baselineAvdRestore = { restored: false, error: error instanceof Error ? error.message : String(error) }; }
  }
  try { fs.unlinkSync(CONTROL_STATE); } catch {}
  return result;
}

function numberFromStat(value) {
  const cleaned = String(value ?? '').replace(/[^0-9]/g, '');
  return cleaned ? Number(cleaned) : 0;
}

function parseMeminfo(text) {
  const values = {};
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^([^:]+):\s+(\d+)\s+kB$/);
    if (m) values[m[1]] = Number(m[2]) * 1024;
  }
  return values;
}

function parseSwapUsedBytes(text) {
  const m = text.match(/used\s*=\s*([0-9.]+)([KMGTP])?/i);
  if (!m) return null;
  const scale = { K: 1024, M: 1024 ** 2, G: 1024 ** 3, T: 1024 ** 4, P: 1024 ** 5 }[m[2]?.toUpperCase()] ?? 1;
  return Math.round(Number(m[1]) * scale);
}

function normalizedMemory(vmText, guestMeminfoText, swapUsedBytes, hostMonoNs, utc) {
  const parsed = parseKeyValueLines(vmText);
  const pageSize = Number(vmText.match(/page size of (\d+) bytes/i)?.[1] ?? 16384);
  const pagesFree = numberFromStat(parsed['Pages free']);
  const pagesInactive = numberFromStat(parsed['Pages inactive']);
  const pagesSpeculative = numberFromStat(parsed['Pages speculative']);
  const pagesCompressed = numberFromStat(parsed['Pages occupied by compressor']);
  const available = (pagesFree + pagesInactive + pagesSpeculative) * pageSize;
  const total = os.totalmem();
  const guest = parseMeminfo(guestMeminfoText);
  return {
    utc,
    host_mono_ns: hostMonoNs,
    host_total_bytes: total,
    host_used_bytes: Math.max(0, total - available),
    host_available_bytes: available,
    host_compressed_bytes: pagesCompressed * pageSize,
    host_swap_used_bytes: swapUsedBytes,
    pagein_count: numberFromStat(parsed['Pageins']),
    pageout_count: numberFromStat(parsed['Pageouts']),
    guest_total_bytes: guest.MemTotal ?? null,
    guest_available_bytes: guest.MemAvailable ?? guest.MemFree ?? null,
    vm_stat: parsed
  };
}

async function sampler(captureDir, sessionId) {
  ensureDir(path.join(captureDir, 'surfaceflinger')); ensureDir(path.join(captureDir, 'gfxinfo'));
  const runtime = discover();
  const procFile = path.join(captureDir, 'host-process.csv');
  const procJSONL = path.join(captureDir, 'host-process.jsonl');
  const memFile = path.join(captureDir, 'host-memory.jsonl');
  const memCSV = path.join(captureDir, 'host-memory.csv');
  const clockFile = path.join(captureDir, 'clock-sync.jsonl');
  const eventsFile = path.join(captureDir, 'host-events.jsonl');
  if (!exists(procFile)) fs.writeFileSync(procFile, 'utc,host_mono_ns,pid,ppid,cpu_pct,rss_kb,nice,state,command\n');
  if (!exists(memCSV)) fs.writeFileSync(memCSV, 'utc,host_mono_ns,host_total_bytes,host_used_bytes,host_available_bytes,host_compressed_bytes,host_swap_used_bytes,pagein_count,pageout_count,guest_total_bytes,guest_available_bytes\n');
  let stopped = false;
  let logcatProc = null;
  let lastSwapUsedBytes = null;
  process.on('SIGTERM', () => { stopped = true; });
  process.on('SIGINT', () => { stopped = true; });
  let tick = 0;
  while (!stopped) {
    const utc = nowISO();
    const hostMonoNs = monoNs().toString();
    const ps = command('/bin/ps', ['-axo', 'pid=,ppid=,%cpu=,rss=,nice=,state=,comm='], { allowFailure: true, timeout: 10000 }).stdout;
    for (const line of ps.split(/\r?\n/)) {
      if (!/emulator|qemu|TFTMAC|tftmac/i.test(line)) continue;
      const m = line.trim().match(/^(\d+)\s+(\d+)\s+([\d.]+)\s+(\d+)\s+(-?\d+)\s+(\S+)\s+(.+)$/);
      if (!m) continue;
      const sample = { utc, host_mono_ns: hostMonoNs, pid: Number(m[1]), ppid: Number(m[2]), cpu_pct: Number(m[3]), rss_kb: Number(m[4]), nice: Number(m[5]), state: m[6], command: m[7] };
      fs.appendFileSync(procFile, [sample.utc, sample.host_mono_ns, sample.pid, sample.ppid, sample.cpu_pct, sample.rss_kb, sample.nice, sample.state, sample.command].map(csvEscape).join(',') + '\n');
      appendJSONL(procJSONL, sample);
    }
    const vm = command('/usr/bin/vm_stat', [], { allowFailure: true, timeout: 10000 }).stdout;
    if (tick % 5 === 0) {
      const swap = command('/usr/sbin/sysctl', ['vm.swapusage'], { allowFailure: true, timeout: 10000 }).stdout;
      lastSwapUsedBytes = parseSwapUsedBytes(swap);
    }
    const readyNow = deviceReady(runtime);
    const guestMem = readyNow ? adb(runtime, ['shell', 'cat', '/proc/meminfo'], { allowFailure: true, timeout: 10000 }).stdout : '';
    const memory = normalizedMemory(vm, guestMem, lastSwapUsedBytes, hostMonoNs, utc);
    appendJSONL(memFile, memory);
    fs.appendFileSync(memCSV, [memory.utc, memory.host_mono_ns, memory.host_total_bytes, memory.host_used_bytes, memory.host_available_bytes, memory.host_compressed_bytes, memory.host_swap_used_bytes, memory.pagein_count, memory.pageout_count, memory.guest_total_bytes, memory.guest_available_bytes].map(csvEscape).join(',') + '\n');
    if (readyNow) {
      if (!logcatProc || logcatProc.exitCode !== null) {
        const fd = fs.openSync(path.join(captureDir, 'logcat.raw.txt'), 'a');
        const err = fs.openSync(path.join(captureDir, 'logcat.stderr.log'), 'a');
        logcatProc = spawn(runtime.adb, ['-P', ADB_PORT, '-s', SERIAL, 'logcat', '-v', 'threadtime'], { env: runtime.env, stdio: ['ignore', fd, err] });
        appendJSONL(eventsFile, { utc: nowISO(), event: 'LOGCAT_STARTED', pid: logcatProc.pid });
      }
      if (tick % 5 === 0) {
        try {
          const sfCounters = surfaceFlingerCounters(runtime);
          appendJSONL(path.join(captureDir, 'surfaceflinger', 'counters.jsonl'), {
            utc,
            host_mono_ns: hostMonoNs,
            renderRateHz: sfCounters.renderRateHz,
            totalMissedFrames: sfCounters.totalMissedFrames,
            gpuMissedFrames: sfCounters.gpuMissedFrames,
            hwcMissedFrames: sfCounters.hwcMissedFrames,
            gameRequested60Hz: sfCounters.gameRequested60Hz
          });
        } catch {}
      }
      if (tick % 7 === 0) {
        const t0 = monoNs();
        const uptime = adb(runtime, ['shell', 'cat', '/proc/uptime'], { allowFailure: true, timeout: 10000 }).stdout.trim();
        const t1 = monoNs();
        const seconds = Number(uptime.split(/\s+/)[0]);
        if (Number.isFinite(seconds)) {
          const guest = BigInt(Math.round(seconds * 1e9));
          const midpoint = (t0 + t1) / 2n;
          appendJSONL(clockFile, { utc: nowISO(), host_t0_ns: t0.toString(), guest_mono_ns: guest.toString(), host_t1_ns: t1.toString(), host_midpoint_ns: midpoint.toString(), rtt_ns: (t1 - t0).toString(), estimated_offset_ns: (midpoint - guest).toString(), source: '/proc/uptime' });
        }
      }
      if (tick % 3 === 0) {
        const gfx = adb(runtime, ['shell', 'dumpsys', 'gfxinfo', PACKAGE, 'framestats'], { allowFailure: true, timeout: 15000 }).stdout;
        fs.appendFileSync(path.join(captureDir, 'gfxinfo', 'framestats.raw.txt'), `\n# ${utc}\n${gfx}\n`);
      }
    }
    tick += 1;
    await sleep(2000);
  }
  if (logcatProc && logcatProc.exitCode === null) { try { logcatProc.kill('SIGTERM'); } catch {} }
  appendJSONL(eventsFile, { utc: nowISO(), event: 'SAMPLER_STOPPED', sessionId });
}

function buildApp() {
  const shellBuilder = path.join(repoRoot, 'scripts', 'build-tftmac-app.command');
  if (exists(shellBuilder)) {
    const built = command('/bin/zsh', [shellBuilder], { timeout: 300000, maxBuffer: 32 * 1024 * 1024 });
    const app = path.join(repoRoot, 'dist', 'TFTMAC.app');
    const installed = '/Applications/TFTMAC.app';
    const binary = path.join(app, 'Contents', 'MacOS', 'TFTMAC');
    if (!executable(binary)) throw new Error(`TFTMAC fullscreen shell build did not produce ${binary}`);
    return {
      action: 'TFTMAC_FULLSCREEN_SHELL_BUILT',
      app,
      installed: exists(installed) ? installed : null,
      binary,
      binarySHA256: sha256File(binary),
      icon: path.join(app, 'Contents', 'Resources', 'TFTMAC.icns'),
      buildOutput: built.stdout.trim()
    };
  }
  const sourcesDir = path.join(repoRoot, 'tftmac', 'Sources');
  const sources = fs.readdirSync(sourcesDir).filter(n => n.endsWith('.swift')).map(n => path.join(sourcesDir, n));
  const dist = path.join(repoRoot, 'dist');
  const app = path.join(dist, 'TFTMAC.app');
  const contents = path.join(app, 'Contents');
  const macos = path.join(contents, 'MacOS');
  ensureDir(macos); ensureDir(path.join(contents, 'Resources'));
  fs.rmSync(app, { recursive: true, force: true });
  ensureDir(macos); ensureDir(path.join(contents, 'Resources'));
  const binary = path.join(macos, 'TFTMAC');
  const developerCandidates = [
    '/Applications/Xcode-26.6.0.app/Contents/Developer',
    path.join(USER_HOME, 'Downloads', 'Xcode.app', 'Contents', 'Developer')
  ];
  const developerDir = developerCandidates.find(candidate => exists(path.join(candidate, 'usr', 'bin', 'xcodebuild')) || exists(path.join(candidate, 'Toolchains', 'XcodeDefault.xctoolchain', 'usr', 'bin', 'swiftc')));
  if (!developerDir) throw new Error('Xcode 26.6 / 17F113 developer directory was not found.');
  const xcodeEnv = { ...process.env, DEVELOPER_DIR: developerDir };
  const version = command('/usr/bin/xcodebuild', ['-version'], { env: xcodeEnv }).stdout.trim();
  if (!/Xcode 26\.6\b/.test(version) || !/Build version 17F113\b/.test(version)) throw new Error(`Wrong Xcode selected for control build: ${version}`);
  const swiftc = command('/usr/bin/xcrun', ['--find', 'swiftc'], { env: xcodeEnv }).stdout.trim();
  const sdkPath = command('/usr/bin/xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { env: xcodeEnv }).stdout.trim();
  command(swiftc, ['-O', '-parse-as-library', '-target', 'arm64-apple-macosx14.0', '-sdk', sdkPath, ...sources, '-o', binary], { timeout: 240000, env: xcodeEnv });
  fs.copyFileSync(path.join(repoRoot, 'tftmac', 'Info.plist'), path.join(contents, 'Info.plist'));
  fs.copyFileSync(scriptPath, path.join(contents, 'Resources', 'tftmac-direct-control.mjs'));
  const labSource = path.join(repoRoot, 'ssot', 'TFTMAC_PERFORMANCE_LAB.sql');
  if (exists(labSource)) fs.copyFileSync(labSource, path.join(contents, 'Resources', 'TFTMAC_PERFORMANCE_LAB.sql'));
  fs.writeFileSync(path.join(contents, 'Resources', 'build-commit.txt'), `${currentGitSha()}\n`);
  command('/usr/bin/codesign', ['--force', '--sign', '-', '--timestamp=none', app], { timeout: 120000 });
  command('/usr/bin/codesign', ['--verify', '--deep', '--strict', '--verbose=2', app], { timeout: 120000 });
  return { app, binary, binarySHA256: sha256File(binary), infoPlistSHA256: sha256File(path.join(contents, 'Info.plist')) };
}

function runtimeProcessAudit() {
  const ps = command('/bin/ps', ['axo', 'pid=,ppid=,etime=,command='], { allowFailure: true, timeout: 10000, maxBuffer: 16 * 1024 * 1024 });
  const lines = ps.stdout.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  const relevant = lines.filter(line => /(TFTMAC|TFT_Ultra_Tablet|TFTMAC_Live_API36|qemu-system-aarch64|\/emulator(?:\s|$)|adb.*fork-server|tftmac-direct-control\.mjs\s+sampler)/i.test(line));
  const classified = relevant.map(line => {
    const match = line.match(/^(\d+)\s+(\d+)\s+(\S+)\s+(.+)$/);
    const pid = match ? Number(match[1]) : null;
    const ppid = match ? Number(match[2]) : null;
    const elapsed = match?.[3] ?? null;
    const commandLine = match?.[4] ?? line;
    let kind = 'OTHER_RELEVANT';
    if (/tftmac-direct-control\.mjs\s+sampler/i.test(commandLine)) kind = 'TFTMAC_SAMPLER';
    else if (/TFTMAC\.app\/Contents\/MacOS\/TFTMAC/i.test(commandLine)) kind = 'TFTMAC_APP';
    else if (/qemu-system-aarch64|\/emulator(?:\s|$)/i.test(commandLine)) kind = 'ANDROID_EMULATOR';
    else if (/adb.*fork-server/i.test(commandLine)) kind = 'ADB_SERVER';
    return { pid, ppid, elapsed, kind, command: commandLine };
  });
  const lsof = command('/usr/sbin/lsof', ['-nP', '-iTCP:5038', '-iTCP:5040', '-iTCP:5582', '-iTCP:5592'], { allowFailure: true, timeout: 10000, maxBuffer: 8 * 1024 * 1024 });
  const portLines = lsof.stdout.split(/\r?\n/).filter(Boolean);
  const adb5040 = portLines.some(line => /:5040\s+\(LISTEN\)/.test(line)) ? 'LISTENER_PRESENT' : 'NO_LISTENER';
  return {
    observedAt: nowISO(),
    processCount: classified.length,
    processes: classified,
    ports: portLines,
    adb5040,
    controlState: readJSON(CONTROL_STATE),
    duplicateRisk: {
      tftmacApps: classified.filter(item => item.kind === 'TFTMAC_APP').length,
      emulators: classified.filter(item => item.kind === 'ANDROID_EMULATOR').length,
      samplers: classified.filter(item => item.kind === 'TFTMAC_SAMPLER').length,
      adbServers: classified.filter(item => item.kind === 'ADB_SERVER').length
    }
  };
}

function cleanupTftmacAdbResidue() {
  const auditBefore = runtimeProcessAudit();
  const tftmacAdb = auditBefore.processes.filter(item => item.kind === 'ADB_SERVER' && /tcp:5040\b/.test(item.command));
  if (!tftmacAdb.length) return { action: 'TFTMAC_ADB_RESIDUE_ABSENT', auditBefore, auditAfter: auditBefore };
  for (const item of tftmacAdb) {
    try { process.kill(item.pid, 'SIGTERM'); } catch {}
  }
  const deadline = Date.now() + 1000;
  while (Date.now() < deadline && tftmacAdb.some(item => processAlive(item.pid))) {
    const until = Date.now() + 50;
    while (Date.now() < until) {}
  }
  for (const item of tftmacAdb) {
    if (processAlive(item.pid)) {
      try { process.kill(item.pid, 'SIGKILL'); } catch {}
    }
  }
  const auditAfter = runtimeProcessAudit();
  if (auditAfter.processes.some(item => item.kind === 'ADB_SERVER' && /tcp:5040\b/.test(item.command))) {
    throw new Error('TFTMAC_ADB_RESIDUE_CLEANUP_FAILED: private ADB listener remains on port 5040');
  }
  return { action: 'TFTMAC_ADB_RESIDUE_CLEANED', killedPids: tftmacAdb.map(item => item.pid), auditBefore, auditAfter };
}

function singleRuntimePreflight() {
  const audit = runtimeProcessAudit();
  const tftmacApps = audit.processes.filter(item => item.kind === 'TFTMAC_APP');
  const blockers = audit.processes.filter(item => ['ANDROID_EMULATOR', 'TFTMAC_SAMPLER', 'ADB_SERVER'].includes(item.kind));
  if (tftmacApps.length > 1) blockers.push(...tftmacApps.slice(1));
  if (blockers.length || audit.ports.length) {
    throw new Error(`SINGLE_RUNTIME_PREFLIGHT_BLOCKED: ${JSON.stringify({ blockers, ports: audit.ports, adb5040: audit.adb5040, tftmacLauncherCount: tftmacApps.length })}`);
  }
  return { pass: true, observedAt: audit.observedAt, tftmacLauncherCount: tftmacApps.length, audit };
}

function openPlayWeb() {
  const url = `https://play.google.com/store/apps/details?id=${PACKAGE}`;
  const result = command('/usr/bin/open', [url], { allowFailure: true, timeout: 30000 });
  return { action: 'PLAY_WEB_OPENED', url, openStatus: result.status, stderr: result.stderr.trim() || null };
}

function installApp() {
  const source = path.join(repoRoot, 'dist', 'TFTMAC.app');
  const destination = '/Applications/TFTMAC.app';
  if (!exists(source)) throw new Error('TFTMAC.app has not been built. Run build first.');
  fs.rmSync(destination, { recursive: true, force: true });
  command('/usr/bin/ditto', [source, destination], { timeout: 120000 });
  command('/usr/bin/codesign', ['--verify', '--deep', '--strict', '--verbose=2', destination], { timeout: 120000 });
  return { action: 'TFTMAC_INSTALLED', source, destination, icon: path.join(destination, 'Contents', 'Resources', 'TFTMAC.icns') };
}

function launchApp() {
  const installed = '/Applications/TFTMAC.app';
  const built = path.join(repoRoot, 'dist', 'TFTMAC.app');
  const app = exists(installed) ? installed : built;
  if (!exists(app)) throw new Error('TFTMAC.app has not been built. Run build first.');
  const result = command('/usr/bin/open', ['-n', app], { allowFailure: true, timeout: 30000 });
  return { app, openStatus: result.status, stderr: result.stderr.trim() || null };
}

async function main() {
  const [action, ...args] = process.argv.slice(2);
  if (action === 'inventory') {
    const r = discover();
    const avdConfig = r.avdConfig ? parseKeyValueLines(r.avdConfig) : null;
    json({ externalVolumeMounted: exists('/Volumes/MAC MINI M4'), externalRoot: r.externalRoot, appSupportRuntime: r.appSupportRuntime, sdkRoot: r.sdkRoot, emulatorVersion: r.emulatorVersion, adbVersion: r.adbVersion, requiredImagePresent: r.requiredImagePresent, requiredImagePath: r.requiredImagePath, avdName: AVD_NAME, avdIni: r.avdIni, avdHome: r.avdHome, avdDir: r.avdDir, avdConfig: avdConfig ? { imageSysdir: avdConfig['image.sysdir.1'] ?? null, cpuArch: avdConfig['hw.cpu.arch'] ?? null, ramSize: avdConfig['hw.ramSize'] ?? null, lcdWidth: avdConfig['hw.lcd.width'] ?? null, lcdHeight: avdConfig['hw.lcd.height'] ?? null, lcdDensity: avdConfig['hw.lcd.density'] ?? null, gpuEnabled: avdConfig['hw.gpu.enabled'] ?? null, gpuMode: avdConfig['hw.gpu.mode'] ?? null, playStoreEnabled: avdConfig['PlayStore.enabled'] ?? null } : null, sdkRoots: r.sdkRoots, avdIniCandidates: r.avdIniCandidates });
    return;
  }
  if (action === 'prepare') { json(prepareAVD()); return; }
  if (action === 'engineering-map-selftest') { json(engineeringMapSelfTest()); return; }
  if (action === 'lab-selftest') { json(labSelfTest()); return; }
  if (action === 'native-gate1-bootstrap') { json(bootstrapNativeGate1Authority()); return; }
  if (action === 'native-gate1-build') { json(nativeGate1Script('build-native-app.command', 'NATIVE_GATE1_BUILD')); return; }
  if (action === 'native-gate1-test') { json(nativeGate1Script('test-native-app.command', 'NATIVE_GATE1_TEST')); return; }
  if (action === 'build') { json(buildApp()); return; }
  if (action === 'install-app') { json(installApp()); return; }
  if (action === 'launch-app') { json(launchApp()); return; }
  if (action === 'open-play-web') { json(openPlayWeb()); return; }
  if (action === 'runtime-process-audit') { json(runtimeProcessAudit()); return; }
  if (action === 'cleanup-tftmac-adb-residue') { json(cleanupTftmacAdbResidue()); return; }
  if (action === 'single-runtime-preflight') { json(singleRuntimePreflight()); return; }
  if (action === 'start') { json(await startControl()); return; }
  if (action === 'start-baseline-control') { json(await startBaselineControl()); return; }
  if (action === 'start-baseline-control-5gb') { json(await startBaselineControl(5120, 'tftmac_5gb_baseline_v1', 800)); return; }
  if (action === 'start-native-controller-probe') { json(await startBaselineControl(5120, 'tftmac_5gb_baseline_v1', 800, true)); return; }
  if (action === 'start-baseline-control-5gb-flush400') { json(await startBaselineControl(5120, 'tftmac_5gb_flush400_exp_v1', 400)); return; }
  if (action === 'play-action') { json(await playAction()); return; }
  if (action === 'play-probe') { json(await playProbe()); return; }
  if (action === 'launch-game') { json(await launchGame()); return; }
  if (action === 'restart-game') { json(await restartGame()); return; }
  if (action === 'gles-capability-probe') { json(glesCapabilityProbe()); return; }
  if (action === 'launch-failure-probe') { json(launchFailureProbe()); return; }
  if (action === 'recover-anr-wait') { json(await recoverAnrWait()); return; }
  if (action === 'logger-health') { json(await loggerHealth()); return; }
  if (action === 'preplay-optimize') { json(await preplayOptimize()); return; }
  if (action === 'restart-effect-analysis') { json(analyzeRestartEffect()); return; }
  if (action === 'analyze-session') { json(analyzeContinuousRun()); return; }
  if (action === 'ingest-analysis') { json(ingestContinuousRunIntoLab()); return; }
  if (action === 'trace-capabilities') { json(traceCapabilities()); return; }
  if (action === 'analyze-latest-closed-run-fast') { json(await analyzeLatestClosedRunFast()); return; }
  if (action === 'latest-closed-run-fast-result') { json(latestClosedRunFastResult()); return; }
  if (action === 'export-latest-closed-run-fast-result') {
    const outputPath = path.join(repoRoot, '.tftmac-latest-run-analysis.json');
    try {
      const result = latestClosedRunFastResult();
      writeJSON(outputPath, result);
      json({ action: 'LATEST_CLOSED_RUN_FAST_RESULT_EXPORTED', outputPath, sessionId: result.sessionId });
    } catch (error) {
      writeJSON(outputPath, { error: error instanceof Error ? error.message : String(error), observedAt: nowISO() });
      json({ action: 'LATEST_CLOSED_RUN_FAST_RESULT_EXPORT_FAILED', outputPath });
    }
    return;
  }
  if (action === 'export-latest-closed-session-state') {
    const outputPath = path.join(repoRoot, '.tftmac-latest-closed-session.json');
    const candidates = fs.readdirSync(CAPTURE_ROOT, { withFileTypes: true })
      .filter(entry => entry.isDirectory())
      .map(entry => {
        const dir = path.join(CAPTURE_ROOT, entry.name);
        return { id: entry.name, dir, session: readJSON(path.join(dir, 'session.json'), null) };
      })
      .filter(row => row.session?.endedUTC)
      .sort((a, b) => a.id.localeCompare(b.id));
    const target = candidates.at(-1);
    if (!target) {
      writeJSON(outputPath, { error: 'NO_CLOSED_SESSION', observedAt: nowISO() });
    } else {
      writeJSON(outputPath, {
        observedAt: nowISO(),
        sessionId: target.id,
        captureDir: target.dir,
        session: target.session,
        seal: readJSON(path.join(target.dir, 'capture-seal.json'), null),
        controlResult: readJSON(path.join(target.dir, 'control-result.json'), null),
        hasFastAnalysis: exists(path.join(target.dir, 'closed-run-fast-analysis.json')),
        hasTrendAnalysis: exists(path.join(target.dir, 'run-trend-analysis.json')),
        hasContinuousAnalysis: exists(path.join(target.dir, 'continuous-run-analysis.json'))
      });
    }
    json({ action: 'LATEST_CLOSED_SESSION_STATE_EXPORTED', outputPath });
    return;
  }
  if (action === 'analyze-latest-closed-run-trends') { json(analyzeLatestClosedRunTrends()); return; }
  if (action === 'compare-latest-runs') { json(compareLatestRuns()); return; }
  if (action === 'screen-state-probe') { json(screenStateProbe()); return; }
  if (action === 'reveal-lock-screen') { json(revealLockScreen()); return; }
  if (action === 'wake-guest-screen') { json(wakeGuestScreenAction()); return; }
  if (action === 'audio-health') { json(audioHealthCheck()); return; }
  if (action === 'emulator-scale-probe') { json(emulatorScaleProbe()); return; }
  if (action === 'audio-backend-probe') { json(audioBackendProbe()); return; }
  if (action === 'disconnect-window-audit') { json(disconnectWindowAudit()); return; }
  if (action === 'runtime-fault-audit') { json(runtimeFaultAudit()); return; }
  if (action === 'graphics-pipeline-audit') { json(graphicsPipelineAudit()); return; }
  if (action === 'native-trace-smoke') { json(await captureNativeTrace(5, 'smoke')); return; }
  if (action === 'native-trace-combat') { json(await captureNativeTrace(20, 'combat')); return; }
  if (action === 'presentation-probe') { json(presentationProbe()); return; }
  if (action === 'window-inventory') { json(emulatorWindowInventory()); return; }
  if (action === 'fit-window') { json(fitEmulatorWindow()); return; }
  if (action === 'android-control') { json(androidControl(args[0])); return; }
  if (action === 'status') { json(await status()); return; }
  if (action === 'play-certification') { json(await playCertification()); return; }
  if (action === 'play-diagnose') { json(await playDiagnose()); return; }
  if (action === 'auth-brief') { json(await authBrief()); return; }
  if (action === 'install-diagnose') { json(await installDiagnose()); return; }
  if (action === 'play-install-brief') { json(await playInstallBrief()); return; }
  if (action === 'play-store-repair') { json(await playStoreRepair()); return; }
  if (action === 'google-account-ui') { json(await googleAccountUI()); return; }
  if (action === 'image-check') { json(imageCheck()); return; }
  if (action === 'device-profiles') { json(deviceProfiles()); return; }
  if (action === 'image-upgrade-start') { json(imageUpgradeStart()); return; }
  if (action === 'image-upgrade-status') { json(imageUpgradeStatus()); return; }
  if (action === 'image-upgrade-worker') { json(await imageUpgradeWorker()); return; }
  if (action === 'marker') { json(marker('stutter')); return; }
  if (action === 'game-settings') { json(gameSettings(args[0], args[1], args[2])); return; }
  if (action === 'quality-report') { json(qualityReport(args[0], args[1])); return; }
  if (action === 'match-boundary-probe') { json(matchBoundaryProbe()); return; }
  if (action === 'analyze-approx-match') { json(analyzeApproximateLatestMatch()); return; }
  if (action === 'ingest-approx-match') { json(ingestApproximateLatestMatch()); return; }
  if (action === 'match-entry') { json(marker('match-entry')); return; }
  if (action === 'combat-start') { json(marker('combat-start')); return; }
  if (action === 'first-place') { json(marker('first-place')); return; }
  if (/^placement-[1-8]$/.test(action)) { json(marker(action)); return; }
  if (action === 'stop') { json(await stopControl()); return; }
  if (action === 'package-state') { const r = discover(); json(packageState(r)); return; }
  if (action === 'package-launch-probe') { json(packageLaunchProbe()); return; }
  if (action === 'sampler') {
    const captureIndex = args.indexOf('--capture');
    const sessionIndex = args.indexOf('--session');
    if (captureIndex < 0 || sessionIndex < 0) throw new Error('sampler requires --capture and --session');
    await sampler(args[captureIndex + 1], args[sessionIndex + 1]);
    return;
  }
  throw new Error('Usage: tftmac-direct-control.mjs inventory|prepare|lab-selftest|build|launch-app|runtime-process-audit|single-runtime-preflight|start|start-baseline-control|play-action|launch-game|gles-capability-probe|launch-failure-probe|status|play-certification|marker|match-entry|combat-start|stop|package-state');
}

main().catch(error => { process.stderr.write(`${error.stack || error.message}\n`); process.exit(1); });
