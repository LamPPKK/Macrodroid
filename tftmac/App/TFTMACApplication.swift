import AppKit

@main
enum TFTMACApplication {
    @MainActor private static var coordinator: AppCoordinator?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let coordinator = AppCoordinator()
        Self.coordinator = coordinator
        application.delegate = coordinator
        application.setActivationPolicy(.regular)
        installMainMenu(on: application, coordinator: coordinator)
        application.run()
    }

    @MainActor
    private static func installMainMenu(on application: NSApplication, coordinator: AppCoordinator) {
        let mainMenu = NSMenu(title: "TFTMAC")

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "TFTMAC")
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About TFTMAC", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let settings = appMenu.addItem(withTitle: "Performance Lab…", action: #selector(AppCoordinator.showSettings(_:)), keyEquivalent: ",")
        settings.target = coordinator
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(withTitle: "Quit TFTMAC", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = application
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        mainMenu.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        let fullscreen = viewMenu.addItem(
            withTitle: "Toggle Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullscreen.keyEquivalentModifierMask = [.command, .control]
        mainMenu.addItem(viewItem)

        let performanceItem = NSMenuItem()
        let performanceMenu = NSMenu(title: "Telemetry")
        performanceItem.submenu = performanceMenu
        let automaticLogger = NSMenuItem(
            title: "Graphics Logger: Automatic While TFT Runs",
            action: nil,
            keyEquivalent: ""
        )
        automaticLogger.state = .on
        automaticLogger.isEnabled = false
        performanceMenu.addItem(automaticLogger)
        performanceMenu.addItem(.separator())
        addTelemetryItem("Mark Match Entry", action: #selector(AppCoordinator.markMatchEntry(_:)), key: "1", to: performanceMenu, coordinator: coordinator)
        addTelemetryItem("Start Controlled A/B Window (Optional)", action: #selector(AppCoordinator.startCombatBenchmark(_:)), key: "2", to: performanceMenu, coordinator: coordinator)
        addTelemetryItem("Mark Visible Stutter", action: #selector(AppCoordinator.markVisibleStutter(_:)), key: "3", to: performanceMenu, coordinator: coordinator)
        addTelemetryItem("End Controlled A/B Window (Optional)", action: #selector(AppCoordinator.endCombatBenchmark(_:)), key: "4", to: performanceMenu, coordinator: coordinator)
        addTelemetryItem("Mark Match End", action: #selector(AppCoordinator.markMatchEnd(_:)), key: "5", to: performanceMenu, coordinator: coordinator)
        performanceMenu.addItem(.separator())
        let reveal = performanceMenu.addItem(withTitle: "Reveal Local Capture Folder", action: #selector(AppCoordinator.revealCaptureFolder(_:)), keyEquivalent: "l")
        reveal.keyEquivalentModifierMask = [.command, .shift]
        reveal.target = coordinator
        mainMenu.addItem(performanceItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        mainMenu.addItem(windowItem)

        application.mainMenu = mainMenu
    }

    @MainActor
    private static func addTelemetryItem(
        _ title: String,
        action: Selector,
        key: String,
        to menu: NSMenu,
        coordinator: AppCoordinator
    ) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.command, .shift]
        item.target = coordinator
    }
}
