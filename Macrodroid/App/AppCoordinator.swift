import AppKit
import UserNotifications

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let mailbox = LatestFrameMailbox()
    private var launcherWindowController: LauncherWindowController?
    private var mainWindowController: MainWindowController?
    private var runtimeController: MacrodroidRuntimeController?
    private var settingsWindowController: RuntimeSettingsWindowController?
    private var activeProfile: MacrodroidRuntimeProfile = .playable
    private var terminationInProgress = false

    // Menu Bar Extra & Dock Hiding
    private var statusItem: NSStatusItem?
    private var isDockHidden: Bool = false
    private var currentAppName: String = ""
    private var currentAppPackage: String = ""
    private var latestGameFrameWindow: GameFrameTelemetryWindow?
    private(set) var activeAppWindows: [String: MainWindowController] = [:]

    // Smart Idle Suspend / Power Efficiency
    private var idleSuspendTask: Task<Void, Never>?

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

        setupPersistentMenuBar()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                handleIncomingFile(url)
            } else {
                handleIncomingURL(url)
            }
        }
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            let url = URL(fileURLWithPath: filename)
            handleIncomingFile(url)
        }
    }

    private func handleIncomingFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "apk" || ext == "xapk" || ext == "apks" {
            launcherWindowController?.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            launcherWindowController?.viewModel.installAPK(at: url)
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

    private func startBackgroundEngine(profile: MacrodroidRuntimeProfile) {
        guard runtimeController == nil || runtimeController?.isRunning == false else { return }
        self.activeProfile = profile
        launcherWindowController?.viewModel.isEngineStarting = true
        launcherWindowController?.viewModel.statusMessage = "Starting background engine…"

        let runtime = MacrodroidRuntimeController(
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

    private func openAppWindow(mode: LaunchMode, profile: MacrodroidRuntimeProfile, app: PlayApp? = nil) {
        cancelIdleSuspendAndResume()
        self.activeProfile = profile
        let appName = app?.name ?? (mode == .android ? "Android Home" : "Application")
        let pkg = app?.bundleIdentifier ?? (mode == .android ? "ANDROID" : "TFT")
        self.currentAppName = appName
        self.currentAppPackage = pkg

        setenv("MACRODROID_MODE", pkg, 1)

        let isPortrait = (app?.name.lowercased().contains("phone") == true) || (app?.aspectRatioIndex == 0)

        // 1. Create or bring-to-front the per-package MainWindowController.
        //    Each unique package gets its own independent window; re-opening
        //    the same package just focuses the existing window.
        if let existing = activeAppWindows[pkg] {
            // Package already has a live window — just focus it.
            mainWindowController = existing
            existing.updateTitle(appName: appName, packageName: pkg)
        } else {
            // New package: create a fresh independent window.
            let controller = MainWindowController(
                mailbox: mailbox,
                appName: appName,
                packageName: pkg,
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
            controller.emulatorView.onFilesDropped = { [weak self] urls in
                self?.handleDroppedFiles(urls)
            }
            controller.emulatorView.onScrollGesture = { [weak self] x, y, dx, dy in
                self?.runtimeController?.sendScrollGesture(x: x, y: y, deltaX: dx, deltaY: dy)
            }
            controller.emulatorView.onPinchGesture = { [weak self] x, y, scale in
                self?.runtimeController?.sendPinchGesture(x: x, y: y, scale: scale)
            }
            controller.onFreeformToggleRequested = { [weak self] in
                guard let self else { return }
                self.runtimeController?.toggleFreeformWindowing(enable: controller.isFreeformActive)
            }
            controller.onOpenSharedFolderRequested = { [weak self] in
                self?.runtimeController?.syncSharedFolder { results in
                    NSLog("[SharedFolderSync] Synced \(results.count) files")
                }
            }
            controller.onTaskSwitcherRequested = { [weak self] in
                self?.presentTaskSwitcher(for: controller)
            }

            if let window = controller.window {
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor in
                        self.activeAppWindows.removeValue(forKey: pkg)
                        let closeBehavior = EngineCloseBehavior.load()
                        if closeBehavior == .stopEngine && self.activeAppWindows.isEmpty {
                            self.restoreDockAndHideMenuBar()
                            self.stopEmulator()
                        } else {
                            await self.runtimeController?.returnToHome(stopPackage: pkg)
                            if self.activeAppWindows.isEmpty {
                                self.restoreDockAndHideMenuBar()
                                self.scheduleIdleSuspendIfNeeded()
                            }
                        }

                        if self.mainWindowController === controller {
                            self.mainWindowController = self.activeAppWindows.values.first
                        }
                        if self.activeAppWindows.isEmpty {
                            self.launcherWindowController?.viewModel.isLaunching = false
                            self.launcherWindowController?.viewModel.isGameRunning = false
                            self.launcherWindowController?.viewModel.selectedApp?.isStarting = false
                            self.launcherWindowController?.window?.makeKeyAndOrderFront(nil)
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
                }
            }
            activeAppWindows[pkg] = controller
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

    private func setupPersistentMenuBar() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        guard let statusItem else { return }
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            if let img = NSImage(
                systemSymbolName: "play.circle.fill",
                accessibilityDescription: "Macrodroid"
            )?.withSymbolConfiguration(config) {
                img.isTemplate = true
                button.image = img
            }
            button.title = currentAppName.isEmpty ? " Macrodroid" : " \(currentAppName)"
        }
        updateMenuBarMenu()
    }

    private func hideDockAndShowMenuBar(appName: String) {
        isDockHidden = true
        NSApp.setActivationPolicy(.accessory)
        setupPersistentMenuBar()
    }

    private func updateMenuBarMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        let isRunning = runtimeController?.isRunning == true
        let isSuspended = (launcherWindowController?.viewModel.statusMessage.contains("Standby") == true)
        let statusTitle: String
        if isSuspended {
            statusTitle = "🟡 Engine: Idle Standby (0% CPU)"
        } else if isRunning {
            statusTitle = "🟢 Engine: Running (\(activeProfile.vCPU) vCPU, \(activeProfile.ramMiB) MB)"
        } else {
            statusTitle = "⚪ Engine: Stopped"
        }
        let statusItemHeader = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItemHeader.isEnabled = false
        menu.addItem(statusItemHeader)

        if !currentAppName.isEmpty && mainWindowController != nil {
            let gameItem = NSMenuItem(
                title: "🎮 Active: \(currentAppName)",
                action: #selector(focusGameWindow),
                keyEquivalent: ""
            )
            gameItem.target = self
            menu.addItem(gameItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Quick Launch Submenu
        let quickLaunchMenu = NSMenu()
        let apps = launcherWindowController?.viewModel.apps ?? []
        if !apps.isEmpty {
            for app in apps {
                let item = NSMenuItem(title: app.name, action: #selector(quickLaunchAppMenuItem(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = app.bundleIdentifier
                quickLaunchMenu.addItem(item)
            }
        } else {
            let emptyItem = NSMenuItem(title: "No installed apps found", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            quickLaunchMenu.addItem(emptyItem)
        }
        let quickLaunchParent = NSMenuItem(title: "Quick Launch App…", action: nil, keyEquivalent: "")
        quickLaunchParent.submenu = quickLaunchMenu
        menu.addItem(quickLaunchParent)

        let auroraItem = NSMenuItem(
            title: "Open Aurora Store",
            action: #selector(openAuroraStoreMenuAction),
            keyEquivalent: ""
        )
        auroraItem.target = self
        menu.addItem(auroraItem)

        let sharedFolderItem = NSMenuItem(
            title: "Open Shared Folder (Mac ⇋ Android)",
            action: #selector(openSharedFolderMenuAction),
            keyEquivalent: ""
        )
        sharedFolderItem.target = self
        menu.addItem(sharedFolderItem)

        let syncSharedItem = NSMenuItem(
            title: "Sync Shared Files Now",
            action: #selector(syncSharedFilesMenuAction),
            keyEquivalent: ""
        )
        syncSharedItem.target = self
        menu.addItem(syncSharedItem)

        menu.addItem(NSMenuItem.separator())

        if mainWindowController != nil {
            let showGameItem = NSMenuItem(
                title: "Focus Game Window",
                action: #selector(focusGameWindow),
                keyEquivalent: ""
            )
            showGameItem.target = self
            menu.addItem(showGameItem)
        }

        let showLauncherItem = NSMenuItem(
            title: "Show Launcher Window",
            action: #selector(showLauncher),
            keyEquivalent: ""
        )
        showLauncherItem.target = self
        menu.addItem(showLauncherItem)

        let toggleDockTitle = isDockHidden ? "Show Dock Icon" : "Hide Dock Icon"
        let toggleDockItem = NSMenuItem(
            title: toggleDockTitle,
            action: #selector(toggleDockIcon),
            keyEquivalent: ""
        )
        toggleDockItem.target = self
        menu.addItem(toggleDockItem)

        if isRunning {
            let sleepResumeTitle = isSuspended ? "Resume Engine" : "Sleep Engine (Save 100% Battery)"
            let sleepResumeItem = NSMenuItem(
                title: sleepResumeTitle,
                action: #selector(toggleSleepResumeMenuAction),
                keyEquivalent: ""
            )
            sleepResumeItem.target = self
            menu.addItem(sleepResumeItem)
        }

        menu.addItem(NSMenuItem.separator())

        if isRunning {
            let stopItem = NSMenuItem(
                title: "Stop Background Engine",
                action: #selector(stopEmulatorMenuAction),
                keyEquivalent: ""
            )
            stopItem.target = self
            menu.addItem(stopItem)
        } else {
            let startItem = NSMenuItem(
                title: "Start Background Engine",
                action: #selector(startEngineMenuAction),
                keyEquivalent: ""
            )
            startItem.target = self
            menu.addItem(startItem)
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Macrodroid",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func restoreDockAndHideMenuBar() {
        isDockHidden = false
        NSApp.setActivationPolicy(.regular)
        currentAppName = ""
        currentAppPackage = ""
        setupPersistentMenuBar()
    }

    @objc func quickLaunchAppMenuItem(_ sender: NSMenuItem) {
        if let pkg = sender.representedObject as? String {
            launchPackageDirectly(pkg)
        }
    }

    @objc func openAuroraStoreMenuAction() {
        launchPackageDirectly(GoogleEcosystemConfig.auroraStorePackage)
    }

    @objc func openSharedFolderMenuAction() {
        SharedFolderConfig.ensureDirectoriesExist()
        NSWorkspace.shared.open(SharedFolderConfig.defaultSharedDirectory)
    }

    @objc func syncSharedFilesMenuAction() {
        runtimeController?.syncSharedFolder { [weak self] results in
            Task { @MainActor in
                self?.mainWindowController?.showToast(
                    icon: "folder.fill",
                    message: "Synced \(results.count) file(s) with Android"
                )
            }
        }
    }

    @objc func toggleSleepResumeMenuAction() {
        if launcherWindowController?.viewModel.statusMessage.contains("Standby") == true {
            cancelIdleSuspendAndResume()
        } else {
            runtimeController?.suspendVM()
        }
        updateMenuBarMenu()
    }

    @objc func startEngineMenuAction() {
        startBackgroundEngine(profile: .playable)
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

    private func presentTaskSwitcher(for controller: MainWindowController) {
        runtimeController?.fetchRunningTasks { [weak self] tasks in
            Task { @MainActor in
                guard let self else { return }
                if tasks.isEmpty {
                    controller.showToast(icon: "rectangle.stack.fill", message: "Task Switcher: No other background tasks")
                    return
                }

                let menu = NSMenu(title: "Running Tasks")
                let headerItem = NSMenuItem(title: "Android Tasks (\(tasks.count) active)", action: nil, keyEquivalent: "")
                headerItem.isEnabled = false
                menu.addItem(headerItem)
                menu.addItem(NSMenuItem.separator())

                for task in tasks {
                    let itemTitle = "\(task.label) (\(task.package))"
                    let item = NSMenuItem(title: itemTitle, action: #selector(self.switchTaskMenuItem(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = task.package
                    if let icon = AppIconExtractor.cachedIcon(for: task.package) {
                        icon.size = NSSize(width: 16, height: 16)
                        item.image = icon
                    }
                    menu.addItem(item)
                }

                menu.addItem(NSMenuItem.separator())
                let freeformItem = NSMenuItem(
                    title: controller.isFreeformActive ? "Freeform Windowing: Active" : "Freeform Windowing: Off",
                    action: #selector(self.toggleFreeformFromMenu),
                    keyEquivalent: ""
                )
                freeformItem.target = self
                menu.addItem(freeformItem)

                if let window = controller.window {
                    let location = NSPoint(x: window.frame.width - 200, y: window.frame.height - 40)
                    menu.popUp(positioning: nil, at: location, in: controller.emulatorView)
                }
            }
        }
    }

    @objc func switchTaskMenuItem(_ sender: NSMenuItem) {
        if let pkg = sender.representedObject as? String {
            runtimeController?.launchPackage(pkg)
            let matchedApp = launcherWindowController?.viewModel.apps.first(where: { $0.bundleIdentifier == pkg })
            let name = matchedApp?.name ?? pkg
            mainWindowController?.updateTitle(appName: name)
            mainWindowController?.showToast(icon: "rectangle.stack.fill", message: "Switched to \(name)")
        }
    }

    @objc func toggleFreeformFromMenu() {
        mainWindowController?.toggleFreeform()
    }

    private func stopCurrentGameOrEngine() {
        Task { @MainActor in
            if mainWindowController != nil {
                // If game window is open, close the game window and return Android to home (keep background engine hot)
                await runtimeController?.returnToHome(stopPackage: currentAppPackage)
                scheduleIdleSuspendIfNeeded()
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
        idleSuspendTask?.cancel()
        idleSuspendTask = nil
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

    private func scheduleIdleSuspendIfNeeded() {
        idleSuspendTask?.cancel()
        let timeout = IdleSuspendPreferences.loadTimeout()
        guard let seconds = timeout.seconds else { return }
        if seconds == 0 {
            runtimeController?.suspendVM()
            return
        }
        idleSuspendTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.runtimeController?.suspendVM()
            } catch { }
        }
    }

    private func cancelIdleSuspendAndResume() {
        idleSuspendTask?.cancel()
        idleSuspendTask = nil
        runtimeController?.resumeVM()
    }

    @objc func showSettings(_ sender: Any?) {
        let settings = settingsWindowController ?? RuntimeSettingsWindowController(profile: MacrodroidRuntimeProfile.load())
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
        if runtimeController?.isRunning == true || statusItem != nil {
            return false
        }
        return sender.windows.allSatisfy { !$0.isVisible }
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

        // Attach the real app icon (PNG cached by AppIconExtractor) so macOS
        // Notification Center shows the Android app's icon in the banner thumbnail.
        let iconFileURL = AppIconExtractor.iconURL(for: record.packageName)
        if AppIconExtractor.hasCachedIcon(for: record.packageName),
           let attachment = try? UNNotificationAttachment(
               identifier: "app-icon-\(record.packageName)",
               url: iconFileURL,
               options: [UNNotificationAttachmentOptionsThumbnailClippingRectKey: CGRect.zero as AnyObject]
           ) {
            content.attachments = [attachment]
        }

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
        cancelIdleSuspendAndResume()
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

    // MARK: - Drag & Drop File Sharing

    private func handleDroppedFiles(_ urls: [URL]) {
        guard let runtimeController else { return }
        runtimeController.importDroppedFiles(urls: urls) { results in
            Task { @MainActor in
                let successfulCount = results.filter { $0.success }.count
                let apks = results.filter { $0.isAPK }
                let regularFiles = results.filter { !$0.isAPK }

                let content = UNMutableNotificationContent()
                content.title = "File Transfer Complete"
                if !apks.isEmpty && regularFiles.isEmpty {
                    let apkNames = apks.map { $0.filename }.joined(separator: ", ")
                    content.body = apks.allSatisfy { $0.success }
                        ? "Installed: \(apkNames)"
                        : "Failed to install some APKs"
                } else if apks.isEmpty && !regularFiles.isEmpty {
                    content.body = regularFiles.allSatisfy { $0.success }
                        ? "Saved \(regularFiles.count) file(s) to Android Downloads"
                        : "Some files failed to transfer"
                } else {
                    content.body = "\(successfulCount) of \(results.count) items processed successfully"
                }
                content.sound = .default

                let req = UNNotificationRequest(
                    identifier: "transfer_\(Int(Date().timeIntervalSince1970))",
                    content: content,
                    trigger: nil
                )
                try? await UNUserNotificationCenter.current().add(req)
            }
        }
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

// MARK: - AppShortcutManager (PlayApp Helpers)

extension AppShortcutManager {
    @discardableResult
    static func createShortcut(for app: PlayApp) -> URL? {
        createShortcut(
            name: app.name,
            bundleIdentifier: app.bundleIdentifier,
            version: app.version,
            customIcon: app.customIcon
        )
    }

    static func createShortcutsForInstalledApps(_ apps: [PlayApp]) {
        for app in apps {
            createShortcut(for: app)
        }
    }
}
