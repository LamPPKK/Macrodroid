import AppKit

// MARK: - InstanceInfo
/// Thông tin về một máy ảo Android đang quản lý
struct InstanceInfo: Identifiable {
    let id: Int
    var name: String
    var grpcPort: Int       // e.g. 5582
    var adbPort: Int        // e.g. 5038
    var adbSerial: String   // e.g. "emulator-5582"
    var runningApp: String? // package name của game đang chạy
    var cpuPercent: Double  // 0…100
    var ramMB: Int
    var isRunning: Bool
    var isMaster: Bool      // chỉ instance 0 là master

    static func defaultInstances() -> [InstanceInfo] {
        [
            InstanceInfo(id: 0, name: "Instance 1 (Master)", grpcPort: 5582, adbPort: 5038,
                         adbSerial: "emulator-5582", runningApp: nil,
                         cpuPercent: 0, ramMB: 0, isRunning: false, isMaster: true),
            InstanceInfo(id: 1, name: "Instance 2", grpcPort: 5584, adbPort: 5040,
                         adbSerial: "emulator-5584", runningApp: nil,
                         cpuPercent: 0, ramMB: 0, isRunning: false, isMaster: false),
            InstanceInfo(id: 2, name: "Instance 3", grpcPort: 5586, adbPort: 5042,
                         adbSerial: "emulator-5586", runningApp: nil,
                         cpuPercent: 0, ramMB: 0, isRunning: false, isMaster: false),
            InstanceInfo(id: 3, name: "Instance 4", grpcPort: 5588, adbPort: 5044,
                         adbSerial: "emulator-5588", runningApp: nil,
                         cpuPercent: 0, ramMB: 0, isRunning: false, isMaster: false)
        ]
    }
}

// MARK: - InstanceCardView
/// Thẻ hiển thị thông tin một máy ảo
@MainActor
final class InstanceCardView: NSView {
    var instance: InstanceInfo { didSet { refresh() } }

    var onStart:  (() -> Void)?
    var onStop:   (() -> Void)?
    var onSelect: (() -> Void)?

    private(set) var isSelectedCard = false

    // Sub-views
    private let background   = NSVisualEffectView()
    private let masterBadge  = NSTextField(labelWithString: "MASTER")
    private let nameLbl      = NSTextField(labelWithString: "")
    private let statusDot    = NSView()
    private let appLbl       = NSTextField(labelWithString: "")
    private let portLbl      = NSTextField(labelWithString: "")
    private let cpuBar       = NSView()
    private let cpuBarFill   = NSView()
    private let cpuLbl       = NSTextField(labelWithString: "")
    private let ramLbl       = NSTextField(labelWithString: "")
    private let startStopBtn = NSButton()

    init(instance: InstanceInfo) {
        self.instance = instance
        super.init(frame: .zero)
        buildUI()
        refresh()
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
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Master badge
        masterBadge.font = .systemFont(ofSize: 9, weight: .heavy)
        masterBadge.textColor = .black
        masterBadge.alignment = .center
        masterBadge.wantsLayer = true
        masterBadge.layer?.backgroundColor = NSColor(
            calibratedRed: 0.0, green: 0.85, blue: 0.45, alpha: 1.0).cgColor
        masterBadge.layer?.cornerRadius = 5
        masterBadge.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(masterBadge)

        // Status dot
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 5
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(statusDot)

        // Name
        nameLbl.font = .systemFont(ofSize: 13, weight: .bold)
        nameLbl.textColor = .white
        nameLbl.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(nameLbl)

        // App running
        appLbl.font = .systemFont(ofSize: 10.5, weight: .medium)
        appLbl.textColor = NSColor.white.withAlphaComponent(0.55)
        appLbl.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(appLbl)

        // Port info
        portLbl.font = .monospacedSystemFont(ofSize: 9.5, weight: .regular)
        portLbl.textColor = NSColor.white.withAlphaComponent(0.40)
        portLbl.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(portLbl)

        // CPU bar background
        cpuBar.wantsLayer = true
        cpuBar.layer?.cornerRadius = 3
        cpuBar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        cpuBar.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(cpuBar)

        // CPU bar fill
        cpuBarFill.wantsLayer = true
        cpuBarFill.layer?.cornerRadius = 3
        cpuBarFill.translatesAutoresizingMaskIntoConstraints = false
        cpuBar.addSubview(cpuBarFill)

        // CPU label
        cpuLbl.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
        cpuLbl.textColor = NSColor.white.withAlphaComponent(0.65)
        cpuLbl.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(cpuLbl)

        // RAM label
        ramLbl.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
        ramLbl.textColor = NSColor.white.withAlphaComponent(0.65)
        ramLbl.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(ramLbl)

        // Start/Stop button
        startStopBtn.bezelStyle = .rounded
        startStopBtn.font = .systemFont(ofSize: 10.5, weight: .semibold)
        startStopBtn.target = self
        startStopBtn.action = #selector(startStopClicked)
        startStopBtn.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(startStopBtn)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 200),
            heightAnchor.constraint(equalToConstant: 150),

            masterBadge.topAnchor.constraint(equalTo: background.topAnchor, constant: 10),
            masterBadge.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -10),
            masterBadge.widthAnchor.constraint(equalToConstant: 52),
            masterBadge.heightAnchor.constraint(equalToConstant: 16),

            statusDot.topAnchor.constraint(equalTo: background.topAnchor, constant: 14),
            statusDot.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            statusDot.widthAnchor.constraint(equalToConstant: 10),
            statusDot.heightAnchor.constraint(equalToConstant: 10),

            nameLbl.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 8),
            nameLbl.centerYAnchor.constraint(equalTo: statusDot.centerYAnchor),
            nameLbl.trailingAnchor.constraint(lessThanOrEqualTo: masterBadge.leadingAnchor, constant: -6),

            appLbl.topAnchor.constraint(equalTo: nameLbl.bottomAnchor, constant: 4),
            appLbl.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            appLbl.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),

            portLbl.topAnchor.constraint(equalTo: appLbl.bottomAnchor, constant: 2),
            portLbl.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),

            cpuBar.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            cpuBar.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),
            cpuBar.heightAnchor.constraint(equalToConstant: 6),
            cpuBar.topAnchor.constraint(equalTo: portLbl.bottomAnchor, constant: 10),

            cpuBarFill.leadingAnchor.constraint(equalTo: cpuBar.leadingAnchor),
            cpuBarFill.topAnchor.constraint(equalTo: cpuBar.topAnchor),
            cpuBarFill.bottomAnchor.constraint(equalTo: cpuBar.bottomAnchor),

            cpuLbl.topAnchor.constraint(equalTo: cpuBar.bottomAnchor, constant: 4),
            cpuLbl.leadingAnchor.constraint(equalTo: cpuBar.leadingAnchor),

            ramLbl.topAnchor.constraint(equalTo: cpuLbl.topAnchor),
            ramLbl.trailingAnchor.constraint(equalTo: cpuBar.trailingAnchor),

            startStopBtn.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -10),
            startStopBtn.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -10),
            startStopBtn.heightAnchor.constraint(equalToConstant: 26)
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(cardClicked))
        addGestureRecognizer(click)
    }

    private func refresh() {
        nameLbl.stringValue = instance.name
        appLbl.stringValue  = instance.runningApp.map { "▶ \($0)" } ?? "No app running"
        portLbl.stringValue = "gRPC:\(instance.grpcPort)  ADB:\(instance.adbSerial)"
        masterBadge.isHidden = !instance.isMaster

        // Status dot color
        statusDot.layer?.backgroundColor = instance.isRunning
            ? NSColor(calibratedRed: 0.0, green: 0.9, blue: 0.45, alpha: 1.0).cgColor
            : NSColor.white.withAlphaComponent(0.25).cgColor

        // CPU bar fill
        let cpu = instance.cpuPercent / 100.0
        let barColor: NSColor = cpu > 0.85 ? .systemRed : cpu > 0.6 ? .systemOrange
            : NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.45, alpha: 1.0)
        cpuBarFill.layer?.backgroundColor = barColor.cgColor
        // Width must be set after layout — defer
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let w = self.cpuBar.bounds.width * CGFloat(cpu)
            self.cpuBarFill.frame = CGRect(x: 0, y: 0, width: w, height: self.cpuBar.bounds.height)
        }
        cpuLbl.stringValue = instance.isRunning ? String(format: "CPU %.0f%%", instance.cpuPercent) : "CPU —"
        ramLbl.stringValue = instance.isRunning ? "\(instance.ramMB) MB" : "— MB"

        // Start/Stop button
        startStopBtn.title = instance.isRunning ? "⏹ Stop" : "▶ Start"
        startStopBtn.contentTintColor = instance.isRunning ? NSColor.systemRed : NSColor(
            calibratedRed: 0.0, green: 0.85, blue: 0.45, alpha: 1.0)

        // Border highlight for selected
        background.layer?.borderColor = isSelectedCard
            ? NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.45, alpha: 0.55).cgColor
            : NSColor.white.withAlphaComponent(0.10).cgColor
        background.layer?.borderWidth = isSelectedCard ? 1.5 : 1.0
    }

    func setSelected(_ sel: Bool) {
        isSelectedCard = sel
        refresh()
    }

    @objc private func startStopClicked() {
        if instance.isRunning { onStop?() } else { onStart?() }
    }
    @objc private func cardClicked() { onSelect?() }
}

// MARK: - WindowArrangementPreset
enum WindowArrangementPreset: String, CaseIterable {
    case grid2x2   = "2×2 Grid"
    case grid3x2   = "3×2 Grid"
    case cascade   = "Cascade"
    case tileAll   = "Tile All"
    case sideBySide = "Side by Side"

    var icon: String {
        switch self {
        case .grid2x2:    return "square.grid.2x2"
        case .grid3x2:    return "square.grid.3x2"
        case .cascade:    return "square.on.square"
        case .tileAll:    return "rectangle.split.3x1"
        case .sideBySide: return "rectangle.split.2x1"
        }
    }
}

// MARK: - MultiInstanceManagerView
/// Panel quản lý đa máy ảo với instance cards, window arrangement presets, và Input Sync Master.
@MainActor
final class MultiInstanceManagerView: NSView {

    // MARK: - Callbacks
    var onStartInstance:  ((Int) -> Void)?
    var onStopInstance:   ((Int) -> Void)?
    var onStartAll:       (() -> Void)?
    var onStopAll:        (() -> Void)?
    var onArrange:        ((WindowArrangementPreset) -> Void)?
    var onSyncMasterToggled: ((Bool) -> Void)?
    var onClose:          (() -> Void)?

    // MARK: - State
    private(set) var instances: [InstanceInfo] = InstanceInfo.defaultInstances()
    private var selectedIndex: Int = 0
    private var isSyncMasterEnabled = false
    nonisolated(unsafe) private var refreshTimer: Timer?

    // MARK: - Sub-views
    private let backdropEffect   = NSVisualEffectView()
    private let toolbar          = NSView()
    private let titleLabel       = NSTextField(labelWithString: "⚡ Multi-Instance Manager")
    private let startAllBtn      = NSButton()
    private let stopAllBtn       = NSButton()
    private let closeBtn         = NSButton()
    private let syncMasterToggle = NSButton()
    private let syncStatusLabel  = NSTextField(labelWithString: "Input Sync: OFF")
    private var cardViews:        [InstanceCardView] = []
    private let cardStack        = NSView()
    private let arrangeSection   = NSView()
    private let infoPanel        = NSVisualEffectView()
    private let infoPanelTitle   = NSTextField(labelWithString: "SELECTED INSTANCE")
    private let infoDetailLabel  = NSTextField(labelWithString: "Select an instance card")

    // MARK: - Init
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
        startRefreshTimer()
    }
    required init?(coder: NSCoder) { nil }

    // MARK: - UI Construction
    private func buildUI() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        backdropEffect.material = .fullScreenUI
        backdropEffect.blendingMode = .withinWindow
        backdropEffect.state = .active
        backdropEffect.wantsLayer = true
        backdropEffect.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.68).cgColor
        backdropEffect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdropEffect)
        NSLayoutConstraint.activate([
            backdropEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdropEffect.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdropEffect.topAnchor.constraint(equalTo: topAnchor),
            backdropEffect.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        buildToolbar()
        buildCardGrid()
        buildArrangeSection()
        buildInfoPanel()
    }

    private func buildToolbar() {
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor(
            calibratedRed: 0.05, green: 0.08, blue: 0.12, alpha: 0.96).cgColor
        toolbar.layer?.borderWidth = 0.5
        toolbar.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        backdropEffect.addSubview(toolbar)

        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = NSColor(calibratedRed: 0.0, green: 0.9, blue: 0.48, alpha: 1.0)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(titleLabel)

        configBtn(startAllBtn, title: "▶ Start All", action: #selector(startAllClicked))
        startAllBtn.layer?.backgroundColor = NSColor(
            calibratedRed: 0.0, green: 0.72, blue: 0.38, alpha: 0.90).cgColor
        startAllBtn.contentTintColor = .black

        configBtn(stopAllBtn, title: "⏹ Stop All", action: #selector(stopAllClicked))
        stopAllBtn.contentTintColor = NSColor.systemRed.withAlphaComponent(0.90)

        configBtn(syncMasterToggle, title: "🔗 Input Sync: OFF", action: #selector(syncToggled))

        syncStatusLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        syncStatusLabel.textColor = NSColor.white.withAlphaComponent(0.45)
        syncStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(syncStatusLabel)

        configBtn(closeBtn, title: "✕ Close (⌘W)", action: #selector(closeTapped))

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: backdropEffect.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: backdropEffect.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: backdropEffect.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 52),

            titleLabel.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 20),
            titleLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            closeBtn.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -16),
            closeBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 120),
            closeBtn.heightAnchor.constraint(equalToConstant: 28),

            stopAllBtn.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -8),
            stopAllBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            stopAllBtn.widthAnchor.constraint(equalToConstant: 100),
            stopAllBtn.heightAnchor.constraint(equalToConstant: 28),

            startAllBtn.trailingAnchor.constraint(equalTo: stopAllBtn.leadingAnchor, constant: -8),
            startAllBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            startAllBtn.widthAnchor.constraint(equalToConstant: 100),
            startAllBtn.heightAnchor.constraint(equalToConstant: 28),

            syncMasterToggle.trailingAnchor.constraint(equalTo: startAllBtn.leadingAnchor, constant: -16),
            syncMasterToggle.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            syncMasterToggle.widthAnchor.constraint(equalToConstant: 152),
            syncMasterToggle.heightAnchor.constraint(equalToConstant: 28),

            syncStatusLabel.trailingAnchor.constraint(equalTo: syncMasterToggle.leadingAnchor, constant: -8),
            syncStatusLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor)
        ])
    }

    private func buildCardGrid() {
        cardStack.wantsLayer = true
        cardStack.layer?.backgroundColor = NSColor.clear.cgColor
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        backdropEffect.addSubview(cardStack)

        NSLayoutConstraint.activate([
            cardStack.leadingAnchor.constraint(equalTo: backdropEffect.leadingAnchor, constant: 24),
            cardStack.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 24),
        ])

        for (i, instance) in instances.enumerated() {
            let card = InstanceCardView(instance: instance)
            card.onStart  = { [weak self] in self?.startInstance(i) }
            card.onStop   = { [weak self] in self?.stopInstance(i) }
            card.onSelect = { [weak self] in self?.selectCard(i) }
            cardStack.addSubview(card)
            cardViews.append(card)

            // 2×2 grid layout
            let col = i % 2
            let row = i / 2
            NSLayoutConstraint.activate([
                card.leadingAnchor.constraint(equalTo: cardStack.leadingAnchor, constant: CGFloat(col) * 216),
                card.topAnchor.constraint(equalTo: cardStack.topAnchor, constant: CGFloat(row) * 166)
            ])
        }

        NSLayoutConstraint.activate([
            cardStack.widthAnchor.constraint(equalToConstant: 432),
            cardStack.heightAnchor.constraint(equalToConstant: 332)
        ])

        selectCard(0)
    }

    private func buildArrangeSection() {
        let sectionTitle = NSTextField(labelWithString: "WINDOW ARRANGEMENT")
        sectionTitle.font = .systemFont(ofSize: 10, weight: .bold)
        sectionTitle.textColor = NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.45, alpha: 0.85)
        sectionTitle.translatesAutoresizingMaskIntoConstraints = false

        arrangeSection.wantsLayer = true
        arrangeSection.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.03).cgColor
        arrangeSection.layer?.cornerRadius = 12
        arrangeSection.layer?.borderWidth = 0.5
        arrangeSection.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        arrangeSection.translatesAutoresizingMaskIntoConstraints = false
        backdropEffect.addSubview(arrangeSection)
        arrangeSection.addSubview(sectionTitle)

        NSLayoutConstraint.activate([
            arrangeSection.leadingAnchor.constraint(equalTo: cardStack.leadingAnchor),
            arrangeSection.topAnchor.constraint(equalTo: cardStack.bottomAnchor, constant: 20),
            arrangeSection.widthAnchor.constraint(equalToConstant: 432),
            arrangeSection.heightAnchor.constraint(equalToConstant: 72),

            sectionTitle.topAnchor.constraint(equalTo: arrangeSection.topAnchor, constant: 10),
            sectionTitle.leadingAnchor.constraint(equalTo: arrangeSection.leadingAnchor, constant: 14)
        ])

        var prevAnchor = arrangeSection.leadingAnchor
        for preset in WindowArrangementPreset.allCases {
            let btn = NSButton()
            btn.title = preset.rawValue
            btn.bezelStyle = .rounded
            btn.font = .systemFont(ofSize: 10.5, weight: .medium)
            btn.toolTip = preset.rawValue
            if let img = NSImage(systemSymbolName: preset.icon, accessibilityDescription: preset.rawValue) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                btn.image = img.withSymbolConfiguration(cfg)
                btn.imagePosition = .imageLeading
            }
            btn.target = self
            btn.action = #selector(arrangeClicked(_:))
            btn.identifier = NSUserInterfaceItemIdentifier(preset.rawValue)
            btn.translatesAutoresizingMaskIntoConstraints = false
            arrangeSection.addSubview(btn)

            NSLayoutConstraint.activate([
                btn.leadingAnchor.constraint(equalTo: prevAnchor,
                    constant: prevAnchor === arrangeSection.leadingAnchor ? 14 : 8),
                btn.topAnchor.constraint(equalTo: sectionTitle.bottomAnchor, constant: 6),
                btn.heightAnchor.constraint(equalToConstant: 26)
            ])
            prevAnchor = btn.trailingAnchor
        }
    }

    private func buildInfoPanel() {
        infoPanel.material = .sidebar
        infoPanel.blendingMode = .withinWindow
        infoPanel.state = .active
        infoPanel.wantsLayer = true
        infoPanel.layer?.cornerRadius = 14
        infoPanel.layer?.masksToBounds = true
        infoPanel.layer?.borderWidth = 0.5
        infoPanel.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        infoPanel.translatesAutoresizingMaskIntoConstraints = false
        backdropEffect.addSubview(infoPanel)

        infoPanelTitle.font = .systemFont(ofSize: 10, weight: .bold)
        infoPanelTitle.textColor = NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.45, alpha: 0.85)
        infoPanelTitle.translatesAutoresizingMaskIntoConstraints = false
        infoPanel.addSubview(infoPanelTitle)

        infoDetailLabel.font = .systemFont(ofSize: 11, weight: .regular)
        infoDetailLabel.textColor = NSColor.white.withAlphaComponent(0.65)
        infoDetailLabel.maximumNumberOfLines = 0
        infoDetailLabel.lineBreakMode = .byWordWrapping
        infoDetailLabel.translatesAutoresizingMaskIntoConstraints = false
        infoPanel.addSubview(infoDetailLabel)

        NSLayoutConstraint.activate([
            infoPanel.leadingAnchor.constraint(equalTo: cardStack.trailingAnchor, constant: 24),
            infoPanel.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 24),
            infoPanel.widthAnchor.constraint(equalToConstant: 240),
            infoPanel.bottomAnchor.constraint(equalTo: arrangeSection.bottomAnchor),

            infoPanelTitle.topAnchor.constraint(equalTo: infoPanel.topAnchor, constant: 14),
            infoPanelTitle.leadingAnchor.constraint(equalTo: infoPanel.leadingAnchor, constant: 16),

            infoDetailLabel.topAnchor.constraint(equalTo: infoPanelTitle.bottomAnchor, constant: 8),
            infoDetailLabel.leadingAnchor.constraint(equalTo: infoPanel.leadingAnchor, constant: 16),
            infoDetailLabel.trailingAnchor.constraint(equalTo: infoPanel.trailingAnchor, constant: -16)
        ])
    }

    private func configBtn(_ btn: NSButton, title: String, action: Selector) {
        btn.title = title
        btn.bezelStyle = .rounded
        btn.font = .systemFont(ofSize: 11, weight: .medium)
        btn.target = self
        btn.action = action
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        btn.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(btn)
    }

    // MARK: - Logic
    private func selectCard(_ index: Int) {
        guard index < cardViews.count else { return }
        cardViews[selectedIndex].setSelected(false)
        selectedIndex = index
        cardViews[index].setSelected(true)
        refreshInfoPanel()
    }

    private func refreshInfoPanel() {
        let inst = instances[selectedIndex]
        infoDetailLabel.stringValue = """
        Name:      \(inst.name)
        gRPC Port: \(inst.grpcPort)
        ADB:       \(inst.adbSerial)
        Status:    \(inst.isRunning ? "Running ✅" : "Idle ⏸")
        App:       \(inst.runningApp ?? "—")
        CPU:       \(inst.isRunning ? String(format: "%.0f%%", inst.cpuPercent) : "—")
        RAM:       \(inst.isRunning ? "\(inst.ramMB) MB" : "—")
        Role:      \(inst.isMaster ? "Master (Input Source)" : "Slave (Sync Target)")
        """
    }

    private func startInstance(_ i: Int) {
        instances[i].isRunning = true
        cardViews[i].instance = instances[i]
        onStartInstance?(i)
        refreshInfoPanel()
    }

    private func stopInstance(_ i: Int) {
        instances[i].isRunning = false
        instances[i].cpuPercent = 0
        instances[i].ramMB = 0
        cardViews[i].instance = instances[i]
        onStopInstance?(i)
        refreshInfoPanel()
    }

    // MARK: - Public API
    func updateInstance(_ info: InstanceInfo) {
        guard info.id < instances.count else { return }
        instances[info.id] = info
        cardViews[info.id].instance = info
        if info.id == selectedIndex { refreshInfoPanel() }
    }

    // MARK: - Refresh timer (simulated telemetry update cadence)
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // In production: fetch real CPU/RAM via ADB or gRPC health probe
                self?.cardViews.forEach { _ in } // placeholder — real data pumped via updateInstance(_:)
            }
        }
    }

    // MARK: - Actions
    @objc private func startAllClicked() {
        for i in instances.indices { startInstance(i) }
        onStartAll?()
    }
    @objc private func stopAllClicked() {
        for i in instances.indices { stopInstance(i) }
        onStopAll?()
    }
    @objc private func syncToggled() {
        isSyncMasterEnabled.toggle()
        syncMasterToggle.title = isSyncMasterEnabled ? "🔗 Input Sync: ON" : "🔗 Input Sync: OFF"
        syncMasterToggle.contentTintColor = isSyncMasterEnabled
            ? NSColor(calibratedRed: 0.0, green: 0.9, blue: 0.48, alpha: 1.0) : .white
        syncStatusLabel.stringValue = isSyncMasterEnabled
            ? "Broadcasting to \(instances.filter(\.isRunning).count - 1) targets"
            : "Input Sync: OFF"
        onSyncMasterToggled?(isSyncMasterEnabled)
    }
    @objc private func arrangeClicked(_ sender: NSButton) {
        guard let preset = WindowArrangementPreset(rawValue: sender.identifier?.rawValue ?? "") else { return }
        onArrange?(preset)
    }
    @objc private func closeTapped() { onClose?() }

    deinit { refreshTimer?.invalidate() }
}
