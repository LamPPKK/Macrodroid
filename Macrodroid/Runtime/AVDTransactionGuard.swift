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
        let macrodroidCaptures = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Macrodroid/Captures")
            .standardizedFileURL.resolvingSymlinksInPath()
        let macrodroidPrefix = macrodroidCaptures.path.hasSuffix("/") ? macrodroidCaptures.path : macrodroidCaptures.path + "/"
        let legacyCaptures = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TFTMAC/Captures")
            .standardizedFileURL.resolvingSymlinksInPath()
        let legacyPrefix = legacyCaptures.path.hasSuffix("/") ? legacyCaptures.path : legacyCaptures.path + "/"

        guard markerConfig.path == expectedConfig.path,
              (backup.path.hasPrefix(capturesPrefix) || backup.path.hasPrefix(macrodroidPrefix) || backup.path.hasPrefix(legacyPrefix)),
              backup.lastPathComponent == "avd-config.before.ini" else {
            throw AVDTransactionGuardError.unexpectedRecoveryPath
        }
    }
}

#if canImport(AppKit)
import AppKit
#endif

enum ClipboardPreferences {
    static let preferenceKey = "macrodroid.clipboardSync.enabled"

    static func isSyncEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: preferenceKey) as? Bool ?? true
    }

    static func setSyncEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: preferenceKey)
    }
}

actor ClipboardSyncCoordinator {
    private var lastSyncedText: String?
    private var lastChangeCount: Int = 0
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if canImport(AppKit)
        let (count, text) = MainActor.assumeIsolated {
            (NSPasteboard.general.changeCount, NSPasteboard.general.string(forType: .string))
        }
        self.lastChangeCount = count
        self.lastSyncedText = text
        #else
        self.lastChangeCount = 0
        self.lastSyncedText = nil
        #endif
    }

    var isEnabled: Bool {
        ClipboardPreferences.isSyncEnabled(defaults: defaults)
    }

    func syncToMac(text: String) async -> Bool {
        guard isEnabled else { return false }
        guard !text.isEmpty, text != lastSyncedText else { return false }
        lastSyncedText = text
        #if canImport(AppKit)
        let newCount: Int? = await MainActor.run { () -> Int? in
            let pb = NSPasteboard.general
            if pb.string(forType: .string) != text {
                pb.clearContents()
                pb.setString(text, forType: .string)
                return pb.changeCount
            }
            return nil
        }
        if let newCount {
            self.lastChangeCount = newCount
            return true
        }
        #endif
        return false
    }

    func checkMacPasteboard() async -> String? {
        guard isEnabled else { return nil }
        #if canImport(AppKit)
        let (count, text) = await MainActor.run {
            (NSPasteboard.general.changeCount, NSPasteboard.general.string(forType: .string))
        }
        guard count != lastChangeCount else { return nil }
        lastChangeCount = count
        guard let text = text, !text.isEmpty, text != lastSyncedText else { return nil }
        lastSyncedText = text
        return text
        #else
        return nil
        #endif
    }

    func simulateSyncState(text: String, changeCount: Int) {
        self.lastSyncedText = text
        self.lastChangeCount = changeCount
    }

    func currentSyncedText() -> String? {
        lastSyncedText
    }
}
