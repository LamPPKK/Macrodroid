import AppKit

@MainActor
final class RuntimeSettingsWindowController: NSWindowController {
    private let experimentButton = NSPopUpButton()
    private let vCPUButton = NSPopUpButton()
    private let ramButton = NSPopUpButton()
    private let refreshButton = NSPopUpButton()
    private let flushButton = NSPopUpButton()
    private let resultLabel = NSTextField(labelWithString: "")
    private var originalProfile: TFTMACRuntimeProfile
    var onSave: ((TFTMACRuntimeProfile, TFTMACRuntimeProfile) -> Void)?

    init(profile: TFTMACRuntimeProfile) {
        originalProfile = profile
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 510),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "TFTMAC Performance Lab"
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

        let title = NSTextField(labelWithString: "Performance Lab")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: "The proven 1920 × 1080, 320-dpi, host-GPU, CoreAudio and ANGLE/Vulkan/MoltenVK pipeline stays fixed. These bounded variables apply after restart so every run remains attributable and recoverable.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 3

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
        let save = NSButton(title: "Save for Next Launch", target: self, action: #selector(saveSettings(_:)))
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

    @objc private func restoreBaseline(_ sender: Any?) {
        let baseline = TFTMACRuntimeProfile.playable
        select(.control, in: experimentButton)
        select(baseline.vCPU, in: vCPUButton)
        select(baseline.ramMiB, in: ramButton)
        select(baseline.refreshHz, in: refreshButton)
        select(baseline.asgDrawFlushInterval, in: flushButton)
        resultLabel.stringValue = "Proven 6-CPU / 5120-MiB / 60-Hz / 800-µs values selected. Save to keep them."
    }

    @objc private func saveSettings(_ sender: Any?) {
        guard let preset = selectedExperimentPreset() else { return }
        let next = TFTMACRuntimeProfile.playable.with(experimentPreset: preset)
        next.save()
        onSave?(originalProfile, next)
        originalProfile = next
        resultLabel.stringValue = "Saved as \(next.identifier). Quit and relaunch TFTMAC to apply it."
    }

    private func selectedInteger(_ button: NSPopUpButton) -> Int? {
        button.titleOfSelectedItem?.split(separator: " ").first.flatMap { Int($0) }
    }

    private func selectedExperimentPreset() -> RuntimeExperimentPreset? {
        RuntimeExperimentPreset.selectableCases.first { $0.displayName == experimentButton.titleOfSelectedItem }
    }
}
