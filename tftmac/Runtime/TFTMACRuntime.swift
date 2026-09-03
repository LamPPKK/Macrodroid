import AppKit
import CryptoKit
import Darwin
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import Metal
import SQLite3
import SwiftProtobuf

struct TFTMACRuntimePaths: Sendable {
    let sdkRoot: URL
    let emulator: URL
    let adb: URL
    let avdHome: URL
    let avdDirectory: URL
    let avdConfig: URL
    let hostApplication: URL
    let applicationSupport: URL

    static func discover() throws -> Self {
        let manager = FileManager.default
        let runtimeRoot = URL(fileURLWithPath: "/Volumes/MAC MINI M4/TFTMAC/Runtime", isDirectory: true)
        let sdkCandidates = ["SDK", "sdk"].map { runtimeRoot.appendingPathComponent($0, isDirectory: true) }
        guard let sdkRoot = sdkCandidates.first(where: {
            manager.isExecutableFile(atPath: $0.appendingPathComponent("emulator/emulator").path)
                && manager.isExecutableFile(atPath: $0.appendingPathComponent("platform-tools/adb").path)
        }) else {
            throw TFTMACRuntimeError("The proven Android runtime is not mounted at /Volumes/MAC MINI M4/TFTMAC/Runtime.")
        }

        let avdCandidates = ["AVD", "avd"].map { runtimeRoot.appendingPathComponent($0, isDirectory: true) }
        guard let avdHome = avdCandidates.first(where: {
            manager.fileExists(atPath: $0.appendingPathComponent("TFT_Ultra_Tablet.ini").path)
        }) else {
            throw TFTMACRuntimeError("The TFT_Ultra_Tablet AVD is missing from the proven runtime.")
        }
        let avdINI = avdHome.appendingPathComponent("TFT_Ultra_Tablet.ini")
        let iniText = try String(contentsOf: avdINI, encoding: .utf8)
        guard let avdPath = iniText.split(whereSeparator: \.isNewline)
            .first(where: { $0.hasPrefix("path=") })?
            .dropFirst("path=".count), !avdPath.isEmpty else {
            throw TFTMACRuntimeError("TFT_Ultra_Tablet.ini does not identify its AVD directory.")
        }
        let avdDirectory = URL(fileURLWithPath: String(avdPath), isDirectory: true)
        let avdConfig = avdDirectory.appendingPathComponent("config.ini")
        guard manager.fileExists(atPath: avdConfig.path) else {
            throw TFTMACRuntimeError("The TFT_Ultra_Tablet config.ini is missing.")
        }

        guard let resourceURL = Bundle.main.resourceURL else {
            throw TFTMACRuntimeError("TFTMAC.app has no Resources directory.")
        }
        let hostApplication = resourceURL.appendingPathComponent("TFTMAC Emulator Host.app", isDirectory: true)
        guard manager.fileExists(atPath: hostApplication.path) else {
            throw TFTMACRuntimeError("TFTMAC Emulator Host.app is missing from the application bundle.")
        }
        let applicationSupport = manager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TFTMAC", isDirectory: true)
        return Self(
            sdkRoot: sdkRoot,
            emulator: sdkRoot.appendingPathComponent("emulator/emulator"),
            adb: sdkRoot.appendingPathComponent("platform-tools/adb"),
            avdHome: avdHome,
            avdDirectory: avdDirectory,
            avdConfig: avdConfig,
            hostApplication: hostApplication,
            applicationSupport: applicationSupport
        )
    }
}

struct EmulatorControllerDiscovery: Sendable {
    let processIdentifier: Int32
    let port: Int
    let token: String
    let recordPath: String
}

struct MouseInput: Sendable {
    let x: Int32
    let y: Int32
    let buttons: Int32
}

struct KeyboardInput: Sendable {
    let text: String?
    let key: String?
}

private enum EmulatorInput: Sendable {
    case touch(TouchInput)
    case mouse(MouseInput)
    case keyboard(KeyboardInput)
}

struct PresentationSample: Sendable {
    let presentedFrames: UInt64
    let presentationFPS: Double
    let sourceFPS: Double
    let mailbox: FrameMailboxSnapshot
    let lastPresentedSequence: UInt32?
    let sampledMonotonicNanoseconds: UInt64
}

private struct FrameVisualSample: Sendable {
    let sampleCount: Int
    let meanLuma: Double
    let nonBlackFraction: Double
    let minimumRGB: Int
    let maximumRGB: Int
    let minimumAlpha: Int
    let maximumAlpha: Int
    let contentSHA256: String?
}

private struct FrameIntervalWindow: Sendable {
    let startedMonotonicNS: UInt64
    let endedMonotonicNS: UInt64
    let frameCount: Int
    let sequenceDropCount: UInt64
    let meanIntervalMS: Double?
    let p95IntervalMS: Double?
    let maximumIntervalMS: Double?
}

private struct GuestMemorySample: Sendable {
    let totalKiB: Int64
    let availableKiB: Int64
    let swapTotalKiB: Int64?
    let swapFreeKiB: Int64?
}

private struct HostResourceSample: Sendable {
    let availableKiB: Int64?
    let compressedKiB: Int64?
    let swapUsedKiB: Int64?
    let pageouts: Int64?
    let thermalState: String
    let powerSource: String
}

private struct SurfaceFlingerSample: Sendable {
    let renderRateHz: Double?
    let totalMissedFrames: Int64?
    let hwcMissedFrames: Int64?
    let gpuMissedFrames: Int64?
    let tftRequestedRateHz: Double?
}

private struct AudioFlingerSample: Sendable {
    let activeOutput: Bool
    let sampleRateHz: Int?
    let stereoOutput: Bool
    let activeTracks: Int?
    let partialUnderruns: Int64?
    let emptyUnderruns: Int64?
}

private struct LogcatAggregate: Sendable {
    let byteStart: UInt64
    let byteEnd: UInt64
    let skippedBytes: UInt64
    let lineCount: Int
    let anrCount: Int
    let inputTimeoutCount: Int
    let fatalCount: Int
    let memoryKillCount: Int
    let choreographerSkipCount: Int
    let angleWarningCount: Int
    let vulkanWarningCount: Int
    let audioErrorCount: Int
}

private struct PipelineLogAggregate: Sendable {
    let sourceStream: String
    let byteStart: UInt64
    let byteEnd: UInt64
    let skippedBytes: UInt64
    let lineCount: Int
    let signals: PipelineLogSignals
}

private struct GraphicsPipelineSnapshot: Sendable {
    static let requiredReceiptKeys: Set<String> = [
        "tft_package_version", "tft_surface", "unreal_engine", "game_graphics_api", "angle",
        "gfxstream", "moltenvk", "host_vulkan_device", "metal_device",
        "native_presenter", "configuration_sha256"
    ]

    let label: String
    let gamePID: Int32?
    let exactLayerName: String?
    let tftSurfaceState: String
    let gameGraphicsAPI: String
    let gameGraphicsAPIConfidence: String
    let angleState: String
    let gfxstreamState: String
    let moltenVKState: String
    let emulatorVersion: String?
    let emulatorBuildID: String?
    let emulatorGPUSelection: String?
    let gfxstreamFeatureReceipt: String?
    let gfxstreamTracingState: String
    let moltenVKVersion: String?
    let moltenVKConfiguration: String
    let hostVulkanDevice: String?
    let vulkanComposition: Bool?
    let nativeSwapchain: Bool?
    let guestEGLImplementation: String?
    let guestVulkanImplementation: String?
    let globalAngleSelection: String?
    let packageAngleSelection: String?
    let metalDeviceName: String?
    let metalRegistryID: String?
    let receipt: GraphicsStackReceipt
}

struct StreamFreshnessWindow: Sendable {
    let startedMonotonicNS: UInt64
    let endedMonotonicNS: UInt64
    let receivedFrames: Int
    let contentChanges: Int
    let identicalFrames: Int
    let longestIdenticalRunFrames: Int
    let longestIdenticalRunMS: Double
    let sequenceDrops: UInt64
    let sampledPixelsPerFrame: Int
}

struct HostPresentationWindow: Sendable {
    let startedMonotonicNS: UInt64
    let endedMonotonicNS: UInt64
    let submittedFrames: Int
    let completedFrames: Int
    let uniqueSourceUploads: Int
    let repeatedSourcePresents: Int
    let drawableMisses: Int
    let commandErrors: Int
    let meanCompletionLatencyMS: Double?
    let p95CompletionLatencyMS: Double?
    let p99CompletionLatencyMS: Double?
    let maximumCompletionLatencyMS: Double?
    let meanGPUTimeMS: Double?
    let p95GPUTimeMS: Double?
    let maximumGPUTimeMS: Double?
}

private struct DiagnosticArtifact: Sendable {
    let graphicsRunID: String?
    let graphicsStackSHA256: String?
    let captureScope: String
    let createdUTC: String
    let createdMonotonicNS: UInt64
    let kind: String
    let trigger: String
    let relativePath: String
    let byteCount: Int64
    let sha256: String
    let analysisState: String
    let normalizedRelativePath: String
    let normalizedSHA256: String
    let normalizedSummaryCSV: String
    let traceProcessorSHA256: String
}

private struct GraphicsPipelineIncident: Sendable {
    let incidentID: String
    let trigger: String
    let observedMonotonicNS: UInt64
    let window: GameFrameTelemetryWindow
    let traceSequence: Int?
    let firstObservedDivergentBoundary: String
    let causalOwner: String
    let causalConfidence: String
    let explicitUnknowns: [String]
}

private enum DiagnosticTraceScope: String, Sendable {
    case combatBenchmark = "COMBAT_BENCHMARK"
    case automaticGraphics = "AUTOMATIC_GRAPHICS"
}

struct TFTMACRuntimeError: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private enum SQLiteValue: Sendable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case null
}

final class TFTMACNativeTelemetry: @unchecked Sendable {
    let sessionIdentifier: String
    let captureDirectory: URL

    private let queue = DispatchQueue(label: "com.flashls1.tftmac.telemetry")
    private let configurationSHA256: String
    private let targetFPS: Int
    private var database: OpaquePointer?
    private var eventLog: FileHandle?
    private var activeGraphicsRunID: String?
    private var activeGraphicsRunPID: Int32?
    private var activeGraphicsStackSHA256: String?
    private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(profile: TFTMACRuntimeProfile, applicationSupport: URL) throws {
        configurationSHA256 = profile.experimentConfigurationReceipt.sha256
        targetFPS = profile.refreshHz
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        sessionIdentifier = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString.lowercased()
        captureDirectory = applicationSupport.appendingPathComponent("Captures/\(sessionIdentifier)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: captureDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let logURL = captureDirectory.appendingPathComponent("native-events.jsonl")
        FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        eventLog = try FileHandle(forWritingTo: logURL)

        // Each capture owns a new UUID-scoped database. Historical per-session
        // databases are immutable evidence and are never reopened or migrated.
        let databaseURL = captureDirectory.appendingPathComponent("TFTMAC_NATIVE_RUNTIME.sqlite")
        guard !FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw TFTMACRuntimeError("A new TFTMAC capture unexpectedly collided with an existing SQL database.")
        }
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            throw TFTMACRuntimeError("The native SQL telemetry database could not be opened.")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
        try executeSchema()
        try execute(
            "INSERT INTO sessions(session_id, started_utc, status, profile_id) VALUES(?, ?, 'STARTING', ?)",
            [.text(sessionIdentifier), .text(Self.utcNow()), .text(profile.identifier)]
        )
        recordEvent("LOGGER_INITIALIZED", payload: [
            "database": databaseURL.lastPathComponent,
            "rawEventLog": logURL.lastPathComponent,
            "loggerStartsBeforeEmulator": true,
            "graphics_logger_mode": "AUTOMATIC_TFT_PROCESS_LIFETIME",
            "graphics_schema_version": 3
        ])
    }

    deinit {
        queue.sync {
            try? eventLog?.close()
            if let database { sqlite3_close(database) }
            database = nil
        }
    }

    func recordReceipt(key: String, value: String, source: String, confidence: String) {
        enqueue {
            try self.execute(
                "INSERT INTO runtime_receipts(session_id, receipt_key, receipt_value, source, confidence, observed_utc) VALUES(?, ?, ?, ?, ?, ?)",
                [.text(self.sessionIdentifier), .text(key), .text(value), .text(source), .text(confidence), .text(Self.utcNow())]
            )
        }
    }

    func markRunning() {
        enqueue {
            try self.execute(
                "UPDATE sessions SET status = 'RUNNING' WHERE session_id = ? AND ended_utc IS NULL",
                [.text(self.sessionIdentifier)]
            )
        }
    }

    /// Opens the single graphics lifecycle owned by the observed TFT process/layer.
    /// The serial SQL queue is the semantic owner, so all previously submitted rows
    /// remain outside the new run and every later row resolves to it automatically.
    func beginOrUpdateGraphicsRun(gamePID: Int32?, exactLayerName: String?, reason: String) {
        queue.sync {
            let nowUTC = Self.utcNow()
            let nowNS = DispatchTime.now().uptimeNanoseconds
            if let activeGraphicsRunID {
                if let activeGraphicsRunPID, let gamePID, activeGraphicsRunPID != gamePID {
                    try? self.closeGraphicsRun(
                        activeGraphicsRunID,
                        endedUTC: nowUTC,
                        endedMonotonicNS: nowNS,
                        reason: "TFT_PROCESS_REPLACED"
                    )
                    self.activeGraphicsRunID = nil
                    self.activeGraphicsRunPID = nil
                    self.activeGraphicsStackSHA256 = nil
                } else {
                    try? self.execute(
                        "UPDATE graphics_runs SET game_pid = COALESCE(?, game_pid), exact_layer_name = COALESCE(?, exact_layer_name), last_observed_utc = ?, last_observed_monotonic_ns = ? WHERE graphics_run_id = ? AND ended_utc IS NULL",
                        [
                            gamePID.map { .integer(Int64($0)) } ?? .null,
                            exactLayerName.map(SQLiteValue.text) ?? .null,
                            .text(nowUTC), .integer(Int64(bitPattern: nowNS)),
                            .text(activeGraphicsRunID)
                        ]
                    )
                    if let gamePID { self.activeGraphicsRunPID = gamePID }
                    return
                }
            }

            let runID = UUID().uuidString.lowercased()
            do {
                try self.execute(
                    "INSERT INTO graphics_runs(graphics_run_id, session_id, game_pid, started_utc, started_monotonic_ns, last_observed_utc, last_observed_monotonic_ns, start_reason, configuration_sha256, target_fps, exact_layer_name) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    [
                        .text(runID), .text(self.sessionIdentifier),
                        gamePID.map { .integer(Int64($0)) } ?? .null,
                        .text(nowUTC), .integer(Int64(bitPattern: nowNS)),
                        .text(nowUTC), .integer(Int64(bitPattern: nowNS)),
                        .text(reason), .text(self.configurationSHA256),
                        .integer(Int64(self.targetFPS)),
                        exactLayerName.map(SQLiteValue.text) ?? .null
                    ]
                )
                self.activeGraphicsRunID = runID
                self.activeGraphicsRunPID = gamePID
                self.activeGraphicsStackSHA256 = nil
            } catch {
                fputs("TFTMAC graphics-run error: \(error.localizedDescription)\n", stderr)
            }
        }
    }

    func updateGraphicsRunLayer(_ exactLayerName: String?) {
        queue.sync {
            guard let activeGraphicsRunID else { return }
            try? self.execute(
                "UPDATE graphics_runs SET exact_layer_name = ?, last_observed_utc = ?, last_observed_monotonic_ns = ? WHERE graphics_run_id = ? AND ended_utc IS NULL",
                [
                    exactLayerName.map(SQLiteValue.text) ?? .null,
                    .text(Self.utcNow()),
                    .integer(Int64(bitPattern: DispatchTime.now().uptimeNanoseconds)),
                    .text(activeGraphicsRunID)
                ]
            )
        }
    }

    func endGraphicsRun(reason: String) {
        queue.sync {
            guard let activeGraphicsRunID else { return }
            try? self.closeGraphicsRun(
                activeGraphicsRunID,
                endedUTC: Self.utcNow(),
                endedMonotonicNS: DispatchTime.now().uptimeNanoseconds,
                reason: reason
            )
            self.activeGraphicsRunID = nil
            self.activeGraphicsRunPID = nil
            self.activeGraphicsStackSHA256 = nil
        }
    }

    fileprivate func currentGraphicsContext() -> (runID: String?, stackSHA256: String?) {
        queue.sync { (activeGraphicsRunID, activeGraphicsStackSHA256) }
    }

    func recordEvent(_ kind: String, payload: [String: Any] = [:]) {
        let payloadText = Self.json(payload)
        let utc = Self.utcNow()
        let monotonic = DispatchTime.now().uptimeNanoseconds
        let lineData = Data((Self.json([
            "session_id": sessionIdentifier,
            "observed_utc": utc,
            "monotonic_ns": String(monotonic),
            "kind": kind,
            "payload": payload
        ]) + "\n").utf8)
        enqueue {
            try self.execute(
                "INSERT INTO events(session_id, observed_utc, monotonic_ns, kind, payload_json) VALUES(?, ?, ?, ?, ?)",
                [.text(self.sessionIdentifier), .text(utc), .integer(Int64(bitPattern: monotonic)), .text(kind), .text(payloadText)]
            )
            try self.eventLog?.write(contentsOf: lineData)
        }
    }

    fileprivate func recordFrameReceived(
        _ frame: EmulatorFrame,
        transport: String,
        sequenceDropCount: UInt64,
        visual: FrameVisualSample
    ) {
        enqueue {
            try self.execute(
                "INSERT INTO frame_samples(session_id, graphics_run_id, sequence, emulator_timestamp_us, received_monotonic_ns, width, height, byte_count, transport, sequence_drop_count, visual_sample_count, mean_luma, nonblack_fraction, minimum_rgb, maximum_rgb, minimum_alpha, maximum_alpha, content_sha256) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(self.sessionIdentifier), self.graphicsRunValue(),
                    .integer(Int64(frame.sequence)),
                    .integer(Int64(bitPattern: frame.emulatorTimestampMicroseconds)),
                    .integer(Int64(bitPattern: frame.receivedMonotonicNanoseconds)),
                    .integer(Int64(frame.width)), .integer(Int64(frame.height)),
                    .integer(Int64(frame.pixels.count)), .text(transport),
                    .integer(Int64(bitPattern: sequenceDropCount)),
                    .integer(Int64(visual.sampleCount)), .real(visual.meanLuma),
                    .real(visual.nonBlackFraction), .integer(Int64(visual.minimumRGB)),
                    .integer(Int64(visual.maximumRGB)), .integer(Int64(visual.minimumAlpha)),
                    .integer(Int64(visual.maximumAlpha)), visual.contentSHA256.map(SQLiteValue.text) ?? .null
                ]
            )
        }
    }

    fileprivate func recordFrameIntervalWindow(_ sample: FrameIntervalWindow) {
        enqueue {
            try self.execute(
                "INSERT INTO frame_interval_windows(session_id, graphics_run_id, started_monotonic_ns, ended_monotonic_ns, frame_count, sequence_drop_count, mean_interval_ms, p95_interval_ms, maximum_interval_ms) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(self.sessionIdentifier), self.graphicsRunValue(),
                    .integer(Int64(bitPattern: sample.startedMonotonicNS)),
                    .integer(Int64(bitPattern: sample.endedMonotonicNS)),
                    .integer(Int64(sample.frameCount)),
                    .integer(Int64(bitPattern: sample.sequenceDropCount)),
                    sample.meanIntervalMS.map(SQLiteValue.real) ?? .null,
                    sample.p95IntervalMS.map(SQLiteValue.real) ?? .null,
                    sample.maximumIntervalMS.map(SQLiteValue.real) ?? .null
                ]
            )
        }
    }

    func recordPresentation(_ sample: PresentationSample) {
        enqueue {
            try self.execute(
                "INSERT INTO presentation_samples(session_id, graphics_run_id, sampled_monotonic_ns, presented_frames, presentation_fps, source_fps, received_frames, mailbox_replacements, sequence_drops, last_sequence) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(self.sessionIdentifier), self.graphicsRunValue(),
                    .integer(Int64(bitPattern: sample.sampledMonotonicNanoseconds)),
                    .integer(Int64(bitPattern: sample.presentedFrames)), .real(sample.presentationFPS), .real(sample.sourceFPS),
                    .integer(Int64(bitPattern: sample.mailbox.receivedFrames)),
                    .integer(Int64(bitPattern: sample.mailbox.replacedBeforePresentation)),
                    .integer(Int64(bitPattern: sample.mailbox.sequenceDrops)),
                    sample.lastPresentedSequence.map { .integer(Int64($0)) } ?? .null
                ]
            )
        }
    }

    func recordResourceSample(emulatorPID: Int32, emulatorCPU: Double?, emulatorRSSKiB: Int64?, gamePID: Int32?, topActivity: String) {
        enqueue {
            try self.execute(
                "INSERT INTO resource_samples(session_id, observed_utc, monotonic_ns, emulator_pid, emulator_cpu_percent, emulator_rss_kib, game_pid, top_activity) VALUES(?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(self.sessionIdentifier), .text(Self.utcNow()),
                    .integer(Int64(bitPattern: DispatchTime.now().uptimeNanoseconds)),
                    .integer(Int64(emulatorPID)), emulatorCPU.map(SQLiteValue.real) ?? .null,
                    emulatorRSSKiB.map(SQLiteValue.integer) ?? .null,
                    gamePID.map { .integer(Int64($0)) } ?? .null, .text(topActivity)
                ]
            )
        }
    }

    fileprivate func recordGuestMemory(_ sample: GuestMemorySample) {
        enqueue {
            try self.execute(
                "INSERT INTO guest_memory_samples(session_id, observed_utc, monotonic_ns, total_kib, available_kib, swap_total_kib, swap_free_kib) VALUES(?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(self.sessionIdentifier), .text(Self.utcNow()),
                    .integer(Int64(bitPattern: DispatchTime.now().uptimeNanoseconds)),
                    .integer(sample.totalKiB), .integer(sample.availableKiB),
                    sample.swapTotalKiB.map(SQLiteValue.integer) ?? .null,
                    sample.swapFreeKiB.map(SQLiteValue.integer) ?? .null
                ]
            )
        }
    }

    fileprivate func recordHostResource(_ sample: HostResourceSample) {
        enqueue {
            try self.execute(
                "INSERT INTO host_resource_samples(session_id, observed_utc, monotonic_ns, available_kib, compressed_kib, swap_used_kib, pageouts, thermal_state, power_source) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(self.sessionIdentifier), .text(Self.utcNow()),
                    .integer(Int64(bitPattern: DispatchTime.now().uptimeNanoseconds)),
                    sample.availableKiB.map(SQLiteValue.integer) ?? .null,
                    sample.compressedKiB.map(SQLiteValue.integer) ?? .null,
                    sample.swapUsedKiB.map(SQLiteValue.integer) ?? .null,
                    sample.pageouts.map(SQLiteValue.integer) ?? .null,
                    .text(sample.thermalState), .text(sample.powerSource)
                ]
            )
        }
    }

    fileprivate func recordClockSync(hostT0NS: UInt64, guestUptimeNS: UInt64, hostT1NS: UInt64) {
        let midpoint = hostT0NS &+ ((hostT1NS &- hostT0NS) / 2)
        enqueue {
            try self.execute(
                "INSERT INTO clock_sync_samples(session_id, observed_utc, host_t0_ns, guest_uptime_ns, host_t1_ns, host_midpoint_ns, round_trip_ns, host_minus_guest_ns) VALUES(?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(self.sessionIdentifier), .text(Self.utcNow()),
                    .integer(Int64(bitPattern: hostT0NS)), .integer(Int64(bitPattern: guestUptimeNS)),
                    .integer(Int64(bitPattern: hostT1NS)), .integer(Int64(bitPattern: midpoint)),
                    .integer(Int64(bitPattern: hostT1NS &- hostT0NS)),
                    .integer(Int64(bitPattern: midpoint &- guestUptimeNS))
                ]
            )
        }
    }

    fileprivate func recordSurfaceFlinger(_ sample: SurfaceFlingerSample, label: String) {
        enqueue {
            try self.execute(
                "INSERT INTO surfaceflinger_samples(session_id, graphics_run_id, observed_utc, monotonic_ns, sample_label, render_rate_hz, total_missed_frames, hwc_missed_frames, gpu_missed_frames, tft_requested_rate_hz) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(self.sessionIdentifier), self.graphicsRunValue(), .text(Self.utcNow()),
                    .integer(Int64(bitPattern: DispatchTime.now().uptimeNanoseconds)), .text(label),
                    sample.renderRateHz.map(SQLiteValue.real) ?? .null,
                    sample.totalMissedFrames.map(SQLiteValue.integer) ?? .null,
                    sample.hwcMissedFrames.map(SQLiteValue.integer) ?? .null,
                    sample.gpuMissedFrames.map(SQLiteValue.integer) ?? .null,
                    sample.tftRequestedRateHz.map(SQLiteValue.real) ?? .null
                ]
            )
        }
    }

    fileprivate func recordAudioFlinger(_ sample: AudioFlingerSample, label: String) {
        enqueue {
            try self.execute(
                "INSERT INTO audio_samples(session_id, observed_utc, monotonic_ns, sample_label, backend, active_output, sample_rate_hz, stereo_output, active_tracks, partial_underruns, empty_underruns) VALUES(?, ?, ?, ?, 'coreaudio', ?, ?, ?, ?, ?, ?)",
                [
                    .text(self.sessionIdentifier), .text(Self.utcNow()),
                    .integer(Int64(bitPattern: DispatchTime.now().uptimeNanoseconds)), .text(label),
                    .integer(sample.activeOutput ? 1 : 0),
                    sample.sampleRateHz.map { .integer(Int64($0)) } ?? .null,
                    .integer(sample.stereoOutput ? 1 : 0),
                    sample.activeTracks.map { .integer(Int64($0)) } ?? .null,
                    sample.partialUnderruns.map(SQLiteValue.integer) ?? .null,
                    sample.emptyUnderruns.map(SQLiteValue.integer) ?? .null
                ]
            )
        }
    }

    fileprivate func recordLogcatAggregate(_ sample: LogcatAggregate) {
        enqueue {
            try self.execute(
                "INSERT INTO logcat_aggregates(session_id, observed_utc, monotonic_ns, byte_start, byte_end, skipped_bytes, line_count, anr_count, input_timeout_count, fatal_count, memory_kill_count, choreographer_skip_count, angle_warning_count, vulkan_warning_count, audio_error_count) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(self.sessionIdentifier), .text(Self.utcNow()),
                    .integer(Int64(bitPattern: DispatchTime.now().uptimeNanoseconds)),
                    .integer(Int64(bitPattern: sample.byteStart)), .integer(Int64(bitPattern: sample.byteEnd)),
                    .integer(Int64(bitPattern: sample.skippedBytes)), .integer(Int64(sample.lineCount)),
                    .integer(Int64(sample.anrCount)), .integer(Int64(sample.inputTimeoutCount)),
                    .integer(Int64(sample.fatalCount)), .integer(Int64(sample.memoryKillCount)),
                    .integer(Int64(sample.choreographerSkipCount)), .integer(Int64(sample.angleWarningCount)),
                    .integer(Int64(sample.vulkanWarningCount)), .integer(Int64(sample.audioErrorCount))
                ]
            )
        }
    }

    fileprivate func recordPipelineLogAggregate(_ sample: PipelineLogAggregate) {
        enqueue {
            try self.execute(
                "INSERT INTO pipeline_log_aggregates(session_id, graphics_run_id, observed_utc, monotonic_ns, source_stream, byte_start, byte_end, skipped_bytes, line_count, gfxstream_warning_count, asg_stall_count, vulkan_error_count, moltenvk_warning_count, shader_error_count, fence_timeout_count) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(self.sessionIdentifier), self.graphicsRunValue(), .text(Self.utcNow()),
                    .integer(Int64(bitPattern: DispatchTime.now().uptimeNanoseconds)),
                    .text(sample.sourceStream),
                    .integer(Int64(bitPattern: sample.byteStart)),
                    .integer(Int64(bitPattern: sample.byteEnd)),
                    .integer(Int64(bitPattern: sample.skippedBytes)),
                    .integer(Int64(sample.lineCount)),
                    .integer(Int64(sample.signals.gfxstreamWarningCount)),
                    .integer(Int64(sample.signals.asgStallCount)),
                    .integer(Int64(sample.signals.vulkanErrorCount)),
                    .integer(Int64(sample.signals.moltenVKWarningCount)),
                    .integer(Int64(sample.signals.shaderErrorCount)),
                    .integer(Int64(sample.signals.fenceTimeoutCount))
                ]
            )
        }
    }

    fileprivate func recordGraphicsPipelineSnapshot(_ sample: GraphicsPipelineSnapshot) {
        enqueue {
            let unknowns = sample.receipt.explicitUnknownKeys()
            let completeness = sample.receipt.completeness(
                requiredKeys: GraphicsPipelineSnapshot.requiredReceiptKeys
            ).rawValue
            try self.execute(
                """
                INSERT INTO graphics_pipeline_snapshots(
                  session_id, graphics_run_id, observed_utc, monotonic_ns, sample_label,
                  stack_sha256, stack_receipt_json, receipt_completeness, explicit_unknowns_json,
                  game_pid, exact_layer_name, tft_surface_state, game_graphics_api,
                  game_graphics_api_confidence, angle_state, gfxstream_state, moltenvk_state,
                  emulator_version, emulator_build_id, emulator_gpu_selection,
                  gfxstream_feature_receipt, gfxstream_tracing_state, moltenvk_version,
                  moltenvk_configuration_json, host_vulkan_device, vulkan_composition,
                  native_swapchain, guest_egl_implementation, guest_vulkan_implementation,
                  global_angle_selection, package_angle_selection, metal_device_name,
                  metal_registry_id
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(self.sessionIdentifier), self.graphicsRunValue(), .text(Self.utcNow()),
                    .integer(Int64(bitPattern: DispatchTime.now().uptimeNanoseconds)),
                    .text(sample.label), .text(sample.receipt.sha256),
                    .text(sample.receipt.canonicalJSON), .text(completeness),
                    .text(Self.jsonArray(unknowns)),
                    sample.gamePID.map { .integer(Int64($0)) } ?? .null,
                    sample.exactLayerName.map(SQLiteValue.text) ?? .null,
                    .text(sample.tftSurfaceState), .text(sample.gameGraphicsAPI),
                    .text(sample.gameGraphicsAPIConfidence), .text(sample.angleState),
                    .text(sample.gfxstreamState), .text(sample.moltenVKState),
                    sample.emulatorVersion.map(SQLiteValue.text) ?? .null,
                    sample.emulatorBuildID.map(SQLiteValue.text) ?? .null,
                    sample.emulatorGPUSelection.map(SQLiteValue.text) ?? .null,
                    sample.gfxstreamFeatureReceipt.map(SQLiteValue.text) ?? .null,
                    .text(sample.gfxstreamTracingState),
                    sample.moltenVKVersion.map(SQLiteValue.text) ?? .null,
                    .text(sample.moltenVKConfiguration),
                    sample.hostVulkanDevice.map(SQLiteValue.text) ?? .null,
                    sample.vulkanComposition.map { .integer($0 ? 1 : 0) } ?? .null,
                    sample.nativeSwapchain.map { .integer($0 ? 1 : 0) } ?? .null,
                    sample.guestEGLImplementation.map(SQLiteValue.text) ?? .null,
                    sample.guestVulkanImplementation.map(SQLiteValue.text) ?? .null,
                    sample.globalAngleSelection.map(SQLiteValue.text) ?? .null,
                    sample.packageAngleSelection.map(SQLiteValue.text) ?? .null,
                    sample.metalDeviceName.map(SQLiteValue.text) ?? .null,
                    sample.metalRegistryID.map(SQLiteValue.text) ?? .null
                ]
            )
            self.activeGraphicsStackSHA256 = sample.receipt.sha256
        }
    }

    func recordStreamFreshness(_ sample: StreamFreshnessWindow) {
        enqueue {
            try self.execute(
                "INSERT INTO stream_freshness_windows(session_id, graphics_run_id, started_monotonic_ns, ended_monotonic_ns, received_frames, content_changes, identical_frames, longest_identical_run_frames, longest_identical_run_ms, sequence_drops, sampled_pixels_per_frame) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(self.sessionIdentifier), self.graphicsRunValue(),
                    .integer(Int64(bitPattern: sample.startedMonotonicNS)),
                    .integer(Int64(bitPattern: sample.endedMonotonicNS)),
                    .integer(Int64(sample.receivedFrames)),
                    .integer(Int64(sample.contentChanges)),
                    .integer(Int64(sample.identicalFrames)),
                    .integer(Int64(sample.longestIdenticalRunFrames)),
                    .real(sample.longestIdenticalRunMS),
                    .integer(Int64(bitPattern: sample.sequenceDrops)),
                    .integer(Int64(sample.sampledPixelsPerFrame))
                ]
            )
        }
    }

    func recordHostPresentation(_ sample: HostPresentationWindow) {
        enqueue {
            try self.execute(
                "INSERT INTO host_presentation_windows(session_id, graphics_run_id, started_monotonic_ns, ended_monotonic_ns, submitted_frames, completed_frames, unique_source_uploads, repeated_source_presents, drawable_misses, command_errors, mean_completion_latency_ms, p95_completion_latency_ms, p99_completion_latency_ms, maximum_completion_latency_ms, mean_gpu_time_ms, p95_gpu_time_ms, maximum_gpu_time_ms) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(self.sessionIdentifier), self.graphicsRunValue(),
                    .integer(Int64(bitPattern: sample.startedMonotonicNS)),
                    .integer(Int64(bitPattern: sample.endedMonotonicNS)),
                    .integer(Int64(sample.submittedFrames)),
                    .integer(Int64(sample.completedFrames)),
                    .integer(Int64(sample.uniqueSourceUploads)),
                    .integer(Int64(sample.repeatedSourcePresents)),
                    .integer(Int64(sample.drawableMisses)),
                    .integer(Int64(sample.commandErrors)),
                    sample.meanCompletionLatencyMS.map(SQLiteValue.real) ?? .null,
                    sample.p95CompletionLatencyMS.map(SQLiteValue.real) ?? .null,
                    sample.p99CompletionLatencyMS.map(SQLiteValue.real) ?? .null,
                    sample.maximumCompletionLatencyMS.map(SQLiteValue.real) ?? .null,
                    sample.meanGPUTimeMS.map(SQLiteValue.real) ?? .null,
                    sample.p95GPUTimeMS.map(SQLiteValue.real) ?? .null,
                    sample.maximumGPUTimeMS.map(SQLiteValue.real) ?? .null
                ]
            )
        }
    }

    func recordGameFrameUpdate(
        _ update: GameFrameTelemetryUpdate,
        layerName: String?,
        refreshPeriodNS: UInt64?
    ) {
        enqueue {
            try self.transaction {
                let observedNS = DispatchTime.now().uptimeNanoseconds
                let windowID = try update.window.map { try self.insertGameFrameWindow($0) }
                if let windowID, let window = update.window {
                    try self.execute(
                        "UPDATE game_frame_intervals SET game_frame_window_id = ? WHERE session_id = ? AND graphics_run_id IS ? AND game_frame_window_id IS NULL AND observed_monotonic_ns >= ? AND observed_monotonic_ns <= ?",
                        [
                            .integer(windowID), .text(self.sessionIdentifier), self.graphicsRunValue(),
                            .integer(Int64(bitPattern: window.startedMonotonicNS)),
                            .integer(Int64(bitPattern: window.endedMonotonicNS))
                        ]
                    )
                }
                for interval in update.intervals {
                    try self.execute(
                "INSERT INTO game_frame_intervals(session_id, graphics_run_id, stack_sha256, game_frame_window_id, observed_monotonic_ns, layer_name, refresh_period_ns, actual_present_ns, interval_ns, interval_ms, missed_vsync_equivalents, is_janky, is_severe) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        [
                            .text(self.sessionIdentifier), self.graphicsRunValue(),
                            self.graphicsStackValue(),
                            windowID.map(SQLiteValue.integer) ?? .null,
                            .integer(Int64(bitPattern: observedNS)),
                            layerName.map(SQLiteValue.text) ?? .null,
                            refreshPeriodNS.map { .integer(Int64(bitPattern: $0)) } ?? .null,
                            .integer(Int64(bitPattern: interval.actualPresentNS)),
                            .integer(Int64(bitPattern: interval.intervalNS)),
                            .real(interval.intervalMS),
                            .integer(Int64(interval.missedVsyncEquivalents)),
                            .integer(interval.isJanky ? 1 : 0),
                            .integer(interval.isSevere ? 1 : 0)
                        ]
                    )
                }
            }
        }
    }

    func recordGameFrameWindow(_ window: GameFrameTelemetryWindow) {
        enqueue { try self.insertGameFrameWindow(window) }
    }

    fileprivate func recordDiagnosticArtifact(_ artifact: DiagnosticArtifact) {
        enqueue {
            try self.execute(
                "INSERT INTO diagnostic_artifacts(session_id, graphics_run_id, stack_sha256, capture_scope, created_utc, created_monotonic_ns, artifact_kind, trigger, relative_path, byte_count, sha256, analysis_state, normalized_relative_path, normalized_sha256, normalized_summary_csv, trace_processor_sha256) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [
                    .text(self.sessionIdentifier), artifact.graphicsRunID.map(SQLiteValue.text) ?? .null,
                    artifact.graphicsStackSHA256.map(SQLiteValue.text) ?? .null,
                    .text(artifact.captureScope), .text(artifact.createdUTC),
                    .integer(Int64(bitPattern: artifact.createdMonotonicNS)),
                    .text(artifact.kind), .text(artifact.trigger), .text(artifact.relativePath),
                    .integer(artifact.byteCount), .text(artifact.sha256), .text(artifact.analysisState),
                    .text(artifact.normalizedRelativePath), .text(artifact.normalizedSHA256),
                    .text(artifact.normalizedSummaryCSV), .text(artifact.traceProcessorSHA256)
                ]
            )
        }
    }

    fileprivate func recordGraphicsPipelineIncident(_ incident: GraphicsPipelineIncident) {
        enqueue {
            let window = incident.window
            try self.execute(
                """
                INSERT INTO graphics_pipeline_incidents(
                  incident_id, session_id, graphics_run_id, trigger, observed_monotonic_ns,
                  stack_sha256,
                  window_started_monotonic_ns, window_ended_monotonic_ns, layer_name,
                  effective_fps, one_percent_low_fps, p95_interval_ms, p99_interval_ms,
                  maximum_interval_ms, jank_count, severe_count, missed_vsync_equivalents,
                  trace_sequence, first_observed_divergent_boundary, causal_owner,
                  causal_confidence, explicit_unknowns_json
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(incident.incidentID), .text(self.sessionIdentifier), self.graphicsRunValue(),
                    .text(incident.trigger), .integer(Int64(bitPattern: incident.observedMonotonicNS)),
                    self.graphicsStackValue(),
                    .integer(Int64(bitPattern: window.startedMonotonicNS)),
                    .integer(Int64(bitPattern: window.endedMonotonicNS)),
                    window.layerName.map(SQLiteValue.text) ?? .null,
                    .real(window.effectiveFPS),
                    window.onePercentLowFPS.map(SQLiteValue.real) ?? .null,
                    window.p95MS.map(SQLiteValue.real) ?? .null,
                    window.p99MS.map(SQLiteValue.real) ?? .null,
                    window.maximumMS.map(SQLiteValue.real) ?? .null,
                    .integer(Int64(window.jankCount)), .integer(Int64(window.severeCount)),
                    .integer(Int64(window.missedVsyncEquivalents)),
                    incident.traceSequence.map { .integer(Int64($0)) } ?? .null,
                    .text(incident.firstObservedDivergentBoundary), .text(incident.causalOwner),
                    .text(incident.causalConfidence), .text(Self.jsonArray(incident.explicitUnknowns))
                ]
            )
        }
    }

    func recordCombatBenchmark(_ run: CombatBenchmarkRun) {
        enqueue {
            let metrics = run.metrics
            try self.execute(
                """
                INSERT OR REPLACE INTO combat_benchmarks(
                  benchmark_id, session_id, preset_id, configuration_sha256, comparison_identity_sha256, configuration_json,
                  tft_package_version, performance_mode_confirmed, started_utc, ended_utc,
                  started_monotonic_ns, ended_monotonic_ns, exact_layer_identity, duration_seconds,
                  surface_availability, clock_coverage, p95_clock_rtt_ms, history_truncated,
                  correctness_passed, weighted_fps, one_percent_low_fps, p50_interval_ms,
                  p95_interval_ms, p99_interval_ms, max_interval_ms, jank_rate, severe_rate,
                  missed_vsync_rate, observer_overhead_invalid, valid, invalid_reason
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(run.benchmarkID), .text(run.sessionID), .text(run.presetID.rawValue),
                    .text(run.configurationSHA256), .text(run.comparisonIdentitySHA256),
                    .text(run.configurationJSON), .text(run.tftPackageVersion),
                    .integer(run.performanceModeConfirmed ? 1 : 0), .text(run.startedUTC), .text(run.endedUTC),
                    .integer(Int64(bitPattern: run.startedMonotonicNS)),
                    .integer(Int64(bitPattern: run.endedMonotonicNS)),
                    run.exactLayerIdentity.map(SQLiteValue.text) ?? .null,
                    .real(metrics.combatDurationSeconds), .real(metrics.surfaceAvailability),
                    .real(metrics.clockCoverage), .real(metrics.p95ClockRoundTripMilliseconds),
                    .integer(metrics.frameHistoryTruncated ? 1 : 0),
                    .integer(metrics.correctnessPassed ? 1 : 0), .real(metrics.weightedFPS),
                    .real(metrics.onePercentLowFPS), .real(run.p50IntervalMilliseconds),
                    .real(metrics.p95IntervalMilliseconds), .real(metrics.p99IntervalMilliseconds),
                    .real(run.maximumIntervalMilliseconds), .real(metrics.jankRate),
                    .real(metrics.severeRate), .real(metrics.missedVsyncRate),
                    .integer(run.observerOverheadInvalid ? 1 : 0),
                    .integer(run.isValid ? 1 : 0),
                    run.invalidReason.map(SQLiteValue.text) ?? .null
                ]
            )
        }
    }

    func recordCombatIncident(_ incident: CombatIncidentRecord) {
        enqueue {
            try self.execute(
                """
                INSERT INTO combat_incidents(
                  incident_id, benchmark_id, session_id, preset_id, trigger, observed_monotonic_ns,
                  effective_fps, one_percent_low_fps, p99_interval_ms, severe_count, trace_sequence,
                  first_divergent_boundary, confidence, explicit_unknowns
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(incident.incidentID), .text(incident.benchmarkID), .text(incident.sessionID),
                    .text(incident.presetID.rawValue), .text(incident.trigger),
                    .integer(Int64(bitPattern: incident.observedMonotonicNS)),
                    incident.effectiveFPS.map(SQLiteValue.real) ?? .null,
                    incident.onePercentLowFPS.map(SQLiteValue.real) ?? .null,
                    incident.p99IntervalMilliseconds.map(SQLiteValue.real) ?? .null,
                    .integer(Int64(incident.severeCount)),
                    incident.traceSequence.map { .integer(Int64($0)) } ?? .null,
                    .text(incident.firstDivergentBoundary), .text(incident.confidence),
                    .text(incident.explicitUnknowns)
                ]
            )
        }
    }

    func recordCombatComparison(_ comparison: CombatComparisonRecord) {
        enqueue {
            let deltas = comparison.analysis.deltas
            try self.execute(
                """
                INSERT INTO combat_comparisons(
                  comparison_id, control_benchmark_id, candidate_benchmark_id,
                  weighted_fps_delta_percent, one_percent_low_delta_percent,
                  p95_delta_percent, p99_delta_percent, jank_delta_points,
                  severe_delta_points, missed_vsync_delta_points, correctness_status,
                  observer_overhead_invalid, decision, created_utc
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(comparison.comparisonID), .text(comparison.controlBenchmarkID),
                    .text(comparison.candidateBenchmarkID), .real(deltas.weightedFPSPercent),
                    .real(deltas.onePercentLowFPSPercent), .real(deltas.p95IntervalPercent),
                    .real(deltas.p99IntervalPercent), .real(deltas.jankRatePercentagePoints),
                    .real(deltas.severeRatePercentagePoints), .real(deltas.missedVsyncRatePercentagePoints),
                    .text(comparison.correctnessStatus),
                    .integer(comparison.observerOverheadInvalid ? 1 : 0),
                    .text(comparison.analysis.decision.rawValue), .text(comparison.createdUTC)
                ]
            )
        }
    }

    func recordGameProcessTransition(previousPID: Int32?, currentPID: Int32?) {
        enqueue {
            let now = Self.utcNow()
            let monotonic = Int64(bitPattern: DispatchTime.now().uptimeNanoseconds)
            if let previousPID {
                try self.execute(
                    "UPDATE game_process_sessions SET ended_utc = ?, ended_monotonic_ns = ? WHERE session_id = ? AND game_pid = ? AND ended_utc IS NULL",
                    [.text(now), .integer(monotonic), .text(self.sessionIdentifier), .integer(Int64(previousPID))]
                )
            }
            if let currentPID {
                try self.execute(
                    "INSERT INTO game_process_sessions(session_id, game_pid, started_utc, started_monotonic_ns) VALUES(?, ?, ?, ?)",
                    [.text(self.sessionIdentifier), .integer(Int64(currentPID)), .text(now), .integer(monotonic)]
                )
            }
        }
    }

    fileprivate func recordInput(_ input: EmulatorInput) {
        let values: [SQLiteValue]
        switch input {
        case .touch(let touch):
            values = [
                .text(sessionIdentifier), .integer(Int64(bitPattern: DispatchTime.now().uptimeNanoseconds)),
                .text("touch"), .integer(Int64(touch.x)), .integer(Int64(touch.y)),
                .null, .integer(Int64(touch.pressure)), .null, .null
            ]
        case .mouse(let mouse):
            values = [
                .text(sessionIdentifier), .integer(Int64(bitPattern: DispatchTime.now().uptimeNanoseconds)),
                .text("mouse"), .integer(Int64(mouse.x)), .integer(Int64(mouse.y)),
                .integer(Int64(mouse.buttons)), .null, .null, .null
            ]
        case .keyboard(let keyboard):
            values = [
                .text(sessionIdentifier), .integer(Int64(bitPattern: DispatchTime.now().uptimeNanoseconds)),
                .text("keyboard"), .null, .null, .null, .null,
                keyboard.text.map { .integer(Int64($0.count)) } ?? .null,
                keyboard.key.map(SQLiteValue.text) ?? .null
            ]
        }
        enqueue {
            try self.execute(
                "INSERT INTO input_samples(session_id, monotonic_ns, input_kind, x, y, buttons, pressure, character_count, special_key) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)",
                values
            )
        }
    }

    func finish(status: String) {
        queue.sync {
            let now = Self.utcNow()
            let monotonic = Int64(bitPattern: DispatchTime.now().uptimeNanoseconds)
            if let activeGraphicsRunID {
                try? self.closeGraphicsRun(
                    activeGraphicsRunID,
                    endedUTC: now,
                    endedMonotonicNS: UInt64(bitPattern: monotonic),
                    reason: "SESSION_SEALED"
                )
                self.activeGraphicsRunID = nil
                self.activeGraphicsRunPID = nil
                self.activeGraphicsStackSHA256 = nil
            }
            try? self.execute(
                "UPDATE game_process_sessions SET ended_utc = ?, ended_monotonic_ns = ? WHERE session_id = ? AND ended_utc IS NULL",
                [.text(now), .integer(monotonic), .text(self.sessionIdentifier)]
            )
            try? self.execute(
                "UPDATE sessions SET ended_utc = ?, status = ? WHERE session_id = ?",
                [.text(now), .text(status), .text(self.sessionIdentifier)]
            )
            try? self.eventLog?.synchronize()
        }
    }

    private func executeSchema() throws {
        let schema = """
        PRAGMA journal_mode=WAL;
        PRAGMA synchronous=NORMAL;
        PRAGMA foreign_keys=ON;
        CREATE TABLE IF NOT EXISTS sessions(
          session_id TEXT PRIMARY KEY,
          started_utc TEXT NOT NULL,
          ended_utc TEXT,
          status TEXT NOT NULL,
          profile_id TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS runtime_receipts(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          receipt_key TEXT NOT NULL,
          receipt_value TEXT NOT NULL,
          source TEXT NOT NULL,
          confidence TEXT NOT NULL,
          observed_utc TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS events(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          observed_utc TEXT NOT NULL,
          monotonic_ns INTEGER NOT NULL,
          kind TEXT NOT NULL,
          payload_json TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS graphics_runs(
          graphics_run_id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL,
          game_pid INTEGER,
          started_utc TEXT NOT NULL,
          started_monotonic_ns INTEGER NOT NULL,
          last_observed_utc TEXT NOT NULL,
          last_observed_monotonic_ns INTEGER NOT NULL,
          ended_utc TEXT,
          ended_monotonic_ns INTEGER,
          start_reason TEXT NOT NULL,
          end_reason TEXT,
          configuration_sha256 TEXT NOT NULL,
          target_fps INTEGER NOT NULL,
          exact_layer_name TEXT
        );
        CREATE TABLE IF NOT EXISTS frame_samples(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          graphics_run_id TEXT,
          sequence INTEGER NOT NULL,
          emulator_timestamp_us INTEGER NOT NULL,
          received_monotonic_ns INTEGER NOT NULL,
          width INTEGER NOT NULL,
          height INTEGER NOT NULL,
          byte_count INTEGER NOT NULL,
          transport TEXT NOT NULL,
          sequence_drop_count INTEGER NOT NULL,
          visual_sample_count INTEGER NOT NULL,
          mean_luma REAL NOT NULL,
          nonblack_fraction REAL NOT NULL,
          minimum_rgb INTEGER NOT NULL,
          maximum_rgb INTEGER NOT NULL,
          minimum_alpha INTEGER NOT NULL,
          maximum_alpha INTEGER NOT NULL,
          content_sha256 TEXT
        );
        CREATE TABLE IF NOT EXISTS presentation_samples(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          graphics_run_id TEXT,
          sampled_monotonic_ns INTEGER NOT NULL,
          presented_frames INTEGER NOT NULL,
          presentation_fps REAL NOT NULL,
          source_fps REAL NOT NULL,
          received_frames INTEGER NOT NULL,
          mailbox_replacements INTEGER NOT NULL,
          sequence_drops INTEGER NOT NULL,
          last_sequence INTEGER
        );
        CREATE TABLE IF NOT EXISTS frame_interval_windows(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          graphics_run_id TEXT,
          started_monotonic_ns INTEGER NOT NULL,
          ended_monotonic_ns INTEGER NOT NULL,
          frame_count INTEGER NOT NULL,
          sequence_drop_count INTEGER NOT NULL,
          mean_interval_ms REAL,
          p95_interval_ms REAL,
          maximum_interval_ms REAL
        );
        CREATE TABLE IF NOT EXISTS game_frame_intervals(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          graphics_run_id TEXT,
          stack_sha256 TEXT,
          game_frame_window_id INTEGER,
          observed_monotonic_ns INTEGER NOT NULL,
          layer_name TEXT,
          refresh_period_ns INTEGER,
          actual_present_ns INTEGER NOT NULL,
          interval_ns INTEGER NOT NULL,
          interval_ms REAL NOT NULL,
          missed_vsync_equivalents INTEGER NOT NULL,
          is_janky INTEGER NOT NULL,
          is_severe INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS game_frame_windows(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          graphics_run_id TEXT,
          stack_sha256 TEXT,
          started_monotonic_ns INTEGER NOT NULL,
          ended_monotonic_ns INTEGER NOT NULL,
          status TEXT NOT NULL,
          unavailable_reason TEXT,
          layer_name TEXT,
          refresh_period_ns INTEGER,
          frame_count INTEGER NOT NULL,
          effective_fps REAL,
          one_percent_low_fps REAL,
          p50_interval_ms REAL,
          p95_interval_ms REAL,
          p99_interval_ms REAL,
          maximum_interval_ms REAL,
          jank_count INTEGER NOT NULL,
          severe_count INTEGER NOT NULL,
          missed_vsync_equivalents INTEGER NOT NULL,
          history_truncated INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS stream_freshness_windows(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          graphics_run_id TEXT,
          started_monotonic_ns INTEGER NOT NULL,
          ended_monotonic_ns INTEGER NOT NULL,
          received_frames INTEGER NOT NULL,
          content_changes INTEGER NOT NULL,
          identical_frames INTEGER NOT NULL,
          longest_identical_run_frames INTEGER NOT NULL,
          longest_identical_run_ms REAL NOT NULL,
          sequence_drops INTEGER NOT NULL,
          sampled_pixels_per_frame INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS host_presentation_windows(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          graphics_run_id TEXT,
          started_monotonic_ns INTEGER NOT NULL,
          ended_monotonic_ns INTEGER NOT NULL,
          submitted_frames INTEGER NOT NULL,
          completed_frames INTEGER NOT NULL,
          unique_source_uploads INTEGER NOT NULL,
          repeated_source_presents INTEGER NOT NULL,
          drawable_misses INTEGER NOT NULL,
          command_errors INTEGER NOT NULL,
          mean_completion_latency_ms REAL,
          p95_completion_latency_ms REAL,
          p99_completion_latency_ms REAL,
          maximum_completion_latency_ms REAL,
          mean_gpu_time_ms REAL,
          p95_gpu_time_ms REAL,
          maximum_gpu_time_ms REAL
        );
        CREATE TABLE IF NOT EXISTS resource_samples(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          observed_utc TEXT NOT NULL,
          monotonic_ns INTEGER NOT NULL,
          emulator_pid INTEGER NOT NULL,
          emulator_cpu_percent REAL,
          emulator_rss_kib INTEGER,
          game_pid INTEGER,
          top_activity TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS guest_memory_samples(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          observed_utc TEXT NOT NULL,
          monotonic_ns INTEGER NOT NULL,
          total_kib INTEGER NOT NULL,
          available_kib INTEGER NOT NULL,
          swap_total_kib INTEGER,
          swap_free_kib INTEGER
        );
        CREATE TABLE IF NOT EXISTS host_resource_samples(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          observed_utc TEXT NOT NULL,
          monotonic_ns INTEGER NOT NULL,
          available_kib INTEGER,
          compressed_kib INTEGER,
          swap_used_kib INTEGER,
          pageouts INTEGER,
          thermal_state TEXT NOT NULL,
          power_source TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS clock_sync_samples(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          observed_utc TEXT NOT NULL,
          host_t0_ns INTEGER NOT NULL,
          guest_uptime_ns INTEGER NOT NULL,
          host_t1_ns INTEGER NOT NULL,
          host_midpoint_ns INTEGER NOT NULL,
          round_trip_ns INTEGER NOT NULL,
          host_minus_guest_ns INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS surfaceflinger_samples(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          graphics_run_id TEXT,
          observed_utc TEXT NOT NULL,
          monotonic_ns INTEGER NOT NULL,
          sample_label TEXT NOT NULL,
          render_rate_hz REAL,
          total_missed_frames INTEGER,
          hwc_missed_frames INTEGER,
          gpu_missed_frames INTEGER,
          tft_requested_rate_hz REAL
        );
        CREATE TABLE IF NOT EXISTS audio_samples(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          observed_utc TEXT NOT NULL,
          monotonic_ns INTEGER NOT NULL,
          sample_label TEXT NOT NULL,
          backend TEXT NOT NULL,
          active_output INTEGER NOT NULL,
          sample_rate_hz INTEGER,
          stereo_output INTEGER NOT NULL,
          active_tracks INTEGER,
          partial_underruns INTEGER,
          empty_underruns INTEGER
        );
        CREATE TABLE IF NOT EXISTS logcat_aggregates(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          observed_utc TEXT NOT NULL,
          monotonic_ns INTEGER NOT NULL,
          byte_start INTEGER NOT NULL,
          byte_end INTEGER NOT NULL,
          skipped_bytes INTEGER NOT NULL,
          line_count INTEGER NOT NULL,
          anr_count INTEGER NOT NULL,
          input_timeout_count INTEGER NOT NULL,
          fatal_count INTEGER NOT NULL,
          memory_kill_count INTEGER NOT NULL,
          choreographer_skip_count INTEGER NOT NULL,
          angle_warning_count INTEGER NOT NULL,
          vulkan_warning_count INTEGER NOT NULL,
          audio_error_count INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS pipeline_log_aggregates(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          graphics_run_id TEXT,
          observed_utc TEXT NOT NULL,
          monotonic_ns INTEGER NOT NULL,
          source_stream TEXT NOT NULL,
          byte_start INTEGER NOT NULL,
          byte_end INTEGER NOT NULL,
          skipped_bytes INTEGER NOT NULL,
          line_count INTEGER NOT NULL,
          gfxstream_warning_count INTEGER NOT NULL,
          asg_stall_count INTEGER NOT NULL,
          vulkan_error_count INTEGER NOT NULL,
          moltenvk_warning_count INTEGER NOT NULL,
          shader_error_count INTEGER NOT NULL,
          fence_timeout_count INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS graphics_pipeline_snapshots(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          graphics_run_id TEXT,
          observed_utc TEXT NOT NULL,
          monotonic_ns INTEGER NOT NULL,
          sample_label TEXT NOT NULL,
          stack_sha256 TEXT NOT NULL,
          stack_receipt_json TEXT NOT NULL,
          receipt_completeness TEXT NOT NULL,
          explicit_unknowns_json TEXT NOT NULL,
          game_pid INTEGER,
          exact_layer_name TEXT,
          tft_surface_state TEXT NOT NULL,
          game_graphics_api TEXT NOT NULL,
          game_graphics_api_confidence TEXT NOT NULL,
          angle_state TEXT NOT NULL,
          gfxstream_state TEXT NOT NULL,
          moltenvk_state TEXT NOT NULL,
          emulator_version TEXT,
          emulator_build_id TEXT,
          emulator_gpu_selection TEXT,
          gfxstream_feature_receipt TEXT,
          gfxstream_tracing_state TEXT NOT NULL,
          moltenvk_version TEXT,
          moltenvk_configuration_json TEXT NOT NULL,
          host_vulkan_device TEXT,
          vulkan_composition INTEGER,
          native_swapchain INTEGER,
          guest_egl_implementation TEXT,
          guest_vulkan_implementation TEXT,
          global_angle_selection TEXT,
          package_angle_selection TEXT,
          metal_device_name TEXT,
          metal_registry_id TEXT
        );
        CREATE TABLE IF NOT EXISTS diagnostic_artifacts(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          graphics_run_id TEXT,
          stack_sha256 TEXT,
          capture_scope TEXT NOT NULL,
          created_utc TEXT NOT NULL,
          created_monotonic_ns INTEGER NOT NULL,
          artifact_kind TEXT NOT NULL,
          trigger TEXT NOT NULL,
          relative_path TEXT NOT NULL,
          byte_count INTEGER NOT NULL,
          sha256 TEXT NOT NULL,
          analysis_state TEXT NOT NULL,
          normalized_relative_path TEXT NOT NULL,
          normalized_sha256 TEXT NOT NULL,
          normalized_summary_csv TEXT NOT NULL,
          trace_processor_sha256 TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS graphics_pipeline_incidents(
          incident_id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL,
          graphics_run_id TEXT,
          trigger TEXT NOT NULL,
          observed_monotonic_ns INTEGER NOT NULL,
          stack_sha256 TEXT,
          window_started_monotonic_ns INTEGER NOT NULL,
          window_ended_monotonic_ns INTEGER NOT NULL,
          layer_name TEXT,
          effective_fps REAL NOT NULL,
          one_percent_low_fps REAL,
          p95_interval_ms REAL,
          p99_interval_ms REAL,
          maximum_interval_ms REAL,
          jank_count INTEGER NOT NULL,
          severe_count INTEGER NOT NULL,
          missed_vsync_equivalents INTEGER NOT NULL,
          trace_sequence INTEGER,
          first_observed_divergent_boundary TEXT NOT NULL,
          causal_owner TEXT NOT NULL,
          causal_confidence TEXT NOT NULL,
          explicit_unknowns_json TEXT NOT NULL
        );
        \(CombatBenchmarkLabStore.schemaSQL)
        CREATE TABLE IF NOT EXISTS game_process_sessions(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          game_pid INTEGER NOT NULL,
          started_utc TEXT NOT NULL,
          started_monotonic_ns INTEGER NOT NULL,
          ended_utc TEXT,
          ended_monotonic_ns INTEGER
        );
        CREATE TABLE IF NOT EXISTS input_samples(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          monotonic_ns INTEGER NOT NULL,
          input_kind TEXT NOT NULL,
          x INTEGER,
          y INTEGER,
          buttons INTEGER,
          pressure INTEGER,
          character_count INTEGER,
          special_key TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_events_kind_time ON events(kind, monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_graphics_runs_session_time ON graphics_runs(session_id, started_monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_frames_time ON frame_samples(received_monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_frames_graphics_run ON frame_samples(graphics_run_id, received_monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_frame_windows_time ON frame_interval_windows(started_monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_game_frame_intervals_time ON game_frame_intervals(observed_monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_game_frame_windows_time ON game_frame_windows(started_monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_game_frame_windows_run ON game_frame_windows(graphics_run_id, started_monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_game_frame_intervals_window ON game_frame_intervals(game_frame_window_id, actual_present_ns);
        CREATE INDEX IF NOT EXISTS idx_stream_freshness_time ON stream_freshness_windows(started_monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_host_presentation_time ON host_presentation_windows(started_monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_resources_time ON resource_samples(monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_guest_memory_time ON guest_memory_samples(monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_host_resources_time ON host_resource_samples(monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_surfaceflinger_time ON surfaceflinger_samples(monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_audio_time ON audio_samples(monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_logcat_time ON logcat_aggregates(monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_pipeline_log_time ON pipeline_log_aggregates(monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_graphics_pipeline_time ON graphics_pipeline_snapshots(monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_graphics_pipeline_run_hash ON graphics_pipeline_snapshots(graphics_run_id, monotonic_ns, stack_sha256);
        CREATE INDEX IF NOT EXISTS idx_diagnostic_artifacts_time ON diagnostic_artifacts(created_monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_graphics_incidents_run_time ON graphics_pipeline_incidents(graphics_run_id, observed_monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_combat_benchmarks_session ON combat_benchmarks(session_id, started_monotonic_ns);
        CREATE INDEX IF NOT EXISTS idx_inputs_time ON input_samples(monotonic_ns);
        DROP VIEW IF EXISTS graphics_frame_facts;
        DROP VIEW IF EXISTS graphics_pipeline_windows;
        DROP VIEW IF EXISTS graphics_window_context;
        CREATE VIEW graphics_window_context AS
        SELECT
          w.id AS game_frame_window_id,
          w.graphics_run_id,
          w.session_id,
          w.started_monotonic_ns,
          w.ended_monotonic_ns,
          (SELECT p.id
             FROM graphics_pipeline_snapshots p
            WHERE p.graphics_run_id = w.graphics_run_id
              AND p.stack_sha256 = w.stack_sha256
              AND p.monotonic_ns <= w.ended_monotonic_ns
            ORDER BY p.monotonic_ns DESC
            LIMIT 1) AS pipeline_snapshot_id,
          (SELECT s.id
             FROM stream_freshness_windows s
            WHERE s.graphics_run_id = w.graphics_run_id
              AND s.started_monotonic_ns < w.ended_monotonic_ns
              AND s.ended_monotonic_ns > w.started_monotonic_ns
            ORDER BY s.started_monotonic_ns DESC
            LIMIT 1) AS stream_window_id,
          (SELECT h.id
             FROM host_presentation_windows h
            WHERE h.graphics_run_id = w.graphics_run_id
              AND h.started_monotonic_ns < w.ended_monotonic_ns
              AND h.ended_monotonic_ns > w.started_monotonic_ns
            ORDER BY h.started_monotonic_ns DESC
            LIMIT 1) AS host_presentation_window_id,
          (SELECT l.id
             FROM pipeline_log_aggregates l
            WHERE l.graphics_run_id = w.graphics_run_id
              AND l.monotonic_ns BETWEEN w.started_monotonic_ns - 5000000000
                                     AND w.ended_monotonic_ns + 5000000000
            ORDER BY l.monotonic_ns DESC
            LIMIT 1) AS pipeline_log_aggregate_id
        FROM game_frame_windows w;
        CREATE VIEW graphics_pipeline_windows AS
        SELECT
          w.id AS game_frame_window_id,
          w.session_id,
          w.graphics_run_id,
          w.started_monotonic_ns,
          w.ended_monotonic_ns,
          w.status AS surface_status,
          w.unavailable_reason,
          w.layer_name,
          w.refresh_period_ns,
          w.frame_count AS surface_frame_count,
          w.effective_fps AS surface_effective_fps,
          w.one_percent_low_fps,
          w.p50_interval_ms,
          w.p95_interval_ms,
          w.p99_interval_ms,
          w.maximum_interval_ms,
          w.jank_count,
          w.severe_count,
          w.missed_vsync_equivalents,
          p.stack_sha256,
          p.stack_receipt_json,
          p.receipt_completeness,
          p.explicit_unknowns_json,
          p.game_graphics_api,
          p.game_graphics_api_confidence,
          p.angle_state,
          p.gfxstream_state,
          p.moltenvk_state,
          p.host_vulkan_device,
          p.metal_device_name,
          s.received_frames AS stream_received_frames,
          CASE WHEN s.ended_monotonic_ns > s.started_monotonic_ns
            THEN s.received_frames * 1000000000.0 / (s.ended_monotonic_ns - s.started_monotonic_ns)
            ELSE NULL END AS stream_received_fps,
          s.content_changes AS stream_content_changes,
          s.identical_frames AS stream_identical_frames,
          s.longest_identical_run_ms,
          s.sequence_drops AS stream_sequence_drops,
          h.submitted_frames AS presenter_submitted_frames,
          h.completed_frames AS presenter_completed_frames,
          CASE WHEN h.ended_monotonic_ns > h.started_monotonic_ns
            THEN h.completed_frames * 1000000000.0 / (h.ended_monotonic_ns - h.started_monotonic_ns)
            ELSE NULL END AS presenter_completed_fps,
          h.repeated_source_presents,
          h.drawable_misses,
          h.command_errors,
          h.p95_completion_latency_ms,
          h.p95_gpu_time_ms,
          l.gfxstream_warning_count,
          l.asg_stall_count,
          l.vulkan_error_count,
          l.moltenvk_warning_count,
          l.shader_error_count,
          l.fence_timeout_count,
          l.skipped_bytes AS pipeline_log_skipped_bytes,
          CASE
            WHEN l.id IS NULL THEN 'UNKNOWN_NO_CORRELATED_LOG_WINDOW'
            WHEN l.skipped_bytes > 0 THEN 'UNKNOWN_TRUNCATED_LOG_WINDOW'
            ELSE 'COMPLETE_CORRELATED_LOG_WINDOW'
          END AS pipeline_log_coverage,
          CASE
            WHEN l.id IS NULL THEN 'NONE_OBSERVED'
            WHEN l.skipped_bytes > 0 THEN 'UNKNOWN_TRUNCATED_LOG_WINDOW'
            WHEN l.gfxstream_warning_count > 0 OR l.asg_stall_count > 0
              OR l.vulkan_error_count > 0 OR l.moltenvk_warning_count > 0
              OR l.shader_error_count > 0 OR l.fence_timeout_count > 0
              THEN 'LOG_CORRELATED_UNATTRIBUTED'
            ELSE 'NONE_OBSERVED'
          END AS concurrent_pipeline_signal,
          CASE
            WHEN w.status <> 'AVAILABLE' THEN 'UNKNOWN_NO_EXACT_SURFACE_SAMPLE'
            WHEN w.effective_fps < 59.0 OR w.jank_count > 0 OR w.severe_count > 0
              OR w.missed_vsync_equivalents > 0 THEN 'TFT_SURFACE_ACTUAL_PRESENT'
            WHEN s.id IS NOT NULL AND (
              s.received_frames * 1000000000.0 / MAX(1, s.ended_monotonic_ns - s.started_monotonic_ns) < 59.0
              OR s.sequence_drops > 0) THEN 'EMULATOR_IMAGE_STREAM'
            WHEN h.id IS NOT NULL AND (
              h.completed_frames * 1000000000.0 / MAX(1, h.ended_monotonic_ns - h.started_monotonic_ns) < 59.0
              OR h.drawable_misses > 0 OR h.command_errors > 0
              OR COALESCE(h.p95_completion_latency_ms, 0) > 16.667
              OR COALESCE(h.p95_gpu_time_ms, 0) > 16.667) THEN 'TFTMAC_NATIVE_PRESENTER'
            ELSE 'NO_OBSERVED_DIVERGENCE'
          END AS first_observed_divergent_boundary,
          CASE
            WHEN w.status <> 'AVAILABLE' THEN 'UNKNOWN'
            WHEN w.effective_fps < 59.0 OR w.jank_count > 0 OR w.severe_count > 0
              OR w.missed_vsync_equivalents > 0 THEN 'UNKNOWN_UPSTREAM_OF_OR_AT_GUEST_SURFACE'
            WHEN s.id IS NOT NULL AND (
              s.received_frames * 1000000000.0 / MAX(1, s.ended_monotonic_ns - s.started_monotonic_ns) < 59.0
              OR s.sequence_drops > 0) THEN 'EMULATOR_OUTPUT_OR_CONTROLLER'
            WHEN h.id IS NOT NULL AND (
              h.completed_frames * 1000000000.0 / MAX(1, h.ended_monotonic_ns - h.started_monotonic_ns) < 59.0
              OR h.drawable_misses > 0 OR h.command_errors > 0
              OR COALESCE(h.p95_completion_latency_ms, 0) > 16.667
              OR COALESCE(h.p95_gpu_time_ms, 0) > 16.667) THEN 'TFTMAC_NATIVE_PRESENTER'
            ELSE 'NONE_OBSERVED'
          END AS causal_owner,
          CASE
            WHEN w.status <> 'AVAILABLE' THEN 'UNKNOWN'
            WHEN w.effective_fps < 59.0 OR w.jank_count > 0 OR w.severe_count > 0
              OR w.missed_vsync_equivalents > 0 THEN 'UNKNOWN'
            WHEN s.id IS NOT NULL AND (
              s.received_frames * 1000000000.0 / MAX(1, s.ended_monotonic_ns - s.started_monotonic_ns) < 59.0
              OR s.sequence_drops > 0) THEN
              CASE WHEN p.receipt_completeness = 'COMPLETE' THEN 'MEDIUM' ELSE 'LOW' END
            WHEN h.id IS NOT NULL AND (
              h.completed_frames * 1000000000.0 / MAX(1, h.ended_monotonic_ns - h.started_monotonic_ns) < 59.0
              OR h.drawable_misses > 0 OR h.command_errors > 0
              OR COALESCE(h.p95_completion_latency_ms, 0) > 16.667
              OR COALESCE(h.p95_gpu_time_ms, 0) > 16.667) THEN
              CASE WHEN p.receipt_completeness = 'COMPLETE' THEN 'MEDIUM' ELSE 'LOW' END
            ELSE 'NOT_APPLICABLE'
          END AS causal_confidence,
          'Internal Unreal, ANGLE, ASG, gfxstream, Vulkan-submit, MoltenVK, and Metal ownership remains UNKNOWN without a shared cross-stack frame ID.' AS attribution_limit
        FROM graphics_window_context c
        JOIN game_frame_windows w ON w.id = c.game_frame_window_id
        LEFT JOIN graphics_pipeline_snapshots p ON p.id = c.pipeline_snapshot_id
        LEFT JOIN stream_freshness_windows s ON s.id = c.stream_window_id
        LEFT JOIN host_presentation_windows h ON h.id = c.host_presentation_window_id
        LEFT JOIN pipeline_log_aggregates l ON l.id = c.pipeline_log_aggregate_id;
        CREATE VIEW graphics_frame_facts AS
        SELECT
          i.id AS game_frame_interval_id,
          i.session_id,
          i.graphics_run_id,
          i.game_frame_window_id,
          i.observed_monotonic_ns,
          i.actual_present_ns,
          i.interval_ns,
          i.interval_ms,
          i.missed_vsync_equivalents,
          i.is_janky,
          i.is_severe,
          i.stack_sha256,
          s.stack_receipt_json,
          s.game_graphics_api,
          s.angle_state,
          s.gfxstream_state,
          s.moltenvk_state,
          s.host_vulkan_device,
          s.metal_device_name,
          p.first_observed_divergent_boundary,
          p.causal_owner,
          p.causal_confidence,
          p.attribution_limit
        FROM game_frame_intervals i
        LEFT JOIN graphics_pipeline_windows p ON p.game_frame_window_id = i.game_frame_window_id
        LEFT JOIN graphics_pipeline_snapshots s ON s.id = (
          SELECT s2.id
            FROM graphics_pipeline_snapshots s2
           WHERE s2.graphics_run_id = i.graphics_run_id
             AND s2.stack_sha256 = i.stack_sha256
             AND s2.monotonic_ns <= i.observed_monotonic_ns
           ORDER BY s2.monotonic_ns DESC
           LIMIT 1
        );
        PRAGMA user_version=3;
        """
        guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else {
            throw TFTMACRuntimeError("The native SQL telemetry schema could not be created.")
        }
    }

    private func enqueue(_ operation: @escaping @Sendable () throws -> Void) {
        queue.async {
            do { try operation() }
            catch { fputs("TFTMAC telemetry error: \(error.localizedDescription)\n", stderr) }
        }
    }

    @discardableResult
    private func insertGameFrameWindow(_ window: GameFrameTelemetryWindow) throws -> Int64 {
        let state = Self.gameFrameStatus(window.status)
        let available: Bool
        if case .available = window.status { available = true } else { available = false }
        try execute(
            "INSERT INTO game_frame_windows(session_id, graphics_run_id, stack_sha256, started_monotonic_ns, ended_monotonic_ns, status, unavailable_reason, layer_name, refresh_period_ns, frame_count, effective_fps, one_percent_low_fps, p50_interval_ms, p95_interval_ms, p99_interval_ms, maximum_interval_ms, jank_count, severe_count, missed_vsync_equivalents, history_truncated) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                .text(sessionIdentifier), graphicsRunValue(), graphicsStackValue(),
                .integer(Int64(bitPattern: window.startedMonotonicNS)),
                .integer(Int64(bitPattern: window.endedMonotonicNS)),
                .text(state.status), state.reason.map(SQLiteValue.text) ?? .null,
                window.layerName.map(SQLiteValue.text) ?? .null,
                window.refreshPeriodNS.map { .integer(Int64(bitPattern: $0)) } ?? .null,
                .integer(Int64(window.frameCount)), available ? .real(window.effectiveFPS) : .null,
                window.onePercentLowFPS.map(SQLiteValue.real) ?? .null,
                window.p50MS.map(SQLiteValue.real) ?? .null,
                window.p95MS.map(SQLiteValue.real) ?? .null,
                window.p99MS.map(SQLiteValue.real) ?? .null,
                window.maximumMS.map(SQLiteValue.real) ?? .null,
                .integer(Int64(window.jankCount)), .integer(Int64(window.severeCount)),
                .integer(Int64(window.missedVsyncEquivalents)),
                .integer(window.historyTruncated ? 1 : 0)
            ]
        )
        guard let database else { throw TFTMACRuntimeError("The telemetry database is closed.") }
        return sqlite3_last_insert_rowid(database)
    }

    private func graphicsRunValue() -> SQLiteValue {
        activeGraphicsRunID.map(SQLiteValue.text) ?? .null
    }

    private func graphicsStackValue() -> SQLiteValue {
        activeGraphicsStackSHA256.map(SQLiteValue.text) ?? .null
    }

    private func closeGraphicsRun(
        _ graphicsRunID: String,
        endedUTC: String,
        endedMonotonicNS: UInt64,
        reason: String
    ) throws {
        try execute(
            "UPDATE graphics_runs SET ended_utc = ?, ended_monotonic_ns = ?, last_observed_utc = ?, last_observed_monotonic_ns = ?, end_reason = ? WHERE graphics_run_id = ? AND ended_utc IS NULL",
            [
                .text(endedUTC), .integer(Int64(bitPattern: endedMonotonicNS)),
                .text(endedUTC), .integer(Int64(bitPattern: endedMonotonicNS)),
                .text(reason), .text(graphicsRunID)
            ]
        )
    }

    private static func gameFrameStatus(_ status: GameFrameTelemetryStatus) -> (status: String, reason: String?) {
        switch status {
        case .available:
            return ("AVAILABLE", nil)
        case .unavailable(.noTFTSurfaceView):
            return ("UNAVAILABLE", "NO_TFT_SURFACE_VIEW")
        case .unavailable(.multipleTFTSurfaceViews):
            return ("UNAVAILABLE", "MULTIPLE_TFT_SURFACE_VIEWS")
        case .unavailable(.noTimestamps):
            return ("UNAVAILABLE", "NO_TIMESTAMPS")
        case .unavailable(.malformedLatency):
            return ("UNAVAILABLE", "MALFORMED_LATENCY")
        case .unavailable(.adbError):
            return ("UNAVAILABLE", "ADB_ERROR")
        }
    }

    private func execute(_ sql: String, _ values: [SQLiteValue]) throws {
        guard let database else { throw TFTMACRuntimeError("The telemetry database is closed.") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw TFTMACRuntimeError("SQLite could not prepare a telemetry statement.")
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .integer(let value): sqlite3_bind_int64(statement, index, value)
            case .real(let value): sqlite3_bind_double(statement, index, value)
            case .text(let value): sqlite3_bind_text(statement, index, value, -1, transientDestructor)
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TFTMACRuntimeError("SQLite could not write a telemetry record.")
        }
    }

    private func transaction(_ operation: () throws -> Void) throws {
        guard let database else { throw TFTMACRuntimeError("The telemetry database is closed.") }
        guard sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
            throw TFTMACRuntimeError("SQLite could not begin a telemetry transaction.")
        }
        do {
            try operation()
            guard sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK else {
                throw TFTMACRuntimeError("SQLite could not commit a telemetry transaction.")
            }
        } catch {
            sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    private static func utcNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func json(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func jsonArray(_ values: [String]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: values,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

private final class NativeFrameAdmissionState: @unchecked Sendable {
    private let lock = NSLock()
    private let mailbox: LatestFrameMailbox
    private let telemetry: TFTMACNativeTelemetry
    private var previousSequence: UInt32?
    private var admittedFirstFrame = false
    private var windowStartedNS: UInt64?
    private var previousReceivedNS: UInt64?
    private var windowFrameCount = 0
    private var windowSequenceDrops: UInt64 = 0
    private var windowIntervalsNS = [UInt64]()
    private var previousContentFingerprint: UInt64?
    private var freshnessContentChanges = 0
    private var freshnessIdenticalFrames = 0
    private var identicalRunFrames = 0
    private var identicalRunStartedNS: UInt64?
    private var longestIdenticalRunFrames = 0
    private var longestIdenticalRunMS = 0.0

    init(mailbox: LatestFrameMailbox, telemetry: TFTMACNativeTelemetry) {
        self.mailbox = mailbox
        self.telemetry = telemetry
    }

    func admit(_ image: Android_Emulation_Control_Image) throws -> Bool {
        let width = Int(image.format.width == 0 ? image.width : image.format.width)
        let height = Int(image.format.height == 0 ? image.height : image.format.height)
        guard width > 0, height > 0 else { return false }
        guard image.format.format == .rgba8888 else {
            throw TFTMACRuntimeError("The emulator returned a non-RGBA8888 frame.")
        }
        try FrameContract.validate(width: width, height: height, byteCount: image.image.count)

        let receivedNS = DispatchTime.now().uptimeNanoseconds
        let fingerprint = Self.sampledContentFingerprint(image.image)
        lock.lock()
        let sequenceDrops: UInt64
        if let previousSequence, image.seq > previousSequence &+ 1 {
            sequenceDrops = UInt64(image.seq - previousSequence - 1)
        } else {
            sequenceDrops = 0
        }
        previousSequence = image.seq
        let isFirstFrame = !admittedFirstFrame
        admittedFirstFrame = true
        if windowStartedNS == nil { windowStartedNS = receivedNS }
        let priorReceivedNS = previousReceivedNS
        if let priorReceivedNS { windowIntervalsNS.append(receivedNS &- priorReceivedNS) }
        previousReceivedNS = receivedNS
        windowFrameCount += 1
        windowSequenceDrops &+= sequenceDrops
        if let previousContentFingerprint {
            if previousContentFingerprint == fingerprint.value {
                freshnessIdenticalFrames += 1
                identicalRunFrames += 1
                if identicalRunStartedNS == nil { identicalRunStartedNS = priorReceivedNS ?? receivedNS }
                longestIdenticalRunFrames = max(longestIdenticalRunFrames, identicalRunFrames)
                if let runStarted = identicalRunStartedNS {
                    longestIdenticalRunMS = max(longestIdenticalRunMS, Double(receivedNS &- runStarted) / 1_000_000)
                }
            } else {
                freshnessContentChanges += 1
                identicalRunFrames = 1
                identicalRunStartedNS = receivedNS
            }
        } else {
            identicalRunFrames = 1
            identicalRunStartedNS = receivedNS
        }
        previousContentFingerprint = fingerprint.value
        var completedWindow: FrameIntervalWindow?
        var completedFreshnessWindow: StreamFreshnessWindow?
        if let started = windowStartedNS, receivedNS &- started >= 1_000_000_000 {
            let sorted = windowIntervalsNS.sorted()
            let mean = sorted.isEmpty ? nil : Double(sorted.reduce(0, &+)) / Double(sorted.count) / 1_000_000
            let p95Index = sorted.isEmpty ? 0 : min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)
            completedWindow = FrameIntervalWindow(
                startedMonotonicNS: started,
                endedMonotonicNS: receivedNS,
                frameCount: windowFrameCount,
                sequenceDropCount: windowSequenceDrops,
                meanIntervalMS: mean,
                p95IntervalMS: sorted.isEmpty ? nil : Double(sorted[p95Index]) / 1_000_000,
                maximumIntervalMS: sorted.last.map { Double($0) / 1_000_000 }
            )
            completedFreshnessWindow = StreamFreshnessWindow(
                startedMonotonicNS: started,
                endedMonotonicNS: receivedNS,
                receivedFrames: windowFrameCount,
                contentChanges: freshnessContentChanges,
                identicalFrames: freshnessIdenticalFrames,
                longestIdenticalRunFrames: longestIdenticalRunFrames,
                longestIdenticalRunMS: longestIdenticalRunMS,
                sequenceDrops: windowSequenceDrops,
                sampledPixelsPerFrame: fingerprint.sampleCount
            )
            windowStartedNS = receivedNS
            windowFrameCount = 0
            windowSequenceDrops = 0
            windowIntervalsNS.removeAll(keepingCapacity: true)
            freshnessContentChanges = 0
            freshnessIdenticalFrames = 0
            longestIdenticalRunFrames = identicalRunFrames
            longestIdenticalRunMS = 0
        }
        lock.unlock()

        let checkpoint = isFirstFrame || image.seq.isMultiple(of: 60)

        let frame = EmulatorFrame(
            pixels: image.image,
            width: width,
            height: height,
            sequence: image.seq,
            emulatorTimestampMicroseconds: image.timestampUs,
            receivedMonotonicNanoseconds: receivedNS
        )
        mailbox.publish(frame)
        if let completedWindow { telemetry.recordFrameIntervalWindow(completedWindow) }
        if let completedFreshnessWindow { telemetry.recordStreamFreshness(completedFreshnessWindow) }
        guard checkpoint else { return isFirstFrame }
        let visual = Self.sampleVisualContent(image.image, includeHash: true)
        telemetry.recordFrameReceived(frame, transport: "raw_grpc_rgba8888", sequenceDropCount: sequenceDrops, visual: visual)
        let visualPayload: [String: Any] = [
            "visual_sample_count": visual.sampleCount,
            "mean_luma": visual.meanLuma,
            "nonblack_fraction": visual.nonBlackFraction,
            "minimum_rgb": visual.minimumRGB,
            "maximum_rgb": visual.maximumRGB,
            "minimum_alpha": visual.minimumAlpha,
            "maximum_alpha": visual.maximumAlpha,
            "content_sha256": visual.contentSHA256 ?? NSNull()
        ]
        if isFirstFrame {
            var payload: [String: Any] = [
                "width": width, "height": height, "bytes": image.image.count,
                "sequence": image.seq, "bottom_up": true,
                "pixel_format": "RGBA8888",
                "rotation": image.format.rotation.rotation.rawValue
            ]
            payload.merge(visualPayload) { current, _ in current }
            telemetry.recordEvent("FIRST_NATIVE_FRAME", payload: payload)
        } else if checkpoint {
            var payload = visualPayload
            payload["sequence"] = image.seq
            payload["emulator_timestamp_us"] = String(image.timestampUs)
            telemetry.recordEvent("FRAME_VISUAL_CHECKPOINT", payload: payload)
        }
        return isFirstFrame
    }

    private static func sampleVisualContent(_ data: Data, includeHash: Bool) -> FrameVisualSample {
        let pixelCount = data.count / FrameContract.bytesPerPixel
        let step = max(1, pixelCount / 4096)
        var sampleCount = 0
        var lumaSum = 0.0
        var nonBlackCount = 0
        var minimumRGB = 255
        var maximumRGB = 0
        var minimumAlpha = 255
        var maximumAlpha = 0

        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var pixel = 0
            while pixel < pixelCount {
                let offset = pixel * FrameContract.bytesPerPixel
                let red = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let blue = Int(bytes[offset + 2])
                let alpha = Int(bytes[offset + 3])
                minimumRGB = Swift.min(minimumRGB, Swift.min(red, Swift.min(green, blue)))
                maximumRGB = Swift.max(maximumRGB, Swift.max(red, Swift.max(green, blue)))
                minimumAlpha = min(minimumAlpha, alpha)
                maximumAlpha = max(maximumAlpha, alpha)
                lumaSum += (0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)) / 255.0
                if max(red, green, blue) > 4 { nonBlackCount += 1 }
                sampleCount += 1
                pixel += step
            }
        }

        let divisor = Double(max(sampleCount, 1))
        let digest = includeHash
            ? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            : nil
        return FrameVisualSample(
            sampleCount: sampleCount,
            meanLuma: lumaSum / divisor,
            nonBlackFraction: Double(nonBlackCount) / divisor,
            minimumRGB: minimumRGB,
            maximumRGB: maximumRGB,
            minimumAlpha: minimumAlpha,
            maximumAlpha: maximumAlpha,
            contentSHA256: digest
        )
    }

    private static func sampledContentFingerprint(_ data: Data) -> (value: UInt64, sampleCount: Int) {
        let pixelCount = data.count / FrameContract.bytesPerPixel
        let step = max(1, pixelCount / 4096)
        var hash: UInt64 = 1_469_598_103_934_665_603
        var sampleCount = 0
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var pixel = 0
            while pixel < pixelCount {
                let offset = pixel * FrameContract.bytesPerPixel
                hash ^= UInt64(bytes[offset])
                hash &*= 1_099_511_628_211
                hash ^= UInt64(bytes[offset + 1]) << 8
                hash &*= 1_099_511_628_211
                hash ^= UInt64(bytes[offset + 2]) << 16
                hash &*= 1_099_511_628_211
                hash ^= UInt64(bytes[offset + 3]) << 24
                hash &*= 1_099_511_628_211
                sampleCount += 1
                pixel += step
            }
        }
        return (hash, sampleCount)
    }
}

actor TFTMACRuntimeService {
    typealias StatusHandler = @MainActor @Sendable (String, Bool) -> Void
    typealias GameFrameHandler = @MainActor @Sendable (GameFrameTelemetryWindow?) -> Void

    private let profile: TFTMACRuntimeProfile
    private let mailbox: LatestFrameMailbox
    private let status: StatusHandler
    private let gameFrame: GameFrameHandler
    private var telemetry: TFTMACNativeTelemetry?
    private var labStore: CombatBenchmarkLabStore?
    private var paths: TFTMACRuntimePaths?
    private var openProcess: Process?
    private var logcatProcess: Process?
    private var logcatOutputHandle: FileHandle?
    private var logcatErrorHandle: FileHandle?
    private var logcatReadOffset: UInt64 = 0
    private var emulatorStdoutReadOffset: UInt64 = 0
    private var emulatorStderrReadOffset: UInt64 = 0
    private var runtimeLease: TFTMACRuntimeLease?
    private var expectedSessionMarker: String?
    private var discovery: EmulatorControllerDiscovery?
    private var inputContinuation: AsyncStream<EmulatorInput>.Continuation?
    private var avdTransaction: AVDConfigurationTransaction?
    private var traceCaptureInProgress = false
    private var traceCaptureTask: Task<Void, Never>?
    private var traceCaptureMeasurementStartNS: UInt64?
    private var traceCaptureMeasurementEndNS: UInt64?
    private var traceCaptureCount = 0
    private var automaticTraceCount = 0
    private var incidentTraceCount = 0
    private var lastAutomaticTraceNS: UInt64 = 0
    private var currentGamePID: Int32?
    private var currentExactLayerName: String?
    private var consecutiveBadGraphicsWindows = 0
    private var graphicsAutomaticTraceCount = 0
    private var graphicsIncidentTraceCount = 0
    private var lastGraphicsAutomaticTraceNS: UInt64 = 0
    private var activeCombatBenchmark: ActiveCombatBenchmark?
    private var benchmarkDeadlineTask: Task<Void, Never>?
    private var latestGameFrameWindow: GameFrameTelemetryWindow?
    private var tftPackageVersion = "unknown"
    private var stopping = false

    init(
        profile: TFTMACRuntimeProfile,
        mailbox: LatestFrameMailbox,
        status: @escaping StatusHandler,
        gameFrame: @escaping GameFrameHandler
    ) {
        self.profile = profile
        self.mailbox = mailbox
        self.status = status
        self.gameFrame = gameFrame
    }

    func run() async throws {
        let applicationSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TFTMAC", isDirectory: true)
        let telemetry = try TFTMACNativeTelemetry(profile: profile, applicationSupport: applicationSupport)
        self.telemetry = telemetry
        labStore = try CombatBenchmarkLabStore(applicationSupport: applicationSupport)
        await status("Starting Android through the native Mac app host…", false)

        do {
            let paths = try TFTMACRuntimePaths.discover()
            self.paths = paths
            let stateRoot = paths.applicationSupport.appendingPathComponent("State", isDirectory: true)
            runtimeLease = try TFTMACRuntimeLease.acquire(stateRoot: stateRoot)
            telemetry.recordEvent("RUNTIME_LEASE_ACQUIRED", payload: [
                "lease": "State/native-runtime.lease",
                "pid": ProcessInfo.processInfo.processIdentifier,
                "exclusive": true
            ])
            try assertRuntimeUnoccupied(telemetry: telemetry)
            try recoverInterruptedAVDTransaction(paths: paths)
            recordFrozenReceipts(telemetry: telemetry, paths: paths)
            avdTransaction = try prepareAVD(paths: paths, telemetry: telemetry)
            try startADBServer(paths: paths, telemetry: telemetry)
            let launchStarted = Date()
            try launchEmulatorHost(paths: paths, telemetry: telemetry)
            let discovery = try await waitForDiscovery(paths: paths, captureDirectory: telemetry.captureDirectory, after: launchStarted)
            self.discovery = discovery
            telemetry.recordEvent("EMULATOR_CONTROLLER_DISCOVERED", payload: [
                "pid": discovery.processIdentifier,
                "grpc_port": discovery.port,
                "record": discovery.recordPath,
                "token_persisted": false
            ])
            try recordHostSchedulingReceipt(telemetry: telemetry)

            let (inputStream, continuation) = AsyncStream.makeStream(of: EmulatorInput.self, bufferingPolicy: .bufferingNewest(256))
            inputContinuation = continuation
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { [profile, mailbox] in
                    try await Self.runController(
                        discovery: discovery,
                        profile: profile,
                        mailbox: mailbox,
                        telemetry: telemetry,
                        inputStream: inputStream,
                        status: self.status
                    )
                }
                group.addTask {
                    try await self.waitForBootAndLaunchGame(paths: paths, telemetry: telemetry)
                }
                group.addTask {
                    try await self.sampleRuntime(paths: paths, telemetry: telemetry, emulatorPID: discovery.processIdentifier)
                }
                group.addTask {
                    try await self.sampleGameFrames(paths: paths, telemetry: telemetry)
                }
                _ = try await group.next()
                group.cancelAll()
            }
            if !stopping { throw TFTMACRuntimeError("The native emulator session ended unexpectedly.") }
        } catch {
            if stopping || error is CancellationError {
                telemetry.recordEvent("RUNTIME_STOP_REQUESTED", payload: ["reason": "application_termination"])
                await cleanup(status: "STOPPED")
                return
            }
            telemetry.recordEvent("RUNTIME_FAILED", payload: [
                "error": error.localizedDescription,
                "diagnostic": String(describing: error),
                "type": String(reflecting: type(of: error))
            ])
            if profile.experimentPreset.isActiveCandidate {
                recordCorrectnessRejection(reason: error.localizedDescription)
                TFTMACRuntimeProfile.playable.with(experimentPreset: .control).save()
                telemetry.recordEvent("EXPERIMENT_AUTO_ROLLBACK", payload: [
                    "failed_preset": profile.experimentPreset.rawValue,
                    "restored_preset": RuntimeExperimentPreset.control.rawValue,
                    "classification": "REJECTED_CORRECTNESS",
                    "applies_after_restart": true
                ])
            }
            await cleanup(status: stopping ? "STOPPED" : "FAILED")
            if !stopping { await status(error.localizedDescription, true) }
            throw error
        }
        await cleanup(status: "STOPPED")
    }

    func sendMouse(_ input: MouseInput) {
        telemetry?.recordInput(.mouse(input))
        inputContinuation?.yield(.mouse(input))
    }

    func sendTouch(_ input: TouchInput) {
        telemetry?.recordInput(.touch(input))
        inputContinuation?.yield(.touch(input))
    }

    func sendKeyboard(_ input: KeyboardInput) {
        telemetry?.recordInput(.keyboard(input))
        inputContinuation?.yield(.keyboard(input))
    }

    func recordPresentation(_ sample: PresentationSample) {
        telemetry?.recordPresentation(sample)
    }

    func recordHostPresentation(_ sample: HostPresentationWindow) {
        telemetry?.recordHostPresentation(sample)
    }

    func startCombatBenchmark(performanceModeConfirmed: Bool) {
        guard activeCombatBenchmark == nil else {
            telemetry?.recordEvent("COMBAT_BENCHMARK_START_REJECTED", payload: ["reason": "ALREADY_RUNNING"])
            return
        }
        guard let telemetry, let paths, discovery != nil else { return }
        if profile.experimentPreset.requiresManualPerformanceModeBetaConfirmation,
           !performanceModeConfirmed {
            telemetry.recordEvent("COMBAT_BENCHMARK_START_REJECTED", payload: [
                "reason": "PERFORMANCE_MODE_BETA_NOT_CONFIRMED",
                "preset_id": profile.experimentPreset.rawValue
            ])
            return
        }

        let nowNS = DispatchTime.now().uptimeNanoseconds
        let receipt = profile.experimentConfigurationReceipt
        activeCombatBenchmark = ActiveCombatBenchmark(
            benchmarkID: UUID().uuidString.lowercased(),
            sessionID: telemetry.sessionIdentifier,
            presetID: profile.experimentPreset,
            configurationSHA256: receipt.sha256,
            comparisonIdentitySHA256: profile.comparisonConfigurationSHA256,
            configurationJSON: receipt.canonicalJSON,
            tftPackageVersion: tftPackageVersion,
            performanceModeConfirmed: performanceModeConfirmed,
            startedUTC: Self.utcNow(),
            startedMonotonicNS: nowNS
        )
        if let active = activeCombatBenchmark {
            let placeholder = active.finish(endedUTC: active.startedUTC, endedMonotonicNS: nowNS)
            telemetry.recordCombatBenchmark(placeholder)
            try? labStore?.record(placeholder)
        }
        automaticTraceCount = 0
        incidentTraceCount = 0
        lastAutomaticTraceNS = 0
        recordClockSync(paths: paths, telemetry: telemetry)
        recordDiagnosticSnapshot(paths: paths, telemetry: telemetry, label: "combat_benchmark_start")
        recordGraphicsPipelineSnapshot(paths: paths, telemetry: telemetry, label: "combat_benchmark_start")
        telemetry.recordEvent("COMBAT_BENCHMARK_STARTED", payload: [
            "benchmark_id": activeCombatBenchmark?.benchmarkID ?? "unknown",
            "preset_id": profile.experimentPreset.rawValue,
            "configuration_sha256": receipt.sha256,
            "performance_mode_beta_confirmed": performanceModeConfirmed,
            "minimum_valid_seconds": 300,
            "automatic_close_seconds": 480,
            "combat_only_trace_budget": 3
        ])
        requestDiagnosticTrace(
            scope: .combatBenchmark,
            trigger: "COMBAT_BENCHMARK_START",
            automatic: false,
            durationSeconds: 20,
            bufferMiB: 32,
            benchmarkStartTrace: true
        )
        benchmarkDeadlineTask?.cancel()
        benchmarkDeadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(480))
            guard !Task.isCancelled else { return }
            await self?.endCombatBenchmark(reason: "AUTOMATIC_EIGHT_MINUTE_CLOSE")
        }
    }

    func markVisibleStutter() {
        guard let telemetry else { return }
        guard currentGamePID != nil, currentExactLayerName != nil else {
            telemetry.recordEvent("VISIBLE_STUTTER_IGNORED", payload: ["reason": "NO_ACTIVE_TFT_GRAPHICS_RUN"])
            return
        }
        let active = activeCombatBenchmark
        telemetry.recordEvent("VISIBLE_STUTTER", payload: [
            "benchmark_id": active?.benchmarkID ?? NSNull(),
            "preset_id": active?.presetID.rawValue ?? profile.experimentPreset.rawValue,
            "graphics_logger_automatic": true,
            "host_monotonic_timestamp": true
        ])
        let traceSequence = requestDiagnosticTrace(
            scope: active == nil ? .automaticGraphics : .combatBenchmark,
            trigger: "VISIBLE_STUTTER",
            automatic: false,
            durationSeconds: 15,
            bufferMiB: 32,
            benchmarkStartTrace: false
        )
        recordGraphicsPipelineIncident(
            trigger: "VISIBLE_STUTTER",
            window: latestGameFrameWindow,
            traceSequence: traceSequence
        )
        recordCombatIncident(
            trigger: "VISIBLE_STUTTER",
            window: latestGameFrameWindow,
            traceSequence: traceSequence
        )
    }

    func endCombatBenchmark(
        reason: String = "USER_ENDED",
        correctnessPassed: Bool = true
    ) {
        guard var active = activeCombatBenchmark, let telemetry else { return }
        benchmarkDeadlineTask?.cancel()
        benchmarkDeadlineTask = nil
        if let paths {
            recordClockSync(paths: paths, telemetry: telemetry)
            recordDiagnosticSnapshot(paths: paths, telemetry: telemetry, label: "combat_benchmark_end")
            recordGraphicsPipelineSnapshot(paths: paths, telemetry: telemetry, label: "combat_benchmark_end")
        }
        if let refreshed = activeCombatBenchmark { active = refreshed }
        let endedNS = DispatchTime.now().uptimeNanoseconds
        let run = active.finish(
            endedUTC: Self.utcNow(),
            endedMonotonicNS: endedNS,
            correctnessPassed: correctnessPassed
        )
        activeCombatBenchmark = nil
        telemetry.recordCombatBenchmark(run)
        telemetry.recordEvent("COMBAT_BENCHMARK_ENDED", payload: [
            "benchmark_id": run.benchmarkID,
            "reason": reason,
            "preset_id": run.presetID.rawValue,
            "duration_seconds": run.metrics.combatDurationSeconds,
            "surface_availability": run.metrics.surfaceAvailability,
            "clock_coverage": run.metrics.clockCoverage,
            "weighted_fps": run.metrics.weightedFPS,
            "one_percent_low_fps": run.metrics.onePercentLowFPS,
            "p95_interval_ms": run.metrics.p95IntervalMilliseconds,
            "p99_interval_ms": run.metrics.p99IntervalMilliseconds,
            "correctness_passed": run.metrics.correctnessPassed,
            "valid": run.isValid,
            "invalid_reason": run.invalidReason ?? NSNull(),
            "observer_overhead_invalid": run.observerOverheadInvalid
        ])
        var comparisonDecision: CombatBenchmarkDecision?
        do {
            try labStore?.record(run)
            if let comparison = try labStore?.comparisonForCandidate(run) {
                comparisonDecision = comparison.analysis.decision
                telemetry.recordCombatComparison(comparison)
                telemetry.recordEvent("COMBAT_COMPARISON_READY", payload: [
                    "comparison_id": comparison.comparisonID,
                    "control_benchmark_id": comparison.controlBenchmarkID,
                    "candidate_benchmark_id": comparison.candidateBenchmarkID,
                    "decision": comparison.analysis.decision.rawValue,
                    "weighted_fps_delta_percent": comparison.analysis.deltas.weightedFPSPercent,
                    "one_percent_low_delta_percent": comparison.analysis.deltas.onePercentLowFPSPercent,
                    "p95_delta_percent": comparison.analysis.deltas.p95IntervalPercent,
                    "p99_delta_percent": comparison.analysis.deltas.p99IntervalPercent,
                    "observer_overhead_invalid": comparison.observerOverheadInvalid
                ])
            }
        } catch {
            telemetry.recordEvent("COMBAT_LAB_PERSISTENCE_FAILED", payload: ["error": error.localizedDescription])
        }
        if run.presetID.isActiveCandidate,
           comparisonDecision != .homeRun,
           comparisonDecision != .promising {
            TFTMACRuntimeProfile.playable.with(experimentPreset: .control).save()
            let classification: String
            if !run.metrics.correctnessPassed {
                classification = "REJECTED_CORRECTNESS"
            } else {
                classification = comparisonDecision?.rawValue ?? "INCONCLUSIVE_NO_MATCHING_CONTROL"
            }
            telemetry.recordEvent("EXPERIMENT_AUTO_ROLLBACK", payload: [
                "failed_preset": run.presetID.rawValue,
                "restored_preset": RuntimeExperimentPreset.control.rawValue,
                "classification": classification,
                "applies_after_restart": true
            ])
        }
    }

    func recordMarker(_ marker: String) {
        let allowed = ["MATCH_ENTRY", "MATCH_END"]
        guard allowed.contains(marker) else { return }
        telemetry?.recordEvent(marker, payload: [
            "source": "native_menu",
            "profile_id": profile.identifier,
            "host_monotonic_timestamp": true
        ])
    }

    func recordSettingsChange(previous: TFTMACRuntimeProfile, next: TFTMACRuntimeProfile) {
        telemetry?.recordEvent("NEXT_LAUNCH_PROFILE_SAVED", payload: [
            "active_profile_id": profile.identifier,
            "previous_saved_profile_id": previous.identifier,
            "next_profile_id": next.identifier,
            "next_vcpu": next.vCPU,
            "next_ram_mib": next.ramMiB,
            "next_refresh_hz": next.refreshHz,
            "next_asg_draw_flush_interval": next.asgDrawFlushInterval,
            "applies_after_restart": true
        ])
    }

    func stop() async {
        guard !stopping else { return }
        stopping = true
        if activeCombatBenchmark != nil { endCombatBenchmark(reason: "APPLICATION_STOP") }
        await status("Sealing SQL telemetry and stopping Android…", false)
        inputContinuation?.finish()
        if let paths,
           let ownedPID = discovery?.processIdentifier,
           Self.processMatchesLaunchedIdentity(ownedPID, sessionMarker: expectedSessionMarker) {
            telemetry?.recordEvent("EMULATOR_STOP_SIGNAL_SENT", payload: [
                "pid": ownedPID,
                "serial": "emulator-5582",
                "method": "adb emu kill",
                "ownership_verified": true
            ])
            _ = try? Self.runCommand(
                paths.adb,
                ["-P", "5038", "-s", "emulator-5582", "emu", "kill"],
                environment: Self.adbEnvironment(paths: paths),
                timeout: 15
            )
        }
    }

    private func cleanup(status finalStatus: String) async {
        inputContinuation?.finish()
        inputContinuation = nil
        var emulatorExitConfirmed = true
        if let paths {
            let ownedPID = discovery?.processIdentifier ?? expectedSessionMarker.flatMap(Self.findOwnedEmulatorPID)
            let ownedProcessExists = ownedPID.map(Self.processExists) ?? false
            let ownsRunningEmulator = ownedPID.map {
                ownedProcessExists && Self.processMatchesLaunchedIdentity($0, sessionMarker: expectedSessionMarker)
            } ?? false
            if ownsRunningEmulator {
                recordDiagnosticSnapshot(paths: paths, telemetry: telemetry, label: "session_end")
                if let telemetry {
                    recordGraphicsPipelineSnapshot(paths: paths, telemetry: telemetry, label: "session_end")
                }
            }
            telemetry?.endGraphicsRun(reason: "APPLICATION_STOP")
            currentGamePID = nil
            currentExactLayerName = nil
            stopLogcatCapture()
            if let ownedPID, ownsRunningEmulator {
                _ = try? Self.runCommand(
                    paths.adb,
                    ["-P", "5038", "-s", "emulator-5582", "emu", "kill"],
                    environment: Self.adbEnvironment(paths: paths),
                    timeout: 15
                )
                emulatorExitConfirmed = await waitForOwnedEmulatorExit(ownedPID)
            } else if let ownedPID, ownedProcessExists {
                emulatorExitConfirmed = false
                telemetry?.recordEvent("EMULATOR_KILL_WITHHELD", payload: [
                    "pid": ownedPID,
                    "reason": "process no longer matches this session ownership marker"
                ])
            } else if ownedPID != nil {
                emulatorExitConfirmed = true
            }
            telemetry?.recordEvent(
                emulatorExitConfirmed ? "EMULATOR_EXIT_CONFIRMED" : "EMULATOR_EXIT_TIMEOUT",
                payload: ["pid": ownedPID ?? 0, "serial": "emulator-5582", "owned": ownsRunningEmulator]
            )
        }
        if openProcess?.isRunning == true { openProcess?.terminate() }
        openProcess = nil
        var avdRestoreConfirmed = avdTransaction == nil
        if let transaction = avdTransaction {
            do {
                guard emulatorExitConfirmed else {
                    throw TFTMACRuntimeError("AVD restore was withheld because the emulator exit was not confirmed.")
                }
                guard !Self.anyEmulatorUsingSharedAVD() else {
                    throw TFTMACRuntimeError("AVD restore was withheld because another TFT_Ultra_Tablet process is active.")
                }
                try transaction.restore()
                avdRestoreConfirmed = true
                telemetry?.recordEvent("AVD_CONFIG_RESTORED", payload: ["sha256": transaction.originalSHA256])
            } catch {
                telemetry?.recordEvent("AVD_CONFIG_RESTORE_FAILED", payload: ["error": error.localizedDescription])
            }
        }
        avdTransaction = nil
        if let traceCaptureTask {
            await traceCaptureTask.value
            self.traceCaptureTask = nil
        }
        let sealedStatus = finalStatus == "STOPPED" && emulatorExitConfirmed && avdRestoreConfirmed ? "STOPPED" : "FAILED"
        telemetry?.finish(status: sealedStatus)
        runtimeLease?.release()
        runtimeLease = nil
        await status(sealedStatus == "STOPPED" ? "TFTMAC stopped cleanly." : "TFTMAC needs attention.", sealedStatus == "FAILED")
    }

    private func startLogcatCapture(paths: TFTMACRuntimePaths, telemetry: TFTMACNativeTelemetry) throws {
        guard logcatProcess == nil else { return }
        let outputURL = telemetry.captureDirectory.appendingPathComponent("logcat.raw.txt")
        let errorURL = telemetry.captureDirectory.appendingPathComponent("logcat.stderr.log")
        let sessionStartSelector = try Self.adb(
            paths: paths,
            ["shell", "date '+%m-%d %H:%M:%S.%3N'"],
            timeout: 10
        ).output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.firstRegexText("^([0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3})$", in: sessionStartSelector) != nil else {
            throw TFTMACRuntimeError("Android did not provide a valid session boundary for local logcat capture.")
        }
        FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        FileManager.default.createFile(atPath: errorURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        let process = Process()
        process.executableURL = paths.adb
        process.arguments = ["-P", "5038", "-s", "emulator-5582", "logcat", "-v", "threadtime", "-T", sessionStartSelector]
        process.environment = Self.adbEnvironment(paths: paths)
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        do {
            try process.run()
        } catch {
            try? outputHandle.close()
            try? errorHandle.close()
            throw error
        }
        logcatProcess = process
        logcatOutputHandle = outputHandle
        logcatErrorHandle = errorHandle
        logcatReadOffset = 0
        telemetry.recordEvent("LOGCAT_CAPTURE_STARTED", payload: [
            "format": "threadtime",
            "raw_file": outputURL.lastPathComponent,
            "stderr_file": errorURL.lastPathComponent,
            "raw_content_local_only": true,
            "raw_content_sensitive": true,
            "raw_content_excluded_from_sql": true,
            "session_start_selector": sessionStartSelector,
            "initial_backlog_lines_requested": 0,
            "process_pid": process.processIdentifier
        ])
    }

    private func stopLogcatCapture() {
        guard let process = logcatProcess else { return }
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        try? logcatOutputHandle?.synchronize()
        try? logcatErrorHandle?.synchronize()
        try? logcatOutputHandle?.close()
        try? logcatErrorHandle?.close()
        telemetry?.recordEvent("LOGCAT_CAPTURE_STOPPED", payload: [
            "termination_status": process.terminationStatus,
            "final_read_offset": String(logcatReadOffset)
        ])
        logcatProcess = nil
        logcatOutputHandle = nil
        logcatErrorHandle = nil
    }

    private func waitForOwnedEmulatorExit(_ processIdentifier: Int32) async -> Bool {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if !Self.processExists(processIdentifier) { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    private func assertRuntimeUnoccupied(telemetry: TFTMACNativeTelemetry) throws {
        let processOutput = (try? Self.runCommand(
            URL(fileURLWithPath: "/bin/ps"),
            ["-axo", "pid=,command="],
            timeout: 10
        ).output) ?? ""
        let emulatorConflicts = processOutput.split(whereSeparator: \.isNewline).filter { line in
            line.contains("qemu-system-aarch64")
                && (line.contains("@TFT_Ultra_Tablet") || line.contains("-port 5582") || line.contains("-grpc 8554"))
        }
        let listenerOutput = (try? Self.runCommand(
            URL(fileURLWithPath: "/usr/sbin/lsof"),
            ["-nP", "-iTCP:5582", "-iTCP:8554", "-sTCP:LISTEN"],
            timeout: 10
        ).output) ?? ""
        let listeners = listenerOutput.split(whereSeparator: \.isNewline).dropFirst()
        guard emulatorConflicts.isEmpty && listeners.isEmpty else {
            throw TFTMACRuntimeError("The shared TFT_Ultra_Tablet runtime or ports 5582/8554 are already in use. Close the existing emulator before launching TFTMAC.")
        }
        telemetry.recordEvent("RUNTIME_OWNERSHIP_PREFLIGHT_PASSED", payload: [
            "avd": "TFT_Ultra_Tablet",
            "console_port": 5582,
            "controller_port": 8554,
            "existing_emulator_count": 0,
            "existing_listener_count": 0
        ])
    }

    private func recordFrozenReceipts(telemetry: TFTMACNativeTelemetry, paths: TFTMACRuntimePaths) {
        let experimentReceipt = profile.experimentConfigurationReceipt
        let receipts: [(String, String, String, String)] = [
            ("engine", "Unreal Engine", "user_locked_fact", "LOCKED"),
            ("runtime_profile_id", profile.identifier, "validated native preferences", "DIRECT"),
            ("runtime_experiment_preset", profile.experimentPreset.rawValue, "named launch experiment", "DIRECT"),
            ("runtime_configuration_sha256", experimentReceipt.sha256, "canonical effective configuration", "DIRECT"),
            ("runtime_configuration_json", experimentReceipt.canonicalJSON, "canonical effective configuration", "DIRECT"),
            ("launcher_method", "/usr/bin/open -n -W --env ... --args ...", "Mactician donor architecture", "DIRECT"),
            ("macos_game_mode_eligible", "true", "LSSupportsGameMode bundle contract", "DIRECT"),
            ("host_qos_requested", profile.experimentPreset.requestsHostLatencyQoS ? "user_interactive" : "default", "named launch experiment", "REQUESTED"),
            ("adb_server_port", "5038", "known-good donor", "DIRECT"),
            ("emulator_console_port", "5582", "known-good donor", "DIRECT"),
            ("adb_serial", "emulator-5582", "known-good donor", "DIRECT"),
            ("controller_port", "\(profile.controllerPort)", "native authenticated controller", "REQUESTED"),
            ("adb_vendor_keys", "ABSENT", "launch environment contract", "DIRECT"),
            ("avd", "TFT_Ultra_Tablet", "installed runtime", "DIRECT"),
            ("resolution", "\(profile.width)x\(profile.height)", "5 GiB gameplay evidence", "DIRECT"),
            ("density_dpi", "\(profile.densityDPI)", "5 GiB gameplay evidence", "DIRECT"),
            ("refresh_hz", "\(profile.refreshHz)", "5 GiB gameplay evidence", "DIRECT"),
            ("vcpu", "\(profile.vCPU)", "5 GiB gameplay evidence", "DIRECT"),
            ("ram_mib", "\(profile.ramMiB)", "latest retained 5 GiB runs", "STRONG"),
            ("gpu_mode", profile.gpuMode, "playable baseline", "DIRECT"),
            ("audio_backend", profile.audioBackend, "audio health receipt", "DIRECT"),
            ("graphics_transport_requested", profile.graphicsTransport, "playable baseline", "REQUESTED"),
            ("emulator_features_requested", profile.effectiveEmulatorFeatures.joined(separator: ","), "named launch experiment", "REQUESTED"),
            ("asg_write_buffer_size", "\(profile.asgWriteBufferSize)", "playable baseline", "REQUESTED"),
            ("asg_write_step_size", "\(profile.asgWriteStepSize)", "playable baseline", "REQUESTED"),
            ("asg_data_ring_size", "\(profile.asgDataRingSize)", "playable baseline", "REQUESTED"),
            ("asg_draw_flush_interval_us", "\(profile.asgDrawFlushInterval)", "playable baseline", "REQUESTED"),
            ("angle_enabled_requested", profile.angleEnabledFeatures, "playable baseline", "REQUESTED"),
            ("angle_disabled_requested", profile.angleDisabledFeatures, "playable baseline", "REQUESTED"),
            ("frame_transport", "raw_grpc_rgba8888", "native admission path", "DIRECT"),
            ("raw_logcat_policy", "LOCAL_SENSITIVE_SESSION_SCOPED_NOT_FOR_SHARING", "privacy contract", "LOCKED"),
            ("sdk_root", paths.sdkRoot.path, "filesystem discovery", "DIRECT")
        ]
        for receipt in receipts {
            telemetry.recordReceipt(key: receipt.0, value: receipt.1, source: receipt.2, confidence: receipt.3)
        }
    }

    private func startADBServer(paths: TFTMACRuntimePaths, telemetry: TFTMACNativeTelemetry) throws {
        let result = try Self.runCommand(
            paths.adb,
            ["-P", "5038", "start-server"],
            environment: Self.adbEnvironment(paths: paths),
            timeout: 30
        )
        guard result.status == 0 else {
            throw TFTMACRuntimeError("ADB server 5038 could not start: \(result.output.suffix(1200))")
        }
        telemetry.recordEvent("ADB_SERVER_STARTED", payload: [
            "port": 5038,
            "serial": "emulator-5582",
            "adb_vendor_keys_present": false,
            "output": result.output.suffix(2000).description
        ])
    }

    private func launchEmulatorHost(paths: TFTMACRuntimePaths, telemetry: TFTMACNativeTelemetry) throws {
        let stdout = telemetry.captureDirectory.appendingPathComponent("emulator.stdout.log")
        let stderr = telemetry.captureDirectory.appendingPathComponent("emulator.stderr.log")
        FileManager.default.createFile(atPath: stdout.path, contents: nil)
        FileManager.default.createFile(atPath: stderr.path, contents: nil)
        for root in Self.controllerDiscoveryRoots(paths: paths) {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        expectedSessionMarker = "androidboot.tftmac.session=\(telemetry.sessionIdentifier)"
        var arguments = [
            "-n", "-W",
            "--env", "TFT_EMULATOR=\(paths.emulator.path)",
            "--env", "TFT_ADB_SERVER_PORT=5038",
            "--env", "ANDROID_ADB_SERVER_PORT=5038",
            "--env", "ADB_MDNS_AUTO_CONNECT=",
            "--env", "ADB_SERVER_SOCKET=",
            "--env", "ANDROID_ADB_SERVER_ADDRESS=",
            "--env", "ANDROID_SDK_ROOT=\(paths.sdkRoot.path)",
            "--env", "ANDROID_AVD_HOME=\(paths.avdHome.path)",
            "--env", "ANDROID_EMULATOR_USE_SYSTEM_LIBS=0",
            "--env", "ANGLE_FEATURE_OVERRIDES_ENABLED=\(profile.angleEnabledFeatures)",
            "--env", "ANGLE_FEATURE_OVERRIDES_DISABLED=\(profile.angleDisabledFeatures)",
            "--env", "MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=0",
            "--env", "MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE=64",
            "--env", "MVK_CONFIG_FAST_MATH_ENABLED=1",
            "--env", "TFT_HOST_LATENCY_QOS=\(profile.experimentPreset.requestsHostLatencyQoS ? "user_interactive" : "default")",
            "--env", "TFT_HOST_STDOUT=\(stdout.path)",
            "--env", "TFT_HOST_STDERR=\(stderr.path)",
            paths.hostApplication.path,
            "--args",
            "@TFT_Ultra_Tablet", "-id", "TFTMAC", "-port", "5582",
            "-gpu", profile.gpuMode, "-audio", profile.audioBackend,
            "-feature", profile.effectiveEmulatorFeatures.joined(separator: ","),
            "-append-userspace-opt", "androidboot.opengles.version=196610",
            "-append-userspace-opt", "androidboot.tftmac.graphics_profile=tftmac",
            "-append-userspace-opt", expectedSessionMarker!,
            "-skin", "\(profile.width)x\(profile.height)",
            "-vsync-rate", "\(profile.refreshHz)",
            "-dns-server", "1.1.1.1,8.8.8.8",
            "-cores", "\(profile.vCPU)", "-memory", "\(profile.ramMiB)",
            "-no-hidpi-scaling", "-no-snapshot", "-no-metrics", "-no-boot-anim",
            "-crash-report-mode", "disabled", "-qt-hide-window",
            "-grpc", "\(profile.controllerPort)", "-grpc-use-token",
            "-idle-grpc-timeout", "300"
        ]
        if let zone = TimeZone.current.identifier.addingPercentEncoding(withAllowedCharacters: .alphanumerics), !zone.isEmpty {
            arguments += ["-timezone", TimeZone.current.identifier]
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "ADB_VENDOR_KEYS")
        process.environment = environment
        try process.run()
        openProcess = process
        telemetry.recordEvent("EMULATOR_HOST_LAUNCHED", payload: [
            "method": "/usr/bin/open",
            "flags": ["-n", "-W", "--env", "--args"],
            "host_application": paths.hostApplication.path,
            "open_pid": process.processIdentifier,
            "adb_vendor_keys_present": false,
            "game_mode_eligible": true,
            "host_qos_requested": profile.experimentPreset.requestsHostLatencyQoS ? "user_interactive" : "default",
            "controller_discovery_roots": Self.controllerDiscoveryRoots(paths: paths).map(\.path),
            "emulator_arguments": Array(arguments.suffix(from: arguments.firstIndex(of: "--args") ?? arguments.startIndex).dropFirst())
        ])
    }

    private func recordHostSchedulingReceipt(telemetry: TFTMACNativeTelemetry) throws {
        let outputURL = telemetry.captureDirectory.appendingPathComponent("emulator.stdout.log")
        guard let output = try? String(contentsOf: outputURL, encoding: .utf8),
              let receipt = HostSchedulingReceipt.parse(output) else {
            throw TFTMACRuntimeError("The emulator host did not publish its macOS scheduling receipt.")
        }
        telemetry.recordReceipt(
            key: "host_qos_pre_exec_effective",
            value: receipt.effective,
            source: "pthread_get_qos_class_np before emulator exec",
            confidence: "DIRECT"
        )
        telemetry.recordReceipt(
            key: "host_qos_set_result",
            value: "\(receipt.setResult)",
            source: "pthread_set_qos_class_self_np",
            confidence: "DIRECT"
        )
        telemetry.recordEvent("HOST_SCHEDULING_RECEIPT", payload: [
            "requested": receipt.requested,
            "set_result": receipt.setResult,
            "pre_exec_effective": receipt.effective,
            "relative_priority": receipt.relativePriority,
            "qemu_child_thread_inheritance": "NOT_CLAIMED_WITHOUT_COMBAT_EVIDENCE"
        ])
        if profile.experimentPreset.requestsHostLatencyQoS, !receipt.userInteractiveVerified {
            throw TFTMACRuntimeError(
                "Combat Latency A could not establish user-interactive scheduling at the emulator launch boundary."
            )
        }
    }

    private func waitForDiscovery(paths: TFTMACRuntimePaths, captureDirectory: URL, after launchStarted: Date) async throws -> EmulatorControllerDiscovery {
        let logURL = captureDirectory.appendingPathComponent("emulator.stdout.log")
        let deadline = Date().addingTimeInterval(90)
        var candidates = [URL]()
        while Date() < deadline {
            try Task.checkCancellation()
            if let log = try? String(contentsOf: logURL, encoding: .utf8) {
                for line in log.split(whereSeparator: \.isNewline) {
                    guard let range = line.range(of: "Advertising in:") else { continue }
                    let path = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                    if !path.isEmpty {
                        let candidate = URL(fileURLWithPath: path)
                        if !candidates.contains(candidate) { candidates.append(candidate) }
                    }
                }
            }
            for root in Self.controllerDiscoveryRoots(paths: paths) {
                if let files = try? FileManager.default.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for file in files where file.lastPathComponent.hasPrefix("pid_") && file.pathExtension == "ini" {
                        if !candidates.contains(file) { candidates.append(file) }
                    }
                }
            }
            for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
                let modified = try? candidate.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                guard modified == nil || modified! >= launchStarted.addingTimeInterval(-2) else { continue }
                guard let text = try? String(contentsOf: candidate, encoding: .utf8) else { continue }
                let values = Self.parseINI(text)
                guard let rawPort = values["grpc.port"], let port = Int(rawPort), port > 0,
                      let token = values["grpc.token"], !token.isEmpty else { continue }
                let name = candidate.deletingPathExtension().lastPathComponent
                let pidText = name.dropFirst("pid_".count).prefix(while: \.isNumber)
                guard let pid = Int32(pidText), Self.processMatchesLaunchedIdentity(pid, sessionMarker: expectedSessionMarker) else { continue }
                return EmulatorControllerDiscovery(processIdentifier: pid, port: port, token: token, recordPath: candidate.path)
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw TFTMACRuntimeError("The emulator did not publish its authenticated controller endpoint.")
    }

    private func waitForBootAndLaunchGame(paths: TFTMACRuntimePaths, telemetry: TFTMACNativeTelemetry) async throws {
        await status("Waiting for the proven ADB identity on emulator-5582…", false)
        var lastState = "missing"
        var previouslyLoggedState: String?
        while !stopping {
            try Task.checkCancellation()
            let result = try? Self.runCommand(
                paths.adb,
                ["-P", "5038", "-s", "emulator-5582", "get-state"],
                environment: Self.adbEnvironment(paths: paths),
                timeout: 10
            )
            let diagnostic = result?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if result?.status == 0 && diagnostic == "device" {
                lastState = "device"
            } else if diagnostic.localizedCaseInsensitiveContains("unauthorized") {
                lastState = "unauthorized"
            } else if diagnostic.localizedCaseInsensitiveContains("offline") {
                lastState = "offline"
            } else {
                lastState = "missing"
            }
            if lastState != previouslyLoggedState {
                telemetry.recordEvent("ADB_STATE_CHANGED", payload: [
                    "previous_state": previouslyLoggedState ?? "none",
                    "current_state": lastState,
                    "serial": "emulator-5582",
                    "diagnostic": String(diagnostic.prefix(800))
                ])
                if lastState == "unauthorized" {
                    telemetry.recordEvent("ADB_UNAUTHORIZED_OBSERVED", payload: [
                        "serial": "emulator-5582",
                        "authorization_is_user_controlled": true
                    ])
                } else if lastState == "offline" {
                    await status("Android is booting; ADB is temporarily offline…", false)
                } else if lastState == "missing" {
                    await status("Waiting for emulator-5582 to appear on ADB 5038…", false)
                }
                previouslyLoggedState = lastState
            }
            if lastState == "device" { break }
            try await Task.sleep(for: .seconds(1))
        }
        try Task.checkCancellation()
        guard lastState == "device" else {
            throw TFTMACRuntimeError("ADB emulator-5582 did not authorize in the logged-in Mac session (last state: \(lastState)).")
        }
        telemetry.recordEvent("ADB_DEVICE_AUTHORIZED", payload: ["port": 5038, "serial": "emulator-5582"])
        try startLogcatCapture(paths: paths, telemetry: telemetry)

        let bootDeadline = Date().addingTimeInterval(300)
        var bootCompleted = false
        while Date() < bootDeadline {
            try Task.checkCancellation()
            let booted = try Self.adb(paths: paths, ["shell", "getprop", "sys.boot_completed"], timeout: 10).output
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if booted == "1" {
                bootCompleted = true
                break
            }
            try await Task.sleep(for: .seconds(1))
        }
        guard bootCompleted else {
            throw TFTMACRuntimeError("Android did not finish booting before the five-minute deadline.")
        }
        try await establishGuestGameplayPower(paths: paths, telemetry: telemetry)
        var manualUnlockRequired = false
        while !stopping {
            try Task.checkCancellation()
            let user = try Self.adb(paths: paths, ["shell", "dumpsys", "user"], timeout: 15).output
            if user.contains("RUNNING_UNLOCKED") { break }
            if !manualUnlockRequired {
                manualUnlockRequired = true
                telemetry.recordEvent("GUEST_SECURE_UNLOCK_REQUIRED", payload: [
                    "user": 0,
                    "pin_entry": "manual_only",
                    "credential_logged": false
                ])
            }
            try await Task.sleep(for: .seconds(1))
        }
        try Task.checkCancellation()
        telemetry.recordEvent("GUEST_UNLOCKED", payload: [
            "user": 0,
            "manual_unlock_was_required": manualUnlockRequired
        ])
        let package = "com.riotgames.league.teamfighttactics"
        let packageDump = try Self.adb(paths: paths, ["shell", "dumpsys", "package", package], timeout: 30).output
        guard packageDump.contains("Package [\(package)]") || packageDump.contains("versionName=") else {
            throw TFTMACRuntimeError("Official TFT is not installed. Open Google Play in Android and install Teamfight Tactics.")
        }
        let installer = try? Self.adb(paths: paths, ["shell", "cmd", "package", "get-install-source", package], timeout: 15).output
        tftPackageVersion = packageDump.split(whereSeparator: \.isNewline)
            .first(where: { $0.contains("versionName=") })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? "unknown"
        let versionCodeLine = packageDump.split(whereSeparator: \.isNewline)
            .first(where: { $0.contains("versionCode=") })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? "unknown"
        let signingLine = packageDump.split(whereSeparator: \.isNewline)
            .first(where: { $0.contains("signatures=PackageSignatures") })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? "unknown"
        telemetry.recordReceipt(key: "official_tft_version", value: tftPackageVersion, source: "dumpsys package", confidence: "DIRECT")
        telemetry.recordReceipt(key: "official_tft_version_code", value: versionCodeLine, source: "dumpsys package", confidence: "DIRECT")
        telemetry.recordReceipt(key: "official_tft_installer", value: installer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown", source: "cmd package get-install-source", confidence: "DIRECT")
        telemetry.recordReceipt(key: "official_tft_signing_receipt", value: signingLine, source: "dumpsys package", confidence: signingLine == "unknown" ? "UNKNOWN" : "DIRECT")
        telemetry.recordEvent("OFFICIAL_TFT_PACKAGE_RECEIPT", payload: [
            "package": package,
            "installer_output": installer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown",
            "version_line": tftPackageVersion,
            "version_code_line": versionCodeLine,
            "signing_line": signingLine
        ])
        try await Task.sleep(for: .milliseconds(750))
        guard logcatProcess?.isRunning == true,
              Self.fileSize(telemetry.captureDirectory.appendingPathComponent("logcat.raw.txt")) > 0 else {
            throw TFTMACRuntimeError("The required local logcat recorder did not become healthy before TFT launch.")
        }
        telemetry.recordEvent("LOGGER_HEALTH_GATE_PASSED", payload: [
            "logcat_growing": true,
            "resource_sampler_active": true,
            "sql_database": "TFTMAC_NATIVE_RUNTIME.sqlite"
        ])
        recordDiagnosticSnapshot(paths: paths, telemetry: telemetry, label: "before_tft_launch")

        let resolved = try? Self.adb(
            paths: paths,
            ["shell", "cmd", "package", "resolve-activity", "--brief", "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", package],
            timeout: 20
        ).output.split(whereSeparator: \.isNewline).last.map(String.init)
        var launched = false
        for component in [resolved, "\(package)/com.epicgames.unreal.SplashActivity", "\(package)/com.epicgames.unreal.GameActivity"].compactMap({ $0 }) {
            let result = try? Self.adb(paths: paths, ["shell", "am", "start", "-W", "-n", component], timeout: 45)
            if result?.status == 0 {
                launched = true
                telemetry.recordEvent("TFT_LAUNCH_REQUESTED", payload: ["component": component])
                break
            }
        }
        guard launched else { throw TFTMACRuntimeError("Android could not launch the official TFT activity.") }
        telemetry.recordEvent("TFT_READY_FOR_USER", payload: [
            "engine": "Unreal Engine",
            "resolution": "1920x1080",
            "refresh_hz": profile.refreshHz,
            "audio_backend": "coreaudio",
            "profile_id": profile.identifier
        ])
        telemetry.markRunning()
        await status("", false)
        while !stopping {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(1))
        }
    }

    private func establishGuestGameplayPower(
        paths: TFTMACRuntimePaths,
        telemetry: TFTMACNativeTelemetry
    ) async throws {
        _ = try Self.adb(paths: paths, ["shell", "dumpsys", "battery", "set", "ac", "1"], timeout: 10)
        _ = try Self.adb(
            paths: paths,
            ["shell", "settings", "put", "global", "stay_on_while_plugged_in", "7"],
            timeout: 10
        )
        _ = try Self.adb(paths: paths, ["shell", "input", "keyevent", "KEYCODE_WAKEUP"], timeout: 10)

        var lastState: GuestPowerState?
        for _ in 0..<12 {
            try Task.checkCancellation()
            let output = try Self.adb(paths: paths, ["shell", "dumpsys", "power"], timeout: 15).output
            lastState = GuestPowerState.parse(output)
            if let state = lastState, state.isGameplayReady {
                telemetry.recordReceipt(
                    key: "guest_gameplay_power_state",
                    value: "powered=true,stay_on=true,wakefulness=Awake",
                    source: "dumpsys battery/settings/power",
                    confidence: "DIRECT"
                )
                telemetry.recordEvent("GUEST_GAMEPLAY_POWER_READY", payload: [
                    "virtual_ac_powered": state.isPowered,
                    "stay_on": state.stayOn,
                    "wakefulness": state.wakefulness,
                    "prevents_secure_unlock_timeout": true
                ])
                return
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        telemetry.recordEvent("GUEST_GAMEPLAY_POWER_FAILED", payload: [
            "virtual_ac_powered": lastState?.isPowered ?? false,
            "stay_on": lastState?.stayOn ?? false,
            "wakefulness": lastState?.wakefulness ?? "UNKNOWN"
        ])
        throw TFTMACRuntimeError(
            "Android did not confirm powered, stay-awake gameplay state before secure unlock."
        )
    }

    private func sampleRuntime(paths: TFTMACRuntimePaths, telemetry: TFTMACNativeTelemetry, emulatorPID: Int32) async throws {
        var sampleIndex = 0
        while !stopping {
            try Task.checkCancellation()
            let ps = try? Self.runCommand(
                URL(fileURLWithPath: "/bin/ps"),
                ["-o", "%cpu=,rss=", "-p", "\(emulatorPID)"],
                timeout: 10
            ).output.trimmingCharacters(in: .whitespacesAndNewlines)
            let pieces = ps?.split(whereSeparator: \.isWhitespace) ?? []
            let cpu = pieces.first.flatMap { Double($0) }
            let rss = pieces.dropFirst().first.flatMap { Int64($0) }
            var gamePID = currentGamePID
            do {
                gamePID = try Self.readTFTProcessID(paths: paths)
                observeGameProcess(
                    gamePID,
                    paths: paths,
                    telemetry: telemetry,
                    observer: "FIVE_SECOND_RUNTIME_SAMPLER"
                )
            } catch {
                telemetry.recordEvent("TFT_PROCESS_OBSERVER_UNAVAILABLE", payload: [
                    "observer": "FIVE_SECOND_RUNTIME_SAMPLER",
                    "state_changed": false,
                    "error": error.localizedDescription
                ])
            }
            let activity = try? Self.adb(paths: paths, ["shell", "dumpsys", "activity", "activities"], timeout: 15).output
                .split(whereSeparator: \.isNewline)
                .first(where: { $0.contains("mResumedActivity") || $0.contains("topResumedActivity") })
                .map(String.init) ?? "unknown"
            telemetry.recordResourceSample(
                emulatorPID: emulatorPID,
                emulatorCPU: cpu,
                emulatorRSSKiB: rss,
                gamePID: gamePID,
                topActivity: activity ?? "unknown"
            )
            if let memoryOutput = try? Self.adb(paths: paths, ["shell", "cat", "/proc/meminfo"], timeout: 10).output,
               let memory = Self.parseGuestMemory(memoryOutput) {
                telemetry.recordGuestMemory(memory)
            }
            telemetry.recordHostResource(Self.collectHostResourceSample())
            let logcatURL = telemetry.captureDirectory.appendingPathComponent("logcat.raw.txt")
            if let aggregate = Self.readLogcatAggregate(url: logcatURL, from: &logcatReadOffset) {
                telemetry.recordLogcatAggregate(aggregate)
                if aggregate.anrCount > 0 || aggregate.inputTimeoutCount > 0
                    || aggregate.fatalCount > 0 || aggregate.memoryKillCount > 0
                    || aggregate.angleWarningCount > 0 || aggregate.vulkanWarningCount > 0
                    || aggregate.audioErrorCount > 0 {
                    telemetry.recordEvent("ANDROID_RUNTIME_INCIDENTS", payload: [
                        "anr_count": aggregate.anrCount,
                        "input_timeout_count": aggregate.inputTimeoutCount,
                        "fatal_count": aggregate.fatalCount,
                        "memory_kill_count": aggregate.memoryKillCount,
                        "angle_warning_count": aggregate.angleWarningCount,
                        "vulkan_warning_count": aggregate.vulkanWarningCount,
                        "audio_error_count": aggregate.audioErrorCount,
                        "raw_log_byte_start": String(aggregate.byteStart),
                        "raw_log_byte_end": String(aggregate.byteEnd)
                    ])
                }
            }
            let emulatorStdout = telemetry.captureDirectory.appendingPathComponent("emulator.stdout.log")
            if let aggregate = Self.readPipelineLogAggregate(
                url: emulatorStdout,
                sourceStream: "emulator_stdout",
                from: &emulatorStdoutReadOffset
            ) {
                telemetry.recordPipelineLogAggregate(aggregate)
                if aggregate.signals.gfxstreamWarningCount > 0 || aggregate.signals.asgStallCount > 0
                    || aggregate.signals.vulkanErrorCount > 0 || aggregate.signals.moltenVKWarningCount > 0
                    || aggregate.signals.shaderErrorCount > 0 || aggregate.signals.fenceTimeoutCount > 0 {
                    telemetry.recordEvent("GRAPHICS_PIPELINE_INCIDENTS", payload: [
                        "source_stream": aggregate.sourceStream,
                        "gfxstream_warning_count": aggregate.signals.gfxstreamWarningCount,
                        "asg_stall_count": aggregate.signals.asgStallCount,
                        "vulkan_error_count": aggregate.signals.vulkanErrorCount,
                        "moltenvk_warning_count": aggregate.signals.moltenVKWarningCount,
                        "shader_error_count": aggregate.signals.shaderErrorCount,
                        "fence_timeout_count": aggregate.signals.fenceTimeoutCount
                    ])
                }
            }
            let emulatorStderr = telemetry.captureDirectory.appendingPathComponent("emulator.stderr.log")
            if let aggregate = Self.readPipelineLogAggregate(
                url: emulatorStderr,
                sourceStream: "emulator_stderr",
                from: &emulatorStderrReadOffset
            ) {
                telemetry.recordPipelineLogAggregate(aggregate)
                if aggregate.signals.gfxstreamWarningCount > 0 || aggregate.signals.asgStallCount > 0
                    || aggregate.signals.vulkanErrorCount > 0 || aggregate.signals.moltenVKWarningCount > 0
                    || aggregate.signals.shaderErrorCount > 0 || aggregate.signals.fenceTimeoutCount > 0 {
                    telemetry.recordEvent("GRAPHICS_PIPELINE_INCIDENTS", payload: [
                        "source_stream": aggregate.sourceStream,
                        "gfxstream_warning_count": aggregate.signals.gfxstreamWarningCount,
                        "asg_stall_count": aggregate.signals.asgStallCount,
                        "vulkan_error_count": aggregate.signals.vulkanErrorCount,
                        "moltenvk_warning_count": aggregate.signals.moltenVKWarningCount,
                        "shader_error_count": aggregate.signals.shaderErrorCount,
                        "fence_timeout_count": aggregate.signals.fenceTimeoutCount
                    ])
                }
            }
            if sampleIndex.isMultiple(of: 6) {
                recordClockSync(paths: paths, telemetry: telemetry)
                recordThirtySecondRuntimeReceipt(paths: paths, telemetry: telemetry)
                if gamePID != nil {
                    recordDiagnosticSnapshot(paths: paths, telemetry: telemetry, label: "gameplay_periodic")
                    recordGraphicsPipelineSnapshot(paths: paths, telemetry: telemetry, label: "gameplay_periodic")
                }
            }
            sampleIndex += 1
            try await Task.sleep(for: .seconds(5))
        }
    }

    private func observeGameProcess(
        _ observedGamePID: Int32?,
        paths: TFTMACRuntimePaths,
        telemetry: TFTMACNativeTelemetry,
        observer: String
    ) {
        guard observedGamePID != currentGamePID else { return }
        let previousGamePID = currentGamePID
        let previousValue: Any = previousGamePID.map { NSNumber(value: $0) } ?? NSNull()
        let currentValue: Any = observedGamePID.map { NSNumber(value: $0) } ?? NSNull()

        if previousGamePID != nil {
            recordGraphicsPipelineSnapshot(
                paths: paths,
                telemetry: telemetry,
                label: observedGamePID == nil ? "tft_process_ended" : "tft_process_replaced"
            )
            telemetry.endGraphicsRun(
                reason: observedGamePID == nil ? "TFT_PROCESS_ENDED" : "TFT_PROCESS_REPLACED"
            )
            telemetry.recordEvent("TFT_GRAPHICS_RUN_ENDED", payload: [
                "game_pid": previousValue,
                "observer": observer,
                "reason": observedGamePID == nil ? "TFT_PROCESS_ENDED" : "TFT_PROCESS_REPLACED"
            ])
            currentGamePID = nil
            currentExactLayerName = nil
            consecutiveBadGraphicsWindows = 0
        }

        telemetry.recordEvent(
            observedGamePID == nil ? "TFT_PROCESS_ENDED" :
                (previousGamePID == nil ? "TFT_PROCESS_STARTED" : "TFT_PROCESS_REPLACED"),
            payload: [
                "previous_pid": previousValue,
                "current_pid": currentValue,
                "observer": observer,
                "graphics_logger_automatic": true
            ]
        )
        telemetry.recordGameProcessTransition(previousPID: previousGamePID, currentPID: observedGamePID)

        if let observedGamePID {
            currentGamePID = observedGamePID
            graphicsAutomaticTraceCount = 0
            graphicsIncidentTraceCount = 0
            lastGraphicsAutomaticTraceNS = 0
            telemetry.beginOrUpdateGraphicsRun(
                gamePID: observedGamePID,
                exactLayerName: currentExactLayerName,
                reason: previousGamePID == nil ? "TFT_PROCESS_STARTED" : "TFT_PROCESS_REPLACED"
            )
            telemetry.recordEvent("TFT_GRAPHICS_RUN_STARTED", payload: [
                "game_pid": observedGamePID,
                "start_trigger": "PROCESS_OBSERVED",
                "observer": observer,
                "manual_start_required": false,
                "target_fps": profile.refreshHz
            ])
            recordGraphicsPipelineSnapshot(
                paths: paths,
                telemetry: telemetry,
                label: previousGamePID == nil ? "tft_process_started" : "tft_process_replaced_started"
            )
        }
    }

    private func sampleGameFrames(paths: TFTMACRuntimePaths, telemetry: TFTMACNativeTelemetry) async throws {
        var sampler = GameFrameTelemetrySampler()
        var lastBoundaryNS = DispatchTime.now().uptimeNanoseconds
        var lastCollectorErrorEventNS: UInt64 = 0
        var previousExactLayerName: String?

        while !stopping {
            try Task.checkCancellation()
            let observedNS = DispatchTime.now().uptimeNanoseconds
            do {
                let observedGamePID = try Self.readTFTProcessID(paths: paths)
                observeGameProcess(
                    observedGamePID,
                    paths: paths,
                    telemetry: telemetry,
                    observer: "ONE_SECOND_GRAPHICS_SAMPLER"
                )
                let layers = try Self.adb(
                    paths: paths,
                    ["shell", "dumpsys", "SurfaceFlinger", "--list"],
                    timeout: 10
                ).output
                let layerStatus = sampler.updateLayerList(layers)
                guard case .available = layerStatus, let layer = sampler.selectedLayer else {
                    consecutiveBadGraphicsWindows = 0
                    if let lostLayer = currentExactLayerName {
                        telemetry.recordEvent("TFT_SURFACE_LAYER_LOST", payload: [
                            "previous_layer": lostLayer,
                            "graphics_run_remains_open_until_process_exit": true
                        ])
                        currentExactLayerName = nil
                        telemetry.updateGraphicsRunLayer(nil)
                    }
                    let window = Self.unavailableGameFrameWindow(
                        status: layerStatus,
                        layerName: nil,
                        startedNS: lastBoundaryNS,
                        endedNS: observedNS
                    )
                    telemetry.recordGameFrameWindow(window)
                    await gameFrame(window)
                    latestGameFrameWindow = window
                    ingestCombatFrameUpdate(nil, window: window)
                    lastBoundaryNS = observedNS
                    try await Task.sleep(for: .seconds(1))
                    continue
                }
                if let previousExactLayerName, previousExactLayerName != layer {
                    telemetry.recordEvent("TFT_SURFACE_LAYER_REPLACED", payload: [
                        "previous_layer": previousExactLayerName,
                        "current_layer": layer,
                        "benchmark_active": activeCombatBenchmark != nil
                    ])
                }
                if currentExactLayerName != layer {
                    let isFirstObservedLayer = currentExactLayerName == nil
                    currentExactLayerName = layer
                    telemetry.beginOrUpdateGraphicsRun(
                        gamePID: currentGamePID,
                        exactLayerName: layer,
                        reason: currentGamePID == nil ? "TFT_LAYER_OBSERVED" : "TFT_PROCESS_LAYER_ACTIVE"
                    )
                    telemetry.recordEvent(
                        isFirstObservedLayer ? "TFT_SURFACE_LAYER_ACTIVE" : "TFT_SURFACE_LAYER_REPLACED",
                        payload: [
                            "layer": layer,
                            "game_pid": currentGamePID.map { NSNumber(value: $0) } ?? NSNull(),
                            "manual_logger_start_required": false
                        ]
                    )
                    recordGraphicsPipelineSnapshot(
                        paths: paths,
                        telemetry: telemetry,
                        label: isFirstObservedLayer ? "tft_surface_active" : "tft_surface_replaced"
                    )
                }
                previousExactLayerName = layer

                let latency = try Self.adb(
                    paths: paths,
                    ["shell", GameFrameTelemetry.surfaceFlingerLatencyShellCommand(layerName: layer)],
                    timeout: 10
                ).output
                let update = sampler.ingestLatency(
                    latency,
                    observedMonotonicNS: DispatchTime.now().uptimeNanoseconds
                )
                telemetry.recordGameFrameUpdate(
                    update,
                    layerName: update.layerName,
                    refreshPeriodNS: update.refreshPeriodNS
                )
                if let window = update.window {
                    await gameFrame(window)
                    latestGameFrameWindow = window
                    ingestCombatFrameUpdate(update, window: window)
                    lastBoundaryNS = window.endedMonotonicNS
                    let lowFPSDegradation = window.frameCount >= 10
                        && (window.onePercentLowFPS ?? window.effectiveFPS) < 30
                    let severeDegradation = window.severeCount > 0 || (window.p99MS ?? 0) >= 50
                    if currentGamePID != nil,
                       currentExactLayerName == layer,
                       (lowFPSDegradation || severeDegradation) {
                        consecutiveBadGraphicsWindows += 1
                    } else {
                        consecutiveBadGraphicsWindows = 0
                    }
                    if consecutiveBadGraphicsWindows >= 2 {
                        let traceSequence = requestDiagnosticTrace(
                           scope: activeCombatBenchmark == nil ? .automaticGraphics : .combatBenchmark,
                           trigger: "AUTO_GAME_FRAME_DEGRADATION",
                           automatic: true,
                           durationSeconds: 15,
                           bufferMiB: 32,
                           benchmarkStartTrace: false
                        )
                        consecutiveBadGraphicsWindows = 0
                        telemetry.recordEvent("GAME_FRAME_DEGRADATION", payload: [
                            "evidence_level": "SURFACEFLINGER_ACTUAL_PRESENT",
                            "effective_fps": window.effectiveFPS,
                            "one_percent_low_fps": window.onePercentLowFPS ?? NSNull(),
                            "p99_interval_ms": window.p99MS ?? NSNull(),
                            "maximum_interval_ms": window.maximumMS ?? NSNull(),
                            "jank_count": window.jankCount,
                            "severe_count": window.severeCount,
                            "missed_vsync_equivalents": window.missedVsyncEquivalents,
                            "trace_sequence": traceSequence.map { NSNumber(value: $0) } ?? NSNull(),
                            "first_observed_divergent_boundary": "TFT_SURFACE_ACTUAL_PRESENT",
                            "cause": "UNKNOWN_UPSTREAM_OF_OR_AT_GUEST_SURFACE"
                        ])
                        recordGraphicsPipelineIncident(
                            trigger: "AUTO_GAME_FRAME_DEGRADATION",
                            window: window,
                            traceSequence: traceSequence
                        )
                        recordCombatIncident(
                            trigger: "AUTO_GAME_FRAME_DEGRADATION",
                            window: window,
                            traceSequence: traceSequence
                        )
                    }
                } else if case .unavailable = update.status {
                    consecutiveBadGraphicsWindows = 0
                    let unavailable = Self.unavailableGameFrameWindow(
                        status: update.status,
                        layerName: update.layerName,
                        startedNS: lastBoundaryNS,
                        endedNS: DispatchTime.now().uptimeNanoseconds
                    )
                    telemetry.recordGameFrameWindow(unavailable)
                    await gameFrame(unavailable)
                    latestGameFrameWindow = unavailable
                    ingestCombatFrameUpdate(nil, window: unavailable)
                    lastBoundaryNS = unavailable.endedMonotonicNS
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                consecutiveBadGraphicsWindows = 0
                let failedAt = DispatchTime.now().uptimeNanoseconds
                let unavailable = Self.unavailableGameFrameWindow(
                    status: .unavailable(.adbError),
                    layerName: sampler.selectedLayer,
                    startedNS: lastBoundaryNS,
                    endedNS: failedAt
                )
                telemetry.recordGameFrameWindow(unavailable)
                latestGameFrameWindow = unavailable
                ingestCombatFrameUpdate(nil, window: unavailable)
                if lastCollectorErrorEventNS == 0
                    || failedAt &- lastCollectorErrorEventNS >= 30_000_000_000 {
                    lastCollectorErrorEventNS = failedAt
                    telemetry.recordEvent("GAME_FRAME_COLLECTOR_UNAVAILABLE", payload: [
                        "reason": "ADB_ERROR",
                        "error": error.localizedDescription,
                        "event_rate_limit_seconds": 30
                    ])
                }
                await gameFrame(unavailable)
                lastBoundaryNS = failedAt
            }
            try await Task.sleep(for: .seconds(1))
        }
    }

    nonisolated private static func unavailableGameFrameWindow(
        status: GameFrameTelemetryStatus,
        layerName: String?,
        startedNS: UInt64,
        endedNS: UInt64
    ) -> GameFrameTelemetryWindow {
        GameFrameTelemetryWindow(
            status: status,
            layerName: layerName,
            refreshPeriodNS: nil,
            startedMonotonicNS: startedNS,
            endedMonotonicNS: max(startedNS, endedNS),
            frameCount: 0,
            effectiveFPS: 0,
            p50MS: nil,
            p95MS: nil,
            p99MS: nil,
            maximumMS: nil,
            onePercentLowFPS: nil,
            jankCount: 0,
            severeCount: 0,
            missedVsyncEquivalents: 0,
            historyTruncated: false
        )
    }

    private func ingestCombatFrameUpdate(
        _ update: GameFrameTelemetryUpdate?,
        window: GameFrameTelemetryWindow
    ) {
        guard var active = activeCombatBenchmark else { return }
        let traceActive: Bool
        if let traceStart = traceCaptureMeasurementStartNS,
           let traceEnd = traceCaptureMeasurementEndNS {
            traceActive = window.endedMonotonicNS > traceStart
                && window.startedMonotonicNS < traceEnd
        } else {
            traceActive = false
        }
        active.ingest(update: update, window: window, traceActive: traceActive)
        activeCombatBenchmark = active
    }

    private func recordCombatIncident(
        trigger: String,
        window: GameFrameTelemetryWindow?,
        traceSequence: Int?
    ) {
        guard let active = activeCombatBenchmark, let telemetry else { return }
        let incident = CombatIncidentRecord(
            incidentID: UUID().uuidString.lowercased(),
            benchmarkID: active.benchmarkID,
            sessionID: active.sessionID,
            presetID: active.presetID,
            trigger: trigger,
            observedMonotonicNS: DispatchTime.now().uptimeNanoseconds,
            effectiveFPS: window?.effectiveFPS,
            onePercentLowFPS: window?.onePercentLowFPS,
            p99IntervalMilliseconds: window?.p99MS,
            severeCount: window?.severeCount ?? 0,
            traceSequence: traceSequence,
            firstDivergentBoundary: "UNKNOWN_PENDING_TRACE_CORRELATION",
            confidence: "UNKNOWN",
            explicitUnknowns: "ASG_VS_GFXSTREAM_VS_MOLTENVK_OWNERSHIP_REQUIRES_FRAME_ID_RING"
        )
        telemetry.recordCombatIncident(incident)
        do { try labStore?.record(incident) }
        catch { telemetry.recordEvent("COMBAT_INCIDENT_PERSISTENCE_FAILED", payload: ["error": error.localizedDescription]) }
    }

    private func recordGraphicsPipelineIncident(
        trigger: String,
        window: GameFrameTelemetryWindow?,
        traceSequence: Int?
    ) {
        guard let telemetry, let window else { return }
        telemetry.recordGraphicsPipelineIncident(GraphicsPipelineIncident(
            incidentID: UUID().uuidString.lowercased(),
            trigger: trigger,
            observedMonotonicNS: DispatchTime.now().uptimeNanoseconds,
            window: window,
            traceSequence: traceSequence,
            firstObservedDivergentBoundary: "TFT_SURFACE_ACTUAL_PRESENT",
            causalOwner: "UNKNOWN_UPSTREAM_OF_OR_AT_GUEST_SURFACE",
            causalConfidence: "LOW",
            explicitUnknowns: [
                "UNREAL_RENDER_THREAD_TIMING",
                "ANGLE_SUBMIT_TIMING",
                "ASG_QUEUE_DEPTH",
                "GFXSTREAM_HOST_RECEIVE_AND_SUBMIT_TIMING",
                "MOLTENVK_COMMAND_BUFFER_TIMING",
                "SHARED_CROSS_STACK_FRAME_ID"
            ]
        ))
    }

    private func recordCorrectnessRejection(reason: String) {
        guard let telemetry else { return }
        let nowNS = DispatchTime.now().uptimeNanoseconds
        let receipt = profile.experimentConfigurationReceipt
        let metrics = CombatBenchmarkMetrics(
            combatDurationSeconds: 0,
            surfaceAvailability: 0,
            clockCoverage: 0,
            p95ClockRoundTripMilliseconds: 0,
            frameHistoryTruncated: false,
            exactLayerStable: false,
            correctnessPassed: false,
            weightedFPS: 0,
            onePercentLowFPS: 0,
            p95IntervalMilliseconds: 0,
            p99IntervalMilliseconds: 0,
            jankRate: 0,
            severeRate: 0,
            missedVsyncRate: 0
        )
        let run = CombatBenchmarkRun(
            benchmarkID: "correctness-\(UUID().uuidString.lowercased())",
            sessionID: telemetry.sessionIdentifier,
            presetID: profile.experimentPreset,
            configurationSHA256: receipt.sha256,
            comparisonIdentitySHA256: profile.comparisonConfigurationSHA256,
            configurationJSON: receipt.canonicalJSON,
            tftPackageVersion: tftPackageVersion,
            performanceModeConfirmed: false,
            startedUTC: Self.utcNow(),
            endedUTC: Self.utcNow(),
            startedMonotonicNS: nowNS,
            endedMonotonicNS: nowNS,
            exactLayerIdentity: nil,
            metrics: metrics,
            p50IntervalMilliseconds: 0,
            maximumIntervalMilliseconds: 0,
            observerOverheadInvalid: false
        )
        telemetry.recordCombatBenchmark(run)
        telemetry.recordEvent("REJECTED_CORRECTNESS", payload: [
            "preset_id": profile.experimentPreset.rawValue,
            "configuration_sha256": receipt.sha256,
            "reason": reason
        ])
        try? labStore?.record(run)
    }

    @discardableResult
    private func requestDiagnosticTrace(
        scope: DiagnosticTraceScope,
        trigger: String,
        automatic: Bool,
        durationSeconds: Int,
        bufferMiB: Int,
        benchmarkStartTrace: Bool
    ) -> Int? {
        guard !stopping, let paths, let telemetry else { return nil }
        let now = DispatchTime.now().uptimeNanoseconds
        switch scope {
        case .combatBenchmark:
            guard activeCombatBenchmark != nil else { return nil }
        case .automaticGraphics:
            guard currentGamePID != nil, currentExactLayerName != nil else {
                telemetry.recordEvent("DIAGNOSTIC_TRACE_SKIPPED", payload: [
                    "scope": scope.rawValue,
                    "trigger": trigger,
                    "reason": "NO_ACTIVE_TFT_GRAPHICS_RUN"
                ])
                return nil
            }
        }
        if traceCaptureInProgress {
            telemetry.recordEvent("DIAGNOSTIC_TRACE_SKIPPED", payload: [
                "scope": scope.rawValue,
                "trigger": trigger,
                "reason": "TRACE_ALREADY_RUNNING"
            ])
            return nil
        }
        switch scope {
        case .combatBenchmark:
            if !benchmarkStartTrace, incidentTraceCount >= 2 {
                telemetry.recordEvent("DIAGNOSTIC_TRACE_SKIPPED", payload: [
                    "scope": scope.rawValue,
                    "trigger": trigger, "reason": "BENCHMARK_INCIDENT_TRACE_LIMIT", "limit": 2
                ])
                return nil
            }
            if automatic {
                guard automaticTraceCount < 2 else { return nil }
                guard lastAutomaticTraceNS == 0 || now &- lastAutomaticTraceNS >= 120_000_000_000 else { return nil }
                automaticTraceCount += 1
                lastAutomaticTraceNS = now
            }
            if !benchmarkStartTrace { incidentTraceCount += 1 }
        case .automaticGraphics:
            guard !benchmarkStartTrace else { return nil }
            if graphicsIncidentTraceCount >= 2 {
                telemetry.recordEvent("DIAGNOSTIC_TRACE_SKIPPED", payload: [
                    "scope": scope.rawValue,
                    "trigger": trigger, "reason": "GRAPHICS_RUN_INCIDENT_TRACE_LIMIT", "limit": 2
                ])
                return nil
            }
            if automatic {
                guard graphicsAutomaticTraceCount < 2 else { return nil }
                guard lastGraphicsAutomaticTraceNS == 0
                    || now &- lastGraphicsAutomaticTraceNS >= 120_000_000_000 else { return nil }
                graphicsAutomaticTraceCount += 1
                lastGraphicsAutomaticTraceNS = now
            }
            graphicsIncidentTraceCount += 1
        }
        traceCaptureInProgress = true
        traceCaptureMeasurementStartNS = now
        traceCaptureMeasurementEndNS = now &+ UInt64(durationSeconds) * 1_000_000_000
        traceCaptureCount += 1
        let sequence = traceCaptureCount
        let graphicsContext = telemetry.currentGraphicsContext()
        telemetry.recordEvent("DIAGNOSTIC_TRACE_STARTED", payload: [
            "scope": scope.rawValue,
            "trigger": trigger,
            "duration_seconds": durationSeconds,
            "capture_started_monotonic_ns": now,
            "capture_ends_monotonic_ns": traceCaptureMeasurementEndNS ?? now,
            "sequence": sequence,
            "buffer_mib": bufferMiB,
            "analysis_state": "RAW_CAPTURE_PENDING"
        ])

        traceCaptureTask = Task.detached(priority: .utility) { [paths, telemetry] in
            do {
                let artifact = try Self.capturePerfettoTrace(
                    paths: paths,
                    telemetry: telemetry,
                    graphicsRunID: graphicsContext.runID,
                    graphicsStackSHA256: graphicsContext.stackSHA256,
                    captureScope: scope.rawValue,
                    trigger: trigger,
                    sequence: sequence,
                    durationSeconds: durationSeconds,
                    bufferMiB: bufferMiB
                )
                await self.finishDiagnosticTrace(
                    artifact: artifact,
                    errorDescription: nil,
                    scope: scope.rawValue,
                    trigger: trigger
                )
            } catch {
                await self.finishDiagnosticTrace(
                    artifact: nil,
                    errorDescription: error.localizedDescription,
                    scope: scope.rawValue,
                    trigger: trigger
                )
            }
        }
        return sequence
    }

    private func finishDiagnosticTrace(
        artifact: DiagnosticArtifact?,
        errorDescription: String?,
        scope: String,
        trigger: String
    ) {
        traceCaptureInProgress = false
        traceCaptureTask = nil
        if let artifact {
            telemetry?.recordDiagnosticArtifact(artifact)
            telemetry?.recordEvent("DIAGNOSTIC_TRACE_COMPLETED", payload: [
                "scope": artifact.captureScope,
                "trigger": artifact.trigger,
                "relative_path": artifact.relativePath,
                "byte_count": artifact.byteCount,
                "sha256": artifact.sha256,
                "analysis_state": artifact.analysisState,
                "normalized_relative_path": artifact.normalizedRelativePath,
                "normalized_sha256": artifact.normalizedSHA256,
                "trace_processor_sha256": artifact.traceProcessorSHA256
            ])
        } else {
            traceCaptureMeasurementEndNS = DispatchTime.now().uptimeNanoseconds
            telemetry?.recordEvent("DIAGNOSTIC_TRACE_FAILED", payload: [
                "scope": scope,
                "trigger": trigger,
                "error": errorDescription ?? "unknown",
                "raw_capture_available": false
            ])
        }
    }

    nonisolated private static func capturePerfettoTrace(
        paths: TFTMACRuntimePaths,
        telemetry: TFTMACNativeTelemetry,
        graphicsRunID: String?,
        graphicsStackSHA256: String?,
        captureScope: String,
        trigger: String,
        sequence: Int,
        durationSeconds: Int,
        bufferMiB: Int
    ) throws -> DiagnosticArtifact {
        let manager = FileManager.default
        let traceDirectory = telemetry.captureDirectory.appendingPathComponent("perfetto", isDirectory: true)
        try manager.createDirectory(at: traceDirectory, withIntermediateDirectories: true)
        let safeTrigger = trigger.lowercased().map { character -> Character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
        }
        let label = String(safeTrigger).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "native-\(label.isEmpty ? "trace" : label)-\(sequence)-\(stamp).pftrace"
        let hostURL = traceDirectory.appendingPathComponent(fileName)
        let metadataURL = hostURL.appendingPathExtension("json")
        let remotePath = "/data/misc/perfetto-traces/tftmac-native-\(UUID().uuidString).pftrace"
        let durationMS = max(1_000, durationSeconds * 1_000)
        let config = """
        buffers { size_kb: \(max(1, bufferMiB) * 1024) fill_policy: RING_BUFFER }
        data_sources { config { name: "android.surfaceflinger.frame" target_buffer: 0 } }
        data_sources { config { name: "android.surfaceflinger.frametimeline" target_buffer: 0 } }
        data_sources { config { name: "android.surfaceflinger.layers" target_buffer: 0 } }
        data_sources { config { name: "android.gpu.memory" target_buffer: 0 } }
        data_sources { config { name: "linux.process_stats" target_buffer: 0 process_stats_config { scan_all_processes_on_start: true } } }
        data_sources { config { name: "linux.sys_stats" target_buffer: 0 sys_stats_config { meminfo_period_ms: 1000 stat_period_ms: 1000 } } }
        data_sources {
          config {
            name: "linux.ftrace"
            target_buffer: 0
            ftrace_config {
              ftrace_events: "sched/sched_switch"
              ftrace_events: "sched/sched_wakeup"
              ftrace_events: "sched/sched_waking"
              ftrace_events: "power/cpu_frequency"
              atrace_apps: "com.riotgames.league.teamfighttactics"
            }
          }
        }
        duration_ms: \(durationMS)
        """
        let trace = try runCommand(
            paths.adb,
            ["-P", "5038", "-s", "emulator-5582", "shell", "perfetto", "--txt", "-c", "-", "-o", remotePath],
            environment: adbEnvironment(paths: paths),
            input: Data(config.utf8),
            timeout: TimeInterval(durationSeconds + 30)
        )
        guard trace.status == 0 else {
            _ = try? adb(paths: paths, ["shell", "rm", "-f", remotePath], timeout: 10)
            throw TFTMACRuntimeError("Perfetto capture failed: \(trace.output.suffix(1200))")
        }
        defer { _ = try? adb(paths: paths, ["shell", "rm", "-f", remotePath], timeout: 10) }
        _ = try adb(paths: paths, ["pull", remotePath, hostURL.path], timeout: 120)
        let data = try Data(contentsOf: hostURL)
        guard !data.isEmpty else { throw TFTMACRuntimeError("Perfetto returned an empty trace.") }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let normalized: (url: URL, data: Data, sha256: String, processorSHA256: String)
        do {
            normalized = try normalizePerfettoTrace(hostURL: hostURL)
        } catch {
            try? manager.removeItem(at: hostURL)
            throw TFTMACRuntimeError("Perfetto trace normalization failed and the unprocessed raw trace was removed: \(error.localizedDescription)")
        }
        let createdUTC = ISO8601DateFormatter().string(from: Date())
        let metadata: [String: Any] = [
            "schema": 1,
            "created_utc": createdUTC,
            "capture_scope": captureScope,
            "graphics_run_id": graphicsRunID ?? NSNull(),
            "graphics_stack_sha256": graphicsStackSHA256 ?? NSNull(),
            "trigger": trigger,
            "duration_seconds": durationSeconds,
            "buffer_mib": bufferMiB,
            "trace_file_name": fileName,
            "byte_count": data.count,
            "sha256": digest,
            "normalized_file_name": normalized.url.lastPathComponent,
            "normalized_sha256": normalized.sha256,
            "trace_processor_version": "58.2",
            "trace_processor_sha256": normalized.processorSHA256,
            "data_sources": [
                "android.surfaceflinger.frame",
                "android.surfaceflinger.frametimeline",
                "android.surfaceflinger.layers",
                "android.gpu.memory",
                "linux.process_stats",
                "linux.sys_stats",
                "linux.ftrace:sched_switch,sched_wakeup,sched_waking,power/cpu_frequency"
            ],
            "analysis_state": "NORMALIZED_TRACE_PROCESSOR_V58_2"
        ]
        let metadataData = try JSONSerialization.data(
            withJSONObject: metadata,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try metadataData.write(to: metadataURL, options: .atomic)
        return DiagnosticArtifact(
            graphicsRunID: graphicsRunID,
            graphicsStackSHA256: graphicsStackSHA256,
            captureScope: captureScope,
            createdUTC: createdUTC,
            createdMonotonicNS: DispatchTime.now().uptimeNanoseconds,
            kind: "PERFETTO_FRAME_PIPELINE_TRACE",
            trigger: trigger,
            relativePath: "perfetto/\(fileName)",
            byteCount: Int64(data.count),
            sha256: digest,
            analysisState: "NORMALIZED_TRACE_PROCESSOR_V58_2",
            normalizedRelativePath: "perfetto/\(normalized.url.lastPathComponent)",
            normalizedSHA256: normalized.sha256,
            normalizedSummaryCSV: String(decoding: normalized.data, as: UTF8.self),
            traceProcessorSHA256: normalized.processorSHA256
        )
    }

    nonisolated private static func normalizePerfettoTrace(
        hostURL: URL
    ) throws -> (url: URL, data: Data, sha256: String, processorSHA256: String) {
        let expectedProcessorSHA = "d29864d1ba3b36855527bb1b0ca3aa7f703cdce338b9680bb922c5c151b358fa"
        guard let resourceURL = Bundle.main.resourceURL else {
            throw TFTMACRuntimeError("TFTMAC has no resource directory for the pinned trace processor.")
        }
        let processorURL = resourceURL.appendingPathComponent("trace_processor_shell")
        guard FileManager.default.isExecutableFile(atPath: processorURL.path) else {
            throw TFTMACRuntimeError("The pinned Perfetto trace_processor_shell is missing from TFTMAC.app.")
        }
        let processorData = try Data(contentsOf: processorURL)
        let processorSHA = SHA256.hash(data: processorData).map { String(format: "%02x", $0) }.joined()
        guard processorSHA == expectedProcessorSHA else {
            throw TFTMACRuntimeError("The packaged Perfetto trace processor failed its SHA-256 receipt.")
        }
        let query = """
        SELECT
          (SELECT start_ts FROM trace_bounds) AS trace_start_ns,
          (SELECT end_ts FROM trace_bounds) AS trace_end_ns,
          (SELECT COUNT(*) FROM process) AS process_rows,
          (SELECT COUNT(*) FROM thread) AS thread_rows,
          (SELECT COUNT(*) FROM sched) AS scheduler_slices,
          (SELECT COUNT(*) FROM counter) AS counter_rows,
          (SELECT COUNT(*) FROM slice WHERE name GLOB '*SurfaceFlinger*' OR name GLOB '*FrameTimeline*') AS surfaceflinger_slices,
          (SELECT COUNT(*) FROM process WHERE name = 'com.riotgames.league.teamfighttactics') AS tft_process_rows;
        """
        let result = try runCommand(
            processorURL,
            ["query", hostURL.path, query],
            timeout: 180
        )
        guard result.status == 0 else {
            throw TFTMACRuntimeError("trace_processor query failed: \(result.output.suffix(1200))")
        }
        let normalizedData = Data(result.output.utf8)
        guard !normalizedData.isEmpty else {
            throw TFTMACRuntimeError("trace_processor returned an empty normalized summary.")
        }
        let normalizedURL = hostURL.appendingPathExtension("normalized.csv")
        try normalizedData.write(to: normalizedURL, options: .atomic)
        let normalizedSHA = SHA256.hash(data: normalizedData).map { String(format: "%02x", $0) }.joined()
        return (normalizedURL, normalizedData, normalizedSHA, processorSHA)
    }

    private func recordClockSync(paths: TFTMACRuntimePaths, telemetry: TFTMACNativeTelemetry) {
        let hostT0 = DispatchTime.now().uptimeNanoseconds
        guard let output = try? Self.adb(paths: paths, ["shell", "cat", "/proc/uptime"], timeout: 10).output,
              let seconds = output.split(whereSeparator: \.isWhitespace).first.flatMap({ Double($0) }) else { return }
        let hostT1 = DispatchTime.now().uptimeNanoseconds
        let guestNS = UInt64(max(0, seconds) * 1_000_000_000)
        telemetry.recordClockSync(hostT0NS: hostT0, guestUptimeNS: guestNS, hostT1NS: hostT1)
        if var active = activeCombatBenchmark {
            active.recordClock(
                hostMidpointNS: hostT0 &+ ((hostT1 &- hostT0) / 2),
                roundTripNS: hostT1 &- hostT0
            )
            activeCombatBenchmark = active
        }
    }

    private func recordDiagnosticSnapshot(paths: TFTMACRuntimePaths, telemetry: TFTMACNativeTelemetry?, label: String) {
        guard let telemetry else { return }
        if let output = try? Self.adb(paths: paths, ["shell", "dumpsys", "SurfaceFlinger"], timeout: 20).output,
           let sample = Self.parseSurfaceFlinger(output) {
            telemetry.recordSurfaceFlinger(sample, label: label)
        }
        if let output = try? Self.adb(paths: paths, ["shell", "dumpsys", "media.audio_flinger"], timeout: 20).output,
           let sample = Self.parseAudioFlinger(output) {
            telemetry.recordAudioFlinger(sample, label: label)
        }
    }

    private func recordThirtySecondRuntimeReceipt(paths: TFTMACRuntimePaths, telemetry: TFTMACNativeTelemetry) {
        let geometry = try? Self.adb(
            paths: paths,
            ["shell", "sh", "-c", "wm size; wm density; dumpsys display | grep -m 1 -E 'DisplayDeviceInfo|fps|refreshRate'"],
            timeout: 15
        ).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let properties = try? Self.adb(
            paths: paths,
            ["shell", "getprop"],
            timeout: 15
        ).output
        telemetry.recordEvent("RUNTIME_THIRTY_SECOND_RECEIPT", payload: [
            "preset_id": profile.experimentPreset.rawValue,
            "configuration_sha256": profile.experimentConfigurationReceipt.sha256,
            "emulator_features_requested": profile.effectiveEmulatorFeatures,
            "display_geometry": geometry ?? "unavailable",
            "guest_egl": Self.firstRegexText("\\[ro.hardware.egl\\]: \\[(.*?)\\]", in: properties ?? "") ?? "unknown",
            "guest_vulkan": Self.firstRegexText("\\[ro.hardware.vulkan\\]: \\[(.*?)\\]", in: properties ?? "") ?? "unknown",
            "cross_boundary_attribution": "CLOCK_SYNC_GATED"
        ])
    }

    private func recordGraphicsPipelineSnapshot(
        paths: TFTMACRuntimePaths,
        telemetry: TFTMACNativeTelemetry,
        label: String
    ) {
        let stdout = Self.readTailText(
            telemetry.captureDirectory.appendingPathComponent("emulator.stdout.log"),
            maximumBytes: 16 * 1024 * 1024
        )
        let stderr = Self.readTailText(
            telemetry.captureDirectory.appendingPathComponent("emulator.stderr.log"),
            maximumBytes: 16 * 1024 * 1024
        )
        let emulatorText = stdout + "\n" + stderr
        let lower = emulatorText.lowercased()
        let layerOutput = try? Self.adb(
            paths: paths,
            ["shell", "dumpsys", "SurfaceFlinger", "--list"],
            timeout: 10
        ).output
        let surfaceState: String
        let exactLayerName: String?
        if let layerOutput {
            switch GameFrameTelemetry.selectTFTSurfaceViewLayer(from: layerOutput) {
            case .selected(let layer):
                surfaceState = "EXACT_LAYER_ACTIVE"
                exactLayerName = layer
            case .unavailable(.multipleTFTSurfaceViews):
                surfaceState = "AMBIGUOUS_MULTIPLE_LAYERS"
                exactLayerName = nil
            case .unavailable:
                surfaceState = "NOT_OBSERVED"
                exactLayerName = nil
            }
        } else {
            surfaceState = "ADB_UNAVAILABLE"
            exactLayerName = nil
        }
        let packageAngleInstance = Self.firstRegexText(
            "(?i)(Created VkInstance:[^\\n]*application:'com\\.riotgames\\.league\\.teamfighttactics'[^\\n]*engine:'ANGLE')",
            in: emulatorText
        ) != nil
        let unrealEngine = Self.firstRegexText(
            "(?i)Created VkInstance:[^\\n]*application:'TFT'[^\\n]*engine:'(UnrealEngine[^']*)'",
            in: emulatorText
        )
        let gameGraphicsAPI = unrealEngine == nil ? "UNKNOWN" : "UNREAL_ENGINE_VULKAN"
        let gameGraphicsAPIConfidence = unrealEngine == nil ? "UNKNOWN" : "DIRECT_VKINSTANCE_RUNTIME_LOG"
        let emulatorVersion = Self.firstRegexText(
            "(?i)Android emulator version\\s+([^\\s]+)",
            in: emulatorText
        )
        let emulatorBuildID = Self.firstRegexText(
            "(?i)\\(build_id\\s+([^\\)]+)\\)",
            in: emulatorText
        )
        let emulatorGPUSelection = Self.firstRegexText(
            "(?i)emuglConfig_init:\\s*([^\\r\\n]+)",
            in: emulatorText
        )
        let rawGfxstreamFeatures = Self.firstRegexText(
            "(?is)Gfxstream features:\\s*(.*?)Gfxstream initialized successfully",
            in: emulatorText
        )
        let gfxstreamFeatureReceipt = rawGfxstreamFeatures.map { raw in
            String(raw.split(whereSeparator: \.isNewline).map {
                String($0)
                    .replacingOccurrences(of: "INFO         |", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }.joined(separator: ";").prefix(8_192))
        }
        let moltenVKVersion = Self.firstRegexText(
            "(?i)(Graphics API Version[^\\r\\n]*VK_DRIVER_ID_MOLTENVK[^\\r\\n]*)",
            in: emulatorText
        )
        let hostDevice = Self.firstRegexText("(?i)Selecting Vulkan device:\\s*([^\\r\\n]+)", in: emulatorText)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let vulkanComposition = Self.firstRegexText("(?i)useVulkanComposition:\\s*(true|false)", in: emulatorText)
            .flatMap(Self.parseBoolean)
        let nativeSwapchain = Self.firstRegexText("(?i)useVulkanNativeSwapchain:\\s*(true|false)", in: emulatorText)
            .flatMap(Self.parseBoolean)
        let guestEGL = try? Self.adb(paths: paths, ["shell", "getprop", "ro.hardware.egl"], timeout: 10).output
        let guestVulkan = try? Self.adb(paths: paths, ["shell", "getprop", "ro.hardware.vulkan"], timeout: 10).output
        let angleSelection = try? Self.adb(
            paths: paths,
            ["shell", "settings", "get", "global", "angle_gl_driver_all_angle"],
            timeout: 10
        ).output
        let packageAnglePackages = try? Self.adb(
            paths: paths,
            ["shell", "settings", "get", "global", "angle_gl_driver_selection_pkgs"],
            timeout: 10
        ).output
        let packageAngleValues = try? Self.adb(
            paths: paths,
            ["shell", "settings", "get", "global", "angle_gl_driver_selection_values"],
            timeout: 10
        ).output
        let packageAngleSelection = [
            Self.nonemptyDiagnosticValue(packageAnglePackages).map { "packages=\($0)" },
            Self.nonemptyDiagnosticValue(packageAngleValues).map { "values=\($0)" }
        ].compactMap { $0 }.joined(separator: ";")
        let metalDevice = MTLCreateSystemDefaultDevice()
        let metalDeviceName = metalDevice?.name
        let metalRegistryID = metalDevice.map { String(format: "0x%016llx", $0.registryID) }
        let gfxstreamActive = lower.contains("gfxstream initialized successfully")
        let moltenVKActive = lower.contains("moltenvk_icd.json")
            || lower.contains("vk_driver_id_moltenvk")
            || lower.contains("graphics adapter vendor moltenvk")
        let angleState = packageAngleInstance
            ? "PACKAGE_PROCESS_ANGLE_INSTANCE_OBSERVED"
            : "NOT_OBSERVED"
        let moltenVKConfiguration = "{\"MVK_CONFIG_FAST_MATH_ENABLED\":\"1\",\"MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE\":\"64\",\"MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS\":\"0\",\"confidence\":\"REQUESTED_LAUNCH_ENVIRONMENT\"}"
        let completeDirectPath = unrealEngine != nil
            && exactLayerName != nil
            && gfxstreamActive
            && moltenVKActive
            && hostDevice != nil
            && vulkanComposition == true
            && nativeSwapchain == true
            && metalDevice != nil
        let pipelinePath = completeDirectPath
            ? "RUN_OBSERVED_COMPONENT_CHAIN:UNREAL_VULKAN->GFXSTREAM->HOST_VULKAN_MOLTENVK->METAL;OUTPUT:EMULATOR_IMAGE_STREAM->TFTMAC_METAL_PRESENTER;NOT_FRAME_CORRELATED"
            : "UNKNOWN_INCOMPLETE_RUNTIME_RECEIPT"
        let receipt = GraphicsStackReceipt(fields: [
            "tft_package_version": GraphicsStackReceiptField(
                value: tftPackageVersion,
                source: "adb dumpsys package com.riotgames.league.teamfighttactics",
                confidence: tftPackageVersion == "unknown" ? "UNKNOWN" : "DIRECT"
            ),
            "tft_surface": GraphicsStackReceiptField(
                value: exactLayerName ?? surfaceState,
                source: "SurfaceFlinger --list exact GameActivity SurfaceView selection",
                confidence: exactLayerName == nil ? "UNKNOWN" : "DIRECT"
            ),
            "unreal_engine": GraphicsStackReceiptField(
                value: unrealEngine ?? "UNKNOWN",
                source: "emulator VkInstance runtime log for application TFT",
                confidence: unrealEngine == nil ? "UNKNOWN" : "DIRECT"
            ),
            "game_graphics_api": GraphicsStackReceiptField(
                value: gameGraphicsAPI,
                source: "emulator VkInstance runtime log for application TFT",
                confidence: gameGraphicsAPIConfidence
            ),
            "angle": GraphicsStackReceiptField(
                value: angleState,
                source: "emulator VkInstance runtime log for official TFT package process",
                confidence: packageAngleInstance ? "DIRECT" : "UNKNOWN"
            ),
            "gfxstream": GraphicsStackReceiptField(
                value: gfxstreamActive ? "ACTIVE" : "UNKNOWN",
                source: "emulator gfxstream initialization log",
                confidence: gfxstreamActive ? "DIRECT" : "UNKNOWN"
            ),
            "gfxstream_features": GraphicsStackReceiptField(
                value: gfxstreamFeatureReceipt ?? "UNKNOWN",
                source: "emulator Gfxstream features receipt",
                confidence: gfxstreamFeatureReceipt == nil ? "UNKNOWN" : "DIRECT"
            ),
            "gfxstream_internal_tracing": GraphicsStackReceiptField(
                value: "NOT_PROVEN_IN_PACKAGED_RUNTIME",
                source: "packaged runtime has no direct GFXSTREAM_BUILD_WITH_TRACING receipt",
                confidence: "UNKNOWN"
            ),
            "moltenvk": GraphicsStackReceiptField(
                value: moltenVKActive ? "ACTIVE" : "UNKNOWN",
                source: "MoltenVK ICD/driver runtime log",
                confidence: moltenVKActive ? "DIRECT" : "UNKNOWN"
            ),
            "moltenvk_version": GraphicsStackReceiptField(
                value: moltenVKVersion ?? "UNKNOWN",
                source: "host Vulkan driver runtime log",
                confidence: moltenVKVersion == nil ? "UNKNOWN" : "DIRECT"
            ),
            "moltenvk_configuration": GraphicsStackReceiptField(
                value: moltenVKConfiguration,
                source: "TFTMAC app-host launch environment",
                confidence: "REQUESTED"
            ),
            "host_vulkan_device": GraphicsStackReceiptField(
                value: hostDevice ?? "UNKNOWN",
                source: "emulator Vulkan device-selection log",
                confidence: hostDevice == nil ? "UNKNOWN" : "DIRECT"
            ),
            "metal_device": GraphicsStackReceiptField(
                value: [metalDeviceName, metalRegistryID].compactMap { $0 }.joined(separator: ";"),
                source: "MTLCreateSystemDefaultDevice",
                confidence: metalDevice == nil ? "UNKNOWN" : "DIRECT"
            ),
            "native_presenter": GraphicsStackReceiptField(
                value: "TFTMAC_MTKVIEW_METAL_PRESENTER",
                source: "TFTMAC native presenter implementation",
                confidence: "DIRECT_SOURCE"
            ),
            "configuration_sha256": GraphicsStackReceiptField(
                value: profile.experimentConfigurationReceipt.sha256,
                source: "canonical effective runtime configuration",
                confidence: "DIRECT"
            ),
            "pipeline_path": GraphicsStackReceiptField(
                value: pipelinePath,
                source: "composition of run-local component receipts; continuous edges require frame-ID correlation",
                confidence: completeDirectPath ? "CORRELATED_NOT_CAUSAL" : "UNKNOWN"
            ),
            "cross_stack_frame_id": GraphicsStackReceiptField(
                value: "NOT_IMPLEMENTED",
                source: "current packaged runtime",
                confidence: "UNKNOWN"
            )
        ])
        telemetry.recordGraphicsPipelineSnapshot(GraphicsPipelineSnapshot(
            label: label,
            gamePID: currentGamePID,
            exactLayerName: exactLayerName ?? currentExactLayerName,
            tftSurfaceState: surfaceState,
            gameGraphicsAPI: gameGraphicsAPI,
            gameGraphicsAPIConfidence: gameGraphicsAPIConfidence,
            angleState: angleState,
            gfxstreamState: gfxstreamActive ? "PROVEN_ACTIVE" : "NOT_OBSERVED",
            moltenVKState: moltenVKActive ? "PROVEN_ACTIVE" : "NOT_OBSERVED",
            emulatorVersion: Self.nonemptyDiagnosticValue(emulatorVersion),
            emulatorBuildID: Self.nonemptyDiagnosticValue(emulatorBuildID),
            emulatorGPUSelection: Self.nonemptyDiagnosticValue(emulatorGPUSelection),
            gfxstreamFeatureReceipt: Self.nonemptyDiagnosticValue(gfxstreamFeatureReceipt),
            gfxstreamTracingState: "UNKNOWN_NOT_PROVEN_IN_PACKAGED_RUNTIME",
            moltenVKVersion: Self.nonemptyDiagnosticValue(moltenVKVersion),
            moltenVKConfiguration: moltenVKConfiguration,
            hostVulkanDevice: Self.nonemptyDiagnosticValue(hostDevice),
            vulkanComposition: vulkanComposition,
            nativeSwapchain: nativeSwapchain,
            guestEGLImplementation: Self.nonemptyDiagnosticValue(guestEGL),
            guestVulkanImplementation: Self.nonemptyDiagnosticValue(guestVulkan),
            globalAngleSelection: Self.nonemptyDiagnosticValue(angleSelection),
            packageAngleSelection: Self.nonemptyDiagnosticValue(packageAngleSelection),
            metalDeviceName: Self.nonemptyDiagnosticValue(metalDeviceName),
            metalRegistryID: Self.nonemptyDiagnosticValue(metalRegistryID),
            receipt: receipt
        ))
    }

    nonisolated private static func fileSize(_ url: URL) -> UInt64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return 0 }
        return size.uint64Value
    }

    nonisolated private static func readTailText(_ url: URL, maximumBytes: UInt64) -> String {
        let end = fileSize(url)
        guard end > 0, let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: end > maximumBytes ? end - maximumBytes : 0)
            let data = try handle.readToEnd() ?? Data()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return ""
        }
    }

    nonisolated private static func parseBoolean(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }

    nonisolated private static func nonemptyDiagnosticValue(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed.lowercased() != "null" else { return nil }
        return String(trimmed.prefix(512))
    }

    nonisolated private static func parseGuestMemory(_ output: String) -> GuestMemorySample? {
        var values = [String: Int64]()
        for line in output.split(whereSeparator: \.isNewline) {
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2,
                  let value = pair[1].split(whereSeparator: \.isWhitespace).first.flatMap({ Int64($0) }) else { continue }
            values[String(pair[0])] = value
        }
        guard let total = values["MemTotal"], let available = values["MemAvailable"] ?? values["MemFree"] else { return nil }
        return GuestMemorySample(
            totalKiB: total,
            availableKiB: available,
            swapTotalKiB: values["SwapTotal"],
            swapFreeKiB: values["SwapFree"]
        )
    }

    nonisolated private static func collectHostResourceSample() -> HostResourceSample {
        let vmOutput = try? runCommand(
            URL(fileURLWithPath: "/usr/bin/vm_stat"),
            [],
            timeout: 5
        ).output
        let pageSize = vmOutput.flatMap { firstRegexInt("page size of ([0-9]+) bytes", in: $0) } ?? 16_384
        func pages(_ label: String) -> Int64? {
            vmOutput.flatMap { firstRegexInt("\(NSRegularExpression.escapedPattern(for: label)):\\s*([0-9]+)", in: $0) }
        }
        let availablePages = ["Pages free", "Pages inactive", "Pages speculative"]
            .compactMap(pages)
            .reduce(0, +)
        let compressedPages = pages("Pages occupied by compressor")
        let pageouts = pages("Pageouts")
        let swapOutput = try? runCommand(
            URL(fileURLWithPath: "/usr/sbin/sysctl"),
            ["-n", "vm.swapusage"],
            timeout: 5
        ).output
        let swapUsedKiB: Int64? = swapOutput.flatMap { output in
            guard let amount = firstRegexDouble("used = ([0-9.]+)", in: output),
                  let unit = firstRegexText("used = [0-9.]+([KMGT])", in: output) else { return nil }
            let multiplier: Double
            switch unit {
            case "K": multiplier = 1
            case "M": multiplier = 1_024
            case "G": multiplier = 1_024 * 1_024
            case "T": multiplier = 1_024 * 1_024 * 1_024
            default: multiplier = 1
            }
            return Int64(amount * multiplier)
        }
        let powerOutput = try? runCommand(
            URL(fileURLWithPath: "/usr/bin/pmset"),
            ["-g", "batt"],
            timeout: 5
        ).output
        let powerSource: String
        if powerOutput?.contains("AC Power") == true { powerSource = "AC" }
        else if powerOutput?.contains("Battery Power") == true { powerSource = "BATTERY" }
        else { powerSource = "UNKNOWN" }
        let thermalState: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalState = "NOMINAL"
        case .fair: thermalState = "FAIR"
        case .serious: thermalState = "SERIOUS"
        case .critical: thermalState = "CRITICAL"
        @unknown default: thermalState = "UNKNOWN"
        }
        return HostResourceSample(
            availableKiB: availablePages > 0 ? (availablePages * pageSize) / 1_024 : nil,
            compressedKiB: compressedPages.map { ($0 * pageSize) / 1_024 },
            swapUsedKiB: swapUsedKiB,
            pageouts: pageouts,
            thermalState: thermalState,
            powerSource: powerSource
        )
    }

    nonisolated private static func parseSurfaceFlinger(_ output: String) -> SurfaceFlingerSample? {
        let renderRate = firstRegexDouble("renderRate=([0-9.]+)\\s*Hz", in: output)
        let totalMissed = firstRegexInt("Total missed frame count:\\s*([0-9]+)", in: output)
        let hwcMissed = firstRegexInt("HWC missed frame count:\\s*([0-9]+)", in: output)
        let gpuMissed = firstRegexInt("GPU missed frame count:\\s*([0-9]+)", in: output)
        let requestedRates = regexDoubles(
            "com\\.riotgames\\.league\\.teamfighttactics[^\\n]*requestedFrameRate:\\s*\\{([0-9.]+)\\s*Hz",
            in: output
        )
        guard renderRate != nil || totalMissed != nil || hwcMissed != nil || gpuMissed != nil else { return nil }
        return SurfaceFlingerSample(
            renderRateHz: renderRate,
            totalMissedFrames: totalMissed,
            hwcMissedFrames: hwcMissed,
            gpuMissedFrames: gpuMissed,
            tftRequestedRateHz: requestedRates.max()
        )
    }

    nonisolated private static func parseAudioFlinger(_ output: String) -> AudioFlingerSample? {
        let chunks = output.components(separatedBy: "Output thread ")
        guard let activeChunk = chunks.first(where: { $0.contains("Standby: no") }) else {
            return output.contains("Output thread ")
                ? AudioFlingerSample(
                    activeOutput: false, sampleRateHz: nil, stereoOutput: false,
                    activeTracks: 0, partialUnderruns: nil, emptyUnderruns: nil
                )
                : nil
        }
        let sampleRate = firstRegexInt("Sample rate:\\s*([0-9]+)\\s*Hz", in: activeChunk).map(Int.init)
        let channelText = firstRegexText("Channel mask:[^\\n]*\\(([^)]*)\\)", in: activeChunk)?.lowercased() ?? ""
        let stereo = (channelText.contains("front-left") && channelText.contains("front-right"))
            || (channelText.contains("left") && channelText.contains("right"))
        let activeTracks = firstRegexInt("[0-9]+ Tracks of which ([0-9]+) are active", in: activeChunk).map(Int.init)
        return AudioFlingerSample(
            activeOutput: true,
            sampleRateHz: sampleRate,
            stereoOutput: stereo,
            activeTracks: activeTracks,
            partialUnderruns: firstRegexInt("underrun counters:\\s*partial=([0-9]+)", in: activeChunk),
            emptyUnderruns: firstRegexInt("underrun counters:[^\\n]*empty=([0-9]+)", in: activeChunk)
        )
    }

    nonisolated private static func readLogcatAggregate(url: URL, from offset: inout UInt64) -> LogcatAggregate? {
        let end = fileSize(url)
        guard end > offset else { return nil }
        let maximumReadBytes: UInt64 = 4 * 1024 * 1024
        let requestedStart = offset
        let actualStart = end - min(end - requestedStart, maximumReadBytes)
        let skipped = actualStart - requestedStart
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: actualStart)
            let data = try handle.read(upToCount: Int(end - actualStart)) ?? Data()
            offset = end
            let text = String(decoding: data, as: UTF8.self)
            let lines = text.split(whereSeparator: \.isNewline)
            var anr = 0
            var inputTimeout = 0
            var fatal = 0
            var memoryKill = 0
            var choreographer = 0
            var angleWarning = 0
            var vulkanWarning = 0
            var audioError = 0
            for rawLine in lines {
                let line = String(rawLine)
                let lower = line.lowercased()
                let warningOrError = lower.contains(" warning") || lower.contains(" error")
                    || lower.contains(" failed") || lower.contains(" fatal")
                    || line.contains(" W ") || line.contains(" E ")
                if lower.contains("anr in com.riotgames.league.teamfighttactics") { anr += 1 }
                if lower.contains("input dispatching timed out") || lower.contains("input timeout") { inputTimeout += 1 }
                if lower.contains("com.riotgames.league.teamfighttactics")
                    && (lower.contains("fatal exception") || lower.contains("fatal signal") || lower.contains("signal 11")) { fatal += 1 }
                if TelemetrySignalClassifier.isConfirmedGuestMemoryKill(line) { memoryKill += 1 }
                if lower.contains("choreographer") && lower.contains("skipped") { choreographer += 1 }
                if lower.contains("angle") && warningOrError { angleWarning += 1 }
                if lower.contains("vulkan") && warningOrError { vulkanWarning += 1 }
                if lower.contains("pcm_writei") && (warningOrError || lower.contains("underrun")) { audioError += 1 }
            }
            return LogcatAggregate(
                byteStart: actualStart, byteEnd: end, skippedBytes: skipped, lineCount: lines.count,
                anrCount: anr, inputTimeoutCount: inputTimeout, fatalCount: fatal,
                memoryKillCount: memoryKill, choreographerSkipCount: choreographer,
                angleWarningCount: angleWarning, vulkanWarningCount: vulkanWarning,
                audioErrorCount: audioError
            )
        } catch {
            return nil
        }
    }

    nonisolated private static func readPipelineLogAggregate(
        url: URL,
        sourceStream: String,
        from offset: inout UInt64
    ) -> PipelineLogAggregate? {
        let end = fileSize(url)
        guard end > offset else { return nil }
        let maximumReadBytes: UInt64 = 4 * 1024 * 1024
        let requestedStart = offset
        let actualStart = end - min(end - requestedStart, maximumReadBytes)
        let skipped = actualStart - requestedStart
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: actualStart)
            let data = try handle.read(upToCount: Int(end - actualStart)) ?? Data()
            offset = end
            let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
            var signals = PipelineLogSignals()
            for line in lines {
                signals = signals + TelemetrySignalClassifier.pipelineSignals(in: String(line))
            }
            return PipelineLogAggregate(
                sourceStream: sourceStream,
                byteStart: actualStart,
                byteEnd: end,
                skippedBytes: skipped,
                lineCount: lines.count,
                signals: signals
            )
        } catch {
            return nil
        }
    }

    nonisolated private static func firstRegexInt(_ pattern: String, in text: String) -> Int64? {
        firstRegexText(pattern, in: text).flatMap(Int64.init)
    }

    nonisolated private static func firstRegexDouble(_ pattern: String, in text: String) -> Double? {
        firstRegexText(pattern, in: text).flatMap(Double.init)
    }

    nonisolated private static func firstRegexText(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    nonisolated private static func regexDoubles(_ pattern: String, in text: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
            return Double(text[range])
        }
    }

    nonisolated private static func runController(
        discovery: EmulatorControllerDiscovery,
        profile: TFTMACRuntimeProfile,
        mailbox: LatestFrameMailbox,
        telemetry: TFTMACNativeTelemetry,
        inputStream: AsyncStream<EmulatorInput>,
        status: @escaping StatusHandler
    ) async throws {
        let transport = try HTTP2ClientTransport.Posix(
            target: .ipv4(address: "127.0.0.1", port: discovery.port),
            transportSecurity: .plaintext
        )
        try await withGRPCClient(transport: transport) { grpc in
            let client = Android_Emulation_Control_EmulatorController.Client(wrapping: grpc)
            let metadata: GRPCCore.Metadata = ["authorization": "Bearer \(discovery.token)"]
            let statusRequest = GRPCCore.ClientRequest(
                message: SwiftProtobuf.Google_Protobuf_Empty(),
                metadata: metadata
            )
            let emulatorStatus: Android_Emulation_Control_EmulatorStatus = try await client.getStatus(
                request: statusRequest,
                serializer: GRPCProtobuf.ProtobufSerializer<SwiftProtobuf.Google_Protobuf_Empty>(),
                deserializer: GRPCProtobuf.ProtobufDeserializer<Android_Emulation_Control_EmulatorStatus>()
            )
            guard emulatorStatus.version.contains("37.1.11") else {
                throw TFTMACRuntimeError("Unexpected Android Emulator version: \(emulatorStatus.version)")
            }
            telemetry.recordEvent("CONTROLLER_AUTHENTICATED", payload: [
                "version": emulatorStatus.version,
                "booted": emulatorStatus.booted,
                "cpu_cores": emulatorStatus.vmConfig.numberOfCpuCores,
                "ram_mib": emulatorStatus.vmConfig.ramSizeBytes / 1024 / 1024
            ])

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    var requestFormat = Android_Emulation_Control_ImageFormat()
                    requestFormat.format = .rgba8888
                    requestFormat.width = 0
                    requestFormat.height = 0
                    requestFormat.display = 0
                    let request = GRPCCore.ClientRequest(message: requestFormat, metadata: metadata)
                    var callOptions = GRPCCore.CallOptions.defaults
                    callOptions.waitForReady = true
                    // grpc-swift-nio-transport 2.9.1 wires maxRequestMessageBytes
                    // into the HTTP/2 stream decoder's payload ceiling, so the
                    // pinned transport requires both limits for an 8.3 MB frame.
                    callOptions.maxRequestMessageBytes = 16 * 1024 * 1024
                    callOptions.maxResponseMessageBytes = 16 * 1024 * 1024

                    let admission = NativeFrameAdmissionState(mailbox: mailbox, telemetry: telemetry)
                    let clock = ContinuousClock()
                    let firstFrameDeadline = clock.now.advanced(by: .seconds(120))
                    var initialImage: Android_Emulation_Control_Image?
                    var recordedFrameWait = false
                    while initialImage == nil {
                        do {
                            initialImage = try await client.getScreenshot(
                                request: request,
                                serializer: GRPCProtobuf.ProtobufSerializer<Android_Emulation_Control_ImageFormat>(),
                                deserializer: GRPCProtobuf.ProtobufDeserializer<Android_Emulation_Control_Image>(),
                                options: callOptions
                            )
                        } catch let error as GRPCCore.RPCError where error.code == .failedPrecondition {
                            if !recordedFrameWait {
                                telemetry.recordEvent("FIRST_NATIVE_FRAME_WAITING", payload: [
                                    "grpc_code": "failedPrecondition",
                                    "reason": error.message,
                                    "timeout_seconds": 120
                                ])
                                recordedFrameWait = true
                            }
                            guard clock.now < firstFrameDeadline else {
                                throw TFTMACRuntimeError("Timed out waiting for Android to post its first native frame.")
                            }
                            try await Task.sleep(for: .milliseconds(250))
                        }
                    }
                    guard let initialImage else {
                        throw TFTMACRuntimeError("Android did not return an initial native frame.")
                    }
                    _ = try admission.admit(initialImage)
                    try await client.streamScreenshot(
                        request: request,
                        serializer: GRPCProtobuf.ProtobufSerializer<Android_Emulation_Control_ImageFormat>(),
                        deserializer: GRPCProtobuf.ProtobufDeserializer<Android_Emulation_Control_Image>(),
                        options: callOptions
                    ) { response in
                        for try await image in response.messages {
                            try Task.checkCancellation()
                            _ = try admission.admit(image)
                        }
                        throw TFTMACRuntimeError("The authenticated screenshot stream ended unexpectedly.")
                    }
                }
                group.addTask {
                    var recordedTouchPipeline = false
                    for await input in inputStream {
                        try Task.checkCancellation()
                        switch input {
                        case .touch(let touch):
                            var contact = Android_Emulation_Control_Touch()
                            contact.x = touch.x
                            contact.y = touch.y
                            contact.identifier = touch.identifier
                            contact.pressure = touch.pressure
                            contact.expiration = .unspecified
                            var event = Android_Emulation_Control_TouchEvent()
                            event.touches = [contact]
                            event.display = 0
                            let request = GRPCCore.ClientRequest(message: event, metadata: metadata)
                            _ = try await client.sendTouch(
                                request: request,
                                serializer: GRPCProtobuf.ProtobufSerializer<Android_Emulation_Control_TouchEvent>(),
                                deserializer: GRPCProtobuf.ProtobufDeserializer<SwiftProtobuf.Google_Protobuf_Empty>()
                            )
                            if !recordedTouchPipeline {
                                telemetry.recordEvent("PRIMARY_TOUCH_INPUT_ACTIVE", payload: [
                                    "transport": "EmulatorController.sendTouch",
                                    "display": 0,
                                    "identifier": touch.identifier
                                ])
                                recordedTouchPipeline = true
                            }
                        case .mouse(let mouse):
                            var event = Android_Emulation_Control_MouseEvent()
                            event.x = mouse.x
                            event.y = mouse.y
                            event.buttons = mouse.buttons
                            event.display = 0
                            let request = GRPCCore.ClientRequest(message: event, metadata: metadata)
                            _ = try await client.sendMouse(
                                request: request,
                                serializer: GRPCProtobuf.ProtobufSerializer<Android_Emulation_Control_MouseEvent>(),
                                deserializer: GRPCProtobuf.ProtobufDeserializer<SwiftProtobuf.Google_Protobuf_Empty>()
                            )
                        case .keyboard(let keyboard):
                            var event = Android_Emulation_Control_KeyboardEvent()
                            event.eventType = .keypress
                            if let key = keyboard.key { event.key = key }
                            else if let text = keyboard.text { event.text = text }
                            let request = GRPCCore.ClientRequest(message: event, metadata: metadata)
                            _ = try await client.sendKey(
                                request: request,
                                serializer: GRPCProtobuf.ProtobufSerializer<Android_Emulation_Control_KeyboardEvent>(),
                                deserializer: GRPCProtobuf.ProtobufDeserializer<SwiftProtobuf.Google_Protobuf_Empty>()
                            )
                        }
                    }
                }
                _ = try await group.next()
                group.cancelAll()
            }
        }
    }

    private func prepareAVD(paths: TFTMACRuntimePaths, telemetry: TFTMACNativeTelemetry) throws -> AVDConfigurationTransaction {
        let transaction = try AVDConfigurationTransaction(
            configURL: paths.avdConfig,
            stateRoot: paths.applicationSupport.appendingPathComponent("State", isDirectory: true),
            captureDirectory: telemetry.captureDirectory,
            profile: profile
        )
        telemetry.recordEvent("AVD_CONFIG_APPLIED", payload: [
            "original_sha256": transaction.originalSHA256,
            "applied_sha256": transaction.appliedSHA256,
            "reversible": true
        ])
        return transaction
    }

    private func recoverInterruptedAVDTransaction(paths: TFTMACRuntimePaths) throws {
        try AVDConfigurationTransaction.recoverIfNeeded(
            configURL: paths.avdConfig,
            stateRoot: paths.applicationSupport.appendingPathComponent("State", isDirectory: true),
            captureRoot: paths.applicationSupport.appendingPathComponent("Captures", isDirectory: true)
        )
    }

    nonisolated private static func adbEnvironment(paths: TFTMACRuntimePaths) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "ADB_VENDOR_KEYS")
        environment.removeValue(forKey: "ADB_SERVER_SOCKET")
        environment.removeValue(forKey: "ANDROID_ADB_SERVER_ADDRESS")
        environment["ANDROID_SDK_ROOT"] = paths.sdkRoot.path
        environment["ANDROID_AVD_HOME"] = paths.avdHome.path
        environment["ANDROID_ADB_SERVER_PORT"] = "5038"
        environment["ADB_MDNS_AUTO_CONNECT"] = ""
        return environment
    }

    nonisolated private static func adb(paths: TFTMACRuntimePaths, _ arguments: [String], timeout: TimeInterval) throws -> ProcessResult {
        let result = try runCommand(
            paths.adb,
            ["-P", "5038", "-s", "emulator-5582"] + arguments,
            environment: adbEnvironment(paths: paths),
            timeout: timeout
        )
        guard result.status == 0 else {
            throw TFTMACRuntimeError("ADB command failed: \(result.output.suffix(1200))")
        }
        return result
    }

    nonisolated private static func readTFTProcessID(paths: TFTMACRuntimePaths) throws -> Int32? {
        let result = try runCommand(
            paths.adb,
            [
                "-P", "5038", "-s", "emulator-5582", "shell", "pidof",
                "com.riotgames.league.teamfighttactics"
            ],
            environment: adbEnvironment(paths: paths),
            timeout: 10
        )
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.status != 0 {
            if output.isEmpty { return nil }
            throw TFTMACRuntimeError("ADB TFT process query failed: \(output.suffix(1200))")
        }
        return output.split(whereSeparator: \.isWhitespace).first.flatMap { Int32($0) }
    }

    nonisolated private static func runCommand(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String]? = nil,
        input: Data? = nil,
        timeout: TimeInterval
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let inputPipe = input.map { _ in Pipe() }
        if let inputPipe { process.standardInput = inputPipe }
        try process.run()
        if let input, let inputPipe {
            inputPipe.fileHandleForWriting.write(input)
            try? inputPipe.fileHandleForWriting.close()
        }
        let timeoutWork = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeoutWork.cancel()
        let output = String(data: data, encoding: .utf8) ?? ""
        return ProcessResult(status: process.terminationStatus, output: output)
    }

    nonisolated private static func parseINI(_ text: String) -> [String: String] {
        var result = [String: String]()
        for line in text.split(whereSeparator: \.isNewline) {
            let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 {
                result[pair[0].trimmingCharacters(in: .whitespaces)] = pair[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return result
    }

    nonisolated private static func processExists(_ processIdentifier: Int32) -> Bool {
        if Darwin.kill(processIdentifier, 0) == 0 { return true }
        return errno != ESRCH
    }

    nonisolated private static func processMatchesLaunchedIdentity(
        _ processIdentifier: Int32,
        sessionMarker: String? = nil
    ) -> Bool {
        guard processExists(processIdentifier),
              let result = try? runCommand(
                URL(fileURLWithPath: "/bin/ps"),
                ["-p", "\(processIdentifier)", "-ww", "-o", "command="],
                timeout: 5
              ), result.status == 0 else { return false }
        let baseIdentityMatches = result.output.contains("qemu-system-aarch64")
            && result.output.contains("@TFT_Ultra_Tablet")
            && result.output.contains("-port 5582")
        return baseIdentityMatches && (sessionMarker.map(result.output.contains) ?? true)
    }

    nonisolated private static func findOwnedEmulatorPID(sessionMarker: String) -> Int32? {
        guard let result = try? runCommand(
            URL(fileURLWithPath: "/bin/ps"),
            ["-axo", "pid=,command="],
            timeout: 10
        ), result.status == 0 else { return nil }
        for line in result.output.split(whereSeparator: \.isNewline) {
            guard line.contains("qemu-system-aarch64"),
                  line.contains("@TFT_Ultra_Tablet"),
                  line.contains(sessionMarker),
                  let pid = line.split(whereSeparator: \.isWhitespace).first.flatMap({ Int32($0) }) else { continue }
            return pid
        }
        return nil
    }

    nonisolated private static func anyEmulatorUsingSharedAVD() -> Bool {
        guard let result = try? runCommand(
            URL(fileURLWithPath: "/bin/ps"),
            ["-axo", "command="],
            timeout: 10
        ), result.status == 0 else { return true }
        return result.output.split(whereSeparator: \.isNewline).contains { line in
            line.contains("qemu-system-aarch64") && line.contains("@TFT_Ultra_Tablet")
        }
    }

    nonisolated private static func controllerDiscoveryRoots(paths: TFTMACRuntimePaths) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/Caches/TemporaryItems/avd/running", isDirectory: true),
            FileManager.default.temporaryDirectory.appendingPathComponent("avd/running", isDirectory: true),
            paths.avdHome.appendingPathComponent("running", isDirectory: true),
            home.appendingPathComponent(".android/avd/running", isDirectory: true)
        ]
        var unique = [URL]()
        for candidate in candidates where !unique.contains(candidate) { unique.append(candidate) }
        return unique
    }

    nonisolated private static func utcNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

private struct ProcessResult: Sendable {
    let status: Int32
    let output: String
}

private final class AVDConfigurationTransaction: @unchecked Sendable {
    let originalSHA256: String
    let appliedSHA256: String

    private let configURL: URL
    private let backupURL: URL
    private let markerURL: URL

    init(
        configURL: URL,
        stateRoot: URL,
        captureDirectory: URL,
        profile: TFTMACRuntimeProfile
    ) throws {
        try FileManager.default.createDirectory(at: stateRoot, withIntermediateDirectories: true)
        self.configURL = configURL
        backupURL = captureDirectory.appendingPathComponent("avd-config.before.ini")
        markerURL = stateRoot.appendingPathComponent("avd-config-transaction.json")
        let original = try Data(contentsOf: configURL)
        originalSHA256 = Self.sha256(original)
        try original.write(to: backupURL, options: .atomic)
        var config = String(decoding: original, as: UTF8.self)
        let values: [String: String] = [
            "hw.cpu.ncore": "\(profile.vCPU)",
            "hw.ramSize": "\(profile.ramMiB)",
            "hw.lcd.width": "\(profile.width)",
            "hw.lcd.height": "\(profile.height)",
            "hw.lcd.density": "\(profile.densityDPI)",
            "hw.gpu.enabled": "yes",
            "hw.gpu.mode": profile.gpuMode,
            "hw.gltransport": profile.graphicsTransport,
            "hw.gltransport.drawFlushInterval": "\(profile.asgDrawFlushInterval)",
            "hw.gltransport.asg.writeBufferSize": "\(profile.asgWriteBufferSize)",
            "hw.gltransport.asg.writeStepSize": "\(profile.asgWriteStepSize)",
            "hw.gltransport.asg.dataRingSize": "\(profile.asgDataRingSize)",
            "showDeviceFrame": "no",
            "skin.name": "\(profile.width)x\(profile.height)",
            "fastboot.forceColdBoot": "yes",
            "fastboot.forceFastBoot": "no"
        ]
        for (key, value) in values { config = Self.setting(key: key, value: value, in: config) }
        let applied = Data(config.utf8)
        appliedSHA256 = Self.sha256(applied)
        let marker: [String: Any] = [
            "schema": 1,
            "config": configURL.path,
            "backup": backupURL.path,
            "original_sha256": originalSHA256,
            "applied_sha256": appliedSHA256
        ]
        let markerData = try JSONSerialization.data(withJSONObject: marker, options: [.prettyPrinted, .sortedKeys])
        try markerData.write(to: markerURL, options: .atomic)
        try applied.write(to: configURL, options: .atomic)
    }

    func restore() throws {
        let original = try Data(contentsOf: backupURL)
        guard Self.sha256(original) == originalSHA256 else {
            throw TFTMACRuntimeError("The AVD backup hash changed; automatic restore stopped safely.")
        }
        let current = try Data(contentsOf: configURL)
        let currentSHA256 = Self.sha256(current)
        let decision = try AVDTransactionGuard.restoreDecision(
            currentSHA256: currentSHA256,
            originalSHA256: originalSHA256,
            appliedSHA256: appliedSHA256
        )
        if decision == .alreadyOriginal {
            try? FileManager.default.removeItem(at: markerURL)
            return
        }
        try original.write(to: configURL, options: .atomic)
        try? FileManager.default.removeItem(at: markerURL)
    }

    static func recoverIfNeeded(configURL expectedConfigURL: URL, stateRoot: URL, captureRoot: URL) throws {
        let markerURL = stateRoot.appendingPathComponent("avd-config-transaction.json")
        guard let data = try? Data(contentsOf: markerURL),
              let marker = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let config = marker["config"] as? String,
              let backup = marker["backup"] as? String,
              let expected = marker["original_sha256"] as? String,
              let applied = marker["applied_sha256"] as? String else { return }
        let markerConfigURL = URL(fileURLWithPath: config)
        let backupURL = URL(fileURLWithPath: backup)
        try AVDTransactionGuard.validateRecoveryPaths(
            markerConfigURL: markerConfigURL,
            expectedConfigURL: expectedConfigURL,
            backupURL: backupURL,
            captureRoot: captureRoot
        )
        let backupData = try Data(contentsOf: backupURL)
        guard sha256(backupData) == expected else {
            throw TFTMACRuntimeError("A prior AVD transaction backup failed its hash check.")
        }
        let currentData = try Data(contentsOf: expectedConfigURL)
        let currentSHA256 = sha256(currentData)
        let decision = try AVDTransactionGuard.restoreDecision(
            currentSHA256: currentSHA256,
            originalSHA256: expected,
            appliedSHA256: applied
        )
        if decision == .alreadyOriginal {
            try FileManager.default.removeItem(at: markerURL)
            return
        }
        try backupData.write(to: expectedConfigURL, options: .atomic)
        try FileManager.default.removeItem(at: markerURL)
    }

    private static func setting(key: String, value: String, in text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let index = lines.firstIndex(where: { $0.hasPrefix("\(key)=") }) {
            lines[index] = "\(key)=\(value)"
        } else {
            lines.append("\(key)=\(value)")
        }
        return lines.joined(separator: "\n")
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class TFTMACRuntimeController {
    private let service: TFTMACRuntimeService
    private var runTask: Task<Void, Never>?
    private(set) var failed = false

    init(
        profile: TFTMACRuntimeProfile,
        mailbox: LatestFrameMailbox,
        status: @escaping TFTMACRuntimeService.StatusHandler,
        gameFrame: @escaping TFTMACRuntimeService.GameFrameHandler
    ) {
        service = TFTMACRuntimeService(profile: profile, mailbox: mailbox, status: status, gameFrame: gameFrame)
    }

    func start() {
        guard runTask == nil else { return }
        runTask = Task { [service] in
            do { try await service.run() }
            catch is CancellationError { }
            catch {
                await MainActor.run { self.failed = true }
            }
        }
    }

    func sendMouse(x: Int32, y: Int32, buttons: Int32) {
        Task { await service.sendMouse(MouseInput(x: x, y: y, buttons: buttons)) }
    }

    func sendTouch(_ input: TouchInput) {
        Task { await service.sendTouch(input) }
    }

    func sendKeyboard(text: String? = nil, key: String? = nil) {
        guard text?.isEmpty == false || key?.isEmpty == false else { return }
        Task { await service.sendKeyboard(KeyboardInput(text: text, key: key)) }
    }

    func recordPresentation(_ sample: PresentationSample) {
        Task { await service.recordPresentation(sample) }
    }

    func recordHostPresentation(_ sample: HostPresentationWindow) {
        Task { await service.recordHostPresentation(sample) }
    }

    func recordMarker(_ marker: String) {
        Task { await service.recordMarker(marker) }
    }

    func startCombatBenchmark(performanceModeConfirmed: Bool) {
        Task { await service.startCombatBenchmark(performanceModeConfirmed: performanceModeConfirmed) }
    }

    func markVisibleStutter() {
        Task { await service.markVisibleStutter() }
    }

    func endCombatBenchmark(correctnessPassed: Bool = true) {
        Task { await service.endCombatBenchmark(correctnessPassed: correctnessPassed) }
    }

    func recordSettingsChange(previous: TFTMACRuntimeProfile, next: TFTMACRuntimeProfile) {
        Task { await service.recordSettingsChange(previous: previous, next: next) }
    }

    func stop() async {
        await service.stop()
        runTask?.cancel()
        _ = await runTask?.result
        runTask = nil
    }
}
