import Foundation
import SQLite3

struct CombatBenchmarkRun: Sendable {
    let benchmarkID: String
    let sessionID: String
    let presetID: RuntimeExperimentPreset
    let configurationSHA256: String
    let comparisonIdentitySHA256: String
    let configurationJSON: String
    let tftPackageVersion: String
    let performanceModeConfirmed: Bool
    let startedUTC: String
    let endedUTC: String
    let startedMonotonicNS: UInt64
    let endedMonotonicNS: UInt64
    let exactLayerIdentity: String?
    let metrics: CombatBenchmarkMetrics
    let p50IntervalMilliseconds: Double
    let maximumIntervalMilliseconds: Double
    let observerOverheadInvalid: Bool

    var validity: CombatBenchmarkValidity { .evaluate(metrics) }
    var isValid: Bool { metrics.correctnessPassed && validity.isValid }
    var invalidReason: String? {
        if !metrics.correctnessPassed { return "REJECTED_CORRECTNESS" }
        let reasons = validity.failures.map(\.rawValue)
        return reasons.isEmpty ? nil : reasons.joined(separator: ",")
    }
}

struct CombatIncidentRecord: Sendable {
    let incidentID: String
    let benchmarkID: String
    let sessionID: String
    let presetID: RuntimeExperimentPreset
    let trigger: String
    let observedMonotonicNS: UInt64
    let effectiveFPS: Double?
    let onePercentLowFPS: Double?
    let p99IntervalMilliseconds: Double?
    let severeCount: Int
    let traceSequence: Int?
    let firstDivergentBoundary: String
    let confidence: String
    let explicitUnknowns: String
}

struct CombatComparisonRecord: Sendable {
    let comparisonID: String
    let controlBenchmarkID: String
    let candidateBenchmarkID: String
    let analysis: CombatBenchmarkAnalysis
    let correctnessStatus: String
    let observerOverheadInvalid: Bool
    let createdUTC: String
}

struct ActiveCombatBenchmark: Sendable {
    let benchmarkID: String
    let sessionID: String
    let presetID: RuntimeExperimentPreset
    let configurationSHA256: String
    let comparisonIdentitySHA256: String
    let configurationJSON: String
    let tftPackageVersion: String
    let performanceModeConfirmed: Bool
    let startedUTC: String
    let startedMonotonicNS: UInt64

    private(set) var intervalMilliseconds = [Double]()
    private(set) var traceActiveIntervals = [Double]()
    private(set) var traceInactiveIntervals = [Double]()
    private(set) var jankCount = 0
    private(set) var severeCount = 0
    private(set) var missedVsyncEquivalents = 0
    private(set) var measuredWindowNS: UInt64 = 0
    private(set) var availableWindowNS: UInt64 = 0
    private(set) var historyTruncated = false
    private(set) var layerNames = Set<String>()
    private(set) var clockSamples = [(hostMidpointNS: UInt64, roundTripNS: UInt64)]()

    mutating func ingest(
        update: GameFrameTelemetryUpdate?,
        window: GameFrameTelemetryWindow,
        traceActive: Bool
    ) {
        let duration = window.endedMonotonicNS >= window.startedMonotonicNS
            ? window.endedMonotonicNS - window.startedMonotonicNS
            : 0
        measuredWindowNS &+= duration
        historyTruncated = historyTruncated || window.historyTruncated
        if case .available = window.status {
            availableWindowNS &+= duration
            if let layerName = window.layerName { layerNames.insert(layerName) }
        }
        guard let update else { return }
        let values = update.intervals.map(\.intervalMS)
        intervalMilliseconds.append(contentsOf: values)
        if traceActive {
            traceActiveIntervals.append(contentsOf: values)
        } else {
            traceInactiveIntervals.append(contentsOf: values)
        }
        jankCount += update.intervals.lazy.filter(\.isJanky).count
        severeCount += update.intervals.lazy.filter(\.isSevere).count
        missedVsyncEquivalents += update.intervals.reduce(0) { $0 + $1.missedVsyncEquivalents }
    }

    mutating func recordClock(hostMidpointNS: UInt64, roundTripNS: UInt64) {
        clockSamples.append((hostMidpointNS, roundTripNS))
    }

    func finish(
        endedUTC: String,
        endedMonotonicNS: UInt64,
        correctnessPassed: Bool = true
    ) -> CombatBenchmarkRun {
        let durationNS = endedMonotonicNS >= startedMonotonicNS
            ? endedMonotonicNS - startedMonotonicNS
            : 0
        let durationSeconds = Double(durationNS) / 1_000_000_000
        let surfaceAvailability = measuredWindowNS == 0
            ? 0
            : min(1, Double(availableWindowNS) / Double(measuredWindowNS))
        let orderedClock = clockSamples.sorted { $0.hostMidpointNS < $1.hostMidpointNS }
        let clockCoverage: Double
        if let first = orderedClock.first?.hostMidpointNS, let last = orderedClock.last?.hostMidpointNS,
           durationNS > 0, last >= first {
            let bracketStart = max(startedMonotonicNS, first)
            let bracketEnd = min(endedMonotonicNS, last)
            clockCoverage = bracketEnd > bracketStart
                ? min(1, Double(bracketEnd - bracketStart) / Double(durationNS))
                : 0
        } else {
            clockCoverage = 0
        }
        let orderedRTTMS = orderedClock.map { Double($0.roundTripNS) / 1_000_000 }.sorted()
        let p95RTTMS = orderedRTTMS.isEmpty ? 1_000_000_000 : Self.percentile(orderedRTTMS, 0.95)
        let ordered = intervalMilliseconds.sorted()
        let intervalTotalMS = ordered.reduce(0, +)
        let weightedFPS = intervalTotalMS > 0 ? Double(ordered.count) / (intervalTotalMS / 1_000) : 0
        let p50 = Self.percentile(ordered, 0.50)
        let p95 = Self.percentile(ordered, 0.95)
        let p99 = Self.percentile(ordered, 0.99)
        let maximum = ordered.last ?? 0
        let count = max(1, ordered.count)
        let metrics = CombatBenchmarkMetrics(
            combatDurationSeconds: durationSeconds,
            surfaceAvailability: surfaceAvailability,
            clockCoverage: clockCoverage,
            p95ClockRoundTripMilliseconds: p95RTTMS,
            frameHistoryTruncated: historyTruncated,
            exactLayerStable: layerNames.count == 1,
            correctnessPassed: correctnessPassed,
            weightedFPS: weightedFPS,
            onePercentLowFPS: CombatBenchmarkMetrics.onePercentLowFPS(from: ordered),
            p95IntervalMilliseconds: p95,
            p99IntervalMilliseconds: p99,
            jankRate: Double(jankCount) / Double(count),
            severeRate: Double(severeCount) / Double(count),
            missedVsyncRate: Double(missedVsyncEquivalents) / Double(count)
        )
        return CombatBenchmarkRun(
            benchmarkID: benchmarkID,
            sessionID: sessionID,
            presetID: presetID,
            configurationSHA256: configurationSHA256,
            comparisonIdentitySHA256: comparisonIdentitySHA256,
            configurationJSON: configurationJSON,
            tftPackageVersion: tftPackageVersion,
            performanceModeConfirmed: performanceModeConfirmed,
            startedUTC: startedUTC,
            endedUTC: endedUTC,
            startedMonotonicNS: startedMonotonicNS,
            endedMonotonicNS: endedMonotonicNS,
            exactLayerIdentity: layerNames.count == 1 ? layerNames.first : nil,
            metrics: metrics,
            p50IntervalMilliseconds: p50,
            maximumIntervalMilliseconds: maximum,
            observerOverheadInvalid: Self.observerOverheadInvalid(
                traceActive: traceActiveIntervals,
                traceInactive: traceInactiveIntervals
            )
        )
    }

    private static func percentile(_ ordered: [Double], _ quantile: Double) -> Double {
        guard !ordered.isEmpty else { return 0 }
        let index = min(ordered.count - 1, max(0, Int(ceil(Double(ordered.count) * quantile)) - 1))
        return ordered[index]
    }

    private static func observerOverheadInvalid(traceActive: [Double], traceInactive: [Double]) -> Bool {
        guard traceActive.count >= 10, traceInactive.count >= 10 else { return false }
        let activeTotal = traceActive.reduce(0, +)
        let inactiveTotal = traceInactive.reduce(0, +)
        guard activeTotal > 0, inactiveTotal > 0 else { return false }
        let activeFPS = Double(traceActive.count) / (activeTotal / 1_000)
        let inactiveFPS = Double(traceInactive.count) / (inactiveTotal / 1_000)
        let fpsDelta = abs((activeFPS - inactiveFPS) / inactiveFPS) * 100
        let activeP95 = percentile(traceActive.sorted(), 0.95)
        let inactiveP95 = percentile(traceInactive.sorted(), 0.95)
        let p95Delta = inactiveP95 > 0 ? abs((activeP95 - inactiveP95) / inactiveP95) * 100 : 0
        return fpsDelta > 5 || p95Delta > 5
    }
}

final class CombatBenchmarkLabStore: @unchecked Sendable {
    private enum Value {
        case integer(Int64)
        case real(Double)
        case text(String)
        case null
    }

    private var database: OpaquePointer?
    private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(applicationSupport: URL) throws {
        try FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        let databaseURL = applicationSupport.appendingPathComponent("TFTMAC_LAB.sqlite")
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            throw TFTMACRuntimeError("The persistent TFTMAC lab database could not be opened.")
        }
        sqlite3_busy_timeout(database, 5_000)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
        try createSchema()
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    func record(_ run: CombatBenchmarkRun) throws {
        try execute(Self.insertBenchmarkSQL, Self.benchmarkValues(run))
    }

    func record(_ incident: CombatIncidentRecord) throws {
        try execute(Self.insertIncidentSQL, Self.incidentValues(incident))
    }

    func comparisonForCandidate(_ candidate: CombatBenchmarkRun) throws -> CombatComparisonRecord? {
        guard candidate.presetID.isActiveCandidate,
              candidate.isValid,
              candidate.exactLayerIdentity != nil,
              let control = try latestValidControl(matching: candidate) else { return nil }
        let analysis = CombatBenchmarkAnalysis(baseline: control.metrics, candidate: candidate.metrics)
        let comparison = CombatComparisonRecord(
            comparisonID: UUID().uuidString.lowercased(),
            controlBenchmarkID: control.benchmarkID,
            candidateBenchmarkID: candidate.benchmarkID,
            analysis: analysis,
            correctnessStatus: candidate.metrics.correctnessPassed ? "PASSED" : "REJECTED_CORRECTNESS",
            observerOverheadInvalid: control.observerOverheadInvalid || candidate.observerOverheadInvalid,
            createdUTC: Self.utcNow()
        )
        try record(comparison)
        return comparison
    }

    func record(_ comparison: CombatComparisonRecord) throws {
        let deltas = comparison.analysis.deltas
        try execute(
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
                .text(comparison.correctnessStatus), .integer(comparison.observerOverheadInvalid ? 1 : 0),
                .text(comparison.analysis.decision.rawValue), .text(comparison.createdUTC)
            ]
        )
    }

    private func latestValidControl(matching candidate: CombatBenchmarkRun) throws -> CombatBenchmarkRun? {
        guard let database else { return nil }
        let sql = """
        SELECT benchmark_id, session_id, configuration_sha256, comparison_identity_sha256,
               configuration_json, tft_package_version, performance_mode_confirmed, started_utc, ended_utc,
               started_monotonic_ns, ended_monotonic_ns, exact_layer_identity,
               duration_seconds, surface_availability, clock_coverage, p95_clock_rtt_ms,
               history_truncated, correctness_passed, weighted_fps, one_percent_low_fps,
               p50_interval_ms, p95_interval_ms, p99_interval_ms, max_interval_ms,
               jank_rate, severe_rate, missed_vsync_rate, observer_overhead_invalid
        FROM combat_benchmarks
        WHERE preset_id = 'control' AND valid = 1 AND correctness_passed = 1
          AND comparison_identity_sha256 = ? AND tft_package_version = ?
          AND exact_layer_identity IS NOT NULL AND ended_utc <= ?
        ORDER BY ended_utc DESC LIMIT 20
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw TFTMACRuntimeError("SQLite could not prepare the control benchmark query.") }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, candidate.comparisonIdentitySHA256, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, candidate.tftPackageVersion, -1, transientDestructor)
        sqlite3_bind_text(statement, 3, candidate.endedUTC, -1, transientDestructor)
        func text(_ index: Int32) -> String {
            guard let value = sqlite3_column_text(statement, index) else { return "" }
            return String(cString: value)
        }
        guard let candidateLayer = CombatLayerIdentity.comparable(candidate.exactLayerIdentity!) else { return nil }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard CombatLayerIdentity.comparable(text(11)) == candidateLayer else { continue }
            let metrics = CombatBenchmarkMetrics(
            combatDurationSeconds: sqlite3_column_double(statement, 12),
            surfaceAvailability: sqlite3_column_double(statement, 13),
            clockCoverage: sqlite3_column_double(statement, 14),
            p95ClockRoundTripMilliseconds: sqlite3_column_double(statement, 15),
            frameHistoryTruncated: sqlite3_column_int(statement, 16) != 0,
            exactLayerStable: sqlite3_column_type(statement, 11) != SQLITE_NULL,
            correctnessPassed: sqlite3_column_int(statement, 17) != 0,
            weightedFPS: sqlite3_column_double(statement, 18),
            onePercentLowFPS: sqlite3_column_double(statement, 19),
            p95IntervalMilliseconds: sqlite3_column_double(statement, 21),
            p99IntervalMilliseconds: sqlite3_column_double(statement, 22),
            jankRate: sqlite3_column_double(statement, 24),
            severeRate: sqlite3_column_double(statement, 25),
            missedVsyncRate: sqlite3_column_double(statement, 26)
        )
            return CombatBenchmarkRun(
                benchmarkID: text(0), sessionID: text(1), presetID: .control,
                configurationSHA256: text(2), comparisonIdentitySHA256: text(3), configurationJSON: text(4),
                tftPackageVersion: text(5), performanceModeConfirmed: sqlite3_column_int(statement, 6) != 0,
                startedUTC: text(7), endedUTC: text(8),
                startedMonotonicNS: UInt64(bitPattern: sqlite3_column_int64(statement, 9)),
                endedMonotonicNS: UInt64(bitPattern: sqlite3_column_int64(statement, 10)),
                exactLayerIdentity: text(11), metrics: metrics,
                p50IntervalMilliseconds: sqlite3_column_double(statement, 20),
                maximumIntervalMilliseconds: sqlite3_column_double(statement, 23),
                observerOverheadInvalid: sqlite3_column_int(statement, 27) != 0
            )
        }
        return nil
    }

    private func createSchema() throws {
        guard let database else { throw TFTMACRuntimeError("The persistent lab database is closed.") }
        guard sqlite3_exec(database, Self.schemaSQL, nil, nil, nil) == SQLITE_OK else {
            throw TFTMACRuntimeError("The persistent combat benchmark schema could not be created.")
        }
        // Existing lab databases predate the comparison identity. Old rows stay
        // nullable and cannot be paired with a new candidate.
        sqlite3_exec(
            database,
            "ALTER TABLE combat_benchmarks ADD COLUMN comparison_identity_sha256 TEXT",
            nil,
            nil,
            nil
        )
    }

    private func execute(_ sql: String, _ values: [Value]) throws {
        guard let database else { throw TFTMACRuntimeError("The persistent lab database is closed.") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw TFTMACRuntimeError("SQLite could not prepare a combat benchmark statement.") }
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
            throw TFTMACRuntimeError("SQLite could not write a combat benchmark statement.")
        }
    }

    static let insertBenchmarkSQL = """
    INSERT OR REPLACE INTO combat_benchmarks(
      benchmark_id, session_id, preset_id, configuration_sha256, comparison_identity_sha256, configuration_json,
      tft_package_version, performance_mode_confirmed, started_utc, ended_utc,
      started_monotonic_ns, ended_monotonic_ns, exact_layer_identity, duration_seconds,
      surface_availability, clock_coverage, p95_clock_rtt_ms, history_truncated,
      correctness_passed, weighted_fps, one_percent_low_fps, p50_interval_ms,
      p95_interval_ms, p99_interval_ms, max_interval_ms, jank_rate, severe_rate,
      missed_vsync_rate, observer_overhead_invalid, valid, invalid_reason
    ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    private static func benchmarkValues(_ run: CombatBenchmarkRun) -> [Value] {
        let metrics = run.metrics
        return [
            .text(run.benchmarkID), .text(run.sessionID), .text(run.presetID.rawValue),
            .text(run.configurationSHA256), .text(run.comparisonIdentitySHA256),
            .text(run.configurationJSON), .text(run.tftPackageVersion),
            .integer(run.performanceModeConfirmed ? 1 : 0), .text(run.startedUTC), .text(run.endedUTC),
            .integer(Int64(bitPattern: run.startedMonotonicNS)), .integer(Int64(bitPattern: run.endedMonotonicNS)),
            run.exactLayerIdentity.map(Value.text) ?? .null, .real(metrics.combatDurationSeconds),
            .real(metrics.surfaceAvailability), .real(metrics.clockCoverage),
            .real(metrics.p95ClockRoundTripMilliseconds), .integer(metrics.frameHistoryTruncated ? 1 : 0),
            .integer(metrics.correctnessPassed ? 1 : 0), .real(metrics.weightedFPS),
            .real(metrics.onePercentLowFPS), .real(run.p50IntervalMilliseconds),
            .real(metrics.p95IntervalMilliseconds), .real(metrics.p99IntervalMilliseconds),
            .real(run.maximumIntervalMilliseconds), .real(metrics.jankRate), .real(metrics.severeRate),
            .real(metrics.missedVsyncRate), .integer(run.observerOverheadInvalid ? 1 : 0),
            .integer(run.isValid ? 1 : 0), run.invalidReason.map(Value.text) ?? .null
        ]
    }

    static let insertIncidentSQL = """
    INSERT INTO combat_incidents(
      incident_id, benchmark_id, session_id, preset_id, trigger, observed_monotonic_ns,
      effective_fps, one_percent_low_fps, p99_interval_ms, severe_count, trace_sequence,
      first_divergent_boundary, confidence, explicit_unknowns
    ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    private static func incidentValues(_ incident: CombatIncidentRecord) -> [Value] {
        [
            .text(incident.incidentID), .text(incident.benchmarkID), .text(incident.sessionID),
            .text(incident.presetID.rawValue), .text(incident.trigger),
            .integer(Int64(bitPattern: incident.observedMonotonicNS)),
            incident.effectiveFPS.map(Value.real) ?? .null,
            incident.onePercentLowFPS.map(Value.real) ?? .null,
            incident.p99IntervalMilliseconds.map(Value.real) ?? .null,
            .integer(Int64(incident.severeCount)),
            incident.traceSequence.map { .integer(Int64($0)) } ?? .null,
            .text(incident.firstDivergentBoundary), .text(incident.confidence),
            .text(incident.explicitUnknowns)
        ]
    }

    static let schemaSQL = """
    CREATE TABLE IF NOT EXISTS combat_benchmarks(
      benchmark_id TEXT PRIMARY KEY, session_id TEXT NOT NULL, preset_id TEXT NOT NULL,
      configuration_sha256 TEXT NOT NULL, comparison_identity_sha256 TEXT NOT NULL,
      configuration_json TEXT NOT NULL,
      tft_package_version TEXT NOT NULL, performance_mode_confirmed INTEGER NOT NULL,
      started_utc TEXT NOT NULL, ended_utc TEXT NOT NULL,
      started_monotonic_ns INTEGER NOT NULL, ended_monotonic_ns INTEGER NOT NULL,
      exact_layer_identity TEXT, duration_seconds REAL NOT NULL,
      surface_availability REAL NOT NULL, clock_coverage REAL NOT NULL,
      p95_clock_rtt_ms REAL NOT NULL, history_truncated INTEGER NOT NULL,
      correctness_passed INTEGER NOT NULL, weighted_fps REAL NOT NULL,
      one_percent_low_fps REAL NOT NULL, p50_interval_ms REAL NOT NULL,
      p95_interval_ms REAL NOT NULL, p99_interval_ms REAL NOT NULL,
      max_interval_ms REAL NOT NULL, jank_rate REAL NOT NULL, severe_rate REAL NOT NULL,
      missed_vsync_rate REAL NOT NULL, observer_overhead_invalid INTEGER NOT NULL,
      valid INTEGER NOT NULL, invalid_reason TEXT
    );
    CREATE TABLE IF NOT EXISTS combat_incidents(
      incident_id TEXT PRIMARY KEY, benchmark_id TEXT NOT NULL, session_id TEXT NOT NULL,
      preset_id TEXT NOT NULL, trigger TEXT NOT NULL, observed_monotonic_ns INTEGER NOT NULL,
      effective_fps REAL, one_percent_low_fps REAL, p99_interval_ms REAL,
      severe_count INTEGER NOT NULL, trace_sequence INTEGER,
      first_divergent_boundary TEXT NOT NULL, confidence TEXT NOT NULL,
      explicit_unknowns TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS combat_comparisons(
      comparison_id TEXT PRIMARY KEY, control_benchmark_id TEXT NOT NULL,
      candidate_benchmark_id TEXT NOT NULL, weighted_fps_delta_percent REAL NOT NULL,
      one_percent_low_delta_percent REAL NOT NULL, p95_delta_percent REAL NOT NULL,
      p99_delta_percent REAL NOT NULL, jank_delta_points REAL NOT NULL,
      severe_delta_points REAL NOT NULL, missed_vsync_delta_points REAL NOT NULL,
      correctness_status TEXT NOT NULL, observer_overhead_invalid INTEGER NOT NULL,
      decision TEXT NOT NULL, created_utc TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_combat_benchmarks_preset_end ON combat_benchmarks(preset_id, ended_utc);
    CREATE INDEX IF NOT EXISTS idx_combat_incidents_benchmark_time ON combat_incidents(benchmark_id, observed_monotonic_ns);
    """

    private static func utcNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
