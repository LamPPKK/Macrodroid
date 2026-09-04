import AppKit

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply official emerald Macrodroid icon to running application
        if let path = Bundle.main.path(forResource: "Macrodroid-Logo", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            NSApp.applicationIconImage = img
        } else if let path = Bundle.main.path(forResource: "Macrodroid-1024", ofType: "png"),
                  let img = NSImage(contentsOfFile: path) {
            NSApp.applicationIconImage = img
        }

        let launcher = LauncherWindowController(
            onLaunch: { [weak self] mode, profile, app in
                self?.startEmulator(mode: mode, profile: profile, app: app)
            },
            onStop: { [weak self] in
                self?.stopEmulator()
            },
            onOpenSettings: { [weak self] in
                self?.showSettings(nil)
            }
        )
        launcherWindowController = launcher
        launcher.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startEmulator(mode: LaunchMode, profile: TFTMACRuntimeProfile, app: PlayApp? = nil) {
        self.activeProfile = profile
        let appName = app?.name ?? (mode == .android ? "Android Home" : "Application")
        self.currentAppName = appName

        if let pkg = app?.bundleIdentifier {
            setenv("MACRODROID_MODE", pkg, 1)
        } else if mode == .android {
            setenv("MACRODROID_MODE", "ANDROID", 1)
        } else {
            setenv("MACRODROID_MODE", "APPLICATION", 1)
        }

        // Determine orientation
        let isPortrait = (app?.name.lowercased().contains("phone") == true) || (app?.aspectRatioIndex == 0)

        let controller = MainWindowController(
            mailbox: mailbox,
            appName: appName,
            isPortrait: isPortrait
        )
        mainWindowController = controller

        let runtime = TFTMACRuntimeController(
            profile: profile,
            mailbox: mailbox,
            status: { [weak controller] text, isError in
                controller?.emulatorView.setStatus(text, isError: isError)
            },
            gameFrame: { [weak controller] window in
                controller?.emulatorView.setGameFrameWindow(window)
            }
        )
        runtimeController = runtime
        controller.emulatorView.onTouchInput = { [weak runtime] input in
            runtime?.sendTouch(input)
        }
        controller.emulatorView.onMouseInput = { [weak runtime] x, y, buttons in
            runtime?.sendMouse(x: x, y: y, buttons: buttons)
        }
        controller.emulatorView.onKeyboardInput = { [weak runtime] text, key in
            runtime?.sendKeyboard(text: text, key: key)
        }
        controller.emulatorView.onPresentationSample = { [weak runtime] sample in
            runtime?.recordPresentation(sample)
        }
        controller.emulatorView.onHostPresentationWindow = { [weak runtime] sample in
            runtime?.recordHostPresentation(sample)
        }

        // When game window closes, stop runtime, restore dock icon, and restore launcher
        if let window = controller.window {
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.restoreDockAndHideMenuBar()
                    await self.runtimeController?.stop()
                    self.runtimeController = nil
                    self.mainWindowController = nil
                    self.launcherWindowController?.viewModel.isLaunching = false
                    self.launcherWindowController?.viewModel.isGameRunning = false
                    self.launcherWindowController?.viewModel.refreshDiscovery()
                    self.launcherWindowController?.window?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }

        launcherWindowController?.viewModel.isLaunching = false
        launcherWindowController?.viewModel.isGameRunning = true

        // 1. Hide icon on macOS Dock
        hideDockAndShowMenuBar(appName: appName)

        // 2. Show game window
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.window?.makeFirstResponder(controller.emulatorView)
        NSApp.activate(ignoringOtherApps: true)

        runtime.start()
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
        stopEmulator()
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
}
