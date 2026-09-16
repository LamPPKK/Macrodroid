import AppKit

// MARK: - FrametimeGraphView
private final class FrametimeGraphView: NSView {
    private let maxSamples = 60
    private var samples: [Double] = []

    override var isFlipped: Bool { true }

    func addSample(_ fps: Double) {
        samples.append(fps)
        if samples.count > maxSamples { samples.removeFirst() }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !samples.isEmpty else { return }
        let barW = bounds.width / CGFloat(maxSamples)
        let maxH = bounds.height
        for (i, fps) in samples.enumerated() {
            let ratio = min(fps / 60.0, 1.5)
            let barH = CGFloat(ratio) * maxH * 0.85
            let x = CGFloat(i) * barW
            let y = maxH - barH
            let color: NSColor
            if fps >= 55 { color = NSColor(calibratedRed: 0.0, green: 0.9, blue: 0.45, alpha: 0.85) }
            else if fps >= 40 { color = NSColor.systemYellow.withAlphaComponent(0.85) }
            else { color = NSColor.systemRed.withAlphaComponent(0.85) }
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: x + 1, y: y, width: max(barW - 2, 1), height: barH),
                         xRadius: 1.5, yRadius: 1.5).fill()
        }
        let lineY = maxH - (maxH * 0.85)
        NSColor.white.withAlphaComponent(0.25).setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: lineY))
        path.line(to: NSPoint(x: bounds.width, y: lineY))
        path.lineWidth = 0.5
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()
    }
}

@MainActor
final class GooglePlayGamesOverlayView: NSVisualEffectView {
    // MARK: - Callbacks
    var onResumeRequested: (() -> Void)?
    var onRemapRequested: (() -> Void)?
    var onToggleKeymapVisibilityRequested: (() -> Void)?
    var onResetKeymapRequested: (() -> Void)?
    var onOpacityChanged: ((Float) -> Void)?
    var onMouseLockRequested: (() -> Void)?
    var onFullscreenRequested: (() -> Void)?
    var onRotateRequested: (() -> Void)?
    var onFreeformRequested: (() -> Void)?
    var onToggleMuteRequested: (() -> Void)?
    var onScreenshotRequested: (() -> Void)?
    var onSharedFolderRequested: (() -> Void)?
    var onSettingsRequested: (() -> Void)?
    var onExitGameRequested: (() -> Void)?
    var onRefreshRateChanged: ((Int) -> Void)?

    // MARK: - UI Components
    private let cardContainer = NSVisualEffectView()
    private let iconImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Game Dashboard")
    private let subtitleLabel = NSTextField(labelWithString: "Macrodroid Play Engine • Host Metal 3 GPU")
    private let playTimeBadge = NSTextField(labelWithString: "⏱️ Session: 0s · Total: 0m")
    private let fpsBadge = NSTextField(labelWithString: "60 FPS")
    private let gamepadStatusBadge = NSTextField(labelWithString: "⌨️ Keyboard & Mouse")

    private let resumeButton = NSButton()
    private let remapButton = NSButton()
    private let toggleKeysButton = NSButton()
    private let resetKeymapButton = NSButton()
    private let mouseLockButton = NSButton()
    private let fullscreenButton = NSButton()
    private let rotateButton = NSButton()
    private let freeformButton = NSButton()
    private let muteButton = NSButton()
    private let screenshotButton = NSButton()
    private let sharedFolderButton = NSButton()
    private let settingsButton = NSButton()
    private let exitButton = NSButton()
    private let refreshRateSegment = NSSegmentedControl(labels: ["60 Hz", "90 Hz", "120 Hz", "144 Hz"], trackingMode: .selectOne, target: nil, action: nil)
    private let opacitySlider = NSSlider(value: 0.85, minValue: 0.1, maxValue: 1.0, target: nil, action: nil)

    private var currentPackage: String?
    private var isMouseAimLocked: Bool = false

    // MARK: - Telemetry graph
    private let frametimeGraph = FrametimeGraphView()
    private let avgFpsLabel     = NSTextField(labelWithString: "Avg: — FPS")
    private let frameDropLabel  = NSTextField(labelWithString: "Frame Drops: 0")
    private let gpuLoadLabel    = NSTextField(labelWithString: "GPU Metal: —%")
    private var frameSamples: [Double] = []
    private var frameDropCount: Int = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func setupView() {
        material = .fullScreenUI
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor

        cardContainer.material = .hudWindow
        cardContainer.blendingMode = .withinWindow
        cardContainer.state = .active
        cardContainer.wantsLayer = true
        cardContainer.layer?.cornerRadius = 16
        cardContainer.layer?.masksToBounds = true
        cardContainer.layer?.borderWidth = 1.0
        cardContainer.layer?.borderColor = NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.45, alpha: 0.35).cgColor
        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardContainer)

        setupHeader()
        setupContentGrid()
        setupFooter()

        NSLayoutConstraint.activate([
            cardContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            cardContainer.widthAnchor.constraint(equalToConstant: 780),
            cardContainer.heightAnchor.constraint(equalToConstant: 540)
        ])
    }

    private func setupHeader() {
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.wantsLayer = true
        iconImageView.layer?.cornerRadius = 8
        iconImageView.layer?.masksToBounds = true
        cardContainer.addSubview(iconImageView)

        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.65)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(subtitleLabel)

        playTimeBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        playTimeBadge.textColor = NSColor(calibratedRed: 0.0, green: 0.92, blue: 0.50, alpha: 1.0)
        playTimeBadge.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(playTimeBadge)

        fpsBadge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        fpsBadge.textColor = NSColor(calibratedRed: 0.0, green: 0.95, blue: 0.45, alpha: 1.0)
        fpsBadge.alignment = .center
        fpsBadge.wantsLayer = true
        fpsBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        fpsBadge.layer?.cornerRadius = 6
        fpsBadge.layer?.borderWidth = 0.5
        fpsBadge.layer?.borderColor = NSColor(calibratedRed: 0.0, green: 0.95, blue: 0.45, alpha: 0.4).cgColor
        fpsBadge.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(fpsBadge)

        gamepadStatusBadge.font = .systemFont(ofSize: 10.5, weight: .semibold)
        gamepadStatusBadge.textColor = NSColor.white.withAlphaComponent(0.85)
        gamepadStatusBadge.alignment = .center
        gamepadStatusBadge.wantsLayer = true
        gamepadStatusBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        gamepadStatusBadge.layer?.cornerRadius = 6
        gamepadStatusBadge.layer?.borderWidth = 0.5
        gamepadStatusBadge.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        gamepadStatusBadge.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(gamepadStatusBadge)

        let headerDivider = NSView()
        headerDivider.wantsLayer = true
        headerDivider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        headerDivider.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(headerDivider)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 20),
            iconImageView.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: 16),
            iconImageView.widthAnchor.constraint(equalToConstant: 40),
            iconImageView.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: gamepadStatusBadge.leadingAnchor, constant: -8),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),

            playTimeBadge.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            playTimeBadge.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 2),

            fpsBadge.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -20),
            fpsBadge.centerYAnchor.constraint(equalTo: iconImageView.centerYAnchor),
            fpsBadge.widthAnchor.constraint(equalToConstant: 72),
            fpsBadge.heightAnchor.constraint(equalToConstant: 24),

            gamepadStatusBadge.trailingAnchor.constraint(equalTo: fpsBadge.leadingAnchor, constant: -8),
            gamepadStatusBadge.centerYAnchor.constraint(equalTo: fpsBadge.centerYAnchor),
            gamepadStatusBadge.heightAnchor.constraint(equalToConstant: 24),
            gamepadStatusBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),

            headerDivider.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 20),
            headerDivider.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -20),
            headerDivider.topAnchor.constraint(equalTo: playTimeBadge.bottomAnchor, constant: 10),
            headerDivider.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    private func setupContentGrid() {
        // Three columns: Left (Controls & Aim), Centre (Live Telemetry), Right (Quick Tune)
        let leftSection   = makeSectionBox(title: "CONTROLS & AIM")
        let centreSection = makeSectionBox(title: "LIVE FRAMETIME")
        let rightSection  = makeSectionBox(title: "QUICK TUNE")

        cardContainer.addSubview(leftSection)
        cardContainer.addSubview(centreSection)
        cardContainer.addSubview(rightSection)

        cardContainer.addSubview(leftSection)
        cardContainer.addSubview(rightSection)

        // Left Section: Controls
        configureButton(remapButton, title: "Remap Controls (⌥⌘K)", icon: "keyboard.fill", action: #selector(remapClicked))
        configureButton(toggleKeysButton, title: "Toggle On-Screen Keys (⌘K)", icon: "eye.fill", action: #selector(toggleKeysClicked))
        configureButton(resetKeymapButton, title: "Reset Keymap to Defaults", icon: "arrow.counterclockwise", action: #selector(resetKeymapClicked))
        configureButton(mouseLockButton, title: "Lock Mouse Aim (F10 / ⌥)", icon: "scope", action: #selector(mouseLockClicked))

        let opacityLabel = NSTextField(labelWithString: "Keymap Opacity:")
        opacityLabel.font = .systemFont(ofSize: 11, weight: .medium)
        opacityLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        opacityLabel.translatesAutoresizingMaskIntoConstraints = false

        opacitySlider.translatesAutoresizingMaskIntoConstraints = false
        opacitySlider.target = self
        opacitySlider.action = #selector(opacitySliderChanged)

        leftSection.addSubview(remapButton)
        leftSection.addSubview(toggleKeysButton)
        leftSection.addSubview(resetKeymapButton)
        leftSection.addSubview(mouseLockButton)
        leftSection.addSubview(opacityLabel)
        leftSection.addSubview(opacitySlider)

        NSLayoutConstraint.activate([
            remapButton.topAnchor.constraint(equalTo: leftSection.topAnchor, constant: 30),
            remapButton.leadingAnchor.constraint(equalTo: leftSection.leadingAnchor, constant: 12),
            remapButton.trailingAnchor.constraint(equalTo: leftSection.trailingAnchor, constant: -12),
            remapButton.heightAnchor.constraint(equalToConstant: 28),

            toggleKeysButton.topAnchor.constraint(equalTo: remapButton.bottomAnchor, constant: 6),
            toggleKeysButton.leadingAnchor.constraint(equalTo: remapButton.leadingAnchor),
            toggleKeysButton.trailingAnchor.constraint(equalTo: remapButton.trailingAnchor),
            toggleKeysButton.heightAnchor.constraint(equalToConstant: 28),

            resetKeymapButton.topAnchor.constraint(equalTo: toggleKeysButton.bottomAnchor, constant: 6),
            resetKeymapButton.leadingAnchor.constraint(equalTo: remapButton.leadingAnchor),
            resetKeymapButton.trailingAnchor.constraint(equalTo: remapButton.trailingAnchor),
            resetKeymapButton.heightAnchor.constraint(equalToConstant: 28),

            mouseLockButton.topAnchor.constraint(equalTo: resetKeymapButton.bottomAnchor, constant: 6),
            mouseLockButton.leadingAnchor.constraint(equalTo: remapButton.leadingAnchor),
            mouseLockButton.trailingAnchor.constraint(equalTo: remapButton.trailingAnchor),
            mouseLockButton.heightAnchor.constraint(equalToConstant: 28),

            opacityLabel.topAnchor.constraint(equalTo: mouseLockButton.bottomAnchor, constant: 10),
            opacityLabel.leadingAnchor.constraint(equalTo: remapButton.leadingAnchor),

            opacitySlider.topAnchor.constraint(equalTo: opacityLabel.bottomAnchor, constant: 4),
            opacitySlider.leadingAnchor.constraint(equalTo: remapButton.leadingAnchor),
            opacitySlider.trailingAnchor.constraint(equalTo: remapButton.trailingAnchor)
        ])

        // Right Section: Display & Performance
        configureButton(fullscreenButton, title: "Toggle Fullscreen (F11 / ⌘F)", icon: "arrow.up.left.and.arrow.down.right", action: #selector(fullscreenClicked))
        configureButton(rotateButton, title: "Rotate Screen (⌘R)", icon: "arrow.triangle.2.circlepath", action: #selector(rotateClicked))
        configureButton(freeformButton, title: "Freeform Multi-Window (⌘M)", icon: "square.on.square", action: #selector(freeformClicked))
        configureButton(muteButton, title: "Mute Game Sound", icon: "speaker.wave.2.fill", action: #selector(muteClicked))

        let refreshLabel = NSTextField(labelWithString: "Refresh Rate Target:")
        refreshLabel.font = .systemFont(ofSize: 11, weight: .medium)
        refreshLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        refreshLabel.translatesAutoresizingMaskIntoConstraints = false

        refreshRateSegment.selectedSegment = 0
        refreshRateSegment.target = self
        refreshRateSegment.action = #selector(refreshSegmentChanged)
        refreshRateSegment.translatesAutoresizingMaskIntoConstraints = false

        rightSection.addSubview(fullscreenButton)
        rightSection.addSubview(rotateButton)
        rightSection.addSubview(freeformButton)
        rightSection.addSubview(muteButton)
        rightSection.addSubview(refreshLabel)
        rightSection.addSubview(refreshRateSegment)

        NSLayoutConstraint.activate([
            fullscreenButton.topAnchor.constraint(equalTo: rightSection.topAnchor, constant: 30),
            fullscreenButton.leadingAnchor.constraint(equalTo: rightSection.leadingAnchor, constant: 12),
            fullscreenButton.trailingAnchor.constraint(equalTo: rightSection.trailingAnchor, constant: -12),
            fullscreenButton.heightAnchor.constraint(equalToConstant: 28),

            rotateButton.topAnchor.constraint(equalTo: fullscreenButton.bottomAnchor, constant: 6),
            rotateButton.leadingAnchor.constraint(equalTo: fullscreenButton.leadingAnchor),
            rotateButton.trailingAnchor.constraint(equalTo: fullscreenButton.trailingAnchor),
            rotateButton.heightAnchor.constraint(equalToConstant: 28),

            freeformButton.topAnchor.constraint(equalTo: rotateButton.bottomAnchor, constant: 6),
            freeformButton.leadingAnchor.constraint(equalTo: fullscreenButton.leadingAnchor),
            freeformButton.trailingAnchor.constraint(equalTo: fullscreenButton.trailingAnchor),
            freeformButton.heightAnchor.constraint(equalToConstant: 28),

            muteButton.topAnchor.constraint(equalTo: freeformButton.bottomAnchor, constant: 6),
            muteButton.leadingAnchor.constraint(equalTo: fullscreenButton.leadingAnchor),
            muteButton.trailingAnchor.constraint(equalTo: fullscreenButton.trailingAnchor),
            muteButton.heightAnchor.constraint(equalToConstant: 28),

            refreshLabel.topAnchor.constraint(equalTo: muteButton.bottomAnchor, constant: 10),
            refreshLabel.leadingAnchor.constraint(equalTo: fullscreenButton.leadingAnchor),

            refreshRateSegment.topAnchor.constraint(equalTo: refreshLabel.bottomAnchor, constant: 4),
            refreshRateSegment.leadingAnchor.constraint(equalTo: fullscreenButton.leadingAnchor),
            refreshRateSegment.trailingAnchor.constraint(equalTo: fullscreenButton.trailingAnchor)
        ])

        // Wire up centre telemetry section
        frametimeGraph.wantsLayer = true
        frametimeGraph.layer?.cornerRadius = 6
        frametimeGraph.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.30).cgColor
        frametimeGraph.translatesAutoresizingMaskIntoConstraints = false
        centreSection.addSubview(frametimeGraph)

        avgFpsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        avgFpsLabel.textColor = NSColor(calibratedRed: 0.0, green: 0.92, blue: 0.50, alpha: 1.0)
        avgFpsLabel.translatesAutoresizingMaskIntoConstraints = false
        centreSection.addSubview(avgFpsLabel)

        frameDropLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        frameDropLabel.textColor = NSColor.systemOrange
        frameDropLabel.translatesAutoresizingMaskIntoConstraints = false
        centreSection.addSubview(frameDropLabel)

        gpuLoadLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        gpuLoadLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        gpuLoadLabel.translatesAutoresizingMaskIntoConstraints = false
        centreSection.addSubview(gpuLoadLabel)

        NSLayoutConstraint.activate([
            frametimeGraph.topAnchor.constraint(equalTo: centreSection.topAnchor, constant: 30),
            frametimeGraph.leadingAnchor.constraint(equalTo: centreSection.leadingAnchor, constant: 10),
            frametimeGraph.trailingAnchor.constraint(equalTo: centreSection.trailingAnchor, constant: -10),
            frametimeGraph.heightAnchor.constraint(equalToConstant: 120),

            avgFpsLabel.topAnchor.constraint(equalTo: frametimeGraph.bottomAnchor, constant: 8),
            avgFpsLabel.leadingAnchor.constraint(equalTo: frametimeGraph.leadingAnchor),

            frameDropLabel.topAnchor.constraint(equalTo: avgFpsLabel.bottomAnchor, constant: 4),
            frameDropLabel.leadingAnchor.constraint(equalTo: frametimeGraph.leadingAnchor),

            gpuLoadLabel.topAnchor.constraint(equalTo: frameDropLabel.bottomAnchor, constant: 4),
            gpuLoadLabel.leadingAnchor.constraint(equalTo: frametimeGraph.leadingAnchor)
        ])

        // 3-column section placement
        NSLayoutConstraint.activate([
            leftSection.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 16),
            leftSection.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: 88),
            leftSection.widthAnchor.constraint(equalToConstant: 210),
            leftSection.heightAnchor.constraint(equalToConstant: 340),

            centreSection.leadingAnchor.constraint(equalTo: leftSection.trailingAnchor, constant: 12),
            centreSection.topAnchor.constraint(equalTo: leftSection.topAnchor),
            centreSection.widthAnchor.constraint(equalToConstant: 280),
            centreSection.heightAnchor.constraint(equalToConstant: 340),

            rightSection.leadingAnchor.constraint(equalTo: centreSection.trailingAnchor, constant: 12),
            rightSection.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -16),
            rightSection.topAnchor.constraint(equalTo: leftSection.topAnchor),
            rightSection.heightAnchor.constraint(equalToConstant: 340)
        ])
    }

    private func setupFooter() {
        let footerDivider = NSView()
        footerDivider.wantsLayer = true
        footerDivider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        footerDivider.translatesAutoresizingMaskIntoConstraints = false
        configureActionButton(screenshotButton, icon: "camera.fill", tooltip: "Take Screenshot (⌘S)", action: #selector(screenshotClicked))
        configureActionButton(sharedFolderButton, icon: "folder.fill", tooltip: "Shared Folder (⌘O)", action: #selector(sharedFolderClicked))
        configureActionButton(settingsButton, icon: "gearshape.fill", tooltip: "Settings (⌘,)", action: #selector(settingsClicked))

        resumeButton.title = "Resume Game (Shift+Tab or Esc)"
        resumeButton.bezelStyle = .rounded
        resumeButton.target = self
        resumeButton.action = #selector(resumeClicked)
        resumeButton.wantsLayer = true
        resumeButton.layer?.backgroundColor = NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.45, alpha: 0.95).cgColor
        resumeButton.layer?.cornerRadius = 8
        resumeButton.contentTintColor = .black
        resumeButton.font = .systemFont(ofSize: 12, weight: .bold)
        resumeButton.translatesAutoresizingMaskIntoConstraints = false

        exitButton.title = "Exit Game"
        exitButton.bezelStyle = .rounded
        exitButton.target = self
        exitButton.action = #selector(exitClicked)
        exitButton.contentTintColor = NSColor.systemRed.withAlphaComponent(0.9)
        exitButton.font = .systemFont(ofSize: 12, weight: .medium)
        exitButton.translatesAutoresizingMaskIntoConstraints = false

        cardContainer.addSubview(footerDivider)
        cardContainer.addSubview(screenshotButton)
        cardContainer.addSubview(sharedFolderButton)
        cardContainer.addSubview(settingsButton)
        cardContainer.addSubview(exitButton)
        cardContainer.addSubview(resumeButton)

        NSLayoutConstraint.activate([
            footerDivider.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 20),
            footerDivider.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -20),
            footerDivider.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor, constant: -62),
            footerDivider.heightAnchor.constraint(equalToConstant: 1),

            screenshotButton.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 20),
            screenshotButton.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor, constant: -16),
            screenshotButton.widthAnchor.constraint(equalToConstant: 32),
            screenshotButton.heightAnchor.constraint(equalToConstant: 32),

            sharedFolderButton.leadingAnchor.constraint(equalTo: screenshotButton.trailingAnchor, constant: 8),
            sharedFolderButton.centerYAnchor.constraint(equalTo: screenshotButton.centerYAnchor),
            sharedFolderButton.widthAnchor.constraint(equalToConstant: 32),
            sharedFolderButton.heightAnchor.constraint(equalToConstant: 32),

            settingsButton.leadingAnchor.constraint(equalTo: sharedFolderButton.trailingAnchor, constant: 8),
            settingsButton.centerYAnchor.constraint(equalTo: screenshotButton.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 32),
            settingsButton.heightAnchor.constraint(equalToConstant: 32),

            exitButton.leadingAnchor.constraint(equalTo: settingsButton.trailingAnchor, constant: 12),
            exitButton.centerYAnchor.constraint(equalTo: screenshotButton.centerYAnchor),
            exitButton.heightAnchor.constraint(equalToConstant: 32),

            resumeButton.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -20),
            resumeButton.centerYAnchor.constraint(equalTo: screenshotButton.centerYAnchor),
            resumeButton.heightAnchor.constraint(equalToConstant: 34),
            resumeButton.widthAnchor.constraint(equalToConstant: 220)
        ])
    }

    private func makeSectionBox(title: String) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        box.layer?.borderWidth = 0.5
        box.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        box.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: title)
        header.font = .systemFont(ofSize: 10.5, weight: .bold)
        header.textColor = NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.45, alpha: 0.9)
        header.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(header)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12)
        ])
        return box
    }

    private func configureButton(_ button: NSButton, title: String, icon: String, action: Selector) {
        button.title = "  \(title)"
        button.bezelStyle = .rounded
        button.alignment = .left
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            button.image = img.withSymbolConfiguration(config)
            button.imagePosition = .imageLeading
        }
    }

    private func configureActionButton(_ button: NSButton, icon: String, tooltip: String, action: Selector) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: tooltip) {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            button.image = img.withSymbolConfiguration(config)
        }
        button.contentTintColor = NSColor.white.withAlphaComponent(0.85)
    }

    // MARK: - Update State
    func configure(appName: String, packageName: String?, fps: Double) {
        currentPackage = packageName
        titleLabel.stringValue = appName
        fpsBadge.stringValue = fps > 0.5 ? String(format: "%.0f FPS", fps) : "60 FPS"
        updateTargetFPS(Int(fps.rounded()))

        if let pkg = packageName, AppIconExtractor.hasCachedIcon(for: pkg) {
            let iconURL = AppIconExtractor.iconURL(for: pkg)
            iconImageView.image = NSImage(contentsOf: iconURL)
        } else if let genericIcon = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: appName) {
            iconImageView.image = genericIcon
            iconImageView.contentTintColor = NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.45, alpha: 0.95)
        }
    }

    func updateTargetFPS(_ fps: Int) {
        switch fps {
        case 90: refreshRateSegment.selectedSegment = 1
        case 120: refreshRateSegment.selectedSegment = 2
        case 144: refreshRateSegment.selectedSegment = 3
        default: refreshRateSegment.selectedSegment = 0
        }
    }

    func updateFPS(_ fps: Double) {
        fpsBadge.stringValue = fps > 0.5 ? String(format: "%.0f FPS", fps) : "— FPS"
        guard fps > 0.5 else { return }
        frametimeGraph.addSample(fps)
        frameSamples.append(fps)
        if frameSamples.count > 360 { frameSamples.removeFirst() }
        if fps < 50 { frameDropCount += 1 }
        frameDropLabel.stringValue = "Frame Drops: \(frameDropCount)"
        let avg = frameSamples.reduce(0, +) / Double(frameSamples.count)
        avgFpsLabel.stringValue = String(format: "Avg: %.0f FPS", avg)
    }

    func updateGPULoad(_ percent: Double) {
        gpuLoadLabel.stringValue = String(format: "GPU Metal: %.0f%%", percent)
        gpuLoadLabel.textColor = percent > 85
            ? NSColor.systemOrange : NSColor.white.withAlphaComponent(0.75)
    }

    /// Show a game achievement toast banner in the overlay.
    func showAchievementToast(icon: String = "🏆", title: String, body: String) {
        let toast = MacrodroidAchievementToastView()
        toast.show(icon: icon, title: title, body: body, in: self)
    }

    func updateMouseLockState(_ locked: Bool) {
        isMouseAimLocked = locked
        mouseLockButton.title = locked ? "  Release Mouse Aim (F10 / ⌥)" : "  Lock Mouse Aim (F10 / ⌥)"
        mouseLockButton.contentTintColor = locked ? NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.45, alpha: 1.0) : .white
    }

    func updatePlayTime(sessionSeconds: Int, totalSeconds: Int) {
        let sessionStr: String
        if sessionSeconds < 60 {
            sessionStr = "\(max(0, sessionSeconds))s"
        } else {
            let m = sessionSeconds / 60
            if m >= 60 {
                let h = m / 60
                let remM = m % 60
                sessionStr = "\(h)h \(remM)m"
            } else {
                sessionStr = "\(m)m"
            }
        }

        let totalStr: String
        if totalSeconds < 60 {
            totalStr = totalSeconds > 0 ? "< 1m" : "0m"
        } else {
            let m = (totalSeconds / 60) % 60
            let h = totalSeconds / 3600
            if h > 0 {
                totalStr = "\(h)h \(m)m"
            } else {
                totalStr = "\(m)m"
            }
        }

        playTimeBadge.stringValue = "⏱️ Session: \(sessionStr) · Total: \(totalStr)"
    }

    func updateGamepadState(connectedName: String?) {
        if let name = connectedName, !name.isEmpty {
            gamepadStatusBadge.stringValue = "🎮 \(name)"
            gamepadStatusBadge.textColor = NSColor(calibratedRed: 0.0, green: 0.95, blue: 0.45, alpha: 1.0)
            gamepadStatusBadge.layer?.borderColor = NSColor(calibratedRed: 0.0, green: 0.95, blue: 0.45, alpha: 0.4).cgColor
        } else {
            gamepadStatusBadge.stringValue = "⌨️ Keyboard & Mouse"
            gamepadStatusBadge.textColor = NSColor.white.withAlphaComponent(0.85)
            gamepadStatusBadge.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        }
    }

    func updateMuteState(_ isMuted: Bool) {
        if isMuted {
            muteButton.title = "  Unmute Game Sound"
            muteButton.contentTintColor = NSColor.systemOrange
            if let img = NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: "Unmute") {
                let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                muteButton.image = img.withSymbolConfiguration(config)
            }
        } else {
            muteButton.title = "  Mute Game Sound"
            muteButton.contentTintColor = .white
            if let img = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Mute") {
                let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                muteButton.image = img.withSymbolConfiguration(config)
            }
        }
    }

    // MARK: - Actions
    @objc private func resumeClicked() { onResumeRequested?() }
    @objc private func remapClicked() { onRemapRequested?() }
    @objc private func toggleKeysClicked() { onToggleKeymapVisibilityRequested?() }
    @objc private func resetKeymapClicked() { onResetKeymapRequested?() }
    @objc private func mouseLockClicked() { onMouseLockRequested?() }
    @objc private func fullscreenClicked() { onFullscreenRequested?() }
    @objc private func rotateClicked() { onRotateRequested?() }
    @objc private func freeformClicked() { onFreeformRequested?() }
    @objc private func muteClicked() { onToggleMuteRequested?() }
    @objc private func screenshotClicked() { onScreenshotRequested?() }
    @objc private func sharedFolderClicked() { onSharedFolderRequested?() }
    @objc private func settingsClicked() { onSettingsRequested?() }
    @objc private func exitClicked() { onExitGameRequested?() }

    @objc private func opacitySliderChanged() {
        onOpacityChanged?(opacitySlider.floatValue)
    }

    @objc private func refreshSegmentChanged() {
        let fps: Int
        switch refreshRateSegment.selectedSegment {
        case 1: fps = 90
        case 2: fps = 120
        case 3: fps = 144
        default: fps = 60
        }
        onRefreshRateChanged?(fps)
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if !cardContainer.frame.contains(location) {
            onResumeRequested?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        // Absorb right clicks so they don't leak into guest game
    }

    override func scrollWheel(with event: NSEvent) {
        // Absorb scroll gestures so they don't leak into guest game
    }

    override func magnify(with event: NSEvent) {
        // Absorb pinch/zoom gestures so they don't leak into guest game
    }
}


// MARK: - MacrodroidAchievementToastView
/// Glassmorphic achievement banner. Slides in from top-right, auto-dismisses after 5s.
@MainActor
final class MacrodroidAchievementToastView: NSView {

    private let displayDuration: TimeInterval = 5.0
    nonisolated(unsafe) private var dismissTimer: Timer?

    private let background = NSVisualEffectView()
    private let iconLabel   = NSTextField(labelWithString: "🏆")
    private let titleLabel  = NSTextField(labelWithString: "Achievement Unlocked!")
    private let bodyLabel   = NSTextField(labelWithString: "")
    private let progressBar = NSView()
    private var progressWidthConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
    }
    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        background.material = .hudWindow
        background.blendingMode = .withinWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1.0
        background.layer?.borderColor = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.0, alpha: 0.45).cgColor
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 320),
            heightAnchor.constraint(equalToConstant: 68)
        ])

        iconLabel.font = .systemFont(ofSize: 24)
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(iconLabel)

        titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.2, alpha: 1.0)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(titleLabel)

        bodyLabel.font = .systemFont(ofSize: 11, weight: .regular)
        bodyLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        bodyLabel.lineBreakMode = .byTruncatingTail
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(bodyLabel)

        progressBar.wantsLayer = true
        progressBar.layer?.backgroundColor = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.0, alpha: 0.7).cgColor
        progressBar.layer?.cornerRadius = 2
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(progressBar)

        progressWidthConstraint = progressBar.widthAnchor.constraint(equalToConstant: 296)
        NSLayoutConstraint.activate([
            iconLabel.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            iconLabel.centerYAnchor.constraint(equalTo: background.centerYAnchor, constant: -4),

            titleLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),

            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            bodyLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            progressBar.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            progressBar.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -6),
            progressBar.heightAnchor.constraint(equalToConstant: 3),
            progressWidthConstraint
        ])
    }

    func show(icon: String = "🏆", title: String, body: String, in parentView: NSView) {
        iconLabel.stringValue = icon
        titleLabel.stringValue = title
        bodyLabel.stringValue = body

        parentView.addSubview(self)
        NSLayoutConstraint.activate([
            trailingAnchor.constraint(equalTo: parentView.trailingAnchor, constant: -16),
            topAnchor.constraint(equalTo: parentView.topAnchor, constant: 12)
        ])

        alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }

        progressWidthConstraint.constant = 296
        layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = displayDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .linear)
            self.progressWidthConstraint.animator().constant = 0
        }

        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            self.animator().alphaValue = 0
        }, completionHandler: { self.removeFromSuperview() })
    }

    deinit { dismissTimer?.invalidate() }
}
