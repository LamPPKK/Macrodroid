//
//  MacrodroidLauncherView.swift
//  Macrodroid (PlayCover-Inspired Modern Architecture & Joy Engine)
//

import AppKit
import Foundation
import SwiftUI

// MARK: - APK Metadata & Real Icon Extractor

struct APKMetadataExtractor {
    struct AppMetadata {
        let packageName: String
        let appName: String
        let versionName: String
        let iconData: Data?
    }

    static func extract(from apkURL: URL, sdkRoot: URL?) -> AppMetadata {
        var packageName = apkURL.deletingPathExtension().lastPathComponent
        var appName = apkURL.deletingPathExtension().lastPathComponent
        let versionName = "1.0.0"
        var iconPathInAPK: String? = nil

        // 1. Try finding aapt in sdkRoot/build-tools/*/aapt
        if let sdk = sdkRoot {
            let buildToolsDir = sdk.appendingPathComponent("build-tools")
            if let versions = try? FileManager.default.contentsOfDirectory(atPath: buildToolsDir.path) {
                let sortedVersions = versions.sorted().reversed()
                for v in sortedVersions {
                    let aaptURL = buildToolsDir.appendingPathComponent(v).appendingPathComponent("aapt")
                    if FileManager.default.isExecutableFile(atPath: aaptURL.path) {
                        let process = Process()
                        process.executableURL = aaptURL
                        process.arguments = ["dump", "badging", apkURL.path]
                        let pipe = Pipe()
                        process.standardOutput = pipe
                        process.standardError = Pipe()
                        if (try? process.run()) != nil {
                            process.waitUntilExit()
                            let outData = pipe.fileHandleForReading.readDataToEndOfFile()
                            let dump = String(decoding: outData, as: UTF8.self)

                            // Parse package: name='...'
                            if let pkgRange = dump.range(of: "package: name='") {
                                let remainder = dump[pkgRange.upperBound...]
                                if let endQuote = remainder.range(of: "'") {
                                    packageName = String(remainder[..<endQuote.lowerBound])
                                }
                            }

                            // Parse application-label:'...'
                            if let labelRange = dump.range(of: "application-label:'") {
                                let remainder = dump[labelRange.upperBound...]
                                if let endQuote = remainder.range(of: "'") {
                                    appName = String(remainder[..<endQuote.lowerBound])
                                }
                            }

                            // Parse highest density icon: 640 -> 480 -> 320 -> 240 -> 160 -> icon='
                            let iconKeys = [
                                "application-icon-640:'",
                                "application-icon-480:'",
                                "application-icon-320:'",
                                "application-icon-240:'",
                                "application-icon-160:'",
                                "icon='"
                            ]
                            for key in iconKeys {
                                if let r = dump.range(of: key) {
                                    let remainder = dump[r.upperBound...]
                                    if let quote = remainder.range(of: "'") {
                                        let candidate = String(remainder[..<quote.lowerBound])
                                        if candidate.hasSuffix(".png") || candidate.hasSuffix(".webp") {
                                            iconPathInAPK = candidate
                                            break
                                        }
                                    }
                                }
                            }
                        }
                        break
                    }
                }
            }
        }

        // 2. If aapt didn't yield a direct PNG, scan zip entries using /usr/bin/unzip -l
        if iconPathInAPK == nil || iconPathInAPK?.hasSuffix(".xml") == true {
            let listProcess = Process()
            listProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            listProcess.arguments = ["-l", apkURL.path]
            let listPipe = Pipe()
            listProcess.standardOutput = listPipe
            listProcess.standardError = Pipe()
            if (try? listProcess.run()) != nil {
                listProcess.waitUntilExit()
                let listData = listPipe.fileHandleForReading.readDataToEndOfFile()
                let listOutput = String(decoding: listData, as: UTF8.self)
                let lines = listOutput.components(separatedBy: .newlines)

                let densityPriority = ["xxxhdpi", "xxhdpi", "xhdpi", "hdpi", "mdpi", ""]
                var candidates: [(path: String, priority: Int)] = []
                for line in lines {
                    let parts = line.split(whereSeparator: \.isWhitespace)
                    if let path = parts.last.map(String.init), (path.hasSuffix(".png") || path.hasSuffix(".webp")) {
                        let lower = path.lowercased()
                        if lower.contains("app_icon") || lower.contains("ic_launcher") || lower.contains("icon") || lower.contains("logo") {
                            var p = 0
                            if !lower.contains("background") && !lower.contains("monochrome") {
                                p += 200
                            }
                            for (idx, d) in densityPriority.enumerated() {
                                if !d.isEmpty && lower.contains(d) {
                                    p += 100 - idx
                                    break
                                }
                            }
                            candidates.append((path, p))
                        }
                    }
                }
                candidates.sort { $0.priority > $1.priority }
                iconPathInAPK = candidates.first?.path
            }
        }

        // 3. Extract icon bytes using /usr/bin/unzip -p <apkPath> <iconPath>
        var iconData: Data? = nil
        if let iconPath = iconPathInAPK {
            let extractProcess = Process()
            extractProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            extractProcess.arguments = ["-p", apkURL.path, iconPath]
            let extractPipe = Pipe()
            extractProcess.standardOutput = extractPipe
            extractProcess.standardError = Pipe()
            if (try? extractProcess.run()) != nil {
                extractProcess.waitUntilExit()
                let data = extractPipe.fileHandleForReading.readDataToEndOfFile()
                if !data.isEmpty {
                    iconData = data
                }
            }
        }

        return AppMetadata(
            packageName: packageName,
            appName: appName,
            versionName: versionName,
            iconData: iconData
        )
    }
}

// MARK: - PlayApp Model

struct PersistedAppRecord: Codable {
    let id: String
    let name: String
    let packageName: String
    let version: String
    let apkPath: String
}

@MainActor
class PlayApp: Identifiable, ObservableObject, Hashable {
    let id: String
    let name: String
    let bundleIdentifier: String
    let version: String
    var url: URL

    @Published var customIcon: NSImage? = nil
    @Published var isStarting: Bool = false
    @Published var isFavorite: Bool = false
    @Published var resolutionIndex: Int = 1 // 0: 720p, 1: 1080p, 2: 1440p, 3: 4K
    @Published var aspectRatioIndex: Int = 1 // 0: Portrait (9:16), 1: Landscape (16:9)
    @Published var vCPU: Int = 6
    @Published var ramMiB: Int = 5120
    @Published var targetFPS: Int = 60

    init(
        id: String,
        name: String,
        bundleIdentifier: String,
        version: String,
        url: URL,
        customIcon: NSImage? = nil
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.url = url
        self.customIcon = customIcon

        if customIcon == nil {
            let iconURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Macrodroid/Icons/\(bundleIdentifier).png")
            if let data = try? Data(contentsOf: iconURL), let img = NSImage(data: data) {
                self.customIcon = img
            }
        }
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    nonisolated static func == (lhs: PlayApp, rhs: PlayApp) -> Bool {
        lhs.id == rhs.id
    }
}

enum LaunchMode: String, CaseIterable, Identifiable {
    case tft = "Game Application"
    case android = "Android Home"

    var id: String { rawValue }
}

// MARK: - PlayCover Design System Theme

enum PlayCoverTheme {
    static let accent = Color(red: 0.0, green: 0.82, blue: 0.60) // PlayCover Mint Cyan
    static let accentGreen = Color(red: 0.18, green: 0.86, blue: 0.44) // Vibrant PlayCover Green
    static let accentBlue = Color(red: 0.25, green: 0.62, blue: 1.00) // Electric Blue
    static let accentGlow = Color(red: 0.0, green: 0.82, blue: 0.60).opacity(0.35)

    static let darkBackground = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let sidebarBackground = Color(red: 0.08, green: 0.10, blue: 0.13)
    static let cardBackground = Color(red: 0.11, green: 0.13, blue: 0.17)
    static let cardHoverBackground = Color(red: 0.14, green: 0.17, blue: 0.22)
    static let borderSubtle = Color.white.opacity(0.08)
    static let textMuted = Color(red: 0.60, green: 0.65, blue: 0.70)
}

// Backward compatibility alias
typealias JoyTheme = PlayCoverTheme

// MARK: - PlayCover Navigation Tabs

enum PlayCoverSidebarTab: Int, CaseIterable, Identifiable {
    case appLibrary = 1
    case keymapping = 2
    case graphics = 3
    case hardware = 4
    case sideload = 5
    case about = 6

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .appLibrary: return "App Library"
        case .keymapping: return "Keymapping"
        case .graphics: return "Graphics & Display"
        case .hardware: return "Engine & Hardware"
        case .sideload: return "Sideload APK"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .appLibrary: return "square.grid.2x2.fill"
        case .keymapping: return "gamecontroller.fill"
        case .graphics: return "display"
        case .hardware: return "cpu.fill"
        case .sideload: return "arrow.down.doc.fill"
        case .about: return "info.circle.fill"
        }
    }
}

// MARK: - Launcher View Model

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var sdkPath: String = "Scanning..."
    @Published var avdName: String = "Scanning..."
    @Published var isReady: Bool = false
    @Published var isLaunching: Bool = false
    @Published var isGameRunning: Bool = false
    @Published var statusMessage: String = "System Ready"

    // Performance Lab & Hardware Configuration
    @Published var experimentPreset: RuntimeExperimentPreset = .control
    @Published var vCPU: Int = 6
    @Published var ramMiB: Int = 5120
    @Published var refreshHz: Int = 60
    @Published var asgDrawFlushInterval: Int = 800
    @Published var saveFeedbackMessage: String = "Changes apply directly on launch."

    // Library State
    @Published var apps: [PlayApp] = []
    @Published var selectedApp: PlayApp? = nil
    @Published var searchText: String = ""
    @Published var isList: Bool = false
    @Published var selectedSidebarItem: Int = PlayCoverSidebarTab.appLibrary.rawValue

    // Controls & Keymapping State
    @Published var inputModeIndex: Int = 0 // 0: Touch Simulation, 1: Direct Bypass
    @Published var mouseSensitivity: Double = 1.0
    @Published var touchSwipeSpeed: Double = 1.0
    @Published var isKeymapOverlayEnabled: Bool = true
    @Published var overlayOpacity: Double = 0.75

    // Sideload & Drop State
    @Published var isSideloading: Bool = false
    @Published var isTargetedForDrop: Bool = false
    @Published var sideloadLogs: [String] = []

    // Background Engine State & Policy
    @Published var isEngineRunning: Bool = false
    @Published var isEngineStarting: Bool = false
    @Published var engineLaunchPolicy: EngineLaunchPolicy = .alwaysBackground
    @Published var engineCloseBehavior: EngineCloseBehavior = .keepWarm

    // Notification Mirroring Preferences
    @Published var isNotificationMirroringEnabled: Bool = true
    @Published var filterSystemNotifications: Bool = true

    // Inspector Sheet
    @Published var inspectingApp: PlayApp? = nil

    var onLaunch: ((LaunchMode, TFTMACRuntimeProfile, PlayApp?) -> Void)?
    var onStop: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onStartEngine: (() -> Void)?
    var onStopEngine: (() -> Void)?
    var onPostTestNotification: ((String, String) -> Void)?

    private var storageURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Macrodroid/installed_apps.json")
    }

    init() {
        refreshDiscovery()
        loadInstalledApps()
    }

    func refreshDiscovery() {
        do {
            let paths = try TFTMACRuntimePaths.discover()
            sdkPath = paths.sdkRoot.path.replacingOccurrences(
                of: FileManager.default.homeDirectoryForCurrentUser.path,
                with: "~"
            )
            avdName = paths.avdName
            isReady = true
            statusMessage = "Discovered AVD: \(paths.avdName)"
        } catch {
            isReady = false
            statusMessage = error.localizedDescription
        }
        let profile = TFTMACRuntimeProfile.load()
        experimentPreset = profile.experimentPreset
        vCPU = profile.vCPU
        ramMiB = profile.ramMiB
        refreshHz = profile.refreshHz
        asgDrawFlushInterval = profile.asgDrawFlushInterval
        engineLaunchPolicy = EngineLaunchPolicy.load()
        engineCloseBehavior = EngineCloseBehavior.load()
        isNotificationMirroringEnabled = NotificationPreferences.isMirroringEnabled()
        filterSystemNotifications = NotificationPreferences.isSystemFilterEnabled()
    }

    func setEngineLaunchPolicy(_ policy: EngineLaunchPolicy) {
        engineLaunchPolicy = policy
        policy.save()
        saveFeedbackMessage = "Đã lưu chế độ khởi động: \(policy.shortTitle)"
        if policy == .alwaysBackground && !isEngineRunning && !isEngineStarting {
            onStartEngine?()
        }
    }

    func setEngineCloseBehavior(_ behavior: EngineCloseBehavior) {
        engineCloseBehavior = behavior
        behavior.save()
        saveFeedbackMessage = "Đã lưu hành vi khi đóng app: \(behavior.displayName)"
    }

    func setNotificationMirroringEnabled(_ enabled: Bool) {
        isNotificationMirroringEnabled = enabled
        NotificationPreferences.setMirroringEnabled(enabled)
        saveFeedbackMessage = enabled ? "Đã bật thông báo macOS từ máy ảo" : "Đã tắt thông báo macOS từ máy ảo"
    }

    func setFilterSystemNotifications(_ enabled: Bool) {
        filterSystemNotifications = enabled
        NotificationPreferences.setSystemFilterEnabled(enabled)
        saveFeedbackMessage = enabled ? "Đã bật lọc thông báo hệ thống Android" : "Đã tắt lọc thông báo hệ thống Android"
    }

    func sendTestNotification() {
        onPostTestNotification?("Macrodroid Test", "Thông báo từ máy ảo Android đã chuyển tiếp thành công sang macOS!")
        saveFeedbackMessage = "Đang gửi thông báo thử nghiệm từ Android guest…"
    }

    func createMacShortcut(for app: PlayApp) {
        if let _ = AppShortcutManager.createShortcut(for: app) {
            saveFeedbackMessage = "Đã tạo lối tắt macOS cho \(app.name) tại ~/Applications/Macrodroid Apps"
        }
    }

    func createAllMacShortcuts() {
        AppShortcutManager.createShortcutsForInstalledApps(apps)
        saveFeedbackMessage = "Đã tạo lối tắt macOS cho toàn bộ \(apps.count) ứng dụng"
    }

    func revealMacShortcutsFolder() {
        AppShortcutManager.revealShortcutsInFinder()
    }

    func loadInstalledApps() {
        guard let data = try? Data(contentsOf: storageURL),
              let records = try? JSONDecoder().decode([PersistedAppRecord].self, from: data) else {
            apps = []
            selectedApp = nil
            return
        }

        var loaded: [PlayApp] = []
        for record in records {
            if !loaded.contains(where: { $0.id == record.id || $0.bundleIdentifier == record.packageName }) {
                let app = PlayApp(
                    id: record.id,
                    name: record.name,
                    bundleIdentifier: record.packageName,
                    version: record.version,
                    url: URL(fileURLWithPath: record.apkPath)
                )
                loaded.append(app)
            }
        }
        self.apps = loaded
        self.selectedApp = loaded.first
    }

    func persistInstalledApps() {
        var uniqueRecords: [PersistedAppRecord] = []
        for app in apps {
            if !uniqueRecords.contains(where: { $0.id == app.id || $0.packageName == app.bundleIdentifier }) {
                uniqueRecords.append(
                    PersistedAppRecord(
                        id: app.id,
                        name: app.name,
                        packageName: app.bundleIdentifier,
                        version: app.version,
                        apkPath: app.url.path
                    )
                )
            }
        }
        if let data = try? JSONEncoder().encode(uniqueRecords) {
            try? FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: storageURL)
        }
    }

    var filteredApps: [PlayApp] {
        if searchText.isEmpty {
            return apps
        }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    func launchApp(_ app: PlayApp) {
        guard isReady && !isLaunching && !isGameRunning else { return }
        selectedApp = app
        isLaunching = true
        app.isStarting = true
        statusMessage = "Launching \(app.name)..."

        var profile = TFTMACRuntimeProfile.playable.with(
            vCPU: vCPU,
            ramMiB: ramMiB,
            refreshHz: refreshHz,
            asgDrawFlushInterval: asgDrawFlushInterval
        )
        profile = profile.with(experimentPreset: experimentPreset)
        profile.save()

        setenv("MACRODROID_MODE", app.bundleIdentifier, 1)
        onLaunch?(.tft, profile, app)
    }

    func stopGame() {
        onStop?()
        selectedApp?.isStarting = false
        isGameRunning = false
        isLaunching = false
    }

    func restoreBaselineProfile() {
        let baseline = TFTMACRuntimeProfile.playable
        experimentPreset = .control
        vCPU = baseline.vCPU
        ramMiB = baseline.ramMiB
        refreshHz = baseline.refreshHz
        asgDrawFlushInterval = baseline.asgDrawFlushInterval
        saveCurrentProfile()
        saveFeedbackMessage = "Restored baseline profile (6-CPU, 5120-MiB, 60-Hz, 800-µs)."
    }

    func saveCurrentProfile() {
        var profile = TFTMACRuntimeProfile.playable.with(
            vCPU: vCPU,
            ramMiB: ramMiB,
            refreshHz: refreshHz,
            asgDrawFlushInterval: asgDrawFlushInterval
        )
        profile = profile.with(experimentPreset: experimentPreset)
        profile.save()
        saveFeedbackMessage = "Configuration saved (\(profile.identifier)). Applied on launch."
    }

    func uninstallApp(_ app: PlayApp) {
        apps.removeAll(where: { $0.id == app.id || $0.bundleIdentifier == app.bundleIdentifier })
        if selectedApp?.id == app.id {
            selectedApp = apps.first
        }
        persistInstalledApps()

        Task {
            if let paths = try? TFTMACRuntimePaths.discover() {
                _ = await Task.detached {
                    let process = Process()
                    process.executableURL = paths.adb
                    process.arguments = ["-P", "5038", "-s", "emulator-5582", "uninstall", app.bundleIdentifier]
                    try? process.run()
                    process.waitUntilExit()
                }.value
            }
        }
    }

    func installAPK(at url: URL) {
        isSideloading = true
        let fileName = url.lastPathComponent
        statusMessage = "Installing \(fileName)..."
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)

        Task {
            let paths = try? TFTMACRuntimePaths.discover()
            let meta = APKMetadataExtractor.extract(from: url, sdkRoot: paths?.sdkRoot)

            var realIcon: NSImage? = nil
            if let iconData = meta.iconData {
                realIcon = NSImage(data: iconData)
                let iconsDir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/Macrodroid/Icons", isDirectory: true)
                try? FileManager.default.createDirectory(at: iconsDir, withIntermediateDirectories: true)
                let iconSaveURL = iconsDir.appendingPathComponent("\(meta.packageName).png")
                try? iconData.write(to: iconSaveURL)
            }

            var installSuccess = true
            var installLog = ""

            if let paths = paths {
                let result = await Task.detached { () -> (Bool, String) in
                    let process = Process()
                    process.executableURL = paths.adb
                    process.arguments = ["-P", "5038", "-s", "emulator-5582", "install", "-r", url.path]
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    do {
                        try process.run()
                        process.waitUntilExit()
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let outStr = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                        let success = process.terminationStatus == 0 && (outStr.contains("Success") || !outStr.contains("Failure"))
                        return (success, outStr)
                    } catch {
                        return (false, error.localizedDescription)
                    }
                }.value
                installSuccess = result.0
                installLog = result.1
            }

            await MainActor.run {
                self.isSideloading = false
                let logEntry = "[\(timestamp)] \(fileName): \(installLog.isEmpty ? (installSuccess ? "Success" : "Completed") : installLog)"
                self.sideloadLogs.append(logEntry)

                let newApp = PlayApp(
                    id: meta.packageName,
                    name: meta.appName,
                    bundleIdentifier: meta.packageName,
                    version: meta.versionName,
                    url: url,
                    customIcon: realIcon
                )

                self.apps.removeAll(where: { $0.id == newApp.id || $0.bundleIdentifier == newApp.bundleIdentifier })
                self.apps.append(newApp)
                self.selectedApp = newApp
                self.persistInstalledApps()

                if !installSuccess && self.isGameRunning {
                    self.statusMessage = "Added \(meta.appName) (Sideload note: \(installLog))"
                } else {
                    self.statusMessage = "Installed \(meta.appName)"
                }
            }
        }
    }
}

// MARK: - Main PlayCover Style Window View

struct MacrodroidLauncherView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @State private var selectedBackgroundColor: Color = PlayCoverTheme.accent
    @State private var selectedTextColor: Color = .white

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // 1. PlayCover Translucent Source List Sidebar
                PlayCoverSidebarView(
                    viewModel: viewModel,
                    selectedTab: $viewModel.selectedSidebarItem
                )
                .frame(width: 230)

                Divider()
                    .background(PlayCoverTheme.borderSubtle)

                // 2. PlayCover Main Content Area
                VStack(spacing: 0) {
                    PlayCoverToolbarView(viewModel: viewModel)

                    Divider()
                        .background(PlayCoverTheme.borderSubtle)

                    Group {
                        switch viewModel.selectedSidebarItem {
                        case PlayCoverSidebarTab.appLibrary.rawValue:
                            PlayCoverAppLibraryView(
                                viewModel: viewModel,
                                selectedBackgroundColor: $selectedBackgroundColor,
                                selectedTextColor: $selectedTextColor
                            )
                        case PlayCoverSidebarTab.keymapping.rawValue:
                            PlayCoverKeymappingView(viewModel: viewModel)
                        case PlayCoverSidebarTab.graphics.rawValue:
                            PlayCoverGraphicsView(viewModel: viewModel)
                        case PlayCoverSidebarTab.hardware.rawValue:
                            PlayCoverHardwareView(viewModel: viewModel)
                        case PlayCoverSidebarTab.sideload.rawValue:
                            PlayCoverSideloadView(viewModel: viewModel)
                        case PlayCoverSidebarTab.about.rawValue:
                            PlayCoverAboutView()
                        default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(PlayCoverTheme.darkBackground)
            }

            // Window Drop Overlay when dragging an APK over
            if viewModel.isTargetedForDrop {
                PlayCoverDropOverlay()
            }
        }
        .sheet(item: $viewModel.inspectingApp) { app in
            PlayCoverAppInspectorSheet(viewModel: viewModel, app: app)
        }
        .onDrop(of: ["public.file-url"], isTargeted: $viewModel.isTargetedForDrop) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url, url.pathExtension.lowercased() == "apk" {
                    Task { @MainActor in
                        viewModel.installAPK(at: url)
                    }
                }
            }
            return true
        }
        .frame(minWidth: 980, minHeight: 640)
    }
}

// MARK: - PlayCover Drag & Drop Target Overlay

struct PlayCoverDropOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(PlayCoverTheme.accent.opacity(0.15))
                        .frame(width: 100, height: 100)

                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [PlayCoverTheme.accent, PlayCoverTheme.accentGreen],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                Text("Drop Android APK to Install")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Package will be parsed, extracted, and installed directly into Macrodroid.")
                    .font(.system(size: 12))
                    .foregroundColor(PlayCoverTheme.textMuted)
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PlayCoverTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [PlayCoverTheme.accent, PlayCoverTheme.accentGreen],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: PlayCoverTheme.accentGlow, radius: 24)
            )
        }
    }
}

// MARK: - PlayCover Sidebar View

struct PlayCoverSidebarView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @Binding var selectedTab: Int

    private var hostArch: String {
        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Intel Core"
        #endif
    }

    private var headerLogo: NSImage? {
        if let path = Bundle.main.path(forResource: "Macrodroid-Logo", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        let fallback = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Assets/Macrodroid-Logo.png").path
        return NSImage(contentsOfFile: fallback)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Macrodroid Branding
            HStack(spacing: 12) {
                if let logo = headerLogo {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .shadow(color: PlayCoverTheme.accentGlow, radius: 6)
                } else {
                    Image(systemName: "hexagon.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundColor(PlayCoverTheme.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Macrodroid")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("PlayCover Engine • \(hostArch)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PlayCoverTheme.textMuted)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .background(PlayCoverTheme.borderSubtle)

            // PlayCover Categorized Navigation
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // SECTION 1: LIBRARY
                    VStack(alignment: .leading, spacing: 3) {
                        Text("LIBRARY")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(PlayCoverTheme.textMuted.opacity(0.8))
                            .padding(.horizontal, 14)
                            .padding(.bottom, 2)

                        sidebarRow(tab: .appLibrary, count: viewModel.apps.isEmpty ? nil : viewModel.apps.count)
                    }

                    // SECTION 2: CONTROLS
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CONTROLS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(PlayCoverTheme.textMuted.opacity(0.8))
                            .padding(.horizontal, 14)
                            .padding(.bottom, 2)

                        sidebarRow(tab: .keymapping, count: nil)
                    }

                    // SECTION 3: SETTINGS
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SETTINGS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(PlayCoverTheme.textMuted.opacity(0.8))
                            .padding(.horizontal, 14)
                            .padding(.bottom, 2)

                        sidebarRow(tab: .graphics, count: nil)
                        sidebarRow(tab: .hardware, count: nil)
                    }

                    // SECTION 4: TOOLS
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TOOLS & SYSTEM")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(PlayCoverTheme.textMuted.opacity(0.8))
                            .padding(.horizontal, 14)
                            .padding(.bottom, 2)

                        sidebarRow(tab: .sideload, count: nil)
                        sidebarRow(tab: .about, count: nil)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            Divider()
                .background(PlayCoverTheme.borderSubtle)

            // Status Footer Capsule (Background Engine & Metal Status)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.isGameRunning ? PlayCoverTheme.accentGreen : (viewModel.isEngineRunning ? Color.green : (viewModel.isEngineStarting ? Color.orange : Color.gray.opacity(0.6))))
                        .frame(width: 8, height: 8)
                        .shadow(color: (viewModel.isGameRunning || viewModel.isEngineRunning) ? PlayCoverTheme.accentGreen : Color.clear, radius: 4)

                    Text(viewModel.isGameRunning ? "Game Active" : (viewModel.isEngineRunning ? "Engine Ready" : (viewModel.isEngineStarting ? "Engine Starting…" : "Engine Idle")))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    if viewModel.isEngineRunning {
                        Button {
                            viewModel.onStopEngine?()
                        } label: {
                            Text("Stop")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.2))
                                .foregroundColor(.red)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Stop Background Engine")
                    } else if !viewModel.isEngineStarting {
                        Button {
                            viewModel.onStartEngine?()
                        } label: {
                            Text("Start")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(PlayCoverTheme.accent.opacity(0.2))
                                .foregroundColor(PlayCoverTheme.accent)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Start Background Engine")
                    }

                    Text("Metal 3")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(PlayCoverTheme.textMuted)
                        .cornerRadius(4)
                }

                Text(viewModel.statusMessage)
                    .font(.system(size: 10))
                    .foregroundColor(PlayCoverTheme.textMuted)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("Chế độ:")
                        .font(.system(size: 9))
                        .foregroundColor(PlayCoverTheme.textMuted.opacity(0.7))
                    Text(viewModel.engineLaunchPolicy == .alwaysBackground ? "Chạy ngầm (Warm)" : "Chạy khi ấn app")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(viewModel.engineLaunchPolicy == .alwaysBackground ? PlayCoverTheme.accentGreen : Color.orange)
                }
            }
            .padding(14)
            .background(Color.black.opacity(0.25))
        }
        .background(PlayCoverTheme.sidebarBackground)
    }

    private func sidebarRow(tab: PlayCoverSidebarTab, count: Int?) -> some View {
        let isSelected = selectedTab == tab.rawValue
        return Button {
            selectedTab = tab.rawValue
        } label: {
            HStack(spacing: 11) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20)
                    .foregroundColor(isSelected ? PlayCoverTheme.accent : PlayCoverTheme.textMuted)

                Text(tab.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.85))

                Spacer()

                if let count = count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isSelected ? .white : PlayCoverTheme.textMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(isSelected ? PlayCoverTheme.accent.opacity(0.3) : Color.white.opacity(0.08))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PlayCover Top Toolbar View

struct PlayCoverToolbarView: View {
    @ObservedObject var viewModel: LauncherViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(PlayCoverTheme.textMuted)
                    .font(.system(size: 12))

                TextField("Search installed apps...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.white)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(PlayCoverTheme.textMuted)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(PlayCoverTheme.borderSubtle, lineWidth: 1)
                    )
            )
            .frame(maxWidth: 320)

            Spacer()

            // Quick Play Button (PlayCover Style)
            if let app = viewModel.selectedApp {
                Button {
                    if viewModel.isGameRunning {
                        viewModel.stopGame()
                    } else {
                        viewModel.launchApp(app)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.isGameRunning ? "stop.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(viewModel.isGameRunning ? "Stop" : "Play")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        viewModel.isGameRunning
                        ? LinearGradient(colors: [Color.red.opacity(0.8), Color.orange.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [PlayCoverTheme.accent, PlayCoverTheme.accentGreen], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .shadow(color: viewModel.isGameRunning ? Color.red.opacity(0.3) : PlayCoverTheme.accentGlow, radius: 4)
                }
                .buttonStyle(.plain)
            }

            // Plus / Import APK Button
            Button {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.canCreateDirectories = false
                panel.canChooseFiles = true
                panel.title = "Select Android APK to Install"
                if panel.runModal() == .OK, let url = panel.url {
                    viewModel.installAPK(at: url)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13))
                    Text("Add App")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .help("Import APK Package")

            // Grid / List Toggle Picker
            Picker("Layout", selection: $viewModel.isList) {
                Image(systemName: "square.grid.2x2").tag(false)
                Image(systemName: "list.bullet").tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 76)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - PlayCover App Library View

struct PlayCoverAppLibraryView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @Binding var selectedBackgroundColor: Color
    @Binding var selectedTextColor: Color

    @State private var gridLayout = [GridItem(.adaptive(minimum: 140, maximum: 170), spacing: 24)]

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            if viewModel.filteredApps.isEmpty {
                VStack(spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(PlayCoverTheme.textMuted.opacity(0.25), style: StrokeStyle(lineWidth: 2, dash: [8]))
                            .frame(width: 140, height: 140)

                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 48))
                            .foregroundColor(PlayCoverTheme.textMuted.opacity(0.4))
                    }
                    .padding(.top, 90)

                    Text("App Library is Empty")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Drag and drop any Android APK into this window, or click below to install apps and play with native Metal 3 acceleration.")
                        .font(.system(size: 12))
                        .foregroundColor(PlayCoverTheme.textMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)

                    Button {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canCreateDirectories = false
                        panel.canChooseFiles = true
                        panel.title = "Select Android APK"
                        if panel.runModal() == .OK, let url = panel.url {
                            viewModel.installAPK(at: url)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc.fill")
                            Text("Install APK Package...")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(
                            LinearGradient(
                                colors: [PlayCoverTheme.accent, PlayCoverTheme.accentGreen],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .shadow(color: PlayCoverTheme.accentGlow, radius: 6)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if viewModel.isList {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.filteredApps) { app in
                            PlayCoverAppListRow(
                                app: app,
                                isSelected: viewModel.selectedApp?.id == app.id,
                                isRunning: viewModel.isGameRunning && viewModel.selectedApp?.id == app.id,
                                onSelect: {
                                    viewModel.selectedApp = app
                                },
                                onLaunch: {
                                    viewModel.launchApp(app)
                                },
                                onOpenSettings: {
                                    viewModel.inspectingApp = app
                                },
                                onUninstall: {
                                    viewModel.uninstallApp(app)
                                }
                            )
                        }
                    }
                    .padding(16)
                } else {
                    LazyVGrid(columns: gridLayout, spacing: 28) {
                        ForEach(viewModel.filteredApps) { app in
                            PlayCoverAppGridTile(
                                app: app,
                                isSelected: viewModel.selectedApp?.id == app.id,
                                isRunning: viewModel.isGameRunning && viewModel.selectedApp?.id == app.id,
                                selectedBackgroundColor: selectedBackgroundColor,
                                selectedTextColor: selectedTextColor,
                                onSelect: {
                                    viewModel.selectedApp = app
                                },
                                onLaunch: {
                                    viewModel.launchApp(app)
                                },
                                onOpenSettings: {
                                    viewModel.inspectingApp = app
                                },
                                onUninstall: {
                                    viewModel.uninstallApp(app)
                                }
                            )
                        }
                    }
                    .padding(28)
                }
            }
        }
    }
}

// MARK: - PlayCover Squircle App Grid Tile

struct PlayCoverAppGridTile: View {
    @ObservedObject var app: PlayApp
    let isSelected: Bool
    let isRunning: Bool
    let selectedBackgroundColor: Color
    let selectedTextColor: Color
    let onSelect: () -> Void
    let onLaunch: () -> Void
    let onOpenSettings: () -> Void
    let onUninstall: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 10) {
            // Squircle Icon Container
            ZStack {
                if let image = app.customIcon {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.15), Color.white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 84, height: 84)
                        .overlay(
                            Text(String(app.name.prefix(1)).uppercased())
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        )
                }

                // Border Highlight
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(
                        isSelected
                        ? PlayCoverTheme.accent
                        : (isRunning ? PlayCoverTheme.accentGreen : Color.white.opacity(0.12)),
                        lineWidth: isSelected || isRunning ? 2.5 : 1
                    )
                    .frame(width: 84, height: 84)

                // Hover Play Overlay
                if isHovered && !app.isStarting && !isRunning {
                    ZStack {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .fill(Color.black.opacity(0.45))
                            .frame(width: 84, height: 84)

                        Circle()
                            .fill(PlayCoverTheme.accent)
                            .frame(width: 38, height: 38)
                            .shadow(color: PlayCoverTheme.accentGlow, radius: 8)

                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: 1.5)
                    }
                }

                // Loading / Running Badge
                if app.isStarting || isRunning {
                    ZStack {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .fill(Color.black.opacity(0.55))
                            .frame(width: 84, height: 84)

                        if app.isStarting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        } else {
                            VStack(spacing: 3) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(PlayCoverTheme.accentGreen)
                                Text("Running")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
            }
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .shadow(
                color: isSelected ? PlayCoverTheme.accentGlow : (isHovered ? Color.black.opacity(0.4) : Color.clear),
                radius: isHovered ? 8 : 4
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)

            // Two-Line App Name & Package Info
            VStack(spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.95))
                    .lineLimit(1)
                    .multilineTextAlignment(.center)

                Text(app.bundleIdentifier)
                    .font(.system(size: 9))
                    .foregroundColor(PlayCoverTheme.textMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .frame(width: 130)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onLaunch()
        }
        .simultaneousGesture(TapGesture().onEnded {
            onSelect()
        })
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("Launch \(app.name)", systemImage: "play.fill") {
                onLaunch()
            }
            Divider()
            Button("App Settings...", systemImage: "slider.horizontal.3") {
                onOpenSettings()
            }
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            }
            Button("Copy Package ID", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(app.bundleIdentifier, forType: .string)
            }
            Divider()
            Button("Uninstall Application", systemImage: "trash", role: .destructive) {
                onUninstall()
            }
        }
    }
}

// MARK: - PlayCover List Row

struct PlayCoverAppListRow: View {
    @ObservedObject var app: PlayApp
    let isSelected: Bool
    let isRunning: Bool
    let onSelect: () -> Void
    let onLaunch: () -> Void
    let onOpenSettings: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            Group {
                if let image = app.customIcon {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text(String(app.name.prefix(1)).uppercased())
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.95))

                Text(app.bundleIdentifier)
                    .font(.system(size: 10))
                    .foregroundColor(PlayCoverTheme.textMuted)
            }

            Spacer()

            if isRunning {
                HStack(spacing: 4) {
                    Circle()
                        .fill(PlayCoverTheme.accentGreen)
                        .frame(width: 6, height: 6)
                    Text("Running")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(PlayCoverTheme.accentGreen)
                }
                .padding(.trailing, 10)
            }

            Text("v\(app.version)")
                .font(.system(size: 11))
                .foregroundColor(PlayCoverTheme.textMuted)
                .frame(width: 60, alignment: .trailing)

            // Inline Play & Settings Buttons
            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundColor(PlayCoverTheme.textMuted)
            }
            .buttonStyle(.plain)

            Button {
                onLaunch()
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(PlayCoverTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? PlayCoverTheme.cardHoverBackground : Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? PlayCoverTheme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onLaunch()
        }
        .simultaneousGesture(TapGesture().onEnded {
            onSelect()
        })
        .contextMenu {
            Button("Launch \(app.name)") { onLaunch() }
            Button("App Settings...") { onOpenSettings() }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
            Divider()
            Button("Uninstall Application", role: .destructive) { onUninstall() }
        }
    }
}

// MARK: - PlayCover Keymapping & Controls View

struct PlayCoverKeymappingView: View {
    @ObservedObject var viewModel: LauncherViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(PlayCoverTheme.accent)

                        Text("Keymapping & Touch Controls")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text("Configure keyboard and mouse touch simulation, smart pointer lock, and on-screen keymap overlays for mobile games on macOS.")
                        .font(.system(size: 12))
                        .foregroundColor(PlayCoverTheme.textMuted)
                }

                // 1. Input Simulation Method
                VStack(alignment: .leading, spacing: 10) {
                    Text("INPUT ENGINE METHOD")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(PlayCoverTheme.textMuted)

                    VStack(spacing: 12) {
                        Picker("", selection: $viewModel.inputModeIndex) {
                            Text("Hardware Touch Emulation (Metal Touch Injection)").tag(0)
                            Text("Direct Mouse & Keyboard Bypass").tag(1)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)

                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(PlayCoverTheme.accent)
                                .padding(.top, 2)

                            Text(viewModel.inputModeIndex == 0
                                 ? "Hardware Touch Emulation injects native multitouch events into Android SurfaceFlinger with zero input lag."
                                 : "Direct Bypass forwards raw macOS mouse and keyboard events directly to the emulator.")
                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(0.85))
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(6)
                    }
                    .padding(16)
                    .background(PlayCoverTheme.cardBackground)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(PlayCoverTheme.borderSubtle, lineWidth: 1))
                }

                // 2. PlayCover Shortcuts & Hotkeys
                VStack(alignment: .leading, spacing: 10) {
                    Text("SHORTCUTS & POINTER CONTROL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(PlayCoverTheme.textMuted)

                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mouse Pointer Lock (Smart Capture)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Captures mouse pointer inside the game viewport for FPS / MOBA look.")
                                    .font(.system(size: 10))
                                    .foregroundColor(PlayCoverTheme.textMuted)
                            }
                            Spacer()
                            Text("⌥ Option Key")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(6)
                                .foregroundColor(PlayCoverTheme.accent)
                        }

                        Divider().background(PlayCoverTheme.borderSubtle)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Keymap Overlay Toggle")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Toggles transparent on-screen button labels over the game canvas.")
                                    .font(.system(size: 10))
                                    .foregroundColor(PlayCoverTheme.textMuted)
                            }
                            Spacer()
                            Text("⌘ + K")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(6)
                                .foregroundColor(PlayCoverTheme.accent)
                        }

                        Divider().background(PlayCoverTheme.borderSubtle)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Fill Viewport (Aspect Ratio Mode)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Toggles between 16:9 Letterbox fit and stretched full-window fill.")
                                    .font(.system(size: 10))
                                    .foregroundColor(PlayCoverTheme.textMuted)
                            }
                            Spacer()
                            Text("Ctrl + Fn + F")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(6)
                                .foregroundColor(PlayCoverTheme.accent)
                        }
                    }
                    .padding(16)
                    .background(PlayCoverTheme.cardBackground)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(PlayCoverTheme.borderSubtle, lineWidth: 1))
                }

                // 3. Mouse & Touch Sensitivity Sliders
                VStack(alignment: .leading, spacing: 10) {
                    Text("SENSITIVITY & TUNING")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(PlayCoverTheme.textMuted)

                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Mouse Look Sensitivity")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                                Text(String(format: "%.1fx", viewModel.mouseSensitivity))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(PlayCoverTheme.accent)
                            }
                            Slider(value: $viewModel.mouseSensitivity, in: 0.5...2.5, step: 0.1)
                        }

                        Divider().background(PlayCoverTheme.borderSubtle)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Touch Swipe Pacing")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                                Text(String(format: "%.1fx", viewModel.touchSwipeSpeed))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(PlayCoverTheme.accent)
                            }
                            Slider(value: $viewModel.touchSwipeSpeed, in: 0.5...2.0, step: 0.1)
                        }
                    }
                    .padding(16)
                    .background(PlayCoverTheme.cardBackground)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(PlayCoverTheme.borderSubtle, lineWidth: 1))
                }

                // 4. Gamepad & Controller Support Status
                VStack(alignment: .leading, spacing: 10) {
                    Text("GAMEPAD & CONTROLLER SUPPORT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(PlayCoverTheme.textMuted)

                    HStack(spacing: 14) {
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 28))
                            .foregroundColor(PlayCoverTheme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Game Controller Framework")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                            Text("PlayStation DualSense, Xbox Wireless, Nintendo Switch Pro, and MFi controllers are supported natively.")
                                .font(.system(size: 10))
                                .foregroundColor(PlayCoverTheme.textMuted)
                        }

                        Spacer()

                        Text("Active")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(PlayCoverTheme.accentGreen.opacity(0.2))
                            .foregroundColor(PlayCoverTheme.accentGreen)
                            .cornerRadius(6)
                    }
                    .padding(16)
                    .background(PlayCoverTheme.cardBackground)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(PlayCoverTheme.borderSubtle, lineWidth: 1))
                }
            }
            .padding(28)
        }
    }
}

// MARK: - PlayCover Graphics & Display View

struct PlayCoverGraphicsView: View {
    @ObservedObject var viewModel: LauncherViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "display")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(PlayCoverTheme.accent)

                        Text("Graphics & Display Settings")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text("Tune display resolution scaling, target refresh rates, and Metal 3 hardware presentation shaders.")
                        .font(.system(size: 12))
                        .foregroundColor(PlayCoverTheme.textMuted)
                }

                // 1. Resolution & Presentation
                VStack(alignment: .leading, spacing: 10) {
                    Text("DISPLAY CANVAS & SCALING")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(PlayCoverTheme.textMuted)

                    VStack(spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Target Presentation Resolution")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Virtual Android viewport resolution mapped onto MetalKit canvas.")
                                    .font(.system(size: 10))
                                    .foregroundColor(PlayCoverTheme.textMuted)
                            }
                            Spacer()
                            Text("1920 × 1080 (1080p)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(6)
                                .foregroundColor(PlayCoverTheme.accent)
                        }

                        Divider().background(PlayCoverTheme.borderSubtle)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Retina Scaling Mode")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Text("HiDPI 320 DPI pixel density with bilinear aspect filtering.")
                                    .font(.system(size: 10))
                                    .foregroundColor(PlayCoverTheme.textMuted)
                            }
                            Spacer()
                            Text("Retina 2x (320 dpi)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.85))
                        }
                    }
                    .padding(16)
                    .background(PlayCoverTheme.cardBackground)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(PlayCoverTheme.borderSubtle, lineWidth: 1))
                }

                // 2. Framerate Target
                VStack(alignment: .leading, spacing: 10) {
                    Text("REFRESH CADENCE & PACING")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(PlayCoverTheme.textMuted)

                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Display Sync Target")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Locks presentation pacing to macOS display refresh rate.")
                                    .font(.system(size: 10))
                                    .foregroundColor(PlayCoverTheme.textMuted)
                            }

                            Spacer()

                            Picker("", selection: $viewModel.refreshHz) {
                                Text("60 Hz (Standard Metal)").tag(60)
                                Text("120 Hz (ProMotion)").tag(120)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 170)
                        }
                    }
                    .padding(16)
                    .background(PlayCoverTheme.cardBackground)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(PlayCoverTheme.borderSubtle, lineWidth: 1))
                }

                // 3. Metal 3 Zero-Copy Pipeline Receipt
                VStack(alignment: .leading, spacing: 10) {
                    Text("METAL PIPELINE RECEIPT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(PlayCoverTheme.textMuted)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 20))
                                .foregroundColor(PlayCoverTheme.accentGreen)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Metal 3 Zero-Copy Shared Texture")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Direct IOSurface texture transfer from Android emulator GPU memory to macOS display server without intermediate CPU copy.")
                                    .font(.system(size: 10))
                                    .foregroundColor(PlayCoverTheme.textMuted)
                            }
                        }
                    }
                    .padding(16)
                    .background(PlayCoverTheme.cardBackground)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(PlayCoverTheme.borderSubtle, lineWidth: 1))
                }
            }
            .padding(28)
        }
    }
}

// MARK: - PlayCover Hardware & Performance View

struct PlayCoverHardwareView: View {
    @ObservedObject var viewModel: LauncherViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "cpu.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(PlayCoverTheme.accent)

                        Text("Device & Hardware Allocation")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text("Allocate host CPU cores and memory to the virtual Android environment and tune scheduling latency experiments.")
                        .font(.system(size: 12))
                        .foregroundColor(PlayCoverTheme.textMuted)
                }

                // 0. Background Engine Controls & Launch Policy Card
                VStack(alignment: .leading, spacing: 10) {
                    Text("HEADLESS BACKGROUND ENGINE & LAUNCH POLICY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(PlayCoverTheme.textMuted)

                    VStack(spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Virtual Machine Engine Status")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Keeps Android running silently as a background service. Games launch directly in independent macOS windows.")
                                    .font(.system(size: 10))
                                    .foregroundColor(PlayCoverTheme.textMuted)
                            }
                            Spacer()
                            Text(viewModel.isEngineRunning ? "Engine Active (Ready)" : (viewModel.isEngineStarting ? "Starting Engine…" : "Engine Idle (Stopped)"))
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(viewModel.isEngineRunning ? PlayCoverTheme.accentGreen.opacity(0.2) : Color.white.opacity(0.08))
                                .foregroundColor(viewModel.isEngineRunning ? PlayCoverTheme.accentGreen : PlayCoverTheme.textMuted)
                                .cornerRadius(6)
                        }

                        Divider().background(PlayCoverTheme.borderSubtle)

                        // Engine Startup Policy: Always background vs On-demand
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Chế độ khởi động Engine (Engine Startup Policy)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                            }

                            Picker("", selection: Binding(
                                get: { viewModel.engineLaunchPolicy },
                                set: { viewModel.setEngineLaunchPolicy($0) }
                            )) {
                                ForEach(EngineLaunchPolicy.allCases, id: \.self) { policy in
                                    Text(policy.displayName).tag(policy)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)

                            Text(viewModel.engineLaunchPolicy.detail)
                                .font(.system(size: 11))
                                .foregroundColor(PlayCoverTheme.textMuted)
                                .padding(.top, 2)
                        }

                        Divider().background(PlayCoverTheme.borderSubtle)

                        // When App Window Closes: Keep warm vs Stop engine
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Khi đóng cửa sổ ứng dụng (When App Window Closes)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                            }

                            Picker("", selection: Binding(
                                get: { viewModel.engineCloseBehavior },
                                set: { viewModel.setEngineCloseBehavior($0) }
                            )) {
                                ForEach(EngineCloseBehavior.allCases, id: \.self) { behavior in
                                    Text(behavior.displayName).tag(behavior)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)

                            Text(viewModel.engineCloseBehavior.detail)
                                .font(.system(size: 11))
                                .foregroundColor(PlayCoverTheme.textMuted)
                                .padding(.top, 2)
                        }

                        Divider().background(PlayCoverTheme.borderSubtle)

                        HStack(spacing: 12) {
                            Button(viewModel.isEngineRunning ? "Restart Background Engine" : "Start Background Engine (Pre-warm)") {
                                viewModel.onStartEngine?()
                            }
                            .buttonStyle(.bordered)
                            .font(.system(size: 11))

                            Spacer()

                            if viewModel.isEngineRunning {
                                Button("Stop Background Engine", role: .destructive) {
                                    viewModel.onStopEngine?()
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .font(.system(size: 11))
                            }
                        }
                    }
                    .padding(16)
                    .background(PlayCoverTheme.cardBackground)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(PlayCoverTheme.borderSubtle, lineWidth: 1))
                }

                // 0.5. Notification Mirroring Section
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("NOTIFICATION FORWARDING (THÔNG BÁO MÁY ẢO -> MACOS)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(PlayCoverTheme.textMuted)

                        Spacer()

                        Text("Apple UNNotificationCenter")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(PlayCoverTheme.accentGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(PlayCoverTheme.accentGreen.opacity(0.12))
                            .cornerRadius(4)
                    }

                    VStack(spacing: 14) {
                        Toggle(isOn: Binding(
                            get: { viewModel.isNotificationMirroringEnabled },
                            set: { viewModel.setNotificationMirroringEnabled($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Chuyển tiếp thông báo ứng dụng sang macOS")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Khi game hoặc ứng dụng trong máy ảo gửi thông báo, Macrodroid sẽ đẩy banner thông báo gốc của macOS.")
                                    .font(.system(size: 10))
                                    .foregroundColor(PlayCoverTheme.textMuted)
                            }
                        }
                        .toggleStyle(.switch)

                        Divider().background(PlayCoverTheme.borderSubtle)

                        Toggle(isOn: Binding(
                            get: { viewModel.filterSystemNotifications },
                            set: { viewModel.setFilterSystemNotifications($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Lọc bỏ thông báo hệ thống Android (System Filter)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Chỉ nhận thông báo từ game/ứng dụng người dùng; ẩn thông báo gỡ lỗi ADB, Play Services và System UI.")
                                    .font(.system(size: 10))
                                    .foregroundColor(PlayCoverTheme.textMuted)
                            }
                        }
                        .toggleStyle(.switch)

                        Divider().background(PlayCoverTheme.borderSubtle)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Kiểm tra thông báo (Test Banner)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Kích hoạt thông báo mẫu từ Android guest để xác thực cấp quyền Notification Center của macOS.")
                                    .font(.system(size: 10))
                                    .foregroundColor(PlayCoverTheme.textMuted)
                            }

                            Spacer()

                            Button(action: {
                                viewModel.sendTestNotification()
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "bell.badge.fill")
                                        .font(.system(size: 11))
                                    Text("Gửi thông báo thử")
                                        .font(.system(size: 11, weight: .medium))
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(16)
                    .background(PlayCoverTheme.cardBackground)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(PlayCoverTheme.borderSubtle, lineWidth: 1))
                }

                // 0.6. macOS App Shortcuts (Spotlight & Dock)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("MAC OS APP WRAPPERS (SPOTLIGHT & DOCK SHORTCUTS)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(PlayCoverTheme.textMuted)

                        Spacer()

                        Text("WSA-Style Integration")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(PlayCoverTheme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(PlayCoverTheme.accent.opacity(0.12))
                            .cornerRadius(4)
                    }

                    VStack(spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Lối tắt ứng dụng độc lập trên macOS")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Tự động sinh các bundle .app trong ~/Applications/Macrodroid Apps để tìm kiếm bằng Spotlight (Cmd+Space) hoặc kéo thả ghim vào Dock.")
                                    .font(.system(size: 10))
                                    .foregroundColor(PlayCoverTheme.textMuted)
                            }
                            Spacer()
                        }

                        Divider().background(PlayCoverTheme.borderSubtle)

                        HStack(spacing: 12) {
                            Button(action: {
                                viewModel.createAllMacShortcuts()
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus.square.dashed")
                                    Text("Tạo lối tắt cho toàn bộ game")
                                }
                                .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button(action: {
                                viewModel.revealMacShortcutsFolder()
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "folder.fill")
                                    Text("Mở thư mục trong Finder")
                                }
                                .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(16)
                    .background(PlayCoverTheme.cardBackground)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(PlayCoverTheme.borderSubtle, lineWidth: 1))
                }

                // 1. Launch Experiment Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("LAUNCH EXPERIMENT PRESET")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(PlayCoverTheme.textMuted)

                    VStack(alignment: .leading, spacing: 10) {
                        Picker("", selection: $viewModel.experimentPreset) {
                            ForEach(RuntimeExperimentPreset.selectableCases, id: \.self) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)

                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(PlayCoverTheme.accent)
                                .padding(.top, 2)

                            Text(viewModel.experimentPreset.detail)
                                .font(.system(size: 11))
                                .foregroundColor(Color.white.opacity(0.85))
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(6)
                    }
                    .padding(16)
                    .background(PlayCoverTheme.cardBackground)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(PlayCoverTheme.borderSubtle, lineWidth: 1))
                }

                // 2. Hardware Resource Allocation
                VStack(alignment: .leading, spacing: 10) {
                    Text("GUEST HARDWARE ALLOCATION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(PlayCoverTheme.textMuted)

                    VStack(spacing: 14) {
                        // vCPU
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Virtual CPUs (vCPU)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Dedicated host performance cores allocated to guest Android VM.")
                                    .font(.system(size: 10))
                                    .foregroundColor(PlayCoverTheme.textMuted)
                            }

                            Spacer()

                            Picker("", selection: $viewModel.vCPU) {
                                Text("4 Cores").tag(4)
                                Text("6 Cores (Optimal)").tag(6)
                                Text("8 Cores (Max)").tag(8)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 170)
                        }

                        Divider().background(PlayCoverTheme.borderSubtle)

                        // RAM
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Android RAM (Memory)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Unified memory allocated to textures, audio buffers, and app heap.")
                                    .font(.system(size: 10))
                                    .foregroundColor(PlayCoverTheme.textMuted)
                            }

                            Spacer()

                            Picker("", selection: $viewModel.ramMiB) {
                                Text("4096 MiB (4 GB)").tag(4096)
                                Text("5120 MiB (5 GB - Optimal)").tag(5120)
                                Text("8192 MiB (8 GB)").tag(8192)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 170)
                        }

                        Divider().background(PlayCoverTheme.borderSubtle)

                        // ASG Draw Flush
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ASG Draw Flush Interval")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Microseconds between Android SurfaceFlinger command flushes.")
                                    .font(.system(size: 10))
                                    .foregroundColor(PlayCoverTheme.textMuted)
                            }

                            Spacer()

                            Picker("", selection: $viewModel.asgDrawFlushInterval) {
                                Text("400 µs (Aggressive)").tag(400)
                                Text("800 µs (Baseline)").tag(800)
                                Text("1600 µs (Conservative)").tag(1600)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 170)
                        }
                    }
                    .padding(16)
                    .background(PlayCoverTheme.cardBackground)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(PlayCoverTheme.borderSubtle, lineWidth: 1))
                }

                // 3. Actions & Feedback
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Button("Restore Baseline Profile") {
                            viewModel.restoreBaselineProfile()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(.white)
                        .cornerRadius(6)

                        Spacer()

                        Button("Save Settings") {
                            viewModel.saveCurrentProfile()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [PlayCoverTheme.accent, PlayCoverTheme.accentGreen],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .font(.system(size: 12, weight: .bold))
                        .cornerRadius(6)
                        .shadow(color: PlayCoverTheme.accentGlow, radius: 4)
                    }

                    if !viewModel.saveFeedbackMessage.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(PlayCoverTheme.accentGreen)
                                .font(.system(size: 12))
                            Text(viewModel.saveFeedbackMessage)
                                .font(.system(size: 11))
                                .foregroundColor(PlayCoverTheme.textMuted)
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .padding(28)
        }
    }
}

// MARK: - PlayCover Sideload & Tools View

struct PlayCoverSideloadView: View {
    @ObservedObject var viewModel: LauncherViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(PlayCoverTheme.accent)

                        Text("Sideload & Package Tools")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text("Install Android APK packages, inspect package badging and permissions, and monitor live ADB installation logs.")
                        .font(.system(size: 12))
                        .foregroundColor(PlayCoverTheme.textMuted)
                }

                // 1. Big Dropzone / Sideload Card
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(PlayCoverTheme.accent.opacity(0.12))
                            .frame(width: 72, height: 72)

                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 32))
                            .foregroundColor(PlayCoverTheme.accent)
                    }

                    VStack(spacing: 4) {
                        Text("Drag & Drop APK File Here")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Supports ARM64 and x86_64 Android application packages")
                            .font(.system(size: 11))
                            .foregroundColor(PlayCoverTheme.textMuted)
                    }

                    Button {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canCreateDirectories = false
                        panel.canChooseFiles = true
                        panel.title = "Select Android APK to Install"
                        if panel.runModal() == .OK, let url = panel.url {
                            viewModel.installAPK(at: url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus")
                            Text("Browse APK File...")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(PlayCoverTheme.accent)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .background(PlayCoverTheme.cardBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(PlayCoverTheme.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                )

                // 2. Active Sideload Status Banner
                if viewModel.isSideloading {
                    HStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                        Text(viewModel.statusMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PlayCoverTheme.cardBackground)
                    .cornerRadius(8)
                }

                // 3. Live ADB Console Log
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("ADB INSTALLATION CONSOLE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(PlayCoverTheme.textMuted)

                        Spacer()

                        Button("Copy Log") {
                            let text = viewModel.sideloadLogs.joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundColor(PlayCoverTheme.accent)

                        Button("Clear") {
                            viewModel.sideloadLogs.removeAll()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundColor(PlayCoverTheme.textMuted)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if viewModel.sideloadLogs.isEmpty {
                            Text("No recent sideload operations. Logs will appear here when an APK is installed.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(PlayCoverTheme.textMuted.opacity(0.6))
                                .padding(12)
                        } else {
                            ForEach(viewModel.sideloadLogs, id: \.self) { log in
                                Text(log)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(log.contains("Failure") ? Color.red : PlayCoverTheme.accentGreen)
                                    .textSelection(.enabled)
                            }
                            .padding(10)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(PlayCoverTheme.borderSubtle, lineWidth: 1))
                }
            }
            .padding(28)
        }
    }
}

// MARK: - PlayCover App Inspector Sheet

struct PlayCoverAppInspectorSheet: View {
    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject var app: PlayApp
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // App Header
            HStack(spacing: 16) {
                if let icon = app.customIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Text(String(app.name.prefix(1)).uppercased())
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)

                    Text(app.bundleIdentifier)
                        .font(.system(size: 11))
                        .foregroundColor(PlayCoverTheme.textMuted)

                    Text("Version \(app.version)")
                        .font(.system(size: 10))
                        .foregroundColor(PlayCoverTheme.textMuted.opacity(0.8))
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider().background(PlayCoverTheme.borderSubtle)

            // Settings Group
            VStack(spacing: 14) {
                // Orientation
                HStack {
                    Text("Aspect Ratio / Orientation")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Picker("", selection: $app.aspectRatioIndex) {
                        Text("Landscape (16:9)").tag(1)
                        Text("Portrait (9:16)").tag(0)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                Divider().background(PlayCoverTheme.borderSubtle)

                // Resolution
                HStack {
                    Text("Display Resolution")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Picker("", selection: $app.resolutionIndex) {
                        Text("720p").tag(0)
                        Text("1080p (Default)").tag(1)
                        Text("1440p (2K)").tag(2)
                        Text("4K").tag(3)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }

                Divider().background(PlayCoverTheme.borderSubtle)

                // Target FPS
                HStack {
                    Text("Target Framerate")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Picker("", selection: $app.targetFPS) {
                        Text("30 FPS").tag(30)
                        Text("60 FPS (Default)").tag(60)
                        Text("120 FPS (ProMotion)").tag(120)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }

                Divider().background(PlayCoverTheme.borderSubtle)

                // Window Mode
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Window Mode")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                        Text("Runs in independent native window via background engine.")
                            .font(.system(size: 10))
                            .foregroundColor(PlayCoverTheme.textMuted)
                    }
                    Spacer()
                    Text("Native Window")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(PlayCoverTheme.accent.opacity(0.15))
                        .foregroundColor(PlayCoverTheme.accent)
                        .cornerRadius(6)
                }
            }
            .padding(16)
            .background(PlayCoverTheme.cardBackground)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(PlayCoverTheme.borderSubtle, lineWidth: 1))

            // Action Buttons
            HStack(spacing: 10) {
                Button("Show APK in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([app.url])
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(PlayCoverTheme.accent)

                Spacer()

                Button(action: {
                    viewModel.createMacShortcut(for: app)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app")
                        Text("Add to Mac / Dock")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)

                Button("Launch App", systemImage: "play.fill") {
                    dismiss()
                    viewModel.launchApp(app)
                }
                .buttonStyle(.borderedProminent)
                .tint(PlayCoverTheme.accent)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(PlayCoverTheme.darkBackground)
    }
}

// MARK: - PlayCover About View

struct PlayCoverAboutView: View {
    private var hostArch: String {
        #if arch(arm64)
        return "Apple Silicon (ARM64)"
        #else
        return "Intel Core (x86_64)"
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("About Macrodroid")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Macrodroid is a high-performance Android gaming runtime and launcher for macOS, crafted with the simplicity and power of PlayCover and accelerated by the Joy Engine.")
                .font(.system(size: 13))
                .foregroundColor(PlayCoverTheme.textMuted)

            VStack(alignment: .leading, spacing: 12) {
                Text("SYSTEM & ARCHITECTURE")
                    .font(.caption).bold()
                    .foregroundColor(PlayCoverTheme.textMuted)

                HStack {
                    Text("Host Architecture:")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                    Spacer()
                    Text(hostArch)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(PlayCoverTheme.accent)
                }

                Divider().background(PlayCoverTheme.borderSubtle)

                HStack {
                    Text("Graphics Presentation:")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Metal 3 (Zero-Copy IOSurface)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(PlayCoverTheme.accentGreen)
                }

                Divider().background(PlayCoverTheme.borderSubtle)

                HStack {
                    Text("IPC & Service Bridge:")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Swift gRPC Core v2")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.85))
                }
            }
            .padding(18)
            .background(PlayCoverTheme.cardBackground)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(PlayCoverTheme.borderSubtle, lineWidth: 1))

            Button("Reveal Local Captures Folder") {
                let captures = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/Macrodroid/Captures", isDirectory: true)
                try? FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
                NSWorkspace.shared.open(captures)
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(32)
    }
}
