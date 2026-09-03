import AppKit

@MainActor
final class MainWindowController: NSWindowController {
    let emulatorView: EmbeddedEmulatorView

    init(mailbox: LatestFrameMailbox) {
        emulatorView = EmbeddedEmulatorView(
            frame: NSRect(x: 0, y: 0, width: 1280, height: 720),
            mailbox: mailbox
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Macrodroid"
        window.titleVisibility = .visible
        window.contentAspectRatio = NSSize(width: 16, height: 9)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.minSize = NSSize(width: 800, height: 450)
        window.center()
        window.contentView = emulatorView
        super.init(window: window)
        shouldCascadeWindows = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    func enterNativeFullscreen() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(nil)
    }
}
