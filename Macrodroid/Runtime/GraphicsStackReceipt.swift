import CryptoKit
import Foundation

struct GraphicsStackReceiptField: Sendable, Equatable {
    let value: String
    let source: String
    let confidence: String

    var isExplicitlyUnknown: Bool {
        confidence.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() == "UNKNOWN"
    }
}

enum GraphicsStackReceiptCompleteness: String, Sendable, Equatable {
    case complete = "COMPLETE"
    case partial = "PARTIAL"
    case unknown = "UNKNOWN"
}

struct GraphicsStackReceipt: Sendable, Equatable {
    let fields: [String: GraphicsStackReceiptField]

    var canonicalJSON: String {
        let object = Dictionary(uniqueKeysWithValues: fields.map { key, field in
            (
                key,
                [
                    "value": field.value,
                    "source": field.source,
                    "confidence": field.confidence
                ]
            )
        })
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    var sha256: String {
        SHA256.hash(data: Data(canonicalJSON.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func explicitUnknownKeys() -> [String] {
        fields.compactMap { key, field in field.isExplicitlyUnknown ? key : nil }.sorted()
    }

    func unresolvedRequiredKeys(requiredKeys: Set<String>) -> [String] {
        requiredKeys.filter { key in
            guard let field = fields[key] else { return true }
            return field.isExplicitlyUnknown
        }.sorted()
    }

    func completeness(requiredKeys: Set<String>) -> GraphicsStackReceiptCompleteness {
        let unresolved = unresolvedRequiredKeys(requiredKeys: requiredKeys)
        if unresolved.isEmpty { return .complete }
        return unresolved.count == requiredKeys.count ? .unknown : .partial
    }
}
