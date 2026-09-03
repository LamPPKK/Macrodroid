import Foundation

enum CombatLayerIdentity {
    static func comparable(_ identity: String) -> String? {
        let stable = "SurfaceView[com.riotgames.league.teamfighttactics/com.epicgames.unreal.GameActivity]"
        return identity.contains(stable) ? stable : nil
    }
}

enum CombatBenchmarkDecision: String, Equatable, Sendable {
    case homeRun = "HOME_RUN"
    case promising = "PROMISING"
    case reject = "REJECT"
    case inconclusive = "INCONCLUSIVE"
}

enum CombatBenchmarkValidityFailure: String, Equatable, Sendable {
    case combatDurationTooShort
    case insufficientSurfaceAvailability
    case insufficientClockCoverage
    case clockRoundTripTooHigh
    case frameHistoryTruncated
    case exactLayerChangedOrAmbiguous
}

struct CombatBenchmarkValidity: Equatable, Sendable {
    static let minimumCombatDurationSeconds = 300.0
    static let minimumSurfaceAvailability = 0.95
    static let minimumClockCoverage = 0.95
    static let maximumP95ClockRoundTripMilliseconds = 10.0

    let failures: [CombatBenchmarkValidityFailure]

    var isValid: Bool { failures.isEmpty }

    static func evaluate(_ metrics: CombatBenchmarkMetrics) -> CombatBenchmarkValidity {
        var failures = [CombatBenchmarkValidityFailure]()
        if metrics.combatDurationSeconds < minimumCombatDurationSeconds {
            failures.append(.combatDurationTooShort)
        }
        if metrics.surfaceAvailability < minimumSurfaceAvailability {
            failures.append(.insufficientSurfaceAvailability)
        }
        if metrics.clockCoverage < minimumClockCoverage {
            failures.append(.insufficientClockCoverage)
        }
        if metrics.p95ClockRoundTripMilliseconds > maximumP95ClockRoundTripMilliseconds {
            failures.append(.clockRoundTripTooHigh)
        }
        if metrics.frameHistoryTruncated {
            failures.append(.frameHistoryTruncated)
        }
        if !metrics.exactLayerStable {
            failures.append(.exactLayerChangedOrAmbiguous)
        }
        return CombatBenchmarkValidity(failures: failures)
    }
}

struct CombatBenchmarkMetrics: Equatable, Sendable {
    let combatDurationSeconds: Double
    let surfaceAvailability: Double
    let clockCoverage: Double
    let p95ClockRoundTripMilliseconds: Double
    let frameHistoryTruncated: Bool
    let exactLayerStable: Bool
    let correctnessPassed: Bool
    let weightedFPS: Double
    let onePercentLowFPS: Double
    let p95IntervalMilliseconds: Double
    let p99IntervalMilliseconds: Double
    let jankRate: Double
    let severeRate: Double
    let missedVsyncRate: Double

    init(
        combatDurationSeconds: Double,
        surfaceAvailability: Double,
        clockCoverage: Double,
        p95ClockRoundTripMilliseconds: Double,
        frameHistoryTruncated: Bool,
        exactLayerStable: Bool,
        correctnessPassed: Bool,
        weightedFPS: Double,
        onePercentLowFPS: Double,
        p95IntervalMilliseconds: Double,
        p99IntervalMilliseconds: Double,
        jankRate: Double,
        severeRate: Double,
        missedVsyncRate: Double
    ) {
        self.combatDurationSeconds = combatDurationSeconds
        self.surfaceAvailability = surfaceAvailability
        self.clockCoverage = clockCoverage
        self.p95ClockRoundTripMilliseconds = p95ClockRoundTripMilliseconds
        self.frameHistoryTruncated = frameHistoryTruncated
        self.exactLayerStable = exactLayerStable
        self.correctnessPassed = correctnessPassed
        self.weightedFPS = weightedFPS
        self.onePercentLowFPS = onePercentLowFPS
        self.p95IntervalMilliseconds = p95IntervalMilliseconds
        self.p99IntervalMilliseconds = p99IntervalMilliseconds
        self.jankRate = jankRate
        self.severeRate = severeRate
        self.missedVsyncRate = missedVsyncRate
    }

    static func onePercentLowFPS(from intervalMilliseconds: [Double]) -> Double {
        guard !intervalMilliseconds.isEmpty else { return 0 }
        let slowFrameCount = max(1, Int(ceil(Double(intervalMilliseconds.count) * 0.01)))
        let slowest = intervalMilliseconds.sorted().suffix(slowFrameCount)
        let meanSlowInterval = slowest.reduce(0, +) / Double(slowest.count)
        return meanSlowInterval > 0 ? 1_000 / meanSlowInterval : 0
    }
}

struct CombatBenchmarkDeltas: Equatable, Sendable {
    /// Positive values mean the candidate has more FPS than the baseline.
    let weightedFPSPercent: Double
    /// Positive values mean the candidate has more 1%-low FPS than the baseline.
    let onePercentLowFPSPercent: Double
    /// Positive values mean the candidate has a longer (worse) frame interval.
    let p95IntervalPercent: Double
    /// Positive values mean the candidate has a longer (worse) frame interval.
    let p99IntervalPercent: Double
    /// Positive values mean more affected frames than the baseline.
    let jankRatePercentagePoints: Double
    /// Positive values mean more severe frames than the baseline.
    let severeRatePercentagePoints: Double
    /// Positive values mean more missed-vsync equivalents than the baseline.
    let missedVsyncRatePercentagePoints: Double

    init(baseline: CombatBenchmarkMetrics, candidate: CombatBenchmarkMetrics) {
        weightedFPSPercent = Self.percentChange(from: baseline.weightedFPS, to: candidate.weightedFPS)
        onePercentLowFPSPercent = Self.percentChange(from: baseline.onePercentLowFPS, to: candidate.onePercentLowFPS)
        p95IntervalPercent = Self.percentChange(from: baseline.p95IntervalMilliseconds, to: candidate.p95IntervalMilliseconds)
        p99IntervalPercent = Self.percentChange(from: baseline.p99IntervalMilliseconds, to: candidate.p99IntervalMilliseconds)
        jankRatePercentagePoints = candidate.jankRate - baseline.jankRate
        severeRatePercentagePoints = candidate.severeRate - baseline.severeRate
        missedVsyncRatePercentagePoints = candidate.missedVsyncRate - baseline.missedVsyncRate
    }

    private static func percentChange(from baseline: Double, to candidate: Double) -> Double {
        guard baseline > 0 else { return candidate == 0 ? 0 : .infinity }
        return ((candidate - baseline) / baseline) * 100
    }
}

struct CombatBenchmarkAnalysis: Equatable, Sendable {
    let baselineValidity: CombatBenchmarkValidity
    let candidateValidity: CombatBenchmarkValidity
    let deltas: CombatBenchmarkDeltas
    let decision: CombatBenchmarkDecision

    init(baseline: CombatBenchmarkMetrics, candidate: CombatBenchmarkMetrics) {
        let baselineValidity = CombatBenchmarkValidity.evaluate(baseline)
        let candidateValidity = CombatBenchmarkValidity.evaluate(candidate)
        self.baselineValidity = baselineValidity
        self.candidateValidity = candidateValidity
        let deltas = CombatBenchmarkDeltas(baseline: baseline, candidate: candidate)
        self.deltas = deltas
        decision = Self.makeDecision(
            baseline: baseline,
            candidate: candidate,
            baselineValidity: baselineValidity,
            candidateValidity: candidateValidity,
            deltas: deltas
        )
    }

    private static func makeDecision(
        baseline: CombatBenchmarkMetrics,
        candidate: CombatBenchmarkMetrics,
        baselineValidity: CombatBenchmarkValidity,
        candidateValidity: CombatBenchmarkValidity,
        deltas: CombatBenchmarkDeltas
    ) -> CombatBenchmarkDecision {
        guard baselineValidity.isValid, candidateValidity.isValid else { return .inconclusive }
        guard baseline.correctnessPassed else { return .inconclusive }
        guard candidate.correctnessPassed else { return .reject }
        if deltas.p95IntervalPercent >= 10 || deltas.p99IntervalPercent >= 10 { return .reject }
        if deltas.weightedFPSPercent < 5 { return .reject }
        if isHomeRun(baseline: baseline, candidate: candidate, deltas: deltas) { return .homeRun }
        if isPromising(deltas) { return .promising }
        return .inconclusive
    }

    private static func isHomeRun(
        baseline: CombatBenchmarkMetrics,
        candidate: CombatBenchmarkMetrics,
        deltas: CombatBenchmarkDeltas
    ) -> Bool {
        deltas.onePercentLowFPSPercent >= 20
            && relativeReductionIsAtLeast30Percent(from: baseline.jankRate, to: candidate.jankRate)
            && relativeReductionIsAtLeast30Percent(from: baseline.severeRate, to: candidate.severeRate)
            && (deltas.weightedFPSPercent >= 10 || deltas.p95IntervalPercent <= -15)
    }

    private static func isPromising(_ deltas: CombatBenchmarkDeltas) -> Bool {
        deltas.weightedFPSPercent >= 5
            && deltas.onePercentLowFPSPercent >= 10
            && deltas.p95IntervalPercent <= 0
            && deltas.p99IntervalPercent <= 0
    }

    private static func relativeReductionIsAtLeast30Percent(from baseline: Double, to candidate: Double) -> Bool {
        guard baseline > 0 else { return false }
        return (baseline - candidate) / baseline >= 0.30
    }
}
