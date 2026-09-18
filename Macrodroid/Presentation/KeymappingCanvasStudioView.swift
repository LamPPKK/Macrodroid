import AppKit

// MARK: - KeyNodeType
/// Các loại node phím có thể kéo-thả vào canvas
enum KeyNodeType: String, CaseIterable {
    case tap        = "Tap Button"
    case dpad       = "D-Pad / WASD"
    case smartAim   = "Smart Aim"
    case mobaSkill  = "MOBA Skill"
    case macroTrigger = "Macro Trigger"
    case swipe      = "Swipe / Drag"

    var icon: String {
        switch self {
        case .tap:           return "hand.tap.fill"
        case .dpad:          return "gamecontroller.fill"
        case .smartAim:      return "scope"
        case .mobaSkill:     return "bolt.circle.fill"
        case .macroTrigger:  return "play.circle.fill"
        case .swipe:         return "arrow.up.right.circle.fill"
        }
    }

    var emoji: String {
        switch self {
        case .tap:           return "🔘"
        case .dpad:          return "🕹️"
        case .smartAim:      return "🎯"
        case .mobaSkill:     return "⚔️"
        case .macroTrigger:  return "⚡"
        case .swipe:         return "👆"
        }
    }

    var color: NSColor {
        switch self {
        case .tap:          return NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.48, alpha: 1.0)
        case .dpad:         return NSColor(calibratedRed: 0.2, green: 0.5, blue: 1.0, alpha: 1.0)
        case .smartAim:     return NSColor(calibratedRed: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)
        case .mobaSkill:    return NSColor(calibratedRed: 1.0, green: 0.65, blue: 0.0, alpha: 1.0)
        case .macroTrigger: return NSColor(calibratedRed: 0.7, green: 0.3, blue: 1.0, alpha: 1.0)
        case .swipe:        return NSColor(calibratedRed: 0.0, green: 0.75, blue: 0.95, alpha: 1.0)
        }
    }
}

// MARK: - KeyNodeView
/// Một node phím trên canvas — có thể kéo di chuyển, click để chọn / mở inspector
@MainActor
final class KeyNodeView: NSView {
    let nodeType: KeyNodeType
    var keyLabel: String
    var normalizedPosition: CGPoint   // 0…1 relative to canvas
    var onSelected: ((KeyNodeView) -> Void)?
    var onMoved: ((KeyNodeView) -> Void)?

    private let background = NSVisualEffectView()
    private let iconLabel  = NSTextField(labelWithString: "")
    private let keyLabelField = NSTextField(labelWithString: "")

    private var isDragging = false
    private var dragOffset: CGPoint = .zero

    private(set) var isSelected = false

    init(type: KeyNodeType, label: String, normalizedPos: CGPoint) {
        self.nodeType = type
        self.keyLabel = label
        self.normalizedPosition = normalizedPos
        super.init(frame: NSRect(x: 0, y: 0, width: 56, height: 56))
        buildUI()
    }
    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        wantsLayer = true
        layer?.zPosition = 10

        background.material = .hudWindow
        background.blendingMode = .withinWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 28
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 2.0
        background.layer?.borderColor = nodeType.color.withAlphaComponent(0.75).cgColor
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        iconLabel.stringValue = nodeType.emoji
        iconLabel.font = .systemFont(ofSize: 20)
        iconLabel.alignment = .center
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(iconLabel)

        keyLabelField.stringValue = keyLabel
        keyLabelField.font = .systemFont(ofSize: 8.5, weight: .bold)
        keyLabelField.textColor = nodeType.color
        keyLabelField.alignment = .center
        keyLabelField.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(keyLabelField)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconLabel.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            iconLabel.topAnchor.constraint(equalTo: background.topAnchor, constant: 6),

            keyLabelField.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            keyLabelField.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -5),
            keyLabelField.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 2),
            keyLabelField.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -2)
        ])

        let trackArea = NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                       owner: self, userInfo: nil)
        addTrackingArea(trackArea)
    }

    func setSelected(_ sel: Bool) {
        isSelected = sel
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            background.layer?.borderWidth = sel ? 3.0 : 2.0
            background.layer?.borderColor = sel
                ? nodeType.color.cgColor
                : nodeType.color.withAlphaComponent(0.75).cgColor
            layer?.shadowOpacity = sel ? 0.6 : 0
            layer?.shadowRadius  = sel ? 8  : 0
            layer?.shadowColor   = nodeType.color.cgColor
        }
    }

    func updateKeyLabel(_ label: String) {
        keyLabel = label
        keyLabelField.stringValue = label
    }

    // MARK: Mouse handling
    override func mouseDown(with event: NSEvent) {
        isDragging = false
        let loc = convert(event.locationInWindow, from: nil)
        dragOffset = CGPoint(x: loc.x - frame.origin.x, y: loc.y - frame.origin.y)
    }

    override func mouseDragged(with event: NSEvent) {
        isDragging = true
        guard let sv = superview else { return }
        var loc = sv.convert(event.locationInWindow, from: nil)
        loc.x -= dragOffset.x
        loc.y -= dragOffset.y
        // Clamp within canvas
        loc.x = max(0, min(sv.bounds.width - frame.width, loc.x))
        loc.y = max(0, min(sv.bounds.height - frame.height, loc.y))
        setFrameOrigin(loc)
        // Update normalized position
        normalizedPosition = CGPoint(
            x: (loc.x + frame.width  / 2) / sv.bounds.width,
            y: (loc.y + frame.height / 2) / sv.bounds.height
        )
        onMoved?(self)
    }

    override func mouseUp(with event: NSEvent) {
        if !isDragging { onSelected?(self) }
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.animator().alphaValue = 0.88
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.animator().alphaValue = 1.0
        }
    }
}

// MARK: - NodePaletteItemView
/// Một item trong thanh palette bên trái — kéo ra canvas để tạo node mới
@MainActor
final class NodePaletteItemView: NSView {
    let nodeType: KeyNodeType
    var onDropped: ((KeyNodeType, CGPoint) -> Void)?

    init(type: KeyNodeType) {
        self.nodeType = type
        super.init(frame: .zero)
        buildUI()
    }
    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = nodeType.color.withAlphaComponent(0.30).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let emojiLabel = NSTextField(labelWithString: nodeType.emoji)
        emojiLabel.font = .systemFont(ofSize: 22)
        emojiLabel.alignment = .center
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emojiLabel)

        let nameLabel = NSTextField(labelWithString: nodeType.rawValue)
        nameLabel.font = .systemFont(ofSize: 9.5, weight: .semibold)
        nameLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byWordWrapping
        nameLabel.maximumNumberOfLines = 2
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 72),
            widthAnchor.constraint(equalToConstant: 76),

            emojiLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emojiLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            nameLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            nameLabel.topAnchor.constraint(equalTo: emojiLabel.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)
        ])

        let trackArea = NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                       owner: self, userInfo: nil)
        addTrackingArea(trackArea)
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            self.layer?.backgroundColor = self.nodeType.color.withAlphaComponent(0.12).cgColor
            self.layer?.borderColor = self.nodeType.color.withAlphaComponent(0.55).cgColor
        }
    }
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            self.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
            self.layer?.borderColor = self.nodeType.color.withAlphaComponent(0.30).cgColor
        }
    }

    // Double-click to add at centre
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDropped?(nodeType, CGPoint(x: 0.5, y: 0.5)) }
    }
}

// MARK: - NodeInspectorPanel
/// Popover inspector cho node đang được chọn
@MainActor
final class NodeInspectorPanel: NSView {

    var onKeyLabelChanged: ((String) -> Void)?
    var onDelete: (() -> Void)?

    private let titleLabel  = NSTextField(labelWithString: "Node Inspector")
    private let typeLabel   = NSTextField(labelWithString: "")
    private let keyField    = NSTextField()
    private let posLabel    = NSTextField(labelWithString: "Position: —")
    private let deleteBtn   = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
    }
    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.15, alpha: 0.92).cgColor
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = NSColor(calibratedRed: 0.0, green: 0.9, blue: 0.48, alpha: 1.0)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        typeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        typeLabel.textColor = NSColor.white.withAlphaComponent(0.65)
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(typeLabel)

        let keyPrompt = NSTextField(labelWithString: "Key / Button:")
        keyPrompt.font = .systemFont(ofSize: 10.5, weight: .medium)
        keyPrompt.textColor = NSColor.white.withAlphaComponent(0.55)
        keyPrompt.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyPrompt)

        keyField.placeholderString = "e.g. W, Space, LMB..."
        keyField.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        keyField.textColor = .white
        keyField.backgroundColor = NSColor.white.withAlphaComponent(0.07)
        keyField.wantsLayer = true
        keyField.layer?.cornerRadius = 6
        keyField.isBordered = false
        keyField.focusRingType = .none
        keyField.target = self
        keyField.action = #selector(keyFieldChanged)
        keyField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyField)

        posLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        posLabel.textColor = NSColor.white.withAlphaComponent(0.45)
        posLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(posLabel)

        deleteBtn.title = "🗑 Delete Node"
        deleteBtn.bezelStyle = .rounded
        deleteBtn.contentTintColor = NSColor.systemRed.withAlphaComponent(0.85)
        deleteBtn.font = .systemFont(ofSize: 11, weight: .medium)
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteClicked)
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(deleteBtn)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 200),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),

            typeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            typeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            keyPrompt.topAnchor.constraint(equalTo: typeLabel.bottomAnchor, constant: 12),
            keyPrompt.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            keyField.topAnchor.constraint(equalTo: keyPrompt.bottomAnchor, constant: 4),
            keyField.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            keyField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            keyField.heightAnchor.constraint(equalToConstant: 28),

            posLabel.topAnchor.constraint(equalTo: keyField.bottomAnchor, constant: 8),
            posLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            deleteBtn.topAnchor.constraint(equalTo: posLabel.bottomAnchor, constant: 12),
            deleteBtn.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            deleteBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            deleteBtn.heightAnchor.constraint(equalToConstant: 28),
            deleteBtn.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
    }

    func configure(for node: KeyNodeView) {
        typeLabel.stringValue = "\(node.nodeType.emoji) \(node.nodeType.rawValue)"
        typeLabel.textColor = node.nodeType.color
        keyField.stringValue = node.keyLabel
        let x = Int(node.normalizedPosition.x * 100)
        let y = Int(node.normalizedPosition.y * 100)
        posLabel.stringValue = "Position: \(x)%, \(y)%"
    }

    func updatePosition(_ pos: CGPoint) {
        let x = Int(pos.x * 100)
        let y = Int(pos.y * 100)
        posLabel.stringValue = "Position: \(x)%, \(y)%"
    }

    @objc private func keyFieldChanged() { onKeyLabelChanged?(keyField.stringValue) }
    @objc private func deleteClicked() { onDelete?() }
}

// MARK: - CanvasGridView
/// Canvas nền với lưới toạ độ mờ nhẹ
private final class CanvasGridView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.0).setFill()
        dirtyRect.fill()

        // Grid lines every 40pt
        NSColor.white.withAlphaComponent(0.05).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 0.5

        var x: CGFloat = 0
        while x <= bounds.width {
            path.move(to: NSPoint(x: x, y: 0))
            path.line(to: NSPoint(x: x, y: bounds.height))
            x += 40
        }
        var y: CGFloat = 0
        while y <= bounds.height {
            path.move(to: NSPoint(x: 0, y: y))
            path.line(to: NSPoint(x: bounds.width, y: y))
            y += 40
        }
        path.stroke()

        // Centre crosshair
        NSColor.white.withAlphaComponent(0.12).setStroke()
        let cross = NSBezierPath()
        cross.lineWidth = 1.0
        cross.move(to: NSPoint(x: bounds.midX, y: 0))
        cross.line(to: NSPoint(x: bounds.midX, y: bounds.height))
        cross.move(to: NSPoint(x: 0, y: bounds.midY))
        cross.line(to: NSPoint(x: bounds.width, y: bounds.midY))
        cross.stroke()
    }
}

// MARK: - KeymappingCanvasStudioView
/// Full-screen overlay canvas studio cho kéo thả phím trực quan.
/// Mở bằng Option+Cmd+K khi game đang chạy.
@MainActor
final class KeymappingCanvasStudioView: NSView {

    // MARK: - Callbacks
    var onClose: (() -> Void)?
    var onSaveProfile: (([KeyNodeView]) -> Void)?

    // MARK: - State
    private var nodes: [KeyNodeView] = []
    private var selectedNode: KeyNodeView? { didSet { updateInspector() } }
    private var isLiveTestMode = false

    // MARK: - Sub-views
    private let backdropEffect = NSVisualEffectView()
    private let canvasContainer = NSView()
    private let gridView        = CanvasGridView()
    private let palettePanel    = NSVisualEffectView()
    private let inspectorPanel  = NodeInspectorPanel()
    private let toolbar         = NSView()

    // Toolbar controls
    private let titleLabel      = NSTextField(labelWithString: "⚙️ Keymapping Canvas Studio")
    private let liveTestToggle  = NSButton()
    private let saveBtn         = NSButton()
    private let closeBtn        = NSButton()
    private let clearBtn        = NSButton()
    private let nodeCountLabel  = NSTextField(labelWithString: "0 nodes")

    // MARK: - Init
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
    }
    required init?(coder: NSCoder) { nil }

    // MARK: - UI Construction
    private func buildUI() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        // Full-screen frosted backdrop
        backdropEffect.material = .fullScreenUI
        backdropEffect.blendingMode = .withinWindow
        backdropEffect.state = .active
        backdropEffect.wantsLayer = true
        backdropEffect.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        backdropEffect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdropEffect)

        NSLayoutConstraint.activate([
            backdropEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdropEffect.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdropEffect.topAnchor.constraint(equalTo: topAnchor),
            backdropEffect.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        buildToolbar()
        buildPalette()
        buildCanvas()
        buildInspector()
        wireInspector()
    }

    private func buildToolbar() {
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor(
            calibratedRed: 0.06, green: 0.09, blue: 0.13, alpha: 0.95).cgColor
        toolbar.layer?.borderWidth = 0.5
        toolbar.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        backdropEffect.addSubview(toolbar)

        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = NSColor(calibratedRed: 0.0, green: 0.9, blue: 0.48, alpha: 1.0)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(titleLabel)

        nodeCountLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        nodeCountLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        nodeCountLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(nodeCountLabel)

        configureToolbarBtn(liveTestToggle, title: "⚡ Live Test", action: #selector(toggleLiveTest))
        configureToolbarBtn(clearBtn, title: "🗑 Clear All", action: #selector(clearAll))
        configureToolbarBtn(saveBtn, title: "💾 Save Profile (⌘S)", action: #selector(saveProfile))
        configureToolbarBtn(closeBtn, title: "✕ Close (⌥⌘K)", action: #selector(closeCanvas))
        saveBtn.layer?.backgroundColor = NSColor(
            calibratedRed: 0.0, green: 0.75, blue: 0.40, alpha: 0.85).cgColor
        saveBtn.contentTintColor = .black

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: backdropEffect.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: backdropEffect.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: backdropEffect.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 48),

            titleLabel.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 96),
            titleLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            nodeCountLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),
            nodeCountLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            closeBtn.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -16),
            closeBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 140),
            closeBtn.heightAnchor.constraint(equalToConstant: 28),

            saveBtn.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -8),
            saveBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            saveBtn.widthAnchor.constraint(equalToConstant: 170),
            saveBtn.heightAnchor.constraint(equalToConstant: 28),

            clearBtn.trailingAnchor.constraint(equalTo: saveBtn.leadingAnchor, constant: -8),
            clearBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            clearBtn.widthAnchor.constraint(equalToConstant: 100),
            clearBtn.heightAnchor.constraint(equalToConstant: 28),

            liveTestToggle.trailingAnchor.constraint(equalTo: clearBtn.leadingAnchor, constant: -8),
            liveTestToggle.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            liveTestToggle.widthAnchor.constraint(equalToConstant: 110),
            liveTestToggle.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func configureToolbarBtn(_ btn: NSButton, title: String, action: Selector) {
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

    private func buildPalette() {
        palettePanel.material = .sidebar
        palettePanel.blendingMode = .withinWindow
        palettePanel.state = .active
        palettePanel.wantsLayer = true
        palettePanel.layer?.borderWidth = 0.5
        palettePanel.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        palettePanel.translatesAutoresizingMaskIntoConstraints = false
        backdropEffect.addSubview(palettePanel)

        let paletteTitle = NSTextField(labelWithString: "NODE PALETTE")
        paletteTitle.font = .systemFont(ofSize: 10, weight: .bold)
        paletteTitle.textColor = NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.45, alpha: 0.9)
        paletteTitle.translatesAutoresizingMaskIntoConstraints = false
        palettePanel.addSubview(paletteTitle)

        let hint = NSTextField(labelWithString: "Double-click to add at centre")
        hint.font = .systemFont(ofSize: 9, weight: .regular)
        hint.textColor = NSColor.white.withAlphaComponent(0.35)
        hint.translatesAutoresizingMaskIntoConstraints = false
        palettePanel.addSubview(hint)

        NSLayoutConstraint.activate([
            palettePanel.leadingAnchor.constraint(equalTo: backdropEffect.leadingAnchor),
            palettePanel.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            palettePanel.bottomAnchor.constraint(equalTo: backdropEffect.bottomAnchor),
            palettePanel.widthAnchor.constraint(equalToConstant: 96),

            paletteTitle.topAnchor.constraint(equalTo: palettePanel.topAnchor, constant: 14),
            paletteTitle.centerXAnchor.constraint(equalTo: palettePanel.centerXAnchor),

            hint.topAnchor.constraint(equalTo: paletteTitle.bottomAnchor, constant: 2),
            hint.centerXAnchor.constraint(equalTo: palettePanel.centerXAnchor),
            hint.leadingAnchor.constraint(equalTo: palettePanel.leadingAnchor, constant: 4),
            hint.trailingAnchor.constraint(equalTo: palettePanel.trailingAnchor, constant: -4)
        ])

        var lastAnchor = hint.bottomAnchor
        for (i, type) in KeyNodeType.allCases.enumerated() {
            let item = NodePaletteItemView(type: type)
            item.onDropped = { [weak self] t, pos in self?.addNode(type: t, normalizedPos: pos) }
            palettePanel.addSubview(item)
            NSLayoutConstraint.activate([
                item.topAnchor.constraint(equalTo: lastAnchor, constant: i == 0 ? 10 : 8),
                item.centerXAnchor.constraint(equalTo: palettePanel.centerXAnchor)
            ])
            lastAnchor = item.bottomAnchor
        }
    }

    private func buildCanvas() {
        canvasContainer.wantsLayer = true
        canvasContainer.layer?.backgroundColor = NSColor.clear.cgColor
        canvasContainer.translatesAutoresizingMaskIntoConstraints = false
        backdropEffect.addSubview(canvasContainer)

        gridView.translatesAutoresizingMaskIntoConstraints = false
        canvasContainer.addSubview(gridView)

        NSLayoutConstraint.activate([
            canvasContainer.leadingAnchor.constraint(equalTo: palettePanel.trailingAnchor),
            canvasContainer.trailingAnchor.constraint(equalTo: inspectorPanel.leadingAnchor),
            canvasContainer.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvasContainer.bottomAnchor.constraint(equalTo: backdropEffect.bottomAnchor),

            gridView.leadingAnchor.constraint(equalTo: canvasContainer.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: canvasContainer.trailingAnchor),
            gridView.topAnchor.constraint(equalTo: canvasContainer.topAnchor),
            gridView.bottomAnchor.constraint(equalTo: canvasContainer.bottomAnchor)
        ])

        // Click on empty canvas to deselect
        let click = NSClickGestureRecognizer(target: self, action: #selector(canvasClicked))
        canvasContainer.addGestureRecognizer(click)
    }

    private func buildInspector() {
        backdropEffect.addSubview(inspectorPanel)
        NSLayoutConstraint.activate([
            inspectorPanel.trailingAnchor.constraint(equalTo: backdropEffect.trailingAnchor),
            inspectorPanel.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 16)
        ])
    }

    private func wireInspector() {
        inspectorPanel.onKeyLabelChanged = { [weak self] label in
            self?.selectedNode?.updateKeyLabel(label)
        }
        inspectorPanel.onDelete = { [weak self] in
            guard let self, let node = self.selectedNode else { return }
            self.removeNode(node)
        }
    }

    // MARK: - Node management
    func addNode(type: KeyNodeType, normalizedPos: CGPoint) {
        let node = KeyNodeView(type: type,
                               label: defaultLabel(for: type),
                               normalizedPos: normalizedPos)
        node.onSelected = { [weak self] n in self?.selectNode(n) }
        node.onMoved    = { [weak self] n in self?.inspectorPanel.updatePosition(n.normalizedPosition) }
        canvasContainer.addSubview(node)
        nodes.append(node)
        layoutNode(node)
        selectNode(node)
        updateNodeCount()

        // Pop-in animation
        node.alphaValue = 0
        node.layer?.transform = CATransform3DMakeScale(0.6, 0.6, 1.0)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            node.animator().alphaValue = 1
            node.layer?.transform = CATransform3DIdentity
        }
    }

    private func layoutNode(_ node: KeyNodeView) {
        let canvas = canvasContainer.bounds
        guard canvas.width > 0, canvas.height > 0 else {
            // Defer layout until canvas has real size
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.layoutNode(node)
            }
            return
        }
        let x = node.normalizedPosition.x * canvas.width  - node.frame.width  / 2
        let y = node.normalizedPosition.y * canvas.height - node.frame.height / 2
        node.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func removeNode(_ node: KeyNodeView) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            node.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                node.removeFromSuperview()
            }
        })
        nodes.removeAll { $0 === node }
        if selectedNode === node { selectedNode = nil }
        updateNodeCount()
    }

    private func selectNode(_ node: KeyNodeView) {
        selectedNode?.setSelected(false)
        selectedNode = node
        node.setSelected(true)
    }

    private func updateInspector() {
        if let node = selectedNode {
            inspectorPanel.configure(for: node)
            inspectorPanel.alphaValue = 1
        } else {
            inspectorPanel.alphaValue = 0.4
        }
    }

    private func updateNodeCount() {
        nodeCountLabel.stringValue = "\(nodes.count) node\(nodes.count == 1 ? "" : "s")"
    }

    private func defaultLabel(for type: KeyNodeType) -> String {
        switch type {
        case .tap:          return "A"
        case .dpad:         return "WASD"
        case .smartAim:     return "RMB"
        case .mobaSkill:    return "Q"
        case .macroTrigger: return "F1"
        case .swipe:        return "Swipe"
        }
    }

    // MARK: - Actions
    @objc private func canvasClicked(_ gr: NSClickGestureRecognizer) {
        // Check the click wasn't on a node
        let loc = gr.location(in: canvasContainer)
        let hitNode = nodes.first { $0.frame.contains(loc) }
        if hitNode == nil {
            selectedNode?.setSelected(false)
            selectedNode = nil
        }
    }

    @objc private func toggleLiveTest() {
        isLiveTestMode.toggle()
        liveTestToggle.title = isLiveTestMode ? "⚡ Testing…" : "⚡ Live Test"
        liveTestToggle.contentTintColor = isLiveTestMode
            ? NSColor(calibratedRed: 0.0, green: 0.9, blue: 0.48, alpha: 1.0)
            : .white
        // Flash nodes to indicate test mode
        nodes.forEach { node in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                node.animator().alphaValue = self.isLiveTestMode ? 0.55 : 1.0
            }
        }
    }

    @objc private func clearAll() {
        nodes.forEach { $0.removeFromSuperview() }
        nodes.removeAll()
        selectedNode = nil
        updateNodeCount()
    }

    @objc private func saveProfile() {
        onSaveProfile?(nodes)
        // Brief success flash on save button
        saveBtn.title = "✓ Saved!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.saveBtn.title = "💾 Save Profile (⌘S)"
        }
    }

    @objc private func closeCanvas() { onClose?() }

    // MARK: - Public API
    /// Load nodes from an existing KeymapProfile
    func loadFromProfile(buttons: [(type: KeyNodeType, label: String, pos: CGPoint)]) {
        clearAll()
        for item in buttons {
            addNode(type: item.type, normalizedPos: item.pos)
            nodes.last?.updateKeyLabel(item.label)
        }
    }
}
