import AppKit

@MainActor
final class MainWindowController: NSWindowController {
    let emulatorView: EmbeddedEmulatorView

    init(mailbox: LatestFrameMailbox) {
        emulatorView = EmbeddedEmulatorView(
            frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
            mailbox: mailbox
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1920, height: 1080),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "TFTMAC"
        window.titleVisibility = .visible
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.minSize = NSSize(width: 960, height: 540)
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
