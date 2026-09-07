import AppKit

@MainActor
final class RuntimeSettingsWindowController: NSWindowController {
    private let experimentButton = NSPopUpButton()
    private let vCPUButton = NSPopUpButton()
    private let ramButton = NSPopUpButton()
    private let refreshButton = NSPopUpButton()
    private let flushButton = NSPopUpButton()
    private let policyButton = NSPopUpButton()
    private let closeBehaviorButton = NSPopUpButton()
    private let idleSuspendButton = NSPopUpButton()
    private let resultLabel = NSTextField(labelWithString: "")
    private var originalProfile: TFTMACRuntimeProfile
    var onSave: ((TFTMACRuntimeProfile, TFTMACRuntimeProfile) -> Void)?

    init(profile: TFTMACRuntimeProfile) {
        originalProfile = profile
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 610),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Macrodroid Settings & Performance Lab"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        configureContent(profile: profile)
    }

    required init?(coder: NSCoder) { nil }

    func refreshFromSavedProfile() {
        originalProfile = TFTMACRuntimeProfile.load()
        select(originalProfile.experimentPreset, in: experimentButton)
        select(originalProfile.vCPU, in: vCPUButton)
        select(originalProfile.ramMiB, in: ramButton)
        select(originalProfile.refreshHz, in: refreshButton)
        select(originalProfile.asgDrawFlushInterval, in: flushButton)
        select(EngineLaunchPolicy.load(), in: policyButton)
        select(EngineCloseBehavior.load(), in: closeBehaviorButton)
        select(IdleSuspendPreferences.loadTimeout(), in: idleSuspendButton)
        resultLabel.stringValue = "Changes are validated, logged, and applied on the next app launch."
    }

    private func configureContent(profile: TFTMACRuntimeProfile) {
        guard let window else { return }
        let effect = NSVisualEffectView()
        effect.material = .windowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = effect

        let title = NSTextField(labelWithString: "Settings & Performance Lab")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: "Configure engine background execution policies, hardware resource allocations, and host scheduling latency.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 3

        policyButton.addItems(withTitles: EngineLaunchPolicy.allCases.map(\.displayName))
        closeBehaviorButton.addItems(withTitles: EngineCloseBehavior.allCases.map(\.displayName))
        idleSuspendButton.addItems(withTitles: IdleSuspendTimeout.allCases.map(\.displayName))
        select(EngineLaunchPolicy.load(), in: policyButton)
        select(EngineCloseBehavior.load(), in: closeBehaviorButton)
        select(IdleSuspendPreferences.loadTimeout(), in: idleSuspendButton)

        experimentButton.addItems(withTitles: RuntimeExperimentPreset.selectableCases.map(\.displayName))
        vCPUButton.addItems(withTitles: TFTMACRuntimeProfile.supportedVCPU.map(String.init))
        ramButton.addItems(withTitles: TFTMACRuntimeProfile.supportedRAMMiB.map { "\($0) MiB" })
        refreshButton.addItems(withTitles: TFTMACRuntimeProfile.supportedRefreshHz.map { "\($0) Hz" })
        flushButton.addItems(withTitles: TFTMACRuntimeProfile.supportedASGDrawFlushIntervals.map { "\($0) µs" })
        for button in [vCPUButton, ramButton, refreshButton, flushButton] {
            button.isEnabled = false
            button.toolTip = "Locked for the controlled Combat Benchmark so the preset is the only changed variable."
        }
        select(profile.experimentPreset, in: experimentButton)
        select(profile.vCPU, in: vCPUButton)
        select(profile.ramMiB, in: ramButton)
        select(profile.refreshHz, in: refreshButton)
        select(profile.asgDrawFlushInterval, in: flushButton)

        let grid = NSGridView(views: [
            [fieldLabel("Engine startup mode"), policyButton],
            [fieldLabel("When window closes"), closeBehaviorButton],
            [fieldLabel("Idle suspend (vCPU sleep)"), idleSuspendButton],
            [fieldLabel("Launch experiment"), experimentButton],
            [fieldLabel("Virtual CPUs"), vCPUButton],
            [fieldLabel("Android RAM"), ramButton],
            [fieldLabel("Guest refresh target"), refreshButton],
            [fieldLabel("ASG draw flush interval"), flushButton],
            [fieldLabel("Play surface"), fixedValue("1920 × 1080 @ 320 dpi")],
            [fieldLabel("Graphics / audio"), fixedValue("Host GPU · CoreAudio")]
        ])
        grid.rowSpacing = 13
        grid.columnSpacing = 24
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false

        resultLabel.stringValue = "Changes are validated, logged, and applied on the next app launch."
        resultLabel.textColor = .secondaryLabelColor
        resultLabel.font = .systemFont(ofSize: 12)

        let baseline = NSButton(title: "Restore Proven Baseline", target: self, action: #selector(restoreBaseline(_:)))
        let save = NSButton(title: "Save Settings", target: self, action: #selector(saveSettings(_:)))
        save.keyEquivalent = "\r"
        save.bezelStyle = .rounded
        let buttons = NSStackView(views: [baseline, NSView(), save])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.distribution = .fill

        let stack = NSStackView(views: [title, subtitle, grid, resultLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -30),
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: effect.bottomAnchor, constant: -24),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            resultLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        return label
    }

    private func fixedValue(_ text: String) -> NSTextField {
        let value = NSTextField(labelWithString: text)
        value.textColor = .secondaryLabelColor
        return value
    }

    private func select(_ value: Int, in button: NSPopUpButton) {
        let candidate = button.itemTitles.first(where: { $0.split(separator: " ").first == "\(value)" })
        if let candidate { button.selectItem(withTitle: candidate) }
    }

    private func select(_ preset: RuntimeExperimentPreset, in button: NSPopUpButton) {
        button.selectItem(withTitle: preset.displayName)
    }

    private func select(_ policy: EngineLaunchPolicy, in button: NSPopUpButton) {
        button.selectItem(withTitle: policy.displayName)
    }

    private func select(_ behavior: EngineCloseBehavior, in button: NSPopUpButton) {
        button.selectItem(withTitle: behavior.displayName)
    }

    private func select(_ timeout: IdleSuspendTimeout, in button: NSPopUpButton) {
        button.selectItem(withTitle: timeout.displayName)
    }

    @objc private func restoreBaseline(_ sender: Any?) {
        let baseline = TFTMACRuntimeProfile.playable
        select(.control, in: experimentButton)
        select(baseline.vCPU, in: vCPUButton)
        select(baseline.ramMiB, in: ramButton)
        select(baseline.refreshHz, in: refreshButton)
        select(baseline.asgDrawFlushInterval, in: flushButton)
        select(EngineLaunchPolicy.alwaysBackground, in: policyButton)
        select(EngineCloseBehavior.keepWarm, in: closeBehaviorButton)
        select(IdleSuspendTimeout.fiveMinutes, in: idleSuspendButton)
        resultLabel.stringValue = "Proven baseline values selected. Save to keep them."
    }

    @objc private func saveSettings(_ sender: Any?) {
        if let policyTitle = policyButton.titleOfSelectedItem,
           let policy = EngineLaunchPolicy.allCases.first(where: { $0.displayName == policyTitle }) {
            policy.save()
        }
        if let closeTitle = closeBehaviorButton.titleOfSelectedItem,
           let closeBehavior = EngineCloseBehavior.allCases.first(where: { $0.displayName == closeTitle }) {
            closeBehavior.save()
        }
        if let idleTitle = idleSuspendButton.titleOfSelectedItem,
           let timeout = IdleSuspendTimeout.allCases.first(where: { $0.displayName == idleTitle }) {
            IdleSuspendPreferences.saveTimeout(timeout)
        }

        guard let preset = selectedExperimentPreset() else { return }
        let next = TFTMACRuntimeProfile.playable.with(experimentPreset: preset)
        next.save()
        onSave?(originalProfile, next)
        originalProfile = next
        resultLabel.stringValue = "Saved successfully. Applied for upcoming sessions."
    }

    private func selectedInteger(_ button: NSPopUpButton) -> Int? {
        button.titleOfSelectedItem?.split(separator: " ").first.flatMap { Int($0) }
    }

    private func selectedExperimentPreset() -> RuntimeExperimentPreset? {
        RuntimeExperimentPreset.selectableCases.first { $0.displayName == experimentButton.titleOfSelectedItem }
    }
}
