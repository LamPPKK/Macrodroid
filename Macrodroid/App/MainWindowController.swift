import AppKit

@MainActor
final class HUDToastView: NSVisualEffectView {
    private let iconImageView = NSImageView()
    private let messageLabel = NSTextField(labelWithString: "")
    private var dismissWorkItem: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor

        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconImageView)

        messageLabel.font = .systemFont(ofSize: 12, weight: .medium)
        messageLabel.textColor = NSColor.white.withAlphaComponent(0.95)
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 16),
            iconImageView.heightAnchor.constraint(equalToConstant: 16),

            messageLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 8),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func present(icon: String?, message: String, in parentView: NSView) {
        dismissWorkItem?.cancel()

        if let icon {
            if let sysImg = NSImage(systemSymbolName: icon, accessibilityDescription: message) {
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                iconImageView.image = sysImg.withSymbolConfiguration(config)
                iconImageView.contentTintColor = NSColor(calibratedRed: 0.0, green: 0.88, blue: 0.38, alpha: 0.95)
            } else {
                iconImageView.image = nil
            }
        } else {
            iconImageView.image = nil
        }
        messageLabel.stringValue = message

        let targetWidth = min(parentView.bounds.width - 40, max(180, CGFloat(message.count) * 7.5 + 54))
        let targetHeight: CGFloat = 28
        let targetX = (parentView.bounds.width - targetWidth) / 2
        let targetY = parentView.bounds.height - targetHeight - 16

        frame = NSRect(x: targetX, y: targetY + 10, width: targetWidth, height: targetHeight)
        alphaValue = 0.0

        if superview == nil {
            parentView.addSubview(self)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
            self.animator().frame = NSRect(x: targetX, y: targetY, width: targetWidth, height: targetHeight)
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().alphaValue = 0.0
            }, completionHandler: {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.alphaValue <= 0.05 {
                        self.removeFromSuperview()
                    }
                }
            })
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: workItem)
    }
}

@MainActor
final class MainWindowController: NSWindowController {
    let emulatorView: EmbeddedEmulatorView
    let appName: String
    private(set) var isPortrait: Bool
    private(set) var isFreeformActive: Bool = false
    var onFreeformToggleRequested: (() -> Void)?
    var onOpenSharedFolderRequested: (() -> Void)?
    var onIMEToggled: ((Bool) -> Void)?
    var onTaskSwitcherRequested: (() -> Void)?
    private let fpsLabel = NSTextField(labelWithString: "— fps")
    private let statusDot = NSView()
    private let toastView = HUDToastView()
    private var toolbarAccessory: NSTitlebarAccessoryViewController?

    init(
        mailbox: LatestFrameMailbox,
        appName: String = "Android Application",
        packageName: String? = nil,
        contentSize: NSSize = NSSize(width: 1280, height: 720),
        isPortrait: Bool = false
    ) {
        self.appName = appName
        self.isPortrait = isPortrait
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

        super.init(window: window)
        shouldCascadeWindows = false

        setupTitlebarAccessory(window: window)
        setupEmulatorCallbacks()

        if let packageName {
            emulatorView.configureForPackage(packageName, appName: appName)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func makeActionButton(
        symbolName: String,
        fallbackText: String,
        tooltip: String,
        action: Selector
    ) -> NSButton {
        let button = NSButton(frame: .zero)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.setButtonType(.momentaryChange)
        button.target = self
        button.action = action
        button.toolTip = tooltip
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip) {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
        } else {
            button.title = fallbackText
        }
        button.imagePosition = .imageOnly
        button.contentTintColor = NSColor.white.withAlphaComponent(0.85)
        return button
    }

    private func setupTitlebarAccessory(window: NSWindow) {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 26))

        let pill = NSVisualEffectView(frame: NSRect(x: 4, y: 2, width: 312, height: 22))
        pill.material = .hudWindow
        pill.blendingMode = .withinWindow
        pill.state = .active
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 11
        pill.layer?.masksToBounds = true
        pill.layer?.borderWidth = 0.5
        pill.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        let rotateBtn = makeActionButton(
            symbolName: "arrow.triangle.2.circlepath",
            fallbackText: "↻",
            tooltip: "Rotate Screen (⌘R)",
            action: #selector(rotateClicked)
        )
        rotateBtn.frame = NSRect(x: 5, y: 1, width: 20, height: 20)
        pill.addSubview(rotateBtn)

        let screenshotBtn = makeActionButton(
            symbolName: "camera.fill",
            fallbackText: "📸",
            tooltip: "Take Lossless Screenshot (⌘S)",
            action: #selector(screenshotClicked)
        )
        screenshotBtn.frame = NSRect(x: 29, y: 1, width: 20, height: 20)
        pill.addSubview(screenshotBtn)

        let keymapBtn = makeActionButton(
            symbolName: "keyboard.fill",
            fallbackText: "⌨️",
            tooltip: "Toggle Keymap Overlay (⌘K, Edit: ⌥⌘K)",
            action: #selector(keymapClicked)
        )
        keymapBtn.frame = NSRect(x: 53, y: 1, width: 20, height: 20)
        pill.addSubview(keymapBtn)

        let mouseLockBtn = makeActionButton(
            symbolName: "scope",
            fallbackText: "🎯",
            tooltip: "Toggle Mouse Aim Lock (⌥)",
            action: #selector(mouseLockClicked)
        )
        mouseLockBtn.frame = NSRect(x: 77, y: 1, width: 20, height: 20)
        pill.addSubview(mouseLockBtn)

        let freeformBtn = makeActionButton(
            symbolName: "square.on.square",
            fallbackText: "⧉",
            tooltip: "Toggle Freeform Multi-Window (⌘M)",
            action: #selector(freeformClicked)
        )
        freeformBtn.frame = NSRect(x: 101, y: 1, width: 20, height: 20)
        pill.addSubview(freeformBtn)

        let sharedFolderBtn = makeActionButton(
            symbolName: "folder.fill",
            fallbackText: "📁",
            tooltip: "Open Shared Folder (⌘O)",
            action: #selector(sharedFolderClicked)
        )
        sharedFolderBtn.frame = NSRect(x: 125, y: 1, width: 20, height: 20)
        pill.addSubview(sharedFolderBtn)

        let imeBtn = makeActionButton(
            symbolName: "character.bubble.fill",
            fallbackText: "VN",
            tooltip: "Toggle Vietnamese IME (⌘I)",
            action: #selector(imeClicked)
        )
        imeBtn.frame = NSRect(x: 149, y: 1, width: 20, height: 20)
        pill.addSubview(imeBtn)

        let taskSwitcherBtn = makeActionButton(
            symbolName: "rectangle.stack.fill",
            fallbackText: "🗂",
            tooltip: "Switch Running App / Tasks (⌘T)",
            action: #selector(taskSwitcherClicked)
        )
        taskSwitcherBtn.frame = NSRect(x: 173, y: 1, width: 20, height: 20)
        pill.addSubview(taskSwitcherBtn)

        let divider = NSView(frame: NSRect(x: 199, y: 5, width: 1, height: 12))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        pill.addSubview(divider)

        statusDot.frame = NSRect(x: 207, y: 8, width: 6, height: 6)
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 3
        statusDot.layer?.backgroundColor = NSColor(calibratedRed: 0.0, green: 0.88, blue: 0.38, alpha: 0.9).cgColor
        pill.addSubview(statusDot)

        fpsLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        fpsLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        fpsLabel.alignment = .left
        fpsLabel.frame = NSRect(x: 217, y: 1, width: 88, height: 20)
        pill.addSubview(fpsLabel)

        container.addSubview(pill)
        accessory.view = container
        accessory.view = container

        window.addTitlebarAccessoryViewController(accessory)
        self.toolbarAccessory = accessory
    }

    private func setupEmulatorCallbacks() {
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

        emulatorView.onRotateRequested = { [weak self] in
            self?.toggleRotation()
        }

        emulatorView.onScreenshotRequested = { [weak self] in
            self?.takeScreenshot()
        }

        emulatorView.onKeymapToggleRequested = { [weak self] in
            self?.toggleKeymapOverlay()
        }

        emulatorView.onKeymapEditorToggleRequested = { [weak self] in
            self?.toggleKeymapEditor()
        }

        emulatorView.onMouseLockToggleRequested = { [weak self] in
            self?.toggleMouseLock()
        }

        emulatorView.onFreeformRequested = { [weak self] in
            self?.toggleFreeform()
        }

        emulatorView.onIMEToggleRequested = { [weak self] in
            self?.toggleVietnameseIME()
        }

        emulatorView.onTaskSwitcherRequested = { [weak self] in
            self?.taskSwitcherClicked()
        }

        emulatorView.onSharedFolderRequested = { [weak self] in
            self?.openSharedFolder()
        }
    }

    @objc func rotateClicked() {
        toggleRotation()
    }

    func toggleRotation() {
        guard let window else { return }
        isPortrait.toggle()
        let currentFrame = window.frame
        let center = NSPoint(x: currentFrame.midX, y: currentFrame.midY)

        let newSize: NSSize
        if isPortrait {
            window.contentAspectRatio = NSSize(width: 9, height: 16)
            window.minSize = NSSize(width: 360, height: 640)
            newSize = NSSize(width: 450, height: 800)
        } else {
            window.contentAspectRatio = NSSize(width: 16, height: 9)
            window.minSize = NSSize(width: 800, height: 450)
            newSize = NSSize(width: 1280, height: 720)
        }

        let newOrigin = NSPoint(
            x: max(20, center.x - newSize.width / 2),
            y: max(40, center.y - newSize.height / 2)
        )
        let newFrame = NSRect(origin: newOrigin, size: newSize)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }

        showToast(
            icon: "arrow.triangle.2.circlepath",
            message: isPortrait ? "Switched to Portrait (9:16)" : "Switched to Landscape (16:9)"
        )
    }

    @objc func screenshotClicked() {
        takeScreenshot()
    }

    func takeScreenshot() {
        guard let image = emulatorView.captureScreenshot() else {
            showToast(icon: "exclamationmark.triangle", message: "Failed to capture screenshot")
            return
        }

        emulatorView.flashShutter()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateStr = dateFormatter.string(from: Date())
        let cleanName = appName.replacingOccurrences(of: " ", with: "_")
        let filename = "Macrodroid_\(cleanName)_\(dateStr).png"

        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Desktop")
        let targetURL = desktopURL.appendingPathComponent(filename)

        if let tiffData = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiffData),
           let pngData = rep.representation(using: .png, properties: [:]) {
            do {
                try pngData.write(to: targetURL)
                showToast(icon: "camera.fill", message: "Saved: \(filename)")
            } catch {
                showToast(icon: "camera.fill", message: "Copied screenshot to Clipboard")
            }
        } else {
            showToast(icon: "camera.fill", message: "Copied screenshot to Clipboard")
        }
    }

    @objc func keymapClicked() {
        toggleKeymapOverlay()
    }

    func toggleKeymapOverlay() {
        let visible = emulatorView.toggleKeymapOverlay()
        showToast(
            icon: "keyboard.fill",
            message: visible ? "Keymap Overlay: Visible" : "Keymap Overlay: Hidden"
        )
    }

    func toggleKeymapEditor() {
        let editing = emulatorView.toggleKeymapEditor()
        showToast(
            icon: "hand.draw.fill",
            message: editing ? "Keymap Editor: Active (Drag keys, ⌥⌘K to save)" : "Keymap Saved & Editor Closed"
        )
    }

    @objc func mouseLockClicked() {
        toggleMouseLock()
    }

    func toggleMouseLock() {
        let locked = emulatorView.toggleMouseLock()
        showToast(
            icon: "scope",
            message: locked ? "Mouse Aim Lock: Enabled (Press ⌥ to exit)" : "Mouse Aim Lock: Released"
        )
    }

    @objc func freeformClicked() {
        toggleFreeform()
    }

    func toggleFreeform() {
        isFreeformActive.toggle()
        onFreeformToggleRequested?()
        showToast(
            icon: "square.on.square",
            message: isFreeformActive ? "Multi-Window Freeform: Enabled" : "Multi-Window Freeform: Standard"
        )
    }

    @objc func sharedFolderClicked() {
        openSharedFolder()
    }

    func openSharedFolder() {
        SharedFolderConfig.ensureDirectoriesExist()
        NSWorkspace.shared.open(SharedFolderConfig.defaultSharedDirectory)
        onOpenSharedFolderRequested?()
        showToast(icon: "folder.fill", message: "Opened ~/Macrodroid/Shared")
    }

    @objc func imeClicked() {
        toggleVietnameseIME()
    }

    func toggleVietnameseIME() {
        emulatorView.isVietnameseIMEEnabled.toggle()
        let isEnabled = emulatorView.isVietnameseIMEEnabled
        onIMEToggled?(isEnabled)
        showToast(
            icon: isEnabled ? "character.bubble.fill" : "keyboard.fill",
            message: isEnabled ? "Vietnamese IME: Telex/VNI Enabled" : "Vietnamese IME: Disabled (Direct Keys)"
        )
    }

    @objc func taskSwitcherClicked() {
        onTaskSwitcherRequested?()
    }

    func showToast(icon: String?, message: String) {
        toastView.present(icon: icon, message: message, in: emulatorView)
    }

    func updateTitle(appName: String, packageName: String? = nil) {
        window?.title = "Macrodroid: \(appName)"
        if let packageName {
            emulatorView.configureForPackage(packageName, appName: appName)
        }
    }

    func enterNativeFullscreen() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(nil)
    }
}
