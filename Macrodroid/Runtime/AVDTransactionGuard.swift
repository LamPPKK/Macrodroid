import AppKit
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
    private var isInitialized: Bool = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if canImport(AppKit)
        if Thread.isMainThread {
            let (count, text) = MainActor.assumeIsolated {
                (NSPasteboard.general.changeCount, NSPasteboard.general.string(forType: .string))
            }
            self.lastChangeCount = count
            self.lastSyncedText = text
            self.isInitialized = true
        } else {
            self.lastChangeCount = 0
            self.lastSyncedText = nil
            self.isInitialized = false
        }
        #else
        self.lastChangeCount = 0
        self.lastSyncedText = nil
        self.isInitialized = true
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
        let newCount: Int = await MainActor.run { () -> Int in
            let pb = NSPasteboard.general
            if pb.string(forType: .string) != text {
                pb.clearContents()
                pb.setString(text, forType: .string)
            }
            return pb.changeCount
        }
        self.lastChangeCount = newCount
        self.isInitialized = true
        return true
        #else
        return false
        #endif
    }

    func checkMacPasteboard() async -> String? {
        guard isEnabled else { return nil }
        #if canImport(AppKit)
        let (count, text) = await MainActor.run {
            (NSPasteboard.general.changeCount, NSPasteboard.general.string(forType: .string))
        }
        guard isInitialized else {
            isInitialized = true
            lastChangeCount = count
            lastSyncedText = text
            return nil
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
        self.isInitialized = true
    }

    func currentSyncedText() -> String? {
        lastSyncedText
    }
}

public struct FileTransferResult: Sendable, Equatable {
    public let filename: String
    public let isAPK: Bool
    public let success: Bool
    public let destination: String
    public let message: String

    public init(filename: String, isAPK: Bool, success: Bool, destination: String, message: String) {
        self.filename = filename
        self.isAPK = isAPK
        self.success = success
        self.destination = destination
        self.message = message
    }
}

public enum IdleSuspendTimeout: String, CaseIterable, Codable, Sendable {
    case immediately = "immediately"
    case oneMinute = "1m"
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case never = "never"

    public var seconds: TimeInterval? {
        switch self {
        case .immediately: return 0
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .never: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .immediately: return "Ngay lập tức (Immediately)"
        case .oneMinute: return "Sau 1 phút (1 minute)"
        case .fiveMinutes: return "Sau 5 phút (5 minutes - Khuyên dùng)"
        case .fifteenMinutes: return "Sau 15 phút (15 minutes)"
        case .never: return "Không bao giờ (Never)"
        }
    }
}

public enum IdleSuspendPreferences {
    public static let preferenceKey = "macrodroid.idle.suspend.timeout"

    public static func loadTimeout(defaults: UserDefaults = .standard) -> IdleSuspendTimeout {
        guard let raw = defaults.string(forKey: preferenceKey),
              let timeout = IdleSuspendTimeout(rawValue: raw) else {
            return .fiveMinutes
        }
        return timeout
    }

    public static func saveTimeout(_ timeout: IdleSuspendTimeout, defaults: UserDefaults = .standard) {
        defaults.set(timeout.rawValue, forKey: preferenceKey)
    }
}

// MARK: - AppShortcutManager (WSA-Style Native macOS Shortcuts & Spotlight Integration)

@MainActor
public enum AppShortcutManager {
    public static var shortcutsDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Applications/Macrodroid Apps", isDirectory: true)
    }

    public static func parseLaunchURL(_ url: URL) -> String? {
        guard url.scheme == "macrodroid", url.host == "launch" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return components.queryItems?.first(where: { $0.name == "pkg" || $0.name == "package" })?.value
    }

    public static func generateLauncherScript(package: String) -> String {
        """
#!/bin/sh
# Open Android app through Macrodroid URL scheme or CLI
exec open "macrodroid://launch?pkg=\(package)" || open -b "com.lamppkk.macrodroid" --args --launch-pkg "\(package)"
"""
    }

    public static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    public static func generateInfoPlist(name: String, package: String, version: String) -> String {
        let safeName = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let sanitizedPkg = package
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let xmlEscapedName = escapeXML(safeName)
        let xmlEscapedPkg = escapeXML(sanitizedPkg)
        let xmlEscapedVersion = escapeXML(version)
        return """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AppLauncher</string>
    <key>CFBundleIdentifier</key>
    <string>com.lamppkk.macrodroid.app.\(xmlEscapedPkg)</string>
    <key>CFBundleName</key>
    <string>\(xmlEscapedName)</string>
    <key>CFBundleDisplayName</key>
    <string>\(xmlEscapedName)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>\(xmlEscapedVersion)</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
"""
    }

    public static func removeShortcut(
        name: String,
        bundleIdentifier: String,
        destinationDirectory: URL? = nil
    ) {
        let dir = destinationDirectory ?? shortcutsDirectory
        let safeName = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let appBundleURL = dir.appendingPathComponent("\(safeName).app", isDirectory: true)
        try? FileManager.default.removeItem(at: appBundleURL)

        if let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for item in contents where item.pathExtension == "app" {
                let infoPlist = item.appendingPathComponent("Contents/Info.plist")
                if let data = try? Data(contentsOf: infoPlist),
                   let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let cfBundleId = dict["CFBundleIdentifier"] as? String {
                    let sanitizedPkg = bundleIdentifier
                        .replacingOccurrences(of: "-", with: "_")
                        .replacingOccurrences(of: " ", with: "_")
                    if cfBundleId == "com.lamppkk.macrodroid.app.\(sanitizedPkg)" {
                        try? FileManager.default.removeItem(at: item)
                    }
                }
            }
        }

        let iconURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Macrodroid/Icons/\(bundleIdentifier).png")
        try? FileManager.default.removeItem(at: iconURL)
    }

    @discardableResult
    public static func createShortcut(
        name: String,
        bundleIdentifier: String,
        version: String = "1.0",
        customIcon: NSImage? = nil,
        destinationDirectory: URL? = nil
    ) -> URL? {
        let dir = destinationDirectory ?? shortcutsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let safeName = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let appBundleURL = dir.appendingPathComponent("\(safeName).app", isDirectory: true)

        let contentsURL = appBundleURL.appendingPathComponent("Contents", isDirectory: true)
        let macosURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        try? FileManager.default.createDirectory(at: macosURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let infoPlistContent = generateInfoPlist(name: name, package: bundleIdentifier, version: version)
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        try? infoPlistContent.write(to: infoPlistURL, atomically: true, encoding: .utf8)

        let launcherScript = generateLauncherScript(package: bundleIdentifier)
        let launcherURL = macosURL.appendingPathComponent("AppLauncher")
        try? launcherScript.write(to: launcherURL, atomically: true, encoding: .utf8)

        var attrs = (try? FileManager.default.attributesOfItem(atPath: launcherURL.path)) ?? [:]
        attrs[.posixPermissions] = 0o755
        try? FileManager.default.setAttributes(attrs, ofItemAtPath: launcherURL.path)

        if let icon = customIcon {
            NSWorkspace.shared.setIcon(icon, forFile: appBundleURL.path, options: [])
        } else {
            let iconURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Macrodroid/Icons/\(bundleIdentifier).png")
            if let iconImg = NSImage(contentsOf: iconURL) {
                NSWorkspace.shared.setIcon(iconImg, forFile: appBundleURL.path, options: [])
            }
        }

        return appBundleURL
    }

    public static func revealShortcutsInFinder(directory: URL? = nil) {
        let dir = directory ?? shortcutsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
}
