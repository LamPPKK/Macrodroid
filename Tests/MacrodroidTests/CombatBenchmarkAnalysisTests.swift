import XCTest

final class CombatBenchmarkAnalysisTests: XCTestCase {
    func testHomeRunRequiresBroadPacingImprovement() {
        let analysis = CombatBenchmarkAnalysis(
            baseline: metrics(),
            candidate: metrics(
                weightedFPS: 58,
                onePercentLowFPS: 18,
                p95IntervalMilliseconds: 24,
                p99IntervalMilliseconds: 36,
                jankRate: 0.05,
                severeRate: 0.001,
                missedVsyncRate: 0.07
            )
        )

        XCTAssertEqual(analysis.decision, .homeRun)
        XCTAssertEqual(analysis.deltas.weightedFPSPercent, 16, accuracy: 0.001)
        XCTAssertEqual(analysis.deltas.p99IntervalPercent, -28, accuracy: 0.001)
    }

    func testPromisingAcceptsOneMaterialImprovementWithoutRegression() {
        let analysis = CombatBenchmarkAnalysis(
            baseline: metrics(),
            candidate: metrics(weightedFPS: 53, onePercentLowFPS: 17)
        )

        XCTAssertEqual(analysis.decision, .promising)
    }

    func testRejectsMaterialFramePacingRegression() {
        let analysis = CombatBenchmarkAnalysis(
            baseline: metrics(),
            candidate: metrics(p99IntervalMilliseconds: 60)
        )

        XCTAssertEqual(analysis.decision, .reject)
    }

    func testCompletedScreeningBelowFivePercentWeightedFPSImprovementRejects() {
        let baseline = metrics()
        let analysis = CombatBenchmarkAnalysis(baseline: baseline, candidate: baseline)

        XCTAssertEqual(analysis.decision, .reject)
    }

    func testInvalidCandidateIsInconclusiveAndReportsEveryFailure() {
        let analysis = CombatBenchmarkAnalysis(
            baseline: metrics(),
            candidate: metrics(
                combatDurationSeconds: 299,
                surfaceAvailability: 0.94,
                clockCoverage: 0.94,
                p95ClockRoundTripMilliseconds: 10.1,
                frameHistoryTruncated: true,
                exactLayerStable: false,
                weightedFPS: 100,
                onePercentLowFPS: 100,
                p95IntervalMilliseconds: 1,
                p99IntervalMilliseconds: 1,
                jankRate: 0,
                severeRate: 0,
                missedVsyncRate: 0
            )
        )

        XCTAssertEqual(analysis.decision, .inconclusive)
        XCTAssertEqual(
            analysis.candidateValidity.failures,
            [.combatDurationTooShort, .insufficientSurfaceAvailability, .insufficientClockCoverage, .clockRoundTripTooHigh, .frameHistoryTruncated, .exactLayerChangedOrAmbiguous]
        )
    }

    func testDeltasUsePercentagePointsForRates() {
        let analysis = CombatBenchmarkAnalysis(
            baseline: metrics(jankRate: 0.10, severeRate: 0.01, missedVsyncRate: 0.12),
            candidate: metrics(jankRate: 0.08, severeRate: 0.007, missedVsyncRate: 0.10)
        )

        XCTAssertEqual(analysis.deltas.jankRatePercentagePoints, -0.02, accuracy: 0.000_001)
        XCTAssertEqual(analysis.deltas.severeRatePercentagePoints, -0.003, accuracy: 0.000_001)
        XCTAssertEqual(analysis.deltas.missedVsyncRatePercentagePoints, -0.02, accuracy: 0.000_001)
    }

    func testCorrectnessRegressionRejectsAnOtherwiseFastCandidate() {
        let analysis = CombatBenchmarkAnalysis(
            baseline: metrics(),
            candidate: metrics(
                correctnessPassed: false,
                weightedFPS: 70,
                onePercentLowFPS: 30,
                p95IntervalMilliseconds: 10,
                p99IntervalMilliseconds: 10,
                jankRate: 0.01,
                severeRate: 0.001,
                missedVsyncRate: 0.01
            )
        )

        XCTAssertEqual(analysis.decision, .reject)
    }

    func testThresholdGapIsInconclusive() {
        let analysis = CombatBenchmarkAnalysis(
            baseline: metrics(),
            candidate: metrics(weightedFPS: 53, onePercentLowFPS: 16)
        )

        XCTAssertEqual(analysis.decision, .inconclusive)
    }

    func testOnePercentLowUsesMeanOfSlowestOnePercent() {
        let intervals = Array(repeating: 16.667, count: 198) + [100, 200]

        XCTAssertEqual(
            CombatBenchmarkMetrics.onePercentLowFPS(from: intervals),
            6.666_667,
            accuracy: 0.000_001
        )
    }

    private func metrics(
        combatDurationSeconds: Double = 480,
        surfaceAvailability: Double = 0.98,
        clockCoverage: Double = 0.99,
        p95ClockRoundTripMilliseconds: Double = 5,
        frameHistoryTruncated: Bool = false,
        exactLayerStable: Bool = true,
        correctnessPassed: Bool = true,
        weightedFPS: Double = 50,
        onePercentLowFPS: Double = 15,
        p95IntervalMilliseconds: Double = 32,
        p99IntervalMilliseconds: Double = 50,
        jankRate: Double = 0.10,
        severeRate: Double = 0.005,
        missedVsyncRate: Double = 0.12
    ) -> CombatBenchmarkMetrics {
        CombatBenchmarkMetrics(
            combatDurationSeconds: combatDurationSeconds,
            surfaceAvailability: surfaceAvailability,
            clockCoverage: clockCoverage,
            p95ClockRoundTripMilliseconds: p95ClockRoundTripMilliseconds,
            frameHistoryTruncated: frameHistoryTruncated,
            exactLayerStable: exactLayerStable,
            correctnessPassed: correctnessPassed,
            weightedFPS: weightedFPS,
            onePercentLowFPS: onePercentLowFPS,
            p95IntervalMilliseconds: p95IntervalMilliseconds,
            p99IntervalMilliseconds: p99IntervalMilliseconds,
            jankRate: jankRate,
            severeRate: severeRate,
            missedVsyncRate: missedVsyncRate
        )
    }

}
