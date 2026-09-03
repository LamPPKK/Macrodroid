import Foundation

struct EmulatorFrame: @unchecked Sendable {
    let pixels: Data
    let width: Int
    let height: Int
    let sequence: UInt32
    let emulatorTimestampMicroseconds: UInt64
    let receivedMonotonicNanoseconds: UInt64
}

enum FrameContractError: LocalizedError, Equatable {
    case inactiveDisplay
    case wrongDimensions(width: Int, height: Int)
    case wrongByteCount(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .inactiveDisplay:
            return "The Android display is inactive."
        case .wrongDimensions(let width, let height):
            return "Expected a 1920×1080 Android frame, received \(width)×\(height)."
        case .wrongByteCount(let expected, let actual):
            return "Expected \(expected) RGBA bytes, received \(actual)."
        }
    }
}

enum FrameContract {
    static let width = 1920
    static let height = 1080
    static let bytesPerPixel = 4
    static let expectedByteCount = width * height * bytesPerPixel

    static func validate(width: Int, height: Int, byteCount: Int) throws {
        guard width > 0, height > 0 else { throw FrameContractError.inactiveDisplay }
        guard width == Self.width, height == Self.height else {
            throw FrameContractError.wrongDimensions(width: width, height: height)
        }
        guard byteCount == expectedByteCount else {
            throw FrameContractError.wrongByteCount(expected: expectedByteCount, actual: byteCount)
        }
    }
}

struct FrameMailboxSnapshot: Sendable {
    let receivedFrames: UInt64
    let replacedBeforePresentation: UInt64
    let sequenceDrops: UInt64
    let latestSequence: UInt32?
    let latestReceiveMonotonicNanoseconds: UInt64?
}

final class LatestFrameMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: EmulatorFrame?
    private var receivedFrames: UInt64 = 0
    private var replacedBeforePresentation: UInt64 = 0
    private var sequenceDrops: UInt64 = 0
    private var previousSequence: UInt32?
    private var latestReceiveMonotonicNanoseconds: UInt64?

    func publish(_ frame: EmulatorFrame) {
        lock.lock()
        defer { lock.unlock() }
        receivedFrames &+= 1
        if latest != nil { replacedBeforePresentation &+= 1 }
        if let previousSequence, frame.sequence > previousSequence &+ 1 {
            sequenceDrops &+= UInt64(frame.sequence - previousSequence - 1)
        }
        previousSequence = frame.sequence
        latestReceiveMonotonicNanoseconds = frame.receivedMonotonicNanoseconds
        latest = frame
    }

    func takeLatest() -> EmulatorFrame? {
        lock.lock()
        defer { lock.unlock() }
        let frame = latest
        latest = nil
        return frame
    }

    func snapshot() -> FrameMailboxSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return FrameMailboxSnapshot(
            receivedFrames: receivedFrames,
            replacedBeforePresentation: replacedBeforePresentation,
            sequenceDrops: sequenceDrops,
            latestSequence: previousSequence,
            latestReceiveMonotonicNanoseconds: latestReceiveMonotonicNanoseconds
        )
    }
}
