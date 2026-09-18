import AppKit

// MARK: - MacrodroidDynamicIslandHUDView
/// Floating "Dynamic Island" mini-HUD bar that sits at the top of the game window.
/// Collapses to a compact pill showing FPS + session time; expands on hover to reveal
/// telemetry, quick mute, screenshot, and mouse-lock toggles.
@MainActor
final class MacrodroidDynamicIslandHUDView: NSView {

    // MARK: - Callbacks
    var onToggleMuteRequested: (() -> Void)?
    var onScreenshotRequested: (() -> Void)?
    var onMouseLockRequested: (() -> Void)?
    var onOverlayRequested: (() -> Void)?

    // MARK: - State
    private var fps: Double = 60.0
    private var sessionSeconds: Int = 0
    private var cpuTempCelsius: Double = 0.0
    private var isMuted: Bool = false
    private var isMouseLocked: Bool = false
    private var isExpanded: Bool = false
    private var hideTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?

    // MARK: - Layout constants
    private let collapsedHeight: CGFloat = 32
    private let expandedHeight: CGFloat = 56
    private let pillWidth: CGFloat = 260
    private let expandedWidth: CGFloat = 420
    private let cornerRadius: CGFloat = 16

    // MARK: - Sub-views (collapsed pill)
    private let pillBackground = NSVisualEffectView()
    private let fpsLabel = NSTextField(labelWithString: "60 FPS")
    private let sessionLabel = NSTextField(labelWithString: "0:00")
    private let dotSeparator = NSTextField(labelWithString: "·")
    private let chevronButton = NSButton()

    // MARK: - Sub-views (expanded tray)
    private let cpuTempLabel  = NSTextField(labelWithString: "CPU —°")
    private let screenshotBtn = NSButton()
    private let muteBtn       = NSButton()
    private let mouseLockBtn  = NSButton()
    private let openOverlayBtn = NSButton()

    // MARK: - Constraints kept for animation
    private var widthConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint!
    private var expandedViews: [NSView] = []

    // MARK: - Init
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
        startSessionTimer()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - UI Construction
    private func buildUI() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        pillBackground.material = .hudWindow
        pillBackground.blendingMode = .withinWindow
        pillBackground.state = .active
        pillBackground.wantsLayer = true
        pillBackground.layer?.cornerRadius = cornerRadius
        pillBackground.layer?.masksToBounds = true
        pillBackground.layer?.borderWidth = 1.0
        pillBackground.layer?.borderColor = NSColor(
            calibratedRed: 0.0, green: 0.9, blue: 0.48, alpha: 0.30).cgColor
        pillBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pillBackground)

        NSLayoutConstraint.activate([
            pillBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            pillBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            pillBackground.topAnchor.constraint(equalTo: topAnchor),
            pillBackground.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        fpsLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        fpsLabel.textColor = NSColor(calibratedRed: 0.0, green: 0.95, blue: 0.48, alpha: 1.0)
        fpsLabel.translatesAutoresizingMaskIntoConstraints = false
        pillBackground.addSubview(fpsLabel)

        dotSeparator.font = .systemFont(ofSize: 13, weight: .thin)
        dotSeparator.textColor = NSColor.white.withAlphaComponent(0.4)
        dotSeparator.translatesAutoresizingMaskIntoConstraints = false
        pillBackground.addSubview(dotSeparator)

        sessionLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        sessionLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        sessionLabel.translatesAutoresizingMaskIntoConstraints = false
        pillBackground.addSubview(sessionLabel)

        chevronButton.isBordered = false
        chevronButton.target = self
        chevronButton.action = #selector(toggleExpand)
        let chevronImg = NSImage(systemSymbolName: "chevron.down.circle.fill",
                                  accessibilityDescription: "Expand HUD")
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        chevronButton.image = chevronImg?.withSymbolConfiguration(cfg)
        chevronButton.contentTintColor = NSColor.white.withAlphaComponent(0.5)
        chevronButton.translatesAutoresizingMaskIntoConstraints = false
        pillBackground.addSubview(chevronButton)

        NSLayoutConstraint.activate([
            fpsLabel.leadingAnchor.constraint(equalTo: pillBackground.leadingAnchor, constant: 14),
            fpsLabel.centerYAnchor.constraint(equalTo: pillBackground.topAnchor, constant: collapsedHeight / 2),

            dotSeparator.leadingAnchor.constraint(equalTo: fpsLabel.trailingAnchor, constant: 6),
            dotSeparator.centerYAnchor.constraint(equalTo: fpsLabel.centerYAnchor),

            sessionLabel.leadingAnchor.constraint(equalTo: dotSeparator.trailingAnchor, constant: 6),
            sessionLabel.centerYAnchor.constraint(equalTo: fpsLabel.centerYAnchor),

            chevronButton.trailingAnchor.constraint(equalTo: pillBackground.trailingAnchor, constant: -10),
            chevronButton.centerYAnchor.constraint(equalTo: fpsLabel.centerYAnchor),
            chevronButton.widthAnchor.constraint(equalToConstant: 20),
            chevronButton.heightAnchor.constraint(equalToConstant: 20)
        ])

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        pillBackground.addSubview(divider)

        cpuTempLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        cpuTempLabel.textColor = NSColor.white.withAlphaComponent(0.65)
        cpuTempLabel.translatesAutoresizingMaskIntoConstraints = false
        pillBackground.addSubview(cpuTempLabel)

        configIconBtn(screenshotBtn, icon: "camera.fill", tip: "Screenshot (Cmd+S)", action: #selector(screenshotTapped))
        configIconBtn(muteBtn, icon: "speaker.wave.2.fill", tip: "Mute (Cmd+Shift+U)", action: #selector(muteTapped))
        configIconBtn(mouseLockBtn, icon: "scope", tip: "Lock Mouse Aim (F10)", action: #selector(mouseLockTapped))
        configIconBtn(openOverlayBtn, icon: "square.grid.2x2.fill", tip: "Open Dashboard (Shift+Tab)", action: #selector(overlayTapped))

        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: pillBackground.leadingAnchor, constant: 12),
            divider.trailingAnchor.constraint(equalTo: pillBackground.trailingAnchor, constant: -12),
            divider.topAnchor.constraint(equalTo: pillBackground.topAnchor, constant: collapsedHeight),
            divider.heightAnchor.constraint(equalToConstant: 0.5),

            cpuTempLabel.leadingAnchor.constraint(equalTo: pillBackground.leadingAnchor, constant: 14),
            cpuTempLabel.centerYAnchor.constraint(equalTo: pillBackground.topAnchor, constant: collapsedHeight + (expandedHeight - collapsedHeight) / 2),

            screenshotBtn.trailingAnchor.constraint(equalTo: openOverlayBtn.leadingAnchor, constant: -4),
            screenshotBtn.centerYAnchor.constraint(equalTo: cpuTempLabel.centerYAnchor),
            screenshotBtn.widthAnchor.constraint(equalToConstant: 28),
            screenshotBtn.heightAnchor.constraint(equalToConstant: 28),

            muteBtn.trailingAnchor.constraint(equalTo: screenshotBtn.leadingAnchor, constant: -4),
            muteBtn.centerYAnchor.constraint(equalTo: cpuTempLabel.centerYAnchor),
            muteBtn.widthAnchor.constraint(equalToConstant: 28),
            muteBtn.heightAnchor.constraint(equalToConstant: 28),

            mouseLockBtn.trailingAnchor.constraint(equalTo: muteBtn.leadingAnchor, constant: -4),
            mouseLockBtn.centerYAnchor.constraint(equalTo: cpuTempLabel.centerYAnchor),
            mouseLockBtn.widthAnchor.constraint(equalToConstant: 28),
            mouseLockBtn.heightAnchor.constraint(equalToConstant: 28),

            openOverlayBtn.trailingAnchor.constraint(equalTo: pillBackground.trailingAnchor, constant: -10),
            openOverlayBtn.centerYAnchor.constraint(equalTo: cpuTempLabel.centerYAnchor),
            openOverlayBtn.widthAnchor.constraint(equalToConstant: 28),
            openOverlayBtn.heightAnchor.constraint(equalToConstant: 28)
        ])

        expandedViews = [divider, cpuTempLabel, screenshotBtn, muteBtn, mouseLockBtn, openOverlayBtn]
        expandedViews.forEach { $0.alphaValue = 0 }

        widthConstraint = widthAnchor.constraint(equalToConstant: pillWidth)
        heightConstraint = heightAnchor.constraint(equalToConstant: collapsedHeight)
        widthConstraint.isActive = true
        heightConstraint.isActive = true
    }

    private func configIconBtn(_ btn: NSButton, icon: String, tip: String, action: Selector) {
        btn.isBordered = false
        btn.toolTip = tip
        btn.target = self
        btn.action = action
        btn.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: tip) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            btn.image = img.withSymbolConfiguration(cfg)
        }
        btn.contentTintColor = NSColor.white.withAlphaComponent(0.80)
        pillBackground.addSubview(btn)
    }

    // MARK: - Session Timer
    private func startSessionTimer() {
        sessionTask?.cancel()
        sessionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { break }
                self.sessionSeconds += 1
                self.refreshSessionLabel()
            }
        }
    }

    private func refreshSessionLabel() {
        let h = sessionSeconds / 3600
        let m = (sessionSeconds % 3600) / 60
        let s = sessionSeconds % 60
        sessionLabel.stringValue = h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                                         : String(format: "%d:%02d", m, s)
    }

    // MARK: - Public Update API
    func updateFPS(_ value: Double) {
        fps = value
        fpsLabel.stringValue = String(format: "%.0f FPS", value)
        if value >= 55 {
            fpsLabel.textColor = NSColor(calibratedRed: 0.0, green: 0.95, blue: 0.48, alpha: 1.0)
        } else if value >= 40 {
            fpsLabel.textColor = NSColor.systemYellow
        } else {
            fpsLabel.textColor = NSColor.systemRed
        }
    }

    func updateCPUTemp(_ celsius: Double) {
        cpuTempCelsius = celsius
        let icon = celsius > 80 ? "🔥" : (celsius > 60 ? "🌡" : "❄️")
        cpuTempLabel.stringValue = "\(icon) CPU \(Int(celsius))°C"
        cpuTempLabel.textColor = celsius > 80 ? NSColor.systemOrange : NSColor.white.withAlphaComponent(0.65)
    }

    func updateMuteState(_ muted: Bool) {
        isMuted = muted
        let iconName = muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            muteBtn.image = img.withSymbolConfiguration(cfg)
        }
        muteBtn.contentTintColor = muted ? NSColor.systemOrange : NSColor.white.withAlphaComponent(0.80)
    }

    func updateMouseLockState(_ locked: Bool) {
        isMouseLocked = locked
        mouseLockBtn.contentTintColor = locked
            ? NSColor(calibratedRed: 0.0, green: 0.95, blue: 0.48, alpha: 1.0)
            : NSColor.white.withAlphaComponent(0.80)
    }

    func resetSession() {
        sessionSeconds = 0
        refreshSessionLabel()
    }

    // MARK: - Expand / Collapse
    @objc private func toggleExpand() {
        setExpanded(!isExpanded, animated: true)
    }

    private func setExpanded(_ expand: Bool, animated: Bool) {
        isExpanded = expand
        let targetH = expand ? expandedHeight : collapsedHeight
        let targetW = expand ? expandedWidth : pillWidth
        let targetAlpha: CGFloat = expand ? 1.0 : 0.0
        let chevronIcon = expand ? "chevron.up.circle.fill" : "chevron.down.circle.fill"

        if let img = NSImage(systemSymbolName: chevronIcon, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            chevronButton.image = img.withSymbolConfiguration(cfg)
        }

        let duration = animated ? 0.22 : 0.0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.heightConstraint.animator().constant = targetH
            self.widthConstraint.animator().constant = targetW
            self.expandedViews.forEach { $0.animator().alphaValue = targetAlpha }
        }

        if expand {
            scheduleAutoHide()
        } else {
            hideTask?.cancel()
        }
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.isExpanded else { return }
            self.setExpanded(false, animated: true)
        }
    }

    override func mouseEntered(with event: NSEvent) { scheduleAutoHide() }
    override func mouseMoved(with event: NSEvent) { scheduleAutoHide() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    // MARK: - Actions
    @objc private func screenshotTapped() { onScreenshotRequested?(); scheduleAutoHide() }
    @objc private func muteTapped() { onToggleMuteRequested?(); scheduleAutoHide() }
    @objc private func mouseLockTapped() { onMouseLockRequested?(); scheduleAutoHide() }
    @objc private func overlayTapped() { onOverlayRequested?(); setExpanded(false, animated: true) }

    deinit {
        sessionTask?.cancel()
        hideTask?.cancel()
    }
}
