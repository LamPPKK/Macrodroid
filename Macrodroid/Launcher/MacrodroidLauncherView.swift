//
//  MacrodroidLauncherView.swift
//  Macrodroid (Joy Engine - Streamlined & Deduplicated)
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

        // 2. If aapt didn't yield a direct PNG (e.g. adaptive XML), scan zip entries using /usr/bin/unzip -l
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

        // 3. Extract the icon bytes using /usr/bin/unzip -p <apkPath> <iconPath>
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
    @Published var resolutionIndex: Int = 2
    @Published var aspectRatioIndex: Int = 1
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

// MARK: - Joy Visual Theme

enum JoyTheme {
    static let accent = Color(red: 0.0, green: 0.82, blue: 0.35)
    static let accentHighlight = Color(red: 0.28, green: 0.98, blue: 0.54)
    static let accentGlow = Color(red: 0.0, green: 0.88, blue: 0.38).opacity(0.35)
    static let darkBackground = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let sidebarBackground = Color(red: 0.08, green: 0.10, blue: 0.13)
    static let cardBackground = Color(red: 0.12, green: 0.15, blue: 0.19)
    static let borderSubtle = Color(red: 0.85, green: 0.90, blue: 0.95).opacity(0.12)
    static let textMuted = Color(red: 0.60, green: 0.65, blue: 0.70)
}

// MARK: - Launcher View Model (Starts Clean with Zero Duplicate Items)

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var sdkPath: String = "Scanning..."
    @Published var avdName: String = "Scanning..."
    @Published var isReady: Bool = false
    @Published var isLaunching: Bool = false
    @Published var isGameRunning: Bool = false
    @Published var statusMessage: String = "System Ready"

    // Performance Lab parameters (fully integrated in-window, no popups)
    @Published var experimentPreset: RuntimeExperimentPreset = .control
    @Published var vCPU: Int = 6
    @Published var ramMiB: Int = 5120
    @Published var refreshHz: Int = 60
    @Published var asgDrawFlushInterval: Int = 800
    @Published var saveFeedbackMessage: String = "Changes apply directly on launch."

    // Library State: Completely empty by default
    @Published var apps: [PlayApp] = []
    @Published var selectedApp: PlayApp? = nil
    @Published var searchText: String = ""
    @Published var isList: Bool = false
    @Published var selectedSidebarItem: Int = 1 // 1: App Library, 2: Performance Lab, 3: About
    @Published var isSideloading: Bool = false
    @Published var sideloadLogs: [String] = []

    var onLaunch: ((LaunchMode, TFTMACRuntimeProfile, PlayApp?) -> Void)?
    var onStop: (() -> Void)?
    var onOpenSettings: (() -> Void)?

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
            // Deduplicate during load
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
        statusMessage = "Starting \(app.name)..."

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
    }

    func restoreBaselineProfile() {
        let baseline = TFTMACRuntimeProfile.playable
        experimentPreset = .control
        vCPU = baseline.vCPU
        ramMiB = baseline.ramMiB
        refreshHz = baseline.refreshHz
        asgDrawFlushInterval = baseline.asgDrawFlushInterval
        saveCurrentProfile()
        saveFeedbackMessage = "Restored baseline (6-CPU, 5120-MiB, 60-Hz, 800-µs)."
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

            // Attempt adb install if emulator is online
            if let paths = paths {
                _ = await Task.detached {
                    let process = Process()
                    process.executableURL = paths.adb
                    process.arguments = ["-P", "5038", "-s", "emulator-5582", "install", "-r", url.path]
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    try? process.run()
                    process.waitUntilExit()
                }.value
            }

            await MainActor.run {
                self.isSideloading = false

                let newApp = PlayApp(
                    id: meta.packageName,
                    name: meta.appName,
                    bundleIdentifier: meta.packageName,
                    version: meta.versionName,
                    url: url,
                    customIcon: realIcon
                )

                // Strictly deduplicate: replace existing app if same package ID
                self.apps.removeAll(where: { $0.id == newApp.id || $0.bundleIdentifier == newApp.bundleIdentifier })
                self.apps.append(newApp)
                self.selectedApp = newApp
                self.persistInstalledApps()
                self.statusMessage = "Installed \(meta.appName)"
            }
        }
    }
}

// MARK: - Joy Main Split View (Streamlined 3-Section Layout)

struct MacrodroidLauncherView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @State private var selectedBackgroundColor: Color = JoyTheme.accent
    @State private var selectedTextColor: Color = .white

    var body: some View {
        HStack(spacing: 0) {
            // 1. Clean Left Sidebar Navigation
            JoySidebarView(
                viewModel: viewModel,
                selectedTab: $viewModel.selectedSidebarItem
            )
            .frame(width: 220)

            Divider()
                .background(JoyTheme.borderSubtle)

            // 2. Main Content Area (Zero Duplicates, No Popups!)
            Group {
                switch viewModel.selectedSidebarItem {
                case 1:
                    JoyAppLibraryView(
                        viewModel: viewModel,
                        selectedBackgroundColor: $selectedBackgroundColor,
                        selectedTextColor: $selectedTextColor
                    )
                case 2:
                    JoyPerformanceConfigurationView(viewModel: viewModel)
                case 3:
                    JoyAboutView()
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(JoyTheme.darkBackground)
        }
        .frame(minWidth: 940, minHeight: 620)
    }
}

// MARK: - Joy Streamlined Sidebar View

struct JoySidebarView: View {
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
            HStack(spacing: 10) {
                if let logo = headerLogo {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .shadow(color: JoyTheme.accentGlow, radius: 4)
                } else {
                    Image(systemName: "hexagon.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .foregroundColor(JoyTheme.accentHighlight)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Macrodroid")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Joy Engine • \(hostArch)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(JoyTheme.textMuted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()
                .background(JoyTheme.borderSubtle)

            // Sidebar Navigation (Streamlined: App Library, Performance Lab, About)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("LIBRARY")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(JoyTheme.textMuted.opacity(0.8))
                            .padding(.horizontal, 12)

                        sidebarRow(tag: 1, title: "App Library", icon: "square.grid.2x2", count: viewModel.apps.isEmpty ? nil : viewModel.apps.count)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("CONFIGURATION")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(JoyTheme.textMuted.opacity(0.8))
                            .padding(.horizontal, 12)

                        sidebarRow(tag: 2, title: "Performance Lab", icon: "slider.horizontal.3", count: nil)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("SYSTEM")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(JoyTheme.textMuted.opacity(0.8))
                            .padding(.horizontal, 12)

                        sidebarRow(tag: 3, title: "About", icon: "info.circle", count: nil)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            Divider()
                .background(JoyTheme.borderSubtle)

            // Status Capsule
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.isGameRunning ? JoyTheme.accentHighlight : (viewModel.isReady ? Color.green : Color.orange))
                        .frame(width: 8, height: 8)
                        .shadow(color: viewModel.isGameRunning ? JoyTheme.accentHighlight : Color.clear, radius: 4)

                    Text(viewModel.isGameRunning ? "Game Session Active" : (viewModel.isReady ? "AVD Ready" : "Initializing"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Text("Metal 3")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(JoyTheme.textMuted)
                        .cornerRadius(4)
                }

                Text(viewModel.avdName)
                    .font(.system(size: 10))
                    .foregroundColor(JoyTheme.textMuted)
                    .lineLimit(1)
            }
            .padding(12)
            .background(Color.black.opacity(0.2))
        }
        .background(JoyTheme.sidebarBackground)
    }

    private func sidebarRow(tag: Int, title: String, icon: String, count: Int?) -> some View {
        Button {
            selectedTab = tag
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundColor(selectedTab == tag ? JoyTheme.accentHighlight : JoyTheme.textMuted)

                Text(title)
                    .font(.system(size: 12, weight: selectedTab == tag ? .semibold : .regular))
                    .foregroundColor(selectedTab == tag ? .white : Color.white.opacity(0.85))

                Spacer()

                if let count = count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(JoyTheme.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selectedTab == tag ? Color.white.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Joy App Library View

struct JoyAppLibraryView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @Binding var selectedBackgroundColor: Color
    @Binding var selectedTextColor: Color

    @State private var gridLayout = [GridItem(.adaptive(minimum: 130, maximum: .infinity))]

    var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar
            HStack(spacing: 12) {
                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(JoyTheme.textMuted)
                        .font(.system(size: 12))

                    TextField("Search library or package...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.white)

                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(JoyTheme.textMuted)
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
                                .stroke(JoyTheme.borderSubtle, lineWidth: 1)
                        )
                )
                .frame(maxWidth: 320)

                Spacer()

                // Plus Button (Install APK)
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
                    Image(systemName: "plus.circle")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .help("Install Android APK")

                // Gear Button (Switches directly to in-window Performance Lab)
                Button {
                    viewModel.selectedSidebarItem = 2
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .help("Performance & Hardware Configuration")

                // Grid / List Toggle Picker
                Picker("Layout", selection: $viewModel.isList) {
                    Image(systemName: "square.grid.2x2").tag(false)
                    Image(systemName: "list.bullet").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 80)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()
                .background(JoyTheme.borderSubtle)

            // Main Display: Clean Empty State or Apps
            ScrollView(.vertical, showsIndicators: true) {
                if viewModel.filteredApps.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 52))
                            .foregroundColor(JoyTheme.textMuted.opacity(0.35))
                            .padding(.top, 100)

                        Text("No Applications Installed")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)

                        Text("Import an Android APK or drag and drop a package into Macrodroid to install and play with native hardware acceleration.")
                            .font(.system(size: 12))
                            .foregroundColor(JoyTheme.textMuted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)

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
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                Text("Import APK Package...")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(JoyTheme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if viewModel.isList {
                        LazyVStack(spacing: 2) {
                            ForEach(viewModel.filteredApps) { app in
                                PlayAppListRow(
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
                                        viewModel.selectedApp = app
                                        viewModel.selectedSidebarItem = 2
                                    },
                                    onUninstall: {
                                        viewModel.uninstallApp(app)
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                    } else {
                        LazyVGrid(columns: gridLayout, spacing: 20) {
                            ForEach(viewModel.filteredApps) { app in
                                PlayAppGridTile(
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
                                        viewModel.selectedApp = app
                                        viewModel.selectedSidebarItem = 2
                                    },
                                    onUninstall: {
                                        viewModel.uninstallApp(app)
                                    }
                                )
                            }
                        }
                        .padding(24)
                    }
                }
            }
        }
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
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
    }
}

// MARK: - Joy Grid Tile (Real Icon Display)

struct PlayAppGridTile: View {
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
        LazyVStack(spacing: 8) {
            ZStack {
                if let image = app.customIcon {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .cornerRadius(15)
                        .shadow(radius: isHovered ? 4 : 1)
                } else {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Text(String(app.name.prefix(1)).uppercased())
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                        )
                }

                if app.isStarting || isRunning {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.black.opacity(0.5))
                            .frame(width: 60, height: 60)

                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                    }
                }
            }

            HStack {
                Text(app.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .foregroundColor(isSelected ? selectedTextColor : Color.white)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isSelected ? selectedBackgroundColor : Color.clear)
                            .brightness(-0.15)
                    )
                    .frame(height: 20)
            }
        }
        .frame(width: 130, height: 130)
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
            Button("Launch \(app.name)") {
                onLaunch()
            }
            Divider()
            Button("Performance Settings", systemImage: "gear") {
                onOpenSettings()
            }
            Button("Show in Finder", systemImage: "finder") {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            }
            Divider()
            Button("Uninstall Application", systemImage: "trash", role: .destructive) {
                onUninstall()
            }
        }
    }
}

// MARK: - Joy List Row (Real Icon Display)

struct PlayAppListRow: View {
    @ObservedObject var app: PlayApp
    let isSelected: Bool
    let isRunning: Bool
    let onSelect: () -> Void
    let onLaunch: () -> Void
    let onOpenSettings: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Group {
                if let image = app.customIcon {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                        .cornerRadius(7.5)
                } else {
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 30, height: 30)
                        .overlay(
                            Text(String(app.name.prefix(1)).uppercased())
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 5)

            Text(app.name)
                .font(.system(size: 13))
                .foregroundColor(isSelected ? .white : Color.white.opacity(0.9))

            Spacer()

            if isRunning {
                Text("Running")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(JoyTheme.accentHighlight)
                    .padding(.trailing, 10)
            }

            Text(app.version)
                .font(.system(size: 11))
                .padding(.horizontal, 15)
                .foregroundColor(JoyTheme.textMuted)
        }
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? JoyTheme.accent.opacity(0.3) : Color.clear)
        )
        .onTapGesture(count: 2) {
            onLaunch()
        }
        .simultaneousGesture(TapGesture().onEnded {
            onSelect()
        })
        .contextMenu {
            Button("Launch \(app.name)") {
                onLaunch()
            }
            Divider()
            Button("Performance Settings", systemImage: "gear") {
                onOpenSettings()
            }
            Divider()
            Button("Uninstall Application", systemImage: "trash", role: .destructive) {
                onUninstall()
            }
        }
    }
}

// MARK: - FULLY INTEGRATED IN-WINDOW PERFORMANCE CONFIGURATION VIEW (NO POPUPS)

struct JoyPerformanceConfigurationView: View {
    @ObservedObject var viewModel: LauncherViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(JoyTheme.accentHighlight)

                        Text("Performance & Hardware Configuration")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text("Configure virtual cores, guest Android memory, refresh cadence, and scheduling experiments directly in Macrodroid. Changes are saved to your runtime profile and applied on launch.")
                        .font(.system(size: 12))
                        .foregroundColor(JoyTheme.textMuted)
                }
                .padding(.bottom, 6)

                // 1. Launch Experiment Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("LAUNCH EXPERIMENT PRESET")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(JoyTheme.textMuted)

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
                                .foregroundColor(JoyTheme.accentHighlight)
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
                    .background(JoyTheme.cardBackground)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(JoyTheme.borderSubtle, lineWidth: 1)
                    )
                }

                // 2. Guest Hardware Allocation Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("GUEST HARDWARE ALLOCATION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(JoyTheme.textMuted)

                    VStack(spacing: 14) {
                        // vCPU
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Virtual CPUs (vCPU)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Dedicated host performance cores allocated to guest Android VM.")
                                    .font(.system(size: 10))
                                    .foregroundColor(JoyTheme.textMuted)
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

                        Divider().background(JoyTheme.borderSubtle)

                        // RAM
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Android RAM (Memory)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Unified memory allocated to guest textures, audio buffers, and app heap.")
                                    .font(.system(size: 10))
                                    .foregroundColor(JoyTheme.textMuted)
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

                        Divider().background(JoyTheme.borderSubtle)

                        // Refresh Hz
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Guest Refresh Target")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Display sync target locked to Metal presentation pipeline.")
                                    .font(.system(size: 10))
                                    .foregroundColor(JoyTheme.textMuted)
                            }

                            Spacer()

                            Picker("", selection: $viewModel.refreshHz) {
                                Text("60 Hz (Proven Metal)").tag(60)
                                Text("120 Hz (ProMotion)").tag(120)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 170)
                        }

                        Divider().background(JoyTheme.borderSubtle)

                        // ASG Flush
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ASG Draw Flush Interval")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Microseconds between Android SurfaceFlinger command flushes.")
                                    .font(.system(size: 10))
                                    .foregroundColor(JoyTheme.textMuted)
                            }

                            Spacer()

                            Picker("", selection: $viewModel.asgDrawFlushInterval) {
                                Text("400 µs (Aggressive)").tag(400)
                                Text("800 µs (Proven Baseline)").tag(800)
                                Text("1600 µs (Conservative)").tag(1600)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 170)
                        }
                    }
                    .padding(16)
                    .background(JoyTheme.cardBackground)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(JoyTheme.borderSubtle, lineWidth: 1)
                    )
                }

                // 3. Display & Surface Pipeline Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("DISPLAY & RENDERING STACK")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(JoyTheme.textMuted)

                    VStack(spacing: 12) {
                        HStack {
                            Text("Play Surface Target")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Text("1920 × 1080 @ 320 dpi (Retina 1440p Scaling)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(JoyTheme.accentHighlight)
                        }

                        Divider().background(JoyTheme.borderSubtle)

                        HStack {
                            Text("Graphics & Audio Engine")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Text("Host GPU · CoreAudio · Metal 3 Zero-Copy")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.85))
                        }
                    }
                    .padding(16)
                    .background(JoyTheme.cardBackground)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(JoyTheme.borderSubtle, lineWidth: 1)
                    )
                }

                // 4. Hotkeys & Short-cuts (Consolidated here, no duplicate tab)
                VStack(alignment: .leading, spacing: 10) {
                    Text("SHORTCUTS & CONTROLS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(JoyTheme.textMuted)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("• ⌥ (Option): Toggle mouse pointer lock in/out of the game window")
                        Text("• ⌘ + K: Toggle live touch & keymapping overlay while running")
                        Text("• Ctrl + Fn + F: Fill game viewport to fit window")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.85))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(JoyTheme.cardBackground)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(JoyTheme.borderSubtle, lineWidth: 1)
                    )
                }

                // 5. Action Buttons & Feedback Banner
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Button("Restore Proven Baseline") {
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
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(JoyTheme.accent)
                        .foregroundColor(.white)
                        .font(.system(size: 12, weight: .bold))
                        .cornerRadius(6)
                        .keyboardShortcut(.defaultAction)
                    }

                    if !viewModel.saveFeedbackMessage.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(JoyTheme.accentHighlight)
                                .font(.system(size: 12))
                            Text(viewModel.saveFeedbackMessage)
                                .font(.system(size: 11))
                                .foregroundColor(JoyTheme.textMuted)
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .padding(28)
        }
    }
}

// MARK: - About View

struct JoyAboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("About Macrodroid")
                .font(.title2).bold()
                .foregroundColor(.white)

            Text("Macrodroid is an open, high-performance game launcher and runtime client powered by the Joy Engine for Apple Silicon and Intel Macs.")
                .foregroundColor(JoyTheme.textMuted)

            VStack(alignment: .leading, spacing: 8) {
                Text("HERITAGE")
                    .font(.caption).bold()
                    .foregroundColor(JoyTheme.textMuted)

                Text("Macrodroid builds upon foundational research and donor contracts for macOS Apple Silicon native gaming.")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.85))
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(8)

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
