import AppKit

// MARK: - SettingsSection
enum SettingsSection: String, CaseIterable {
    case display    = "Display & Graphics"
    case engine     = "Engine & Virtualization"
    case controls   = "Controls & Gamepads"
    case audio      = "Audio & Communication"
    case telemetry  = "Telemetry & Benchmarks"
    case about      = "About & Hardware"

    var icon: String {
        switch self {
        case .display:   return "display"
        case .engine:    return "cpu.fill"
        case .controls:  return "gamecontroller.fill"
        case .audio:     return "speaker.wave.3.fill"
        case .telemetry: return "chart.xyaxis.line"
        case .about:     return "info.circle.fill"
        }
    }
    var emoji: String {
        switch self {
        case .display:   return "🖥️"
        case .engine:    return "⚡"
        case .controls:  return "🎮"
        case .audio:     return "🔊"
        case .telemetry: return "📊"
        case .about:     return "ℹ️"
        }
    }
}

// MARK: - SettingsSidebarItemView
@MainActor
final class SettingsSidebarItemView: NSView {
    let section: SettingsSection
    var onSelect: (() -> Void)?
    private(set) var isActive = false

    private let bg        = NSView()
    private let iconLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")

    init(section: SettingsSection) {
        self.section = section
        super.init(frame: .zero)
        buildUI()
    }
    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        bg.wantsLayer = true
        bg.layer?.cornerRadius = 8
        bg.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bg)

        iconLabel.stringValue = section.emoji
        iconLabel.font = .systemFont(ofSize: 16)
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(iconLabel)

        nameLabel.stringValue = section.rawValue
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = NSColor.white.withAlphaComponent(0.80)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            bg.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            bg.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            bg.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            bg.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            iconLabel.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 10),
            iconLabel.centerYAnchor.constraint(equalTo: bg.centerYAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -8)
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(click)
    }

    func setActive(_ active: Bool) {
        isActive = active
        bg.layer?.backgroundColor = active
            ? NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.45, alpha: 0.18).cgColor
            : NSColor.clear.cgColor
        nameLabel.textColor = active
            ? NSColor(calibratedRed: 0.0, green: 0.9, blue: 0.48, alpha: 1.0)
            : NSColor.white.withAlphaComponent(0.80)
        nameLabel.font = active
            ? .systemFont(ofSize: 12, weight: .semibold)
            : .systemFont(ofSize: 12, weight: .medium)
    }
    @objc private func tapped() { onSelect?() }
}

// MARK: - ModernSettingsView
/// macOS Sequoia-style settings window with sidebar navigation and content panels.
@MainActor
final class ModernSettingsView: NSView {

    var onClose: (() -> Void)?

    private var activeSection: SettingsSection = .display
    private var sidebarItems: [SettingsSidebarItemView] = []

    private let sidebar       = NSVisualEffectView()
    private let contentArea   = NSView()
    private let toolbar       = NSView()
    private let titleLabel    = NSTextField(labelWithString: "Settings")
    private let closeBtn      = NSButton()
    private let contentTitle  = NSTextField(labelWithString: "")
    private let contentScroll = NSScrollView()
    private let contentStack  = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
        showSection(.display)
    }
    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 820),
            heightAnchor.constraint(equalToConstant: 560)
        ])

        // Toolbar
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor(
            calibratedRed: 0.05, green: 0.08, blue: 0.12, alpha: 0.97).cgColor
        toolbar.layer?.borderWidth = 0.5
        toolbar.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbar)

        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = NSColor(calibratedRed: 0.0, green: 0.9, blue: 0.48, alpha: 1.0)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(titleLabel)

        closeBtn.title = "✕"
        closeBtn.isBordered = false
        closeBtn.font = .systemFont(ofSize: 14, weight: .semibold)
        closeBtn.contentTintColor = NSColor.white.withAlphaComponent(0.55)
        closeBtn.target = self
        closeBtn.action = #selector(closeTapped)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(closeBtn)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            closeBtn.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -16),
            closeBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor)
        ])

        // Sidebar
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active
        sidebar.wantsLayer = true
        sidebar.layer?.borderWidth = 0.5
        sidebar.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sidebar)

        let sidebarStack = NSStackView()
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 2
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarStack)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            sidebar.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 210),
            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 10)
        ])

        for section in SettingsSection.allCases {
            let item = SettingsSidebarItemView(section: section)
            item.onSelect = { [weak self] in self?.showSection(section) }
            sidebarStack.addArrangedSubview(item)
            item.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true
            sidebarItems.append(item)
        }

        // Content area
        contentArea.wantsLayer = true
        contentArea.layer?.backgroundColor = NSColor.clear.cgColor
        contentArea.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentArea)

        contentTitle.font = .systemFont(ofSize: 18, weight: .bold)
        contentTitle.textColor = .white
        contentTitle.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(contentTitle)

        contentScroll.hasVerticalScroller = true
        contentScroll.hasHorizontalScroller = false
        contentScroll.drawsBackground = false
        contentScroll.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(contentScroll)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.documentView = contentStack

        NSLayoutConstraint.activate([
            contentArea.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentArea.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            contentArea.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentTitle.topAnchor.constraint(equalTo: contentArea.topAnchor, constant: 24),
            contentTitle.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor, constant: 24),

            contentScroll.topAnchor.constraint(equalTo: contentTitle.bottomAnchor, constant: 16),
            contentScroll.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor, constant: 20),
            contentScroll.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor, constant: -20),
            contentScroll.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor, constant: -20),

            contentStack.leadingAnchor.constraint(equalTo: contentScroll.contentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: contentScroll.contentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: contentScroll.contentView.topAnchor)
        ])
    }

    // MARK: - Section routing
    private func showSection(_ section: SettingsSection) {
        activeSection = section
        sidebarItems.forEach { $0.setActive($0.section == section) }
        contentTitle.stringValue = "\(section.emoji)  \(section.rawValue)"
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch section {
        case .display:   buildDisplayContent()
        case .engine:    buildEngineContent()
        case .controls:  buildControlsContent()
        case .audio:     buildAudioContent()
        case .telemetry: buildTelemetryContent()
        case .about:     buildAboutContent()
        }
    }

    // MARK: - Content builders
    private func row(_ label: String, control: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 42).isActive = true

        let lbl = NSTextField(labelWithString: label)
        lbl.font = .systemFont(ofSize: 12, weight: .medium)
        lbl.textColor = NSColor.white.withAlphaComponent(0.80)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(lbl)
        container.addSubview(control)
        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            lbl.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func sectionHeader(_ text: String) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.font = .systemFont(ofSize: 10, weight: .bold)
        lbl.textColor = NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.45, alpha: 0.80)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }

    private func divider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private func addRows(_ views: [NSView]) {
        views.forEach {
            contentStack.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }
    }

    private func buildDisplayContent() {
        let resSegment = NSSegmentedControl(labels: ["720p", "1080p", "1440p", "4K"], trackingMode: .selectOne, target: nil, action: nil)
        resSegment.selectedSegment = 1
        resSegment.translatesAutoresizingMaskIntoConstraints = false

        let fpsSegment = NSSegmentedControl(labels: ["30 Hz", "60 Hz", "90 Hz", "120 Hz", "144 Hz"], trackingMode: .selectOne, target: nil, action: nil)
        fpsSegment.selectedSegment = 1
        fpsSegment.translatesAutoresizingMaskIntoConstraints = false

        let aaToggle = NSButton()
        aaToggle.setButtonType(.switch)
        aaToggle.title = "Enabled"
        aaToggle.state = .on
        aaToggle.translatesAutoresizingMaskIntoConstraints = false

        let hdrToggle = NSButton()
        hdrToggle.setButtonType(.switch)
        hdrToggle.title = "HDR / P3 Wide Color"
        hdrToggle.state = .off
        hdrToggle.translatesAutoresizingMaskIntoConstraints = false

        addRows([
            sectionHeader("RESOLUTION"),
            row("Default Resolution", control: resSegment),
            divider(),
            sectionHeader("REFRESH RATE"),
            row("ProMotion Target", control: fpsSegment),
            divider(),
            sectionHeader("IMAGE QUALITY"),
            row("Anti-Aliasing (MSAA)", control: aaToggle),
            row("HDR Display", control: hdrToggle)
        ])
    }

    private func buildEngineContent() {
        let cpuSlider = NSSlider(value: 4, minValue: 2, maxValue: 8, target: nil, action: nil)
        cpuSlider.numberOfTickMarks = 4
        cpuSlider.allowsTickMarkValuesOnly = true
        cpuSlider.translatesAutoresizingMaskIntoConstraints = false

        let ramSegment = NSSegmentedControl(labels: ["2 GB", "4 GB", "6 GB", "8 GB", "12 GB"], trackingMode: .selectOne, target: nil, action: nil)
        ramSegment.selectedSegment = 2
        ramSegment.translatesAutoresizingMaskIntoConstraints = false

        let launchSegment = NSSegmentedControl(labels: ["Always BG", "On-Demand"], trackingMode: .selectOne, target: nil, action: nil)
        launchSegment.selectedSegment = 1
        launchSegment.translatesAutoresizingMaskIntoConstraints = false

        let idleSuspend = NSButton()
        idleSuspend.setButtonType(.switch)
        idleSuspend.title = "Suspend engine when idle"
        idleSuspend.state = .on
        idleSuspend.translatesAutoresizingMaskIntoConstraints = false

        addRows([
            sectionHeader("VIRTUALIZATION"),
            row("vCPU Cores", control: cpuSlider),
            row("Guest RAM", control: ramSegment),
            divider(),
            sectionHeader("LAUNCH POLICY"),
            row("Background Engine", control: launchSegment),
            row("Idle Suspend", control: idleSuspend)
        ])
    }

    private func buildControlsContent() {
        let info = NSTextField(labelWithString: "🎮 No gamepad connected.\nConnect a DualSense, Xbox, or MFi controller via Bluetooth or USB.")
        info.font = .systemFont(ofSize: 12, weight: .regular)
        info.textColor = NSColor.white.withAlphaComponent(0.55)
        info.maximumNumberOfLines = 3
        info.lineBreakMode = .byWordWrapping
        info.translatesAutoresizingMaskIntoConstraints = false

        let deadzoneSlider = NSSlider(value: 0.10, minValue: 0, maxValue: 0.30, target: nil, action: nil)
        deadzoneSlider.translatesAutoresizingMaskIntoConstraints = false

        let hapticToggle = NSButton()
        hapticToggle.setButtonType(.switch)
        hapticToggle.title = "DualSense Haptic Feedback"
        hapticToggle.state = .on
        hapticToggle.translatesAutoresizingMaskIntoConstraints = false

        addRows([
            sectionHeader("CONNECTED GAMEPADS"),
            info,
            divider(),
            sectionHeader("ANALOG TUNING"),
            row("Deadzone Radius", control: deadzoneSlider),
            row("Haptic Feedback", control: hapticToggle)
        ])
    }

    private func buildAudioContent() {
        let micToggle = NSButton()
        micToggle.setButtonType(.switch)
        micToggle.title = "Route host mic to game"
        micToggle.state = .off
        micToggle.translatesAutoresizingMaskIntoConstraints = false

        let bufferSegment = NSSegmentedControl(labels: ["Low", "Med", "High"], trackingMode: .selectOne, target: nil, action: nil)
        bufferSegment.selectedSegment = 1
        bufferSegment.translatesAutoresizingMaskIntoConstraints = false

        addRows([
            sectionHeader("MICROPHONE"),
            row("Host Microphone", control: micToggle),
            divider(),
            sectionHeader("CORE AUDIO BUFFER"),
            row("Latency", control: bufferSegment)
        ])
    }

    private func buildTelemetryContent() {
        let exportBtn = NSButton()
        exportBtn.title = "📤 Export Diagnostic Report"
        exportBtn.bezelStyle = .rounded
        exportBtn.translatesAutoresizingMaskIntoConstraints = false

        let benchBtn = NSButton()
        benchBtn.title = "🏁 Run Combat Benchmark"
        benchBtn.bezelStyle = .rounded
        benchBtn.translatesAutoresizingMaskIntoConstraints = false

        let info = NSTextField(labelWithString: "Benchmarks measure average FPS, frametime variance, and GPU Metal load over a 30-second combat simulation. Results are saved to the Telemetry SQLite database.")
        info.font = .systemFont(ofSize: 11, weight: .regular)
        info.textColor = NSColor.white.withAlphaComponent(0.55)
        info.maximumNumberOfLines = 5
        info.lineBreakMode = .byWordWrapping
        info.translatesAutoresizingMaskIntoConstraints = false

        addRows([
            sectionHeader("DIAGNOSTICS"),
            info,
            exportBtn,
            divider(),
            sectionHeader("BENCHMARK"),
            benchBtn
        ])
    }

    private func buildAboutContent() {
        let chipInfo = NSTextField(labelWithString: "Chip: Apple Silicon (M-series)\nMetal 3 GPU: Active\nUnified Memory: Detected\nBuild: Macrodroid 5.4.0")
        chipInfo.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        chipInfo.textColor = NSColor.white.withAlphaComponent(0.75)
        chipInfo.maximumNumberOfLines = 6
        chipInfo.lineBreakMode = .byWordWrapping
        chipInfo.translatesAutoresizingMaskIntoConstraints = false

        let updateBtn = NSButton()
        updateBtn.title = "🔍 Check for Updates"
        updateBtn.bezelStyle = .rounded
        updateBtn.translatesAutoresizingMaskIntoConstraints = false

        addRows([
            sectionHeader("HARDWARE INFO"),
            chipInfo,
            divider(),
            sectionHeader("UPDATE"),
            updateBtn
        ])
    }

    @objc private func closeTapped() { onClose?() }
}
