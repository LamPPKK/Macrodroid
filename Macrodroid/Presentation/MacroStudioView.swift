import AppKit

// MARK: - MacroStepRowView
/// Một dòng trong timeline hiển thị một MacroAction
@MainActor
final class MacroStepRowView: NSView {
    var action: MacroAction { didSet { refresh() } }
    var index: Int
    var onDelete: (() -> Void)?

    private let indexLabel   = NSTextField(labelWithString: "")
    private let iconLabel    = NSTextField(labelWithString: "")
    private let descLabel    = NSTextField(labelWithString: "")
    private let delayLabel   = NSTextField(labelWithString: "")
    private let deleteBtn    = NSButton()
    private let rowBG        = NSView()

    init(action: MacroAction, index: Int) {
        self.action = action
        self.index  = index
        super.init(frame: .zero)
        buildUI()
        refresh()
    }
    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        rowBG.wantsLayer = true
        rowBG.layer?.cornerRadius = 8
        rowBG.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        rowBG.layer?.borderWidth = 0.5
        rowBG.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        rowBG.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowBG)

        indexLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        indexLabel.textColor = NSColor.white.withAlphaComponent(0.35)
        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        rowBG.addSubview(indexLabel)

        iconLabel.font = .systemFont(ofSize: 14)
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        rowBG.addSubview(iconLabel)

        descLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        descLabel.textColor = .white
        descLabel.lineBreakMode = .byTruncatingTail
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        rowBG.addSubview(descLabel)

        delayLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        delayLabel.textColor = NSColor.white.withAlphaComponent(0.45)
        delayLabel.translatesAutoresizingMaskIntoConstraints = false
        rowBG.addSubview(delayLabel)

        deleteBtn.isBordered = false
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteTapped)
        if let img = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Delete") {
            deleteBtn.image = img.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        }
        deleteBtn.contentTintColor = NSColor.white.withAlphaComponent(0.30)
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        rowBG.addSubview(deleteBtn)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            rowBG.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowBG.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowBG.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            rowBG.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            indexLabel.leadingAnchor.constraint(equalTo: rowBG.leadingAnchor, constant: 10),
            indexLabel.centerYAnchor.constraint(equalTo: rowBG.centerYAnchor),
            indexLabel.widthAnchor.constraint(equalToConstant: 22),

            iconLabel.leadingAnchor.constraint(equalTo: indexLabel.trailingAnchor, constant: 6),
            iconLabel.centerYAnchor.constraint(equalTo: rowBG.centerYAnchor),

            descLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 8),
            descLabel.centerYAnchor.constraint(equalTo: rowBG.centerYAnchor),
            descLabel.trailingAnchor.constraint(lessThanOrEqualTo: delayLabel.leadingAnchor, constant: -8),

            delayLabel.trailingAnchor.constraint(equalTo: deleteBtn.leadingAnchor, constant: -8),
            delayLabel.centerYAnchor.constraint(equalTo: rowBG.centerYAnchor),

            deleteBtn.trailingAnchor.constraint(equalTo: rowBG.trailingAnchor, constant: -10),
            deleteBtn.centerYAnchor.constraint(equalTo: rowBG.centerYAnchor),
            deleteBtn.widthAnchor.constraint(equalToConstant: 18),
            deleteBtn.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    private func refresh() {
        indexLabel.stringValue = "\(index + 1)"
        switch action.type {
        case .touchDown:
            iconLabel.stringValue = "👆"
            let x = action.normalizedX.map { Int($0 * 100) } ?? 0
            let y = action.normalizedY.map { Int($0 * 100) } ?? 0
            descLabel.stringValue = "Touch Down at (\(x)%, \(y)%)"
            descLabel.textColor = NSColor(calibratedRed: 0.0, green: 0.9, blue: 0.5, alpha: 1.0)
        case .touchMove:
            iconLabel.stringValue = "↔️"
            let x = action.normalizedX.map { Int($0 * 100) } ?? 0
            let y = action.normalizedY.map { Int($0 * 100) } ?? 0
            descLabel.stringValue = "Drag to (\(x)%, \(y)%)"
            descLabel.textColor = NSColor(calibratedRed: 0.3, green: 0.7, blue: 1.0, alpha: 1.0)
        case .touchUp:
            iconLabel.stringValue = "☝️"
            descLabel.stringValue = "Touch Up"
            descLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        case .keyPress:
            iconLabel.stringValue = "⌨️"
            descLabel.stringValue = "Key: \(action.keyString ?? "?")"
            descLabel.textColor = NSColor.systemYellow
        case .delay:
            iconLabel.stringValue = "⏱️"
            descLabel.stringValue = "Delay \(action.delayAfterMS ?? 0)ms"
            descLabel.textColor = NSColor.white.withAlphaComponent(0.55)
        }
        delayLabel.stringValue = action.delayAfterMS.map { "+\($0)ms" } ?? ""
    }

    @objc private func deleteTapped() { onDelete?() }
}

// MARK: - MacroStudioView
/// Giao diện Macro Automation Studio với timeline editor, recording controls, và anti-detection config.
@MainActor
final class MacroStudioView: NSView {

    // MARK: - Callbacks
    var onStartRecording: (() -> Void)?
    var onStopRecording:  (() -> Void)?
    var onPlayMacro:      ((MacroSequence) -> Void)?
    var onSaveMacro:      ((MacroSequence) -> Void)?
    var onClose:          (() -> Void)?

    // MARK: - State
    private var sequence = MacroSequence(name: "New Macro", packageName: "", actions: [])
    private var isRecording = false
    nonisolated(unsafe) private var recordTimer: Timer?
    private var recordElapsed: Int = 0

    // MARK: - UI
    private let backdropEffect   = NSVisualEffectView()
    private let toolbar          = NSView()
    private let titleLabel       = NSTextField(labelWithString: "⚡ Macro Automation Studio")
    private let recordBtn        = NSButton()
    private let playBtn          = NSButton()
    private let saveBtn          = NSButton()
    private let closeBtn         = NSButton()
    private let timerLabel       = NSTextField(labelWithString: "00:00.000")
    private let stepCountLabel   = NSTextField(labelWithString: "0 steps")
    private let timelineScroll   = NSScrollView()
    private let timelineStack    = NSStackView()
    private let configPanel      = NSVisualEffectView()

    // Config controls
    private let repeatField      = NSTextField()
    private let speedSegment     = NSSegmentedControl(
        labels: ["0.5×","1×","2×","4×"], trackingMode: .selectOne, target: nil, action: nil)
    private let jitterToggle     = NSButton()
    private let jitterSlider     = NSSlider(value: 2.0, minValue: 0, maxValue: 5.0, target: nil, action: nil)
    private let jitterValueLabel = NSTextField(labelWithString: "±2px")
    private let macroNameField   = NSTextField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
    }
    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        backdropEffect.material = .fullScreenUI
        backdropEffect.blendingMode = .withinWindow
        backdropEffect.state = .active
        backdropEffect.wantsLayer = true
        backdropEffect.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.70).cgColor
        backdropEffect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdropEffect)
        NSLayoutConstraint.activate([
            backdropEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdropEffect.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdropEffect.topAnchor.constraint(equalTo: topAnchor),
            backdropEffect.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        buildToolbar()
        buildTimeline()
        buildConfigPanel()
    }

    // MARK: - Toolbar
    private func buildToolbar() {
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor(
            calibratedRed: 0.05, green: 0.08, blue: 0.12, alpha: 0.96).cgColor
        toolbar.layer?.borderWidth = 0.5
        toolbar.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        backdropEffect.addSubview(toolbar)

        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = NSColor(calibratedRed: 0.0, green: 0.9, blue: 0.48, alpha: 1.0)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(titleLabel)

        timerLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        timerLabel.textColor = NSColor.systemRed
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(timerLabel)

        stepCountLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        stepCountLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        stepCountLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(stepCountLabel)

        configToolbarBtn(recordBtn, title: "⏺ Record (⌥⌘R)", action: #selector(recordTapped))
        recordBtn.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.85).cgColor
        recordBtn.contentTintColor = .white

        configToolbarBtn(playBtn, title: "▶ Play (⌥⌘P)", action: #selector(playTapped))
        playBtn.layer?.backgroundColor = NSColor(
            calibratedRed: 0.0, green: 0.72, blue: 0.38, alpha: 0.85).cgColor
        playBtn.contentTintColor = .black

        configToolbarBtn(saveBtn, title: "💾 Save", action: #selector(saveTapped))
        configToolbarBtn(closeBtn, title: "✕ Close", action: #selector(closeTapped))

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: backdropEffect.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: backdropEffect.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: backdropEffect.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 52),

            titleLabel.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 20),
            titleLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            timerLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 20),
            timerLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            stepCountLabel.leadingAnchor.constraint(equalTo: timerLabel.trailingAnchor, constant: 14),
            stepCountLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            closeBtn.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -16),
            closeBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 90),
            closeBtn.heightAnchor.constraint(equalToConstant: 28),

            saveBtn.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -8),
            saveBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            saveBtn.widthAnchor.constraint(equalToConstant: 90),
            saveBtn.heightAnchor.constraint(equalToConstant: 28),

            playBtn.trailingAnchor.constraint(equalTo: saveBtn.leadingAnchor, constant: -8),
            playBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            playBtn.widthAnchor.constraint(equalToConstant: 140),
            playBtn.heightAnchor.constraint(equalToConstant: 28),

            recordBtn.trailingAnchor.constraint(equalTo: playBtn.leadingAnchor, constant: -8),
            recordBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            recordBtn.widthAnchor.constraint(equalToConstant: 150),
            recordBtn.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func configToolbarBtn(_ btn: NSButton, title: String, action: Selector) {
        btn.title = title
        btn.bezelStyle = .rounded
        btn.font = .systemFont(ofSize: 11, weight: .semibold)
        btn.target = self
        btn.action = action
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        btn.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(btn)
    }

    // MARK: - Timeline
    private func buildTimeline() {
        timelineScroll.hasVerticalScroller = true
        timelineScroll.hasHorizontalScroller = false
        timelineScroll.drawsBackground = false
        timelineScroll.translatesAutoresizingMaskIntoConstraints = false
        backdropEffect.addSubview(timelineScroll)

        timelineStack.orientation = .vertical
        timelineStack.alignment = .leading
        timelineStack.spacing = 0
        timelineStack.translatesAutoresizingMaskIntoConstraints = false
        timelineScroll.documentView = timelineStack

        NSLayoutConstraint.activate([
            timelineScroll.leadingAnchor.constraint(equalTo: backdropEffect.leadingAnchor, constant: 16),
            timelineScroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 16),
            timelineScroll.bottomAnchor.constraint(equalTo: backdropEffect.bottomAnchor, constant: -16),
            timelineScroll.widthAnchor.constraint(equalToConstant: 520),

            timelineStack.leadingAnchor.constraint(equalTo: timelineScroll.contentView.leadingAnchor),
            timelineStack.trailingAnchor.constraint(equalTo: timelineScroll.contentView.trailingAnchor),
            timelineStack.topAnchor.constraint(equalTo: timelineScroll.contentView.topAnchor)
        ])

        refreshTimeline()
    }

    private func refreshTimeline() {
        timelineStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, action) in sequence.actions.enumerated() {
            let row = MacroStepRowView(action: action, index: i)
            row.onDelete = { [weak self] in self?.deleteStep(i) }
            timelineStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: timelineStack.widthAnchor).isActive = true
        }
        if sequence.actions.isEmpty {
            let empty = NSTextField(labelWithString: "No steps recorded yet.\nPress ⏺ Record to start capturing actions.")
            empty.font = .systemFont(ofSize: 13, weight: .regular)
            empty.textColor = NSColor.white.withAlphaComponent(0.35)
            empty.alignment = .center
            empty.maximumNumberOfLines = 2
            empty.translatesAutoresizingMaskIntoConstraints = false
            timelineStack.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: timelineStack.widthAnchor).isActive = true
        }
        stepCountLabel.stringValue = "\(sequence.actions.count) step\(sequence.actions.count == 1 ? "" : "s")"
    }

    private func deleteStep(_ index: Int) {
        guard index < sequence.actions.count else { return }
        sequence.actions.remove(at: index)
        refreshTimeline()
    }

    // MARK: - Config Panel
    private func buildConfigPanel() {
        configPanel.material = .sidebar
        configPanel.blendingMode = .withinWindow
        configPanel.state = .active
        configPanel.wantsLayer = true
        configPanel.layer?.cornerRadius = 14
        configPanel.layer?.masksToBounds = true
        configPanel.layer?.borderWidth = 0.5
        configPanel.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        configPanel.translatesAutoresizingMaskIntoConstraints = false
        backdropEffect.addSubview(configPanel)

        NSLayoutConstraint.activate([
            configPanel.leadingAnchor.constraint(equalTo: timelineScroll.trailingAnchor, constant: 16),
            configPanel.trailingAnchor.constraint(equalTo: backdropEffect.trailingAnchor, constant: -16),
            configPanel.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 16),
            configPanel.bottomAnchor.constraint(equalTo: backdropEffect.bottomAnchor, constant: -16)
        ])

        func sectionTitle(_ text: String) -> NSTextField {
            let lbl = NSTextField(labelWithString: text)
            lbl.font = .systemFont(ofSize: 10, weight: .bold)
            lbl.textColor = NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.45, alpha: 0.85)
            lbl.translatesAutoresizingMaskIntoConstraints = false
            return lbl
        }
        func bodyLabel(_ text: String) -> NSTextField {
            let lbl = NSTextField(labelWithString: text)
            lbl.font = .systemFont(ofSize: 11, weight: .medium)
            lbl.textColor = NSColor.white.withAlphaComponent(0.60)
            lbl.translatesAutoresizingMaskIntoConstraints = false
            return lbl
        }

        let nameTitle   = sectionTitle("MACRO NAME")
        let repeatTitle = sectionTitle("LOOP SETTINGS")
        let speedTitle  = sectionTitle("PLAYBACK SPEED")
        let jitterTitle = sectionTitle("ANTI-DETECTION JITTER")
        let repeatLbl   = bodyLabel("Repeat count (0 = ∞):")
        let jitterLbl   = bodyLabel("Touch jitter radius:")

        macroNameField.placeholderString = "e.g. Auto-Farm Loop"
        macroNameField.font = .systemFont(ofSize: 12, weight: .semibold)
        macroNameField.textColor = .white
        macroNameField.backgroundColor = NSColor.white.withAlphaComponent(0.07)
        macroNameField.isBordered = false
        macroNameField.focusRingType = .none
        macroNameField.target = self
        macroNameField.action = #selector(nameChanged)
        macroNameField.translatesAutoresizingMaskIntoConstraints = false
        configPanel.addSubview(macroNameField)

        repeatField.placeholderString = "1"
        repeatField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        repeatField.textColor = .white
        repeatField.backgroundColor = NSColor.white.withAlphaComponent(0.07)
        repeatField.isBordered = false
        repeatField.focusRingType = .none
        repeatField.translatesAutoresizingMaskIntoConstraints = false
        configPanel.addSubview(repeatField)

        speedSegment.selectedSegment = 1
        speedSegment.target = self
        speedSegment.action = #selector(speedChanged)
        speedSegment.translatesAutoresizingMaskIntoConstraints = false
        configPanel.addSubview(speedSegment)

        jitterToggle.setButtonType(.switch)
        jitterToggle.title = "Enable Human Jitter"
        jitterToggle.font = .systemFont(ofSize: 11, weight: .medium)
        jitterToggle.state = .on
        jitterToggle.target = self
        jitterToggle.action = #selector(jitterToggled)
        jitterToggle.translatesAutoresizingMaskIntoConstraints = false
        configPanel.addSubview(jitterToggle)

        jitterSlider.target = self
        jitterSlider.action = #selector(jitterSliderChanged)
        jitterSlider.translatesAutoresizingMaskIntoConstraints = false
        configPanel.addSubview(jitterSlider)

        jitterValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        jitterValueLabel.textColor = NSColor(calibratedRed: 0.0, green: 0.9, blue: 0.48, alpha: 1.0)
        jitterValueLabel.translatesAutoresizingMaskIntoConstraints = false
        configPanel.addSubview(jitterValueLabel)

        for v in [nameTitle, repeatTitle, speedTitle, jitterTitle, repeatLbl, jitterLbl] {
            configPanel.addSubview(v)
        }

        NSLayoutConstraint.activate([
            nameTitle.topAnchor.constraint(equalTo: configPanel.topAnchor, constant: 16),
            nameTitle.leadingAnchor.constraint(equalTo: configPanel.leadingAnchor, constant: 16),

            macroNameField.topAnchor.constraint(equalTo: nameTitle.bottomAnchor, constant: 6),
            macroNameField.leadingAnchor.constraint(equalTo: configPanel.leadingAnchor, constant: 16),
            macroNameField.trailingAnchor.constraint(equalTo: configPanel.trailingAnchor, constant: -16),
            macroNameField.heightAnchor.constraint(equalToConstant: 28),

            repeatTitle.topAnchor.constraint(equalTo: macroNameField.bottomAnchor, constant: 18),
            repeatTitle.leadingAnchor.constraint(equalTo: nameTitle.leadingAnchor),

            repeatLbl.topAnchor.constraint(equalTo: repeatTitle.bottomAnchor, constant: 6),
            repeatLbl.leadingAnchor.constraint(equalTo: nameTitle.leadingAnchor),

            repeatField.topAnchor.constraint(equalTo: repeatLbl.bottomAnchor, constant: 4),
            repeatField.leadingAnchor.constraint(equalTo: nameTitle.leadingAnchor),
            repeatField.widthAnchor.constraint(equalToConstant: 80),
            repeatField.heightAnchor.constraint(equalToConstant: 26),

            speedTitle.topAnchor.constraint(equalTo: repeatField.bottomAnchor, constant: 18),
            speedTitle.leadingAnchor.constraint(equalTo: nameTitle.leadingAnchor),

            speedSegment.topAnchor.constraint(equalTo: speedTitle.bottomAnchor, constant: 6),
            speedSegment.leadingAnchor.constraint(equalTo: nameTitle.leadingAnchor),
            speedSegment.trailingAnchor.constraint(equalTo: configPanel.trailingAnchor, constant: -16),

            jitterTitle.topAnchor.constraint(equalTo: speedSegment.bottomAnchor, constant: 18),
            jitterTitle.leadingAnchor.constraint(equalTo: nameTitle.leadingAnchor),

            jitterToggle.topAnchor.constraint(equalTo: jitterTitle.bottomAnchor, constant: 6),
            jitterToggle.leadingAnchor.constraint(equalTo: nameTitle.leadingAnchor),

            jitterLbl.topAnchor.constraint(equalTo: jitterToggle.bottomAnchor, constant: 8),
            jitterLbl.leadingAnchor.constraint(equalTo: nameTitle.leadingAnchor),

            jitterSlider.topAnchor.constraint(equalTo: jitterLbl.bottomAnchor, constant: 4),
            jitterSlider.leadingAnchor.constraint(equalTo: nameTitle.leadingAnchor),
            jitterSlider.trailingAnchor.constraint(equalTo: jitterValueLabel.leadingAnchor, constant: -8),

            jitterValueLabel.centerYAnchor.constraint(equalTo: jitterSlider.centerYAnchor),
            jitterValueLabel.trailingAnchor.constraint(equalTo: configPanel.trailingAnchor, constant: -16),
            jitterValueLabel.widthAnchor.constraint(equalToConstant: 36)
        ])
    }

    // MARK: - Public API
    func loadSequence(_ seq: MacroSequence) {
        sequence = seq
        macroNameField.stringValue = seq.name
        repeatField.stringValue = "\(seq.repeatCount)"
        jitterToggle.state = seq.enableHumanJitter ? .on : .off
        switch seq.speedMultiplier {
        case 0.5: speedSegment.selectedSegment = 0
        case 2.0: speedSegment.selectedSegment = 2
        case 4.0: speedSegment.selectedSegment = 3
        default:  speedSegment.selectedSegment = 1
        }
        refreshTimeline()
    }

    func appendAction(_ action: MacroAction) {
        sequence.actions.append(action)
        refreshTimeline()
        // Scroll to bottom
        DispatchQueue.main.async { [weak self] in
            guard let sv = self?.timelineScroll else { return }
            sv.contentView.scroll(to: NSPoint(x: 0, y: sv.documentView?.bounds.maxY ?? 0))
        }
    }

    // MARK: - Recording timer
    private func startRecordTimer() {
        recordElapsed = 0
        recordTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordElapsed += 10
                let ms = (self?.recordElapsed ?? 0)
                let min = ms / 60000
                let sec = (ms % 60000) / 1000
                let centisec = (ms % 1000) / 10
                self?.timerLabel.stringValue = String(format: "%02d:%02d.%03d", min, sec, centisec)
            }
        }
    }
    private func stopRecordTimer() {
        recordTimer?.invalidate()
        recordTimer = nil
    }

    // MARK: - Actions
    @objc private func recordTapped() {
        isRecording.toggle()
        if isRecording {
            recordBtn.title = "⏹ Stop (⌥⌘R)"
            recordBtn.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.85).cgColor
            startRecordTimer()
            onStartRecording?()
        } else {
            recordBtn.title = "⏺ Record (⌥⌘R)"
            recordBtn.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.85).cgColor
            stopRecordTimer()
            onStopRecording?()
        }
    }
    @objc private func playTapped()  { onPlayMacro?(sequence) }
    @objc private func saveTapped()  {
        sequence.name = macroNameField.stringValue.isEmpty ? "Macro" : macroNameField.stringValue
        sequence.repeatCount = Int(repeatField.stringValue) ?? 1
        onSaveMacro?(sequence)
        saveBtn.title = "✓ Saved!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.saveBtn.title = "💾 Save" }
    }
    @objc private func closeTapped() { stopRecordTimer(); onClose?() }
    @objc private func nameChanged() { sequence.name = macroNameField.stringValue }
    @objc private func speedChanged() {
        let speeds: [Double] = [0.5, 1.0, 2.0, 4.0]
        sequence.speedMultiplier = speeds[speedSegment.selectedSegment]
    }
    @objc private func jitterToggled()  { sequence.enableHumanJitter = jitterToggle.state == .on }
    @objc private func jitterSliderChanged() {
        let v = jitterSlider.doubleValue
        jitterValueLabel.stringValue = String(format: "±%.0fpx", v)
    }

    deinit { recordTimer?.invalidate() }
}
