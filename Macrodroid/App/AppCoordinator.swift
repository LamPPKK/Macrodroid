import AppKit
import UserNotifications

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let mailbox = LatestFrameMailbox()
    private var launcherWindowController: LauncherWindowController?
    private var mainWindowController: MainWindowController?
    private var runtimeController: TFTMACRuntimeController?
    private var settingsWindowController: RuntimeSettingsWindowController?
    private var activeProfile: TFTMACRuntimeProfile = .playable
    private var terminationInProgress = false

    // Menu Bar Extra & Dock Hiding
    private var statusItem: NSStatusItem?
    private var isDockHidden: Bool = false
    private var currentAppName: String = ""
    private var currentAppPackage: String = ""
    private var latestGameFrameWindow: GameFrameTelemetryWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply official emerald Macrodroid icon to running application
        if let path = Bundle.main.path(forResource: "Macrodroid-Logo", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            NSApp.applicationIconImage = img
        } else if let path = Bundle.main.path(forResource: "Macrodroid-1024", ofType: "png"),
                  let img = NSImage(contentsOfFile: path) {
            NSApp.applicationIconImage = img
        }

        // Configure macOS UserNotificationCenter
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                NSLog("[Macrodroid Notifications] Authorization error: \(error)")
            } else {
                NSLog("[Macrodroid Notifications] Authorization granted: \(granted)")
            }
        }

        let launcher = LauncherWindowController(
            onLaunch: { [weak self] mode, profile, app in
                self?.openAppWindow(mode: mode, profile: profile, app: app)
            },
            onStop: { [weak self] in
                self?.stopCurrentGameOrEngine()
            },
            onOpenSettings: { [weak self] in
                self?.showSettings(nil)
            }
        )
        launcher.viewModel.onStartEngine = { [weak self] in
            self?.startBackgroundEngine(profile: .playable)
        }
        launcher.viewModel.onStopEngine = { [weak self] in
            self?.stopEmulator()
        }
        launcher.viewModel.onPostTestNotification = { [weak self] title, body in
            guard let self else { return }
            if self.runtimeController == nil || self.runtimeController?.isRunning == false {
                self.startBackgroundEngine(profile: .playable)
            }
            self.runtimeController?.postTestGuestNotification(title: title, body: body)
        }
        launcherWindowController = launcher
        launcher.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Engine launch policy: auto-start in background if policy is .alwaysBackground
        let launchPolicy = EngineLaunchPolicy.load()
        if launchPolicy == .alwaysBackground {
            startBackgroundEngine(profile: .playable)
        } else {
            launcher.viewModel.statusMessage = "Engine Idle (On-Demand Mode)"
            launcher.viewModel.isEngineStarting = false
            launcher.viewModel.isEngineRunning = false
        }

        // Direct package launch from command line (--launch-pkg <pkg>)
        if let idx = CommandLine.arguments.firstIndex(of: "--launch-pkg"),
           idx + 1 < CommandLine.arguments.count {
            let pkg = CommandLine.arguments[idx + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.launchPackageDirectly(pkg)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleIncomingURL(url)
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "macrodroid" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        if components.host == "launch" || components.path.contains("launch") {
            if let pkgItem = components.queryItems?.first(where: { $0.name == "pkg" || $0.name == "package" }),
               let pkg = pkgItem.value, !pkg.isEmpty {
                launchPackageDirectly(pkg)
            }
        }
    }

    private func startBackgroundEngine(profile: TFTMACRuntimeProfile) {
        guard runtimeController == nil || runtimeController?.isRunning == false else { return }
        self.activeProfile = profile
        launcherWindowController?.viewModel.isEngineStarting = true
        launcherWindowController?.viewModel.statusMessage = "Starting background engine…"

        let runtime = TFTMACRuntimeController(
            profile: profile,
            mailbox: mailbox,
            status: { [weak self] text, isError in
                Task { @MainActor in
                    self?.launcherWindowController?.viewModel.statusMessage = text
                    self?.mainWindowController?.emulatorView.setStatus(text, isError: isError)
                    if text.contains("Ready") || text.contains("authorized") || text.contains("booted") || text.contains("GUEST_UNLOCKED") {
                        self?.launcherWindowController?.viewModel.isEngineStarting = false
                        self?.launcherWindowController?.viewModel.isEngineRunning = true
                    }
                }
            },
            gameFrame: { [weak self] window in
                Task { @MainActor in
                    self?.latestGameFrameWindow = window
                    self?.mainWindowController?.emulatorView.setGameFrameWindow(window)
                }
            },
            onNotification: { [weak self] record in
                self?.handleGuestNotification(record)
            }
        )
        runtimeController = runtime
        runtime.start()
    }

    private func openAppWindow(mode: LaunchMode, profile: TFTMACRuntimeProfile, app: PlayApp? = nil) {
        self.activeProfile = profile
        let appName = app?.name ?? (mode == .android ? "Android Home" : "Application")
        let pkg = app?.bundleIdentifier ?? (mode == .android ? "ANDROID" : "TFT")
        self.currentAppName = appName
        self.currentAppPackage = pkg

        setenv("MACRODROID_MODE", pkg, 1)

        let isPortrait = (app?.name.lowercased().contains("phone") == true) || (app?.aspectRatioIndex == 0)

        // 1. Create or show MainWindowController
        if mainWindowController == nil {
            let controller = MainWindowController(
                mailbox: mailbox,
                appName: appName,
                isPortrait: isPortrait
            )
            mainWindowController = controller
            if let latestGameFrameWindow {
                controller.emulatorView.setGameFrameWindow(latestGameFrameWindow)
            }

            controller.emulatorView.onTouchInput = { [weak self] input in
                self?.runtimeController?.sendTouch(input)
            }
            controller.emulatorView.onMouseInput = { [weak self] x, y, buttons in
                self?.runtimeController?.sendMouse(x: x, y: y, buttons: buttons)
            }
            controller.emulatorView.onKeyboardInput = { [weak self] text, key in
                self?.runtimeController?.sendKeyboard(text: text, key: key)
            }
            controller.emulatorView.onPasteInput = { [weak self] text in
                self?.runtimeController?.sendClipboard(text)
            }
            controller.emulatorView.onPresentationSample = { [weak self] sample in
                self?.runtimeController?.recordPresentation(sample)
            }
            controller.emulatorView.onHostPresentationWindow = { [weak self] sample in
                self?.runtimeController?.recordHostPresentation(sample)
            }

            if let window = controller.window {
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor in
                        self.restoreDockAndHideMenuBar()
                        let closeBehavior = EngineCloseBehavior.load()
                        if closeBehavior == .stopEngine {
                            self.stopEmulator()
                        } else {
                            // Keep background engine running! Just return Android guest to home
                            await self.runtimeController?.returnToHome(stopPackage: self.currentAppPackage)
                        }

                        self.mainWindowController = nil
                        self.launcherWindowController?.viewModel.isLaunching = false
                        self.launcherWindowController?.viewModel.isGameRunning = false
                        self.launcherWindowController?.viewModel.selectedApp?.isStarting = false
                        self.launcherWindowController?.window?.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }
        } else {
            mainWindowController?.updateTitle(appName: appName)
        }

        // 2. If background engine is not running, start it
        if runtimeController == nil || runtimeController?.isRunning == false {
            startBackgroundEngine(profile: profile)
        } else {
            runtimeController?.launchPackage(pkg)
        }

        launcherWindowController?.viewModel.isLaunching = false
        launcherWindowController?.viewModel.isGameRunning = true

        // 3. Show game window
        hideDockAndShowMenuBar(appName: appName)
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        if let view = mainWindowController?.emulatorView {
            mainWindowController?.window?.makeFirstResponder(view)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideDockAndShowMenuBar(appName: String) {
        isDockHidden = true
        // Set activation policy to .accessory: removes application icon from Dock
        NSApp.setActivationPolicy(.accessory)

        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }

        guard let statusItem else { return }

        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            if let img = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: "Macrodroid")?.withSymbolConfiguration(config) {
                img.isTemplate = true
                button.image = img
            }
            button.title = " \(appName)"
        }

        updateMenuBarMenu()
    }

    private func updateMenuBarMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "🎮 \(currentAppName) (Running)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let showGameItem = NSMenuItem(title: "Show Game Window", action: #selector(focusGameWindow), keyEquivalent: "")
        showGameItem.target = self
        menu.addItem(showGameItem)

        let toggleDockTitle = isDockHidden ? "Show Dock Icon" : "Hide Dock Icon"
        let toggleDockItem = NSMenuItem(title: toggleDockTitle, action: #selector(toggleDockIcon), keyEquivalent: "")
        toggleDockItem.target = self
        menu.addItem(toggleDockItem)

        let showLauncherItem = NSMenuItem(title: "Show Launcher Window", action: #selector(showLauncher), keyEquivalent: "")
        showLauncherItem.target = self
        menu.addItem(showLauncherItem)

        menu.addItem(NSMenuItem.separator())

        let stopItem = NSMenuItem(title: "Stop Game Session", action: #selector(stopEmulatorMenuAction), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Macrodroid", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func restoreDockAndHideMenuBar() {
        isDockHidden = false
        // Restore standard application Dock icon
        NSApp.setActivationPolicy(.regular)

        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc func focusGameWindow() {
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func toggleDockIcon() {
        if isDockHidden {
            isDockHidden = false
            NSApp.setActivationPolicy(.regular)
        } else {
            isDockHidden = true
            NSApp.setActivationPolicy(.accessory)
        }
        updateMenuBarMenu()
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showLauncher() {
        launcherWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func stopEmulatorMenuAction() {
        stopCurrentGameOrEngine()
    }

    private func stopCurrentGameOrEngine() {
        Task { @MainActor in
            if mainWindowController != nil {
                // If game window is open, close the game window and return Android to home (keep background engine hot)
                await runtimeController?.returnToHome(stopPackage: currentAppPackage)
                mainWindowController?.close()
                mainWindowController = nil
                restoreDockAndHideMenuBar()
                launcherWindowController?.viewModel.isGameRunning = false
                launcherWindowController?.viewModel.isLaunching = false
                launcherWindowController?.viewModel.selectedApp?.isStarting = false
                launcherWindowController?.window?.makeKeyAndOrderFront(nil)
            } else {
                // If no game window is active, stop the background engine
                stopEmulator()
            }
        }
    }

    private func stopEmulator() {
        Task { @MainActor in
            restoreDockAndHideMenuBar()
            await runtimeController?.stop()
            runtimeController = nil
            mainWindowController?.close()
            mainWindowController = nil
            launcherWindowController?.viewModel.isLaunching = false
            launcherWindowController?.viewModel.isGameRunning = false
            launcherWindowController?.viewModel.isEngineRunning = false
            launcherWindowController?.viewModel.isEngineStarting = false
            launcherWindowController?.viewModel.statusMessage = "Background Engine Stopped"
            launcherWindowController?.viewModel.refreshDiscovery()
            launcherWindowController?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func showSettings(_ sender: Any?) {
        let settings = settingsWindowController ?? RuntimeSettingsWindowController(profile: TFTMACRuntimeProfile.load())
        settings.onSave = { [weak self] previous, next in
            self?.runtimeController?.recordSettingsChange(previous: previous, next: next)
        }
        settingsWindowController = settings
        settings.refreshFromSavedProfile()
        settings.showWindow(sender)
        settings.window?.makeKeyAndOrderFront(sender)
    }

    @objc func markMatchEntry(_ sender: Any?) { recordMarker("MATCH_ENTRY") }
    @objc func startCombatBenchmark(_ sender: Any?) {
        runtimeController?.startCombatBenchmark(performanceModeConfirmed: false)
    }
    @objc func markVisibleStutter(_ sender: Any?) { runtimeController?.markVisibleStutter() }
    @objc func endCombatBenchmark(_ sender: Any?) {
        var correctnessPassed = true
        if activeProfile.experimentPreset.isActiveCandidate {
            let alert = NSAlert()
            alert.messageText = "Did Combat Latency A preserve correctness?"
            alert.informativeText = "Reject the run if boot, graphics, input, audio, login, or gameplay correctness regressed. Macrodroid will restore Control for the next launch."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "All Correct — End")
            alert.addButton(withTitle: "Reject: Correctness Problem")
            correctnessPassed = alert.runModal() == .alertFirstButtonReturn
        }
        runtimeController?.endCombatBenchmark(correctnessPassed: correctnessPassed)
    }
    @objc func markMatchEnd(_ sender: Any?) { recordMarker("MATCH_END") }

    @objc func revealCaptureFolder(_ sender: Any?) {
        let captures = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Macrodroid/Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        NSWorkspace.shared.open(captures)
    }

    private func recordMarker(_ marker: String) {
        runtimeController?.recordMarker(marker)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        sender.windows.allSatisfy { !$0.isVisible }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationInProgress { return .terminateLater }
        guard let runtimeController else { return .terminateNow }
        terminationInProgress = true
        Task { @MainActor in
            await runtimeController.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: - Notification Forwarding & Interaction

    private func handleGuestNotification(_ record: GuestNotificationRecord) {
        guard NotificationPreferences.isMirroringEnabled() else { return }
        if NotificationPreferences.isSystemFilterEnabled() && record.isSystemPackage {
            return
        }

        let content = UNMutableNotificationContent()
        let fallbackAppName = record.packageName.components(separatedBy: ".").last?.capitalized ?? "Android App"
        let resolvedAppTitle = record.appName.isEmpty ? fallbackAppName : record.appName

        content.title = record.title.isEmpty ? resolvedAppTitle : record.title
        if !record.title.isEmpty && !resolvedAppTitle.isEmpty && resolvedAppTitle != record.title {
            content.subtitle = resolvedAppTitle
        }
        content.body = record.text.isEmpty ? "New notification" : record.text
        content.sound = .default
        content.userInfo = [
            "packageName": record.packageName,
            "notificationKey": record.key
        ]

        let request = UNNotificationRequest(
            identifier: record.key,
            content: content,
            trigger: nil // Deliver immediately to macOS Notification Center
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[Macrodroid Notifications] Failed to schedule notification: \(error)")
            }
        }
    }

    private func handleNotificationClick(packageName: String) {
        launchPackageDirectly(packageName)
    }

    private func launchPackageDirectly(_ packageName: String) {
        guard !packageName.isEmpty else { return }
        if mainWindowController != nil && currentAppPackage == packageName {
            focusGameWindow()
            return
        }
        let matchedApp = launcherWindowController?.viewModel.apps.first(where: { $0.bundleIdentifier == packageName })
        let targetApp = matchedApp ?? PlayApp(
            id: UUID().uuidString,
            name: packageName.components(separatedBy: ".").last?.capitalized ?? packageName,
            bundleIdentifier: packageName,
            version: "1.0",
            url: URL(fileURLWithPath: "/tmp")
        )
        openAppWindow(mode: .tft, profile: activeProfile, app: targetApp)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let pkg = response.notification.request.content.userInfo["packageName"] as? String ?? ""
        Task { @MainActor in
            self.handleNotificationClick(packageName: pkg)
        }
        completionHandler()
    }
}

// MARK: - AppShortcutManager (WSA-Style Native macOS Shortcuts & Spotlight Integration)

@MainActor
enum AppShortcutManager {
    static var shortcutsDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Applications/Macrodroid Apps", isDirectory: true)
    }

    @discardableResult
    static func createShortcut(for app: PlayApp) -> URL? {
        let dir = shortcutsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let safeName = app.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let appBundleURL = dir.appendingPathComponent("\(safeName).app", isDirectory: true)

        let contentsURL = appBundleURL.appendingPathComponent("Contents", isDirectory: true)
        let macosURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        try? FileManager.default.createDirectory(at: macosURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let sanitizedPkg = app.bundleIdentifier
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let infoPlistContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AppLauncher</string>
    <key>CFBundleIdentifier</key>
    <string>com.lamppkk.macrodroid.app.\(sanitizedPkg)</string>
    <key>CFBundleName</key>
    <string>\(safeName)</string>
    <key>CFBundleDisplayName</key>
    <string>\(safeName)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>\(app.version)</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
"""
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        try? infoPlistContent.write(to: infoPlistURL, atomically: true, encoding: .utf8)

        let launcherScript = """
#!/bin/sh
# Open Android app through Macrodroid URL scheme or CLI
exec open "macrodroid://launch?pkg=\(app.bundleIdentifier)" || open -b "com.lamppkk.macrodroid" --args --launch-pkg "\(app.bundleIdentifier)"
"""
        let launcherURL = macosURL.appendingPathComponent("AppLauncher")
        try? launcherScript.write(to: launcherURL, atomically: true, encoding: .utf8)

        var attrs = (try? FileManager.default.attributesOfItem(atPath: launcherURL.path)) ?? [:]
        attrs[.posixPermissions] = 0o755
        try? FileManager.default.setAttributes(attrs, ofItemAtPath: launcherURL.path)

        if let icon = app.customIcon {
            NSWorkspace.shared.setIcon(icon, forFile: appBundleURL.path, options: [])
        } else {
            let iconURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Macrodroid/Icons/\(app.bundleIdentifier).png")
            if let iconImg = NSImage(contentsOf: iconURL) {
                NSWorkspace.shared.setIcon(iconImg, forFile: appBundleURL.path, options: [])
            }
        }

        return appBundleURL
    }

    static func revealShortcutsInFinder() {
        let dir = shortcutsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    static func createShortcutsForInstalledApps(_ apps: [PlayApp]) {
        for app in apps {
            createShortcut(for: app)
        }
    }
}
