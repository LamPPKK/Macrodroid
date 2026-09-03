import XCTest

final class GraphicsStackReceiptTests: XCTestCase {
    func testCanonicalJSONAndHashIgnoreFieldInsertionOrder() {
        let surface = GraphicsStackReceiptField(value: "EXACT_LAYER_ACTIVE", source: "SURFACEFLINGER", confidence: "PROVEN")
        let angle = GraphicsStackReceiptField(value: "PROVEN_ACTIVE", source: "EMULATOR_STDERR", confidence: "PROVEN")

        let first = GraphicsStackReceipt(fields: ["surface": surface, "angle": angle])
        let second = GraphicsStackReceipt(fields: ["angle": angle, "surface": surface])

        XCTAssertEqual(first.canonicalJSON, second.canonicalJSON)
        XCTAssertEqual(first.sha256, second.sha256)
    }

    func testFieldValueChangeChangesHash() {
        let baseline = GraphicsStackReceipt(fields: [
            "gfxstream": GraphicsStackReceiptField(value: "PROVEN_ACTIVE", source: "EMULATOR_STDOUT", confidence: "PROVEN")
        ])
        let changed = GraphicsStackReceipt(fields: [
            "gfxstream": GraphicsStackReceiptField(value: "NOT_OBSERVED", source: "EMULATOR_STDOUT", confidence: "PROVEN")
        ])

        XCTAssertNotEqual(baseline.sha256, changed.sha256)
    }

    func testCompletenessAndExplicitUnknownsAreDeterministic() {
        let receipt = GraphicsStackReceipt(fields: [
            "surface": GraphicsStackReceiptField(value: "EXACT_LAYER_ACTIVE", source: "SURFACEFLINGER", confidence: "PROVEN"),
            "moltenvk": GraphicsStackReceiptField(value: "", source: "EMULATOR_STDERR", confidence: "UNKNOWN"),
            "angle": GraphicsStackReceiptField(value: "", source: "ADB_GETPROP", confidence: "UNKNOWN")
        ])

        XCTAssertEqual(receipt.explicitUnknownKeys(), ["angle", "moltenvk"])
        XCTAssertEqual(receipt.unresolvedRequiredKeys(requiredKeys: ["surface", "moltenvk", "gfxstream"]), ["gfxstream", "moltenvk"])
        XCTAssertEqual(receipt.completeness(requiredKeys: ["surface", "moltenvk", "gfxstream"]), .partial)
        XCTAssertEqual(receipt.completeness(requiredKeys: ["moltenvk", "gfxstream"]), .unknown)
        XCTAssertEqual(receipt.completeness(requiredKeys: ["surface"]), .complete)
    }

}
