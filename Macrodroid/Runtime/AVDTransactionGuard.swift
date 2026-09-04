import Foundation

enum AVDTransactionRestoreDecision: Equatable, Sendable {
    case alreadyOriginal
    case restoreBackup
}

enum AVDTransactionGuardError: LocalizedError, Equatable, Sendable {
    case conflictingCurrentConfiguration
    case unexpectedRecoveryPath

    var errorDescription: String? {
        switch self {
        case .conflictingCurrentConfiguration:
            return "The AVD config changed after TFTMAC applied its profile; automatic restore stopped without overwriting it."
        case .unexpectedRecoveryPath:
            return "The interrupted AVD transaction names a path outside TFTMAC's exact config and capture roots; recovery stopped safely."
        }
    }
}

enum AVDTransactionGuard {
    static func restoreDecision(
        currentSHA256: String,
        originalSHA256: String,
        appliedSHA256: String
    ) throws -> AVDTransactionRestoreDecision {
        if currentSHA256 == originalSHA256 { return .alreadyOriginal }
        guard currentSHA256 == appliedSHA256 else {
            throw AVDTransactionGuardError.conflictingCurrentConfiguration
        }
        return .restoreBackup
    }

    static func validateRecoveryPaths(
        markerConfigURL: URL,
        expectedConfigURL: URL,
        backupURL: URL,
        captureRoot: URL
    ) throws {
        let markerConfig = markerConfigURL.standardizedFileURL.resolvingSymlinksInPath()
        let expectedConfig = expectedConfigURL.standardizedFileURL.resolvingSymlinksInPath()
        let backup = backupURL.standardizedFileURL.resolvingSymlinksInPath()
        let captures = captureRoot.standardizedFileURL.resolvingSymlinksInPath()
        let capturesPrefix = captures.path.hasSuffix("/") ? captures.path : captures.path + "/"
        guard markerConfig.path == expectedConfig.path,
              backup.path.hasPrefix(capturesPrefix),
              backup.lastPathComponent == "avd-config.before.ini" else {
            throw AVDTransactionGuardError.unexpectedRecoveryPath
        }
    }
}
