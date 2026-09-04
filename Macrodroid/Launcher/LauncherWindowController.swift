import AppKit
import SwiftUI

@MainActor
final class LauncherWindowController: NSWindowController {
    let viewModel: LauncherViewModel

    init(
        onLaunch: @escaping (LaunchMode, TFTMACRuntimeProfile, PlayApp?) -> Void,
        onStop: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        let model = LauncherViewModel()
        self.viewModel = model

        let contentView = MacrodroidLauncherView(viewModel: model)
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 880, height: 560)
        window.title = "Macrodroid"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.contentViewController = hostingController
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 13 / 255.0, green: 17 / 255.0, blue: 21 / 255.0, alpha: 1.0)
        window.center()
        super.init(window: window)
        shouldCascadeWindows = false

        model.onLaunch = { mode, profile, app in
            onLaunch(mode, profile, app)
        }
        model.onStop = {
            onStop()
        }
        model.onOpenSettings = {
            onOpenSettings()
        }
    }

    required init?(coder: NSCoder) {
        nil
    }
}
