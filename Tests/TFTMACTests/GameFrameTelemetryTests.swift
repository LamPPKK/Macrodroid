import XCTest

final class GameFrameTelemetryTests: XCTestCase {
    private let layer = "SurfaceView[com.riotgames.league.teamfighttactics/com.epicgames.unreal.GameActivity](BLAST)#42"
    private let refresh: UInt64 = 16_666_667

    func testSteadySixtyHertzProducesSixtyFPSWindow() throws {
        var sampler = GameFrameTelemetrySampler()
        XCTAssertEqual(sampler.updateLayerList(layer), .available)
        _ = sampler.ingestLatency(latency(timestamps: timestamps(count: 1)), observedMonotonicNS: 1)
        let update = sampler.ingestLatency(latency(timestamps: timestamps(count: 61)), observedMonotonicNS: 1_000_000_001)
        let window = try XCTUnwrap(update.window)
        XCTAssertEqual(window.frameCount, 60)
        XCTAssertEqual(window.effectiveFPS, 60, accuracy: 0.001)
        XCTAssertEqual(window.p95MS ?? 0, 16.666667, accuracy: 0.001)
        XCTAssertEqual(window.jankCount, 0)
        XCTAssertEqual(window.missedVsyncEquivalents, 0)
    }

    func testHitchCountsJankAndMissedVsyncs() throws {
        var sampler = GameFrameTelemetrySampler()
        _ = sampler.updateLayerList(layer)
        _ = sampler.ingestLatency(latency(timestamps: timestamps(count: 1)), observedMonotonicNS: 1)
        var values = timestamps(count: 31)
        let hitchTimestamp = values.last! + 150_000_003
        values += [hitchTimestamp, hitchTimestamp + refresh, hitchTimestamp + (2 * refresh)]
        let window = try XCTUnwrap(sampler.ingestLatency(latency(timestamps: values), observedMonotonicNS: 1_000_000_001).window)
        XCTAssertEqual(window.maximumMS ?? 0, 150, accuracy: 0.001)
        XCTAssertEqual(window.jankCount, 1)
        XCTAssertEqual(window.severeCount, 1)
        XCTAssertEqual(window.missedVsyncEquivalents, 8)
        XCTAssertEqual(window.onePercentLowFPS ?? 0, 6.666666, accuracy: 0.001)
    }

    func testOverlappingPollsDoNotDuplicateIntervals() throws {
        var sampler = GameFrameTelemetrySampler()
        _ = sampler.updateLayerList(layer)
        let first = sampler.ingestLatency(latency(timestamps: timestamps(count: 40)), observedMonotonicNS: 1)
        XCTAssertEqual(first.intervals.count, 0)
        let secondValues = Array(timestamps(count: 40).suffix(20)) + timestamps(count: 20, start: 41 * refresh)
        let second = sampler.ingestLatency(latency(timestamps: secondValues), observedMonotonicNS: 500_000_001)
        XCTAssertEqual(second.intervals.count, 20)
        XCTAssertNil(second.window)
        let thirdValues = Array(secondValues.suffix(20)) + timestamps(count: 30, start: 61 * refresh)
        let third = sampler.ingestLatency(latency(timestamps: thirdValues), observedMonotonicNS: 1_000_000_001)
        XCTAssertEqual(third.intervals.count, 30)
        XCTAssertEqual(try XCTUnwrap(third.window).frameCount, 50)
    }

    func testLayerResetPreventsCrossLayerInterval() {
        var sampler = GameFrameTelemetrySampler()
        _ = sampler.updateLayerList(layer)
        _ = sampler.ingestLatency(latency(timestamps: timestamps(count: 3)), observedMonotonicNS: 100)
        _ = sampler.updateLayerList(layer.replacingOccurrences(of: "#42", with: "#43"))
        let update = sampler.ingestLatency(latency(timestamps: timestamps(count: 3, start: 9_000_000_000)), observedMonotonicNS: 200)
        XCTAssertEqual(update.intervals.count, 0)
    }

    func testMissingAndMultipleLayersFailClosed() {
        XCTAssertEqual(GameFrameTelemetry.selectTFTSurfaceViewLayer(from: "unrelated"), .unavailable(.noTFTSurfaceView))
        XCTAssertEqual(GameFrameTelemetry.selectTFTSurfaceViewLayer(from: "\(layer)\n\(layer.replacingOccurrences(of: "#42", with: "#43"))"), .unavailable(.multipleTFTSurfaceViews))
        var sampler = GameFrameTelemetrySampler()
        XCTAssertEqual(sampler.updateLayerList("unrelated"), .unavailable(.noTFTSurfaceView))
        XCTAssertNil(sampler.ingestLatency(latency(timestamps: timestamps(count: 2)), observedMonotonicNS: 1_000_000_000).window)
    }

    func testAndroidSixteenRequestedLayerPrefixIsPreservedForExactQuery() {
        let requested = "RequestedLayerState{d6240da \(layer) parentId=128}"
        XCTAssertEqual(
            GameFrameTelemetry.selectTFTSurfaceViewLayer(from: requested),
            .selected("d6240da \(layer)")
        )
        XCTAssertEqual(
            GameFrameTelemetry.surfaceFlingerLatencyShellCommand(layerName: "d6240da \(layer)"),
            "dumpsys SurfaceFlinger --latency 'd6240da \(layer)'"
        )
    }

    func testNoNewFrameWindowIsAnActualZeroNotUnavailable() throws {
        var sampler = GameFrameTelemetrySampler()
        _ = sampler.updateLayerList(layer)
        _ = sampler.ingestLatency(latency(timestamps: timestamps(count: 2)), observedMonotonicNS: 100)
        let update = sampler.ingestLatency(latency(timestamps: timestamps(count: 2)), observedMonotonicNS: 1_000_000_100)
        let window = try XCTUnwrap(update.window)
        XCTAssertEqual(window.status, .available)
        XCTAssertEqual(window.frameCount, 0)
        let empty = sampler.ingestLatency(latency(timestamps: timestamps(count: 2)), observedMonotonicNS: 2_000_000_100)
        XCTAssertEqual(try XCTUnwrap(empty.window).frameCount, 0)
        XCTAssertEqual(try XCTUnwrap(empty.window).effectiveFPS, 0)
    }

    func testZeroAndSentinelRowsAreFiltered() throws {
        let raw = "\(refresh)\n0 0 0\n9223372036854775807 9223372036854775807 9223372036854775807\n18446744073709551615 18446744073709551615 18446744073709551615\n1 2 3\n"
        let poll = try XCTUnwrap(GameFrameTelemetry.parseSurfaceFlingerLatency(raw))
        XCTAssertEqual(poll.samples, [GameFrameLatencySample(desiredPresentNS: 1, actualPresentNS: 2, frameReadyNS: 3)])
    }

    private func timestamps(count: Int, start: UInt64 = 16_666_667) -> [UInt64] {
        (0..<count).map { start + UInt64($0) * refresh }
    }

    private func latency(timestamps: [UInt64]) -> String {
        ([String(refresh)] + timestamps.map { "\($0 + 1) \($0) \($0 + 2)" }).joined(separator: "\n")
    }
}
