import AppKit

@MainActor
final class MainWindowController: NSWindowController {
    let emulatorView: EmbeddedEmulatorView
    let appName: String
    private let fpsLabel = NSTextField(labelWithString: "— fps")
    private let statusDot = NSView()
    private var fpsAccessory: NSTitlebarAccessoryViewController?

    init(
        mailbox: LatestFrameMailbox,
        appName: String = "Android Application",
        contentSize: NSSize = NSSize(width: 1280, height: 720),
        isPortrait: Bool = false
    ) {
        self.appName = appName
        let effectiveSize = isPortrait ? NSSize(width: 450, height: 800) : contentSize

        emulatorView = EmbeddedEmulatorView(
            frame: NSRect(origin: .zero, size: effectiveSize),
            mailbox: mailbox
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: effectiveSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Macrodroid: \(appName)"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false

        if isPortrait {
            window.contentAspectRatio = NSSize(width: 9, height: 16)
            window.minSize = NSSize(width: 360, height: 640)
        } else {
            window.contentAspectRatio = NSSize(width: 16, height: 9)
            window.minSize = NSSize(width: 800, height: 450)
        }

        window.collectionBehavior.insert(.fullScreenPrimary)
        window.center()
        window.contentView = emulatorView

        // Modern Sleek Titlebar Glass FPS Meter
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 88, height: 26))

        let pill = NSVisualEffectView(frame: NSRect(x: 4, y: 3, width: 78, height: 20))
        pill.material = .hudWindow
        pill.blendingMode = .withinWindow
        pill.state = .active
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 10
        pill.layer?.masksToBounds = true
        pill.layer?.borderWidth = 0.5
        pill.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        // Status Dot (Emerald Pulse)
        statusDot.frame = NSRect(x: 8, y: 7, width: 6, height: 6)
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 3
        statusDot.layer?.backgroundColor = NSColor(calibratedRed: 0.0, green: 0.88, blue: 0.38, alpha: 0.9).cgColor
        pill.addSubview(statusDot)

        // Framerate Label
        fpsLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        fpsLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        fpsLabel.alignment = .left
        fpsLabel.frame = NSRect(x: 18, y: 0, width: 56, height: 20)

        pill.addSubview(fpsLabel)
        container.addSubview(pill)
        accessory.view = container

        window.addTitlebarAccessoryViewController(accessory)
        self.fpsAccessory = accessory

        super.init(window: window)
        shouldCascadeWindows = false

        emulatorView.onFPSChanged = { [weak self] fps in
            guard let self else { return }
            let formatted = fps > 0.5 ? String(format: "%.0f fps", fps) : "— fps"
            self.fpsLabel.stringValue = formatted

            if fps >= 55 {
                self.statusDot.layer?.backgroundColor = NSColor(calibratedRed: 0.0, green: 0.88, blue: 0.38, alpha: 0.95).cgColor
                self.fpsLabel.textColor = NSColor.white.withAlphaComponent(0.95)
            } else if fps >= 30 {
                self.statusDot.layer?.backgroundColor = NSColor.systemYellow.cgColor
                self.fpsLabel.textColor = NSColor.systemYellow
            } else if fps > 0 {
                self.statusDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
                self.fpsLabel.textColor = NSColor.systemOrange
            } else {
                self.statusDot.layer?.backgroundColor = NSColor.systemGray.cgColor
                self.fpsLabel.textColor = NSColor.white.withAlphaComponent(0.5)
            }
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    func updateTitle(appName: String) {
        window?.title = "Macrodroid: \(appName)"
    }

    func enterNativeFullscreen() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(nil)
    }
}
