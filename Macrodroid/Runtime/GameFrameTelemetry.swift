import Foundation

enum GameFrameTelemetryUnavailable: Sendable, Equatable {
    case noTFTSurfaceView
    case multipleTFTSurfaceViews
    case noTimestamps
    case malformedLatency
    case adbError
}

enum GameFrameTelemetryStatus: Sendable, Equatable {
    case available
    case unavailable(GameFrameTelemetryUnavailable)
}

enum GameFrameLayerSelection: Sendable, Equatable {
    case selected(String)
    case unavailable(GameFrameTelemetryUnavailable)
}

struct GameFrameLatencySample: Sendable, Equatable {
    let desiredPresentNS: UInt64
    let actualPresentNS: UInt64
    let frameReadyNS: UInt64
}

struct GameFrameLatencyPoll: Sendable, Equatable {
    let refreshPeriodNS: UInt64
    let samples: [GameFrameLatencySample]
    let historyTruncated: Bool
}

struct GameFramePresentInterval: Sendable, Equatable {
    let actualPresentNS: UInt64
    let intervalNS: UInt64
    let intervalMS: Double
    let missedVsyncEquivalents: Int
    let isJanky: Bool
    let isSevere: Bool
}

struct GameFrameTelemetryWindow: Sendable, Equatable {
    let status: GameFrameTelemetryStatus
    let layerName: String?
    let refreshPeriodNS: UInt64?
    let startedMonotonicNS: UInt64
    let endedMonotonicNS: UInt64
    let frameCount: Int
    let effectiveFPS: Double
    let p50MS: Double?
    let p95MS: Double?
    let p99MS: Double?
    let maximumMS: Double?
    let onePercentLowFPS: Double?
    let jankCount: Int
    let severeCount: Int
    let missedVsyncEquivalents: Int
    let historyTruncated: Bool
}

struct GameFrameTelemetryUpdate: Sendable, Equatable {
    let status: GameFrameTelemetryStatus
    let layerName: String?
    let refreshPeriodNS: UInt64?
    let intervals: [GameFramePresentInterval]
    let window: GameFrameTelemetryWindow?
}

enum GameFrameTelemetry {
    static let tftGameActivitySurface = "SurfaceView[com.riotgames.league.teamfighttactics/com.epicgames.unreal.GameActivity](BLAST)"
    static let maxLatencyHistoryFrames = 128

    static func selectTFTSurfaceViewLayer(from output: String) -> GameFrameLayerSelection {
        let matches = output.split(whereSeparator: \.isNewline).compactMap { rawLine -> String? in
            let line = normalizedLayerLine(String(rawLine))
            guard line.contains(tftGameActivitySurface) else { return nil }
            return line
        }
        switch matches.count {
        case 0: return .unavailable(.noTFTSurfaceView)
        case 1: return .selected(matches[0])
        default: return .unavailable(.multipleTFTSurfaceViews)
        }
    }

    static func parseSurfaceFlingerLatency(_ output: String) -> GameFrameLatencyPoll? {
        let lines = output.split(whereSeparator: \.isNewline)
        guard let first = lines.first,
              let refresh = UInt64(first.trimmingCharacters(in: .whitespacesAndNewlines)), refresh > 0 else {
            return nil
        }
        let samples = lines.dropFirst().compactMap(parseLatencyLine).sorted { $0.actualPresentNS < $1.actualPresentNS }
        return GameFrameLatencyPoll(
            refreshPeriodNS: refresh,
            samples: samples,
            historyTruncated: samples.count >= maxLatencyHistoryFrames
        )
    }

    static func surfaceFlingerLatencyShellCommand(layerName: String) -> String {
        "dumpsys SurfaceFlinger --latency \(androidShellQuote(layerName))"
    }

    private static func normalizedLayerLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("RequestedLayerState{") else { return trimmed }
        let start = trimmed.index(trimmed.startIndex, offsetBy: "RequestedLayerState{".count)
        let remainder = String(trimmed[start...])
        guard let parent = remainder.range(of: " parentId=") else { return remainder }
        return String(remainder[..<parent.lowerBound])
    }

    private static func parseLatencyLine(_ line: Substring) -> GameFrameLatencySample? {
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count == 3,
              let desired = UInt64(fields[0]), let actual = UInt64(fields[1]), let ready = UInt64(fields[2]),
              desired > 0, actual > 0, ready > 0,
              !isSentinel(desired), !isSentinel(actual), !isSentinel(ready) else { return nil }
        return GameFrameLatencySample(desiredPresentNS: desired, actualPresentNS: actual, frameReadyNS: ready)
    }

    private static func isSentinel(_ value: UInt64) -> Bool {
        value == UInt64.max || value == UInt64(Int64.max)
    }

    private static func androidShellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct GameFrameTelemetrySampler: Sendable {
    private(set) var status: GameFrameTelemetryStatus = .unavailable(.noTFTSurfaceView)
    private(set) var selectedLayer: String?
    private let windowDurationNS: UInt64
    private var previousActualPresentNS: UInt64?
    private var recentActualPresentNS = [UInt64]()
    private var windowStartedNS: UInt64?
    private var windowIntervals = [GameFramePresentInterval]()
    private var windowHistoryTruncated = false
    private var windowRefreshPeriodNS: UInt64?

    init(windowDurationNS: UInt64 = 1_000_000_000) {
        self.windowDurationNS = windowDurationNS
    }

    mutating func updateLayerList(_ output: String) -> GameFrameTelemetryStatus {
        switch GameFrameTelemetry.selectTFTSurfaceViewLayer(from: output) {
        case .selected(let layer):
            if selectedLayer != layer { reset(layer: layer) }
            status = .available
        case .unavailable(let reason):
            selectedLayer = nil
            status = .unavailable(reason)
            resetTimingState()
        }
        return status
    }

    mutating func ingestLatency(_ output: String, observedMonotonicNS: UInt64) -> GameFrameTelemetryUpdate {
        guard case .available = status else {
            return GameFrameTelemetryUpdate(
                status: status, layerName: selectedLayer, refreshPeriodNS: nil,
                intervals: [], window: nil
            )
        }
        guard let poll = GameFrameTelemetry.parseSurfaceFlingerLatency(output) else {
            status = .unavailable(.malformedLatency)
            resetTimingState()
            return GameFrameTelemetryUpdate(
                status: status, layerName: selectedLayer, refreshPeriodNS: nil,
                intervals: [], window: nil
            )
        }

        guard !poll.samples.isEmpty || previousActualPresentNS != nil else {
            status = .unavailable(.noTimestamps)
            return GameFrameTelemetryUpdate(
                status: status, layerName: selectedLayer, refreshPeriodNS: poll.refreshPeriodNS,
                intervals: [], window: nil
            )
        }

        // The first successful poll establishes a boundary. SurfaceFlinger
        // returns a rolling history, so treating that backlog as frames seen
        // during this session would inflate the first measurement window.
        if previousActualPresentNS == nil, let latest = poll.samples.last {
            previousActualPresentNS = latest.actualPresentNS
            recentActualPresentNS = poll.samples.map(\.actualPresentNS)
            windowStartedNS = observedMonotonicNS
            windowRefreshPeriodNS = poll.refreshPeriodNS
            return GameFrameTelemetryUpdate(
                status: status, layerName: selectedLayer, refreshPeriodNS: poll.refreshPeriodNS,
                intervals: [], window: nil
            )
        }

        if windowStartedNS == nil { windowStartedNS = observedMonotonicNS }
        windowRefreshPeriodNS = poll.refreshPeriodNS
        let previousWasRetained = previousActualPresentNS.map { previous in
            poll.samples.contains(where: { $0.actualPresentNS == previous })
        } ?? true
        let newSamples = poll.samples.filter { !recentActualPresentNS.contains($0.actualPresentNS) }
        recentActualPresentNS.append(contentsOf: newSamples.map(\.actualPresentNS))
        if recentActualPresentNS.count > GameFrameTelemetry.maxLatencyHistoryFrames {
            recentActualPresentNS.removeFirst(recentActualPresentNS.count - GameFrameTelemetry.maxLatencyHistoryFrames)
        }

        var intervals = [GameFramePresentInterval]()
        if poll.historyTruncated, !previousWasRetained, !newSamples.isEmpty {
            // More frames arrived than the SurfaceFlinger ring retained. Do
            // not collapse the missing history into one fabricated interval.
            previousActualPresentNS = newSamples.first?.actualPresentNS
            windowHistoryTruncated = true
        }
        for sample in newSamples {
            defer { previousActualPresentNS = sample.actualPresentNS }
            guard let previous = previousActualPresentNS, sample.actualPresentNS > previous else { continue }
            let intervalNS = sample.actualPresentNS - previous
            let interval = makeInterval(actualPresentNS: sample.actualPresentNS, intervalNS: intervalNS, refreshPeriodNS: poll.refreshPeriodNS)
            intervals.append(interval)
            windowIntervals.append(interval)
        }
        let completedWindow: GameFrameTelemetryWindow?
        if let started = windowStartedNS, observedMonotonicNS >= started &+ windowDurationNS {
            completedWindow = makeWindow(startedNS: started, endedNS: observedMonotonicNS)
            windowStartedNS = observedMonotonicNS
            windowIntervals.removeAll(keepingCapacity: true)
            windowHistoryTruncated = false
            windowRefreshPeriodNS = poll.refreshPeriodNS
        } else {
            completedWindow = nil
        }
        return GameFrameTelemetryUpdate(
            status: status, layerName: selectedLayer, refreshPeriodNS: poll.refreshPeriodNS,
            intervals: intervals, window: completedWindow
        )
    }

    private mutating func reset(layer: String?) {
        selectedLayer = layer
        resetTimingState()
    }

    private mutating func resetTimingState() {
        previousActualPresentNS = nil
        recentActualPresentNS.removeAll(keepingCapacity: true)
        windowStartedNS = nil
        windowIntervals.removeAll(keepingCapacity: true)
        windowHistoryTruncated = false
        windowRefreshPeriodNS = nil
    }

    private func makeInterval(actualPresentNS: UInt64, intervalNS: UInt64, refreshPeriodNS: UInt64) -> GameFramePresentInterval {
        let vsyncs = max(1, Int((Double(intervalNS) / Double(refreshPeriodNS)).rounded()))
        return GameFramePresentInterval(
            actualPresentNS: actualPresentNS,
            intervalNS: intervalNS,
            intervalMS: Double(intervalNS) / 1_000_000,
            missedVsyncEquivalents: max(0, vsyncs - 1),
            isJanky: Double(intervalNS) > Double(refreshPeriodNS) * 1.5,
            isSevere: Double(intervalNS) >= Double(refreshPeriodNS) * 3
        )
    }

    private func makeWindow(startedNS: UInt64, endedNS: UInt64) -> GameFrameTelemetryWindow {
        let sorted = windowIntervals.map(\.intervalMS).sorted()
        let elapsed = max(1, endedNS - startedNS)
        let fps = Double(windowIntervals.count) * 1_000_000_000 / Double(elapsed)
        let slowFrameCount = max(1, Int(ceil(Double(sorted.count) * 0.01)))
        let slowMeanMS = sorted.isEmpty ? nil : sorted.suffix(slowFrameCount).reduce(0, +) / Double(slowFrameCount)
        let onePercentLow = slowMeanMS.map { $0 > 0 ? 1000 / $0 : 0 }
        return GameFrameTelemetryWindow(
            status: status,
            layerName: selectedLayer,
            refreshPeriodNS: windowRefreshPeriodNS,
            startedMonotonicNS: startedNS,
            endedMonotonicNS: endedNS,
            frameCount: windowIntervals.count,
            effectiveFPS: fps,
            p50MS: percentile(sorted, 0.50),
            p95MS: percentile(sorted, 0.95),
            p99MS: percentile(sorted, 0.99),
            maximumMS: sorted.last,
            onePercentLowFPS: onePercentLow,
            jankCount: windowIntervals.filter(\.isJanky).count,
            severeCount: windowIntervals.filter(\.isSevere).count,
            missedVsyncEquivalents: windowIntervals.reduce(0) { $0 + $1.missedVsyncEquivalents },
            historyTruncated: windowHistoryTruncated
        )
    }

    private func percentile(_ sorted: [Double], _ percentile: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        return sorted[percentileIndex(count: sorted.count, percentile: percentile)]
    }

    private func percentileIndex(count: Int, percentile: Double) -> Int {
        min(count - 1, max(0, Int(ceil(Double(count) * percentile)) - 1))
    }
}
