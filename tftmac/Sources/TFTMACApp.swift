import AppKit

@MainActor
final class TFTMACAppDelegate: NSObject, NSApplicationDelegate {
    private let bridge = TFTMACRuntimeBridge()
    private lazy var coordinator = TFTMACWindowCoordinator(bridge: bridge)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        coordinator.installWindows()
        bridge.onEmulatorReady = { [weak coordinator] pid in
            coordinator?.attachEmulator(pid: pid)
        }
        bridge.onRuntimeStopped = { [weak coordinator] in
            coordinator?.detachEmulator()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.bridge.start()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        bridge.stopSynchronouslyForTermination()
        return .terminateNow
    }
}

@main
struct TFTMACMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = TFTMACAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
