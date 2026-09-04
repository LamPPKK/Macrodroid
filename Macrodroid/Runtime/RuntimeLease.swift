import Darwin
import Foundation

enum RuntimeLeaseError: LocalizedError, Sendable {
    case alreadyOwned(processIdentifier: Int32)
    case cannotCreate(String)

    var errorDescription: String? {
        switch self {
        case .alreadyOwned(let processIdentifier):
            return "TFTMAC runtime is already owned by process \(processIdentifier). Close the other TFTMAC session first."
        case .cannotCreate(let reason):
            return "TFTMAC could not acquire its runtime lease: \(reason)"
        }
    }
}

final class TFTMACRuntimeLease: @unchecked Sendable {
    let processIdentifier: Int32
    let token: String
    let url: URL
    private var released = false

    private init(url: URL, processIdentifier: Int32, token: String) {
        self.url = url
        self.processIdentifier = processIdentifier
        self.token = token
    }

    static func acquire(stateRoot: URL, processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier) throws -> Self {
        try FileManager.default.createDirectory(
            at: stateRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = stateRoot.appendingPathComponent("native-runtime.lease")
        let token = UUID().uuidString.lowercased()
        for _ in 0..<2 {
            let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
            if descriptor >= 0 {
                let payload: [String: Any] = [
                    "schema": 1,
                    "pid": processIdentifier,
                    "token": token,
                    "created_utc": ISO8601DateFormatter().string(from: Date())
                ]
                do {
                    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                    try writeAll(data, to: descriptor)
                    _ = Darwin.fsync(descriptor)
                    Darwin.close(descriptor)
                    return Self(url: url, processIdentifier: processIdentifier, token: token)
                } catch {
                    Darwin.close(descriptor)
                    try? FileManager.default.removeItem(at: url)
                    throw RuntimeLeaseError.cannotCreate(error.localizedDescription)
                }
            }
            guard errno == EEXIST else {
                throw RuntimeLeaseError.cannotCreate(String(cString: strerror(errno)))
            }
            if let owner = leaseOwner(at: url), processExists(owner) {
                throw RuntimeLeaseError.alreadyOwned(processIdentifier: owner)
            }
            do { try FileManager.default.removeItem(at: url) }
            catch { throw RuntimeLeaseError.cannotCreate("stale lease could not be removed") }
        }
        throw RuntimeLeaseError.cannotCreate("another launch won the lease race")
    }

    func release() {
        guard !released else { return }
        released = true
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["token"] as? String == token else { return }
        try? FileManager.default.removeItem(at: url)
    }

    deinit { release() }

    private static func leaseOwner(at url: URL) -> Int32? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = object["pid"] as? NSNumber else { return nil }
        return number.int32Value
    }

    private static func processExists(_ processIdentifier: Int32) -> Bool {
        if Darwin.kill(processIdentifier, 0) == 0 { return true }
        return errno != ESRCH
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var written = 0
            while written < rawBuffer.count {
                let result = Darwin.write(descriptor, baseAddress.advanced(by: written), rawBuffer.count - written)
                guard result > 0 else { throw RuntimeLeaseError.cannotCreate(String(cString: strerror(errno))) }
                written += result
            }
        }
    }
}
