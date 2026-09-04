#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const buildRoot = '/Volumes/MAC MINI M4/TFTMAC/Build';
const reclaimRoot = '/Volumes/MAC MINI M4/TFTMAC/Build.reclaiming';
const runtimeRoot = '/Volumes/MAC MINI M4/TFTMAC/Runtime';
const receipt = path.resolve('ssot/storage-reclamation.json');
const sourceAuthority = path.resolve('Vendor/AndroidEmulator/SOURCE.json');

function run(exe, args, options = {}) {
  return spawnSync(exe, args, { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, ...options });
}
function allocatedBytes(root) {
  if (!fs.existsSync(root)) return 0;
  const result = run('/usr/bin/du', ['-sk', root]);
  if (result.status !== 0) throw new Error(`du failed for ${root}: ${result.stderr || result.stdout}`);
  const kib = Number(String(result.stdout).trim().split(/\s+/)[0]);
  if (!Number.isFinite(kib)) throw new Error(`Could not parse du output for ${root}`);
  return kib * 1024;
}
function sha256(file) {
  const h = crypto.createHash('sha256');
  h.update(fs.readFileSync(file));
  return h.digest('hex');
}
function fail(message) { throw new Error(message); }
function df() {
  const result = run('/bin/df', ['-kP', '/Volumes/MAC MINI M4']);
  if (result.status !== 0) fail(`df failed: ${result.stderr || result.stdout}`);
  return result.stdout.trim();
}

if (!fs.existsSync('/Volumes/MAC MINI M4')) fail('External volume is not mounted.');
if (!fs.existsSync(runtimeRoot)) fail('Authoritative TFTMAC Runtime root is missing.');
if (!path.resolve(buildRoot).startsWith('/Volumes/MAC MINI M4/TFTMAC/')) fail('Unsafe Build path.');
if (path.resolve(buildRoot) === path.resolve(runtimeRoot)) fail('Build and Runtime roots collide.');

const ps = run('/bin/ps', ['-axo', 'pid=,command=']);
if (ps.status !== 0) fail('Could not inspect process table.');
const liveBuildUsers = ps.stdout.split(/\r?\n/).filter(line => line.includes(buildRoot) || line.includes(reclaimRoot));
if (liveBuildUsers.length) fail(`Build tree is not quiescent: ${liveBuildUsers.join(' | ')}`);

const existingReceipt = fs.existsSync(receipt) ? JSON.parse(fs.readFileSync(receipt, 'utf8')) : null;
const dfBefore = existingReceipt?.dfBefore ?? df();
const runtimeBytesBefore = existingReceipt?.runtimeBytesBefore ?? allocatedBytes(runtimeRoot);
const buildBytesBefore = existingReceipt?.buildBytesBefore ?? allocatedBytes(fs.existsSync(buildRoot) ? buildRoot : reclaimRoot);

if (fs.existsSync(buildRoot) && fs.existsSync(reclaimRoot)) fail('Both Build and Build.reclaiming exist; refusing ambiguous deletion.');
if (fs.existsSync(buildRoot)) fs.renameSync(buildRoot, reclaimRoot);

const staged = {
  schema: 1,
  observedAt: existingReceipt?.observedAt ?? new Date().toISOString(),
  buildRoot,
  reclaimRoot,
  runtimeRoot,
  quiescence: { liveBuildUsers: [] },
  buildBytesBefore,
  runtimeBytesBefore,
  dfBefore,
  state: fs.existsSync(reclaimRoot) ? 'RECLAIMING' : 'ALREADY_ABSENT'
};
fs.writeFileSync(receipt, `${JSON.stringify(staged, null, 2)}\n`);

if (fs.existsSync(reclaimRoot)) fs.rmSync(reclaimRoot, { recursive: true, force: false, maxRetries: 3, retryDelay: 250 });
if (fs.existsSync(buildRoot) || fs.existsSync(reclaimRoot)) fail('Build reclamation is incomplete.');

const authority = JSON.parse(fs.readFileSync(sourceAuthority, 'utf8'));
const sdkRoot = path.join(runtimeRoot, 'sdk');
const emulator = path.join(sdkRoot, 'emulator', 'emulator');
const adb = path.join(sdkRoot, 'platform-tools', 'adb');
const installedProto = path.join(sdkRoot, 'emulator', 'lib', 'emulator_controller.proto');
const avdIni = path.join(runtimeRoot, 'avd', 'TFT_Ultra_Tablet.ini');
for (const required of [emulator, adb, installedProto, avdIni]) {
  if (!fs.existsSync(required)) fail(`Authoritative Runtime component missing after reclamation: ${required}`);
}
const installedProtoSHA256 = sha256(installedProto);
if (installedProtoSHA256 !== authority.installedProtoSHA256 || installedProtoSHA256 !== authority.vendoredProtoSHA256) {
  fail(`Runtime protocol authority changed: ${installedProtoSHA256}`);
}

const runtimeBytesAfter = allocatedBytes(runtimeRoot);
const output = {
  ...staged,
  completedAt: new Date().toISOString(),
  buildBytesAfter: 0,
  reclaimedBytes: buildBytesBefore,
  runtimeBytesAfter,
  runtimeAllocatedByteDelta: runtimeBytesAfter - runtimeBytesBefore,
  runtimeIntegrity: {
    emulatorPresent: true,
    adbPresent: true,
    avdPresent: true,
    installedProtoSHA256,
    frozenProtoMatch: true
  },
  dfAfter: df(),
  state: 'COMPLETE',
  result: 'PASS'
};
fs.writeFileSync(receipt, `${JSON.stringify(output, null, 2)}\n`);
process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
