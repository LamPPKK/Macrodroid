import AppKit
import MetalKit

private final class PresenterGPUState: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = [0, 0, 0]
    private var completedPresentations: UInt64 = 0

    func availableUploadSlot(excluding current: Int?) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return inFlight.indices.first(where: { inFlight[$0] == 0 && $0 != current })
            ?? inFlight.indices.first(where: { inFlight[$0] == 0 })
    }

    func beginPresentation(slot: Int) {
        lock.lock()
        inFlight[slot] += 1
        lock.unlock()
    }

    func completePresentation(slot: Int) {
        lock.lock()
        inFlight[slot] = max(0, inFlight[slot] - 1)
        completedPresentations &+= 1
        lock.unlock()
    }

    func completedCount() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return completedPresentations
    }
}

private final class HostPresentationTelemetry: @unchecked Sendable {
    private struct WindowState {
        var startedMonotonicNS: UInt64
        var submittedFrames = 0
        var completedFrames = 0
        var uniqueSourceUploads = 0
        var repeatedSourcePresents = 0
        var drawableMisses = 0
        var encoderMisses = 0
        var commandBufferMisses = 0
        var commandErrors = 0
        var completionLatenciesMS = [Double]()
        var gpuTimesMS = [Double]()
    }

    private let lock = NSLock()
    private var window = WindowState(startedMonotonicNS: DispatchTime.now().uptimeNanoseconds)
    // A 60 Hz presenter needs only about 60 entries/window; this cap protects telemetry itself
    // from becoming a source of memory pressure if the display rate changes.
    private let maximumSamples = 256

    func recordSubmitted(uniqueSourceUpload: Bool) {
        lock.lock()
        window.submittedFrames += 1
        if uniqueSourceUpload {
            window.uniqueSourceUploads += 1
        } else {
            window.repeatedSourcePresents += 1
        }
        lock.unlock()
    }

    func recordDrawableMiss() {
        lock.lock()
        window.drawableMisses += 1
        lock.unlock()
    }

    func recordEncoderMiss() {
        lock.lock()
        window.encoderMisses += 1
        lock.unlock()
    }

    func recordCommandBufferMiss() {
        lock.lock()
        window.commandBufferMisses += 1
        lock.unlock()
    }

    func recordCompletion(submittedMonotonicNS: UInt64, commandBuffer: MTLCommandBuffer) {
        let completedMonotonicNS = DispatchTime.now().uptimeNanoseconds
        let completionMS = Double(completedMonotonicNS &- submittedMonotonicNS) / 1_000_000
        let gpuStart = commandBuffer.gpuStartTime
        let gpuEnd = commandBuffer.gpuEndTime
        let gpuMS: Double? = gpuStart > 0 && gpuEnd >= gpuStart ? (gpuEnd - gpuStart) * 1_000 : nil
        // A completed-handler normally sees `.completed` or `.error`; treat any other terminal
        // outcome as failed so the persisted count does not hide cancelled/abnormal work.
        let wasError = commandBuffer.status != .completed || commandBuffer.error != nil

        lock.lock()
        window.completedFrames += 1
        if wasError { window.commandErrors += 1 }
        if window.completionLatenciesMS.count < maximumSamples {
            window.completionLatenciesMS.append(completionMS)
        }
        if let gpuMS, window.gpuTimesMS.count < maximumSamples {
            window.gpuTimesMS.append(gpuMS)
        }
        lock.unlock()
    }

    /// Drains a bounded approximately-one-second host window. Completion callbacks may arrive on
    /// Metal worker threads, so the whole snapshot/reset operation is lock-protected.
    func drainIfNeeded(nowMonotonicNS: UInt64) -> HostPresentationWindow? {
        lock.lock()
        defer { lock.unlock() }
        let elapsedNS = nowMonotonicNS &- window.startedMonotonicNS
        guard elapsedNS >= 1_000_000_000 else { return nil }
        let snapshot = window
        window = WindowState(startedMonotonicNS: nowMonotonicNS)
        return HostPresentationWindow(
            startedMonotonicNS: snapshot.startedMonotonicNS,
            endedMonotonicNS: nowMonotonicNS,
            submittedFrames: snapshot.submittedFrames,
            completedFrames: snapshot.completedFrames,
            uniqueSourceUploads: snapshot.uniqueSourceUploads,
            repeatedSourcePresents: snapshot.repeatedSourcePresents,
            // The shared schema exposes one presentation-miss field. Encoder and command-buffer
            // misses cannot produce a drawable either, so include them while retaining separate
            // in-memory counters above for their distinct collection paths.
            drawableMisses: snapshot.drawableMisses + snapshot.encoderMisses + snapshot.commandBufferMisses,
            commandErrors: snapshot.commandErrors,
            meanCompletionLatencyMS: Self.mean(snapshot.completionLatenciesMS),
            p95CompletionLatencyMS: Self.percentile(snapshot.completionLatenciesMS, percentile: 0.95),
            p99CompletionLatencyMS: Self.percentile(snapshot.completionLatenciesMS, percentile: 0.99),
            maximumCompletionLatencyMS: snapshot.completionLatenciesMS.max(),
            meanGPUTimeMS: Self.mean(snapshot.gpuTimesMS),
            p95GPUTimeMS: Self.percentile(snapshot.gpuTimesMS, percentile: 0.95),
            maximumGPUTimeMS: snapshot.gpuTimesMS.max()
        )
    }

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func percentile(_ values: [Double], percentile: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * percentile)) - 1))
        return sorted[index]
    }
}

// MARK: - In-Game Overlay Views

private final class NonInteractiveOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class KeyBadgeView: NSView {
    private let label = NSTextField(labelWithString: "")
    let keyIdentifier: String
    var keyCode: UInt16
    var buttonId: UUID?
    var normalizedX: Double
    var normalizedY: Double
    var isEditing: Bool = false {
        didSet {
            updateAppearance()
        }
    }
    var onPositionChanged: ((Double, Double) -> Void)?

    private var initialDragPoint: NSPoint?
    private var initialFrameOrigin: NSPoint?

    init(
        key: String,
        keyCode: UInt16 = 0,
        normalizedX: Double = 0.5,
        normalizedY: Double = 0.5,
        buttonId: UUID? = nil
    ) {
        self.keyIdentifier = key
        self.keyCode = keyCode
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.buttonId = buttonId
        super.init(frame: .zero)
        wantsLayer = true

        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        layer?.borderColor = NSColor(calibratedRed: 0.0, green: 0.85, blue: 1.0, alpha: 0.6).cgColor
        layer?.borderWidth = 1.0
        layer?.cornerRadius = 8

        if key == "FIRE" {
            label.stringValue = "🔥 FIRE"
            label.font = .systemFont(ofSize: 10, weight: .bold)
        } else if key == "ADS" {
            label.stringValue = "🎯 ADS"
            label.font = .systemFont(ofSize: 10, weight: .bold)
        } else if key == "AIM" {
            label.stringValue = "🕹 AIM"
            label.font = .systemFont(ofSize: 10, weight: .bold)
        } else {
            label.stringValue = key
            label.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        }
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    private func updateAppearance() {
        if isEditing {
            layer?.borderColor = NSColor.systemOrange.cgColor
            layer?.borderWidth = 1.5
        } else {
            layer?.borderColor = NSColor(calibratedRed: 0.0, green: 0.85, blue: 1.0, alpha: 0.6).cgColor
            layer?.borderWidth = 1.0
        }
    }

    func setHighlighted(_ highlighted: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            if highlighted {
                layer?.backgroundColor = NSColor(calibratedRed: 0.0, green: 0.85, blue: 1.0, alpha: 0.95).cgColor
                layer?.borderColor = NSColor.white.cgColor
                label.textColor = .black
            } else {
                layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
                layer?.borderColor = isEditing
                    ? NSColor.systemOrange.cgColor
                    : NSColor(calibratedRed: 0.0, green: 0.85, blue: 1.0, alpha: 0.6).cgColor
                label.textColor = .white
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEditing else { return }
        initialDragPoint = event.locationInWindow
        initialFrameOrigin = frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEditing, let start = initialDragPoint, let origin = initialFrameOrigin, let parent = superview else { return }
        let current = event.locationInWindow
        let deltaX = current.x - start.x
        let deltaY = current.y - start.y

        var newOrigin = NSPoint(x: origin.x + deltaX, y: origin.y + deltaY)
        newOrigin.x = max(0, min(parent.bounds.width - bounds.width, newOrigin.x))
        newOrigin.y = max(0, min(parent.bounds.height - bounds.height, newOrigin.y))
        frame.origin = newOrigin

        let midX = frame.midX
        let midY = frame.midY
        let displayedRect = (parent as? KeymappingOverlayView)?.displayedRect ?? parent.bounds
        let normX = displayedRect.width > 0 ? max(0.0, min(1.0, (midX - displayedRect.minX) / displayedRect.width)) : 0.5
        let normY = displayedRect.height > 0 ? max(0.0, min(1.0, 1.0 - ((midY - displayedRect.minY) / displayedRect.height))) : 0.5
        self.normalizedX = normX
        self.normalizedY = normY
        onPositionChanged?(normX, normY)
    }

    override func mouseUp(with event: NSEvent) {
        guard isEditing else { return }
        initialDragPoint = nil
        initialFrameOrigin = nil
    }
}

@MainActor
final class KeymappingOverlayView: NSView {
    private(set) var profile: KeymapProfile
    private var badges: [String: KeyBadgeView] = [:]
    private let hintView = NSVisualEffectView()
    private let hintLabel = NSTextField(labelWithString: "⌨️ KEYMAP OVERLAY · Press ⌘K to toggle · ⌥⌘K to edit")

    var currentResolution = FrameContract.standard1080p {
        didSet {
            layoutBadges()
        }
    }

    var displayedRect: CGRect {
        let mapper = ViewportMapper(
            sourceSize: CGSize(width: currentResolution.width, height: currentResolution.height),
            viewportSize: bounds.size
        )
        return mapper.displayedRect
    }

    func updateResolution(_ resolution: FrameContract.Resolution) {
        guard currentResolution != resolution else { return }
        self.currentResolution = resolution
    }

    var isEditing: Bool = false {
        didSet {
            updateEditingState()
        }
    }

    override init(frame frameRect: NSRect) {
        self.profile = KeymapProfile.defaultPreset(package: "default", appName: "Game")
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setupOverlayUI()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if !isEditing {
            return nil
        }
        return super.hitTest(point)
    }

    private func setupOverlayUI() {
        hintView.material = .hudWindow
        hintView.blendingMode = .withinWindow
        hintView.state = .active
        hintView.wantsLayer = true
        hintView.layer?.cornerRadius = 10
        hintView.layer?.masksToBounds = true
        hintView.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.9)
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintView.addSubview(hintLabel)
        addSubview(hintView)

        NSLayoutConstraint.activate([
            hintView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            hintView.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: hintView.topAnchor, constant: 4),
            hintLabel.bottomAnchor.constraint(equalTo: hintView.bottomAnchor, constant: -4),
            hintLabel.leadingAnchor.constraint(equalTo: hintView.leadingAnchor, constant: 12),
            hintLabel.trailingAnchor.constraint(equalTo: hintView.trailingAnchor, constant: -12)
        ])

        rebuildBadges()
    }

    func loadProfile(_ newProfile: KeymapProfile) {
        self.profile = newProfile
        alphaValue = CGFloat(newProfile.overlayOpacity)
        rebuildBadges()
    }

    private func rebuildBadges() {
        for (_, badge) in badges {
            badge.removeFromSuperview()
        }
        badges.removeAll()

        for btn in profile.buttons {
            let badge = KeyBadgeView(
                key: btn.key,
                keyCode: btn.keyCode,
                normalizedX: btn.normalizedX,
                normalizedY: btn.normalizedY,
                buttonId: btn.id
            )
            badge.isEditing = isEditing
            let id = btn.id
            badge.onPositionChanged = { [weak self] normX, normY in
                guard let self else { return }
                if let idx = self.profile.buttons.firstIndex(where: { $0.id == id }) {
                    self.profile.buttons[idx].normalizedX = normX
                    self.profile.buttons[idx].normalizedY = normY
                }
            }
            badges[btn.key] = badge
            addSubview(badge)
        }

        if let dpad = profile.dpad {
            let dpadOffset: Double = 0.05
            let dpadConfigs: [(key: String, code: UInt16, offX: Double, offY: Double)] = [
                ("W", dpad.wKeyCode, 0.0, -dpadOffset),
                ("A", dpad.aKeyCode, -dpadOffset, 0.0),
                ("S", dpad.sKeyCode, 0.0, dpadOffset),
                ("D", dpad.dKeyCode, dpadOffset, 0.0)
            ]
            for (k, code, offX, offY) in dpadConfigs {
                let badge = KeyBadgeView(
                    key: k,
                    keyCode: code,
                    normalizedX: max(0.05, min(0.95, dpad.normalizedCenterX + offX)),
                    normalizedY: max(0.05, min(0.95, dpad.normalizedCenterY + offY))
                )
                badge.isEditing = isEditing
                badges[k] = badge
                addSubview(badge)
            }
        }

        if let aim = profile.mouseAim {
            let aimBadge = KeyBadgeView(
                key: "AIM",
                keyCode: aim.toggleKeyCode,
                normalizedX: aim.normalizedCenterX,
                normalizedY: aim.normalizedCenterY
            )
            aimBadge.isEditing = isEditing
            aimBadge.onPositionChanged = { [weak self] normX, normY in
                self?.profile.mouseAim?.normalizedCenterX = normX
                self?.profile.mouseAim?.normalizedCenterY = normY
            }
            badges["AIM"] = aimBadge
            addSubview(aimBadge)

            if aim.leftClickFire {
                let fireBadge = KeyBadgeView(
                    key: "FIRE",
                    keyCode: 998,
                    normalizedX: aim.normalizedFireX,
                    normalizedY: aim.normalizedFireY
                )
                fireBadge.isEditing = isEditing
                fireBadge.onPositionChanged = { [weak self] normX, normY in
                    self?.profile.mouseAim?.normalizedFireX = normX
                    self?.profile.mouseAim?.normalizedFireY = normY
                }
                badges["FIRE"] = fireBadge
                addSubview(fireBadge)
            }

            if aim.rightClickADS {
                let adsBadge = KeyBadgeView(
                    key: "ADS",
                    keyCode: 999,
                    normalizedX: aim.normalizedADSX,
                    normalizedY: aim.normalizedADSY
                )
                adsBadge.isEditing = isEditing
                adsBadge.onPositionChanged = { [weak self] normX, normY in
                    self?.profile.mouseAim?.normalizedADSX = normX
                    self?.profile.mouseAim?.normalizedADSY = normY
                }
                badges["ADS"] = adsBadge
                addSubview(adsBadge)
            }
        }

        layoutBadges()
    }

    override func layout() {
        super.layout()
        layoutBadges()
    }

    private func layoutBadges() {
        let displayedRect = self.displayedRect
        guard displayedRect.width > 0, displayedRect.height > 0 else { return }

        for (_, badge) in badges {
            let badgeSize: CGFloat = {
                if badge.keyIdentifier == "SPACE" { return 72 }
                if badge.keyIdentifier == "FIRE" || badge.keyIdentifier == "ADS" || badge.keyIdentifier == "AIM" {
                    return 56
                }
                return 36
            }()
            let badgeHeight: CGFloat = 36
            let centerX = displayedRect.minX + CGFloat(badge.normalizedX) * displayedRect.width
            let centerY = displayedRect.minY + CGFloat(1.0 - badge.normalizedY) * displayedRect.height

            badge.frame = NSRect(
                x: centerX - badgeSize / 2,
                y: centerY - badgeHeight / 2,
                width: badgeSize,
                height: badgeHeight
            )
        }
    }

    private func updateEditingState() {
        for (_, badge) in badges {
            badge.isEditing = isEditing
        }
        if isEditing {
            hintLabel.stringValue = "🎯 KEYMAP EDITOR · Drag keys to position · Press ⌥⌘K to save & finish"
            hintView.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.35).cgColor
        } else {
            hintLabel.stringValue = "⌨️ KEYMAP OVERLAY · Press ⌘K to toggle · ⌥⌘K to edit"
            hintView.layer?.backgroundColor = nil
        }
    }

    @discardableResult
    func toggleEditing() -> Bool {
        isEditing.toggle()
        if !isEditing {
            KeymapProfileStore.saveProfile(profile)
        }
        return isEditing
    }

    func highlight(event: NSEvent, isDown: Bool) {
        if let badge = badges.values.first(where: { $0.keyCode == event.keyCode }) {
            badge.setHighlighted(isDown)
            return
        }
        let key: String
        if event.keyCode == 49 {
            key = "SPACE"
        } else if let chars = event.charactersIgnoringModifiers?.uppercased(), let first = chars.first {
            key = String(first)
        } else {
            return
        }
        badges[key]?.setHighlighted(isDown)
    }
}

@MainActor
final class EmbeddedEmulatorView: MTKView, MTKViewDelegate {
    var onTouchInput: ((TouchInput) -> Void)?
    var onMouseInput: ((Int32, Int32, Int32) -> Void)?
    var onKeyboardInput: ((String?, String?) -> Void)?
    var onPasteInput: ((String) -> Void)?
    var onPresentationSample: ((PresentationSample) -> Void)?
    var onHostPresentationWindow: ((HostPresentationWindow) -> Void)?
    var onFPSChanged: ((Double) -> Void)?
    var onFilesDropped: (([URL]) -> Void)?
    var onRotateRequested: (() -> Void)?
    var onScreenshotRequested: (() -> Void)?
    var onKeymapToggleRequested: (() -> Void)?
    var onMouseLockToggleRequested: (() -> Void)?
    var onFreeformRequested: (() -> Void)?
    var onSharedFolderRequested: (() -> Void)?
    var onScrollGesture: ((Int32, Int32, CGFloat, CGFloat) -> Void)?
    var onPinchGesture: ((Int32, Int32, CGFloat) -> Void)?
    var onIMEToggleRequested: (() -> Void)?
    var onTaskSwitcherRequested: (() -> Void)?
    var onAndroidBackRequested: (() -> Void)?
    var onAndroidHomeRequested: (() -> Void)?
    var onAndroidRecentsRequested: (() -> Void)?
    var onKeymapEditorToggleRequested: (() -> Void)?
    var onGamepadStatusChanged: ((GamepadState?) -> Void)?
    var onMacroStatusChanged: ((String) -> Void)?
    var onMacroRecordToggleRequested: (() -> Void)?
    var onMacroPlayToggleRequested: (() -> Void)?
    var onOpenSettingsRequested: (() -> Void)?
    var onFullscreenRequested: (() -> Void)?
    var onGPGOverlayToggleRequested: (() -> Void)?
    var onExitGameRequested: (() -> Void)?
    var onKeymapResetRequested: (() -> Void)?
    var onAudioMuteToggleRequested: ((Bool) -> Void)?
    private(set) var targetRefreshRate: Int = 60
    private(set) var isBackgroundThrottled: Bool = false
    private(set) var isAudioMuted: Bool = false
    private(set) var sessionStartTime: Date?
    private var initialTotalPlayTimeSeconds: Int = 0
    private var sessionDurationTask: Task<Void, Never>?

    var currentSessionDurationSeconds: Int {
        guard let sessionStartTime else { return 0 }
        return max(0, Int(Date().timeIntervalSince(sessionStartTime)))
    }

    let gpgOverlay = GooglePlayGamesOverlayView()
    private var wasMouseAimLockedBeforeOverlay: Bool = false

    var isKeymapEnabled = true
    var isVietnameseIMEEnabled = false
    private var markedTextStorage = NSMutableAttributedString()
    private var markedTextSelectionRange = NSRange(location: NSNotFound, length: 0)

    private(set) var isMouseLocked = false
    private var previousModifierFlags: NSEvent.ModifierFlags = []
    private let keymappingOverlay = KeymappingOverlayView()
    private let shutterFlashView = NonInteractiveOverlayView()
    private var dpadWPressed = false
    private var dpadAPressed = false
    private var dpadSPressed = false
    private var dpadDPressed = false
    private var lastDpadTouch: (x: Int32, y: Int32)?
    private var gamepadDpadUpPressed = false
    private var gamepadDpadDownPressed = false
    private var gamepadDpadLeftPressed = false
    private var gamepadDpadRightPressed = false
    private var lastGamepadDpadTouch: (x: Int32, y: Int32)?
    private var lastGamepadStickTouch: (x: Int32, y: Int32)?
    private var lastMacroActionTimestamp: UInt64 = 0
    private var activeKeymapTouches: [String: (x: Int32, y: Int32)] = [:]
    private var trackingArea: NSTrackingArea?
    private var isSmartCursorReleased = false
    private var currentAimStrokeOffset: CGPoint = .zero
    private var isAimTouchActive = false
    private var activeFireTouch: TouchPoint?
    private var isLeftClickFiring = false
    private var activeADSTouch: TouchPoint?
    private var isRightClickAiming = false
    private(set) var currentPackageName: String?
    private(set) var currentAppName: String?
    private(set) var isMacroRecording = false
    private(set) var isMacroPlaying = false
    private var activeMacroSequence = MacroSequence(name: "Macro", packageName: "default")
    private var macroPlaybackTimer: DispatchSourceTimer?
    private var currentResolution = FrameContract.standard1080p

    private let mailbox: LatestFrameMailbox
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let gpuState = PresenterGPUState()
    private let hostPresentationTelemetry = HostPresentationTelemetry()
    private var textures: [MTLTexture?] = [nil, nil, nil]
    private var currentTextureSlot: Int?
    private var lastPresentedSequence: UInt32?
    private var lastSampleTime = CACurrentMediaTime()
    private var lastSamplePresentationCount: UInt64 = 0
    private var lastSampleReceivedCount: UInt64 = 0
    private var lastSourceFPS: Double = 0
    private var lastPresentationFPS: Double = 0
    private var lastHostGPUTimeP95MS: Double?
    private var gameFrameWindow: GameFrameTelemetryWindow?
    private var primaryTouchSequence = PrimaryTouchSequence()
    private let statusLabel = NSTextField(labelWithString: "Preparing native Android runtime…")
    private let fpsLabel = NSTextField(labelWithString: "0 FPS")
    private let dropOverlayView = NSView()
    private let dropLabel = NSTextField(labelWithString: "Drop files to transfer to Android\nor drop .apk to install")

    init(frame: NSRect, mailbox: LatestFrameMailbox) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Macrodroid requires a Metal-capable GPU")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Macrodroid could not create its persistent Metal command queue")
        }
        self.mailbox = mailbox
        self.commandQueue = commandQueue
        do {
            pipeline = try Self.makePipeline(device: device)
        } catch {
            fatalError("Macrodroid could not create its native frame pipeline: \(error.localizedDescription)")
        }
        super.init(frame: frame, device: device)
        framebufferOnly = true
        colorPixelFormat = .bgra8Unorm_srgb
        preferredFramesPerSecond = 60
        enableSetNeedsDisplay = false
        isPaused = false
        clearColor = MTLClearColorMake(0.015, 0.018, 0.025, 1.0)
        delegate = self
        registerForDraggedTypes([.fileURL])
        configureOverlays()
        updatePerformanceOverlay()
        setupGamepadHandlers()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        sessionDurationTask?.cancel()
        if isMouseLocked {
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
            NSCursor.unhide()
        }
    }

    override var acceptsFirstResponder: Bool { true }

    func setStatus(_ text: String, isError: Bool) {
        // Informational runtime state belongs in SQL telemetry, not over the
        // Android display. Only a terminal error may interrupt the game view.
        guard isError, !text.isEmpty else {
            statusLabel.isHidden = true
            return
        }
        statusLabel.stringValue = text
        statusLabel.textColor = .systemRed
        statusLabel.isHidden = false
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, isMouseLocked {
            setMouseLocked(false)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [
            .mouseMoved,
            .activeInKeyWindow,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        window?.acceptsMouseMovedEvents = true
    }

    override func resignFirstResponder() -> Bool {
        if isMouseLocked {
            setMouseLocked(false)
        }
        return super.resignFirstResponder()
    }

    func flashShutter() {
        shutterFlashView.alphaValue = 0.75
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            shutterFlashView.animator().alphaValue = 0.0
        }
    }

    func captureScreenshot() -> NSImage? {
        if let slot = currentTextureSlot, let texture = textures[slot] {
            let width = texture.width
            let height = texture.height
            let bytesPerRow = width * FrameContract.bytesPerPixel
            var rawData = Data(count: height * bytesPerRow)
            let copied: Bool = rawData.withUnsafeMutableBytes { ptr in
                guard let baseAddress = ptr.baseAddress else { return false }
                texture.getBytes(
                    baseAddress,
                    bytesPerRow: bytesPerRow,
                    from: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0
                )
                return true
            }
            if copied,
               let provider = CGDataProvider(data: rawData as CFData),
               let cgImage = CGImage(
                   width: width,
                   height: height,
                   bitsPerComponent: 8,
                   bitsPerPixel: 32,
                   bytesPerRow: bytesPerRow,
                   space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider,
                   decode: nil,
                   shouldInterpolate: false,
                   intent: .defaultIntent
               ) {
                return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
            }
        }

        guard bounds.width > 0, bounds.height > 0 else { return nil }
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    @discardableResult
    func toggleKeymapOverlay() -> Bool {
        keymappingOverlay.isHidden.toggle()
        return !keymappingOverlay.isHidden
    }

    var isKeymapOverlayVisible: Bool {
        !keymappingOverlay.isHidden
    }

    @discardableResult
    func toggleKeymapEditor() -> Bool {
        if keymappingOverlay.isHidden {
            keymappingOverlay.isHidden = false
        }
        return keymappingOverlay.toggleEditing()
    }

    var isKeymapEditorActive: Bool {
        keymappingOverlay.isEditing
    }

    func configureForPackage(_ packageName: String, appName: String? = nil) {
        currentPackageName = packageName
        currentAppName = appName
        let resolvedAppName = appName ?? packageName
        let profile = KeymapProfileStore.loadProfile(for: packageName, appName: resolvedAppName)
        keymappingOverlay.loadProfile(profile)
        let appProfile = AppProfileStore.loadProfile(for: packageName, appName: resolvedAppName)
        isKeymapEnabled = appProfile.isKeymapEnabled
        isVietnameseIMEEnabled = appProfile.isVietnameseIMEEnabled
        setTargetFPS(appProfile.targetFPS.maxFPS)
        let dims = appProfile.effectiveDimensions
        currentResolution = FrameContract.Resolution(width: Int(dims.width), height: Int(dims.height))
        keymappingOverlay.updateResolution(currentResolution)

        initialTotalPlayTimeSeconds = appProfile.totalPlayTimeSeconds
        sessionStartTime = Date()
        gpgOverlay.updatePlayTime(sessionSeconds: 0, totalSeconds: initialTotalPlayTimeSeconds)
        gpgOverlay.updateMuteState(isAudioMuted)
        gpgOverlay.updateGamepadState(connectedName: GamepadManager.shared.currentState?.name)

        sessionDurationTask?.cancel()
        sessionDurationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, !Task.isCancelled else { break }
                let session = self.currentSessionDurationSeconds
                let total = self.initialTotalPlayTimeSeconds + session
                self.gpgOverlay.updatePlayTime(sessionSeconds: session, totalSeconds: total)
            }
        }
    }

    func resetKeymapToDefaults() {
        guard let pkg = currentPackageName else { return }
        let resolvedName = currentAppName ?? pkg
        let newProfile = KeymapProfileStore.resetToDefault(for: pkg, appName: resolvedName)
        keymappingOverlay.loadProfile(newProfile)
        onKeymapResetRequested?()
    }

    @discardableResult
    func toggleGPGOverlay() -> Bool {
        gpgOverlay.isHidden.toggle()
        if !gpgOverlay.isHidden {
            wasMouseAimLockedBeforeOverlay = isMouseLocked
            if isMouseLocked {
                setMouseLocked(false)
            }
            gpgOverlay.configure(
                appName: currentAppName ?? "Android Application",
                packageName: currentPackageName,
                fps: Double(preferredFramesPerSecond)
            )
            let session = currentSessionDurationSeconds
            let total = initialTotalPlayTimeSeconds + session
            gpgOverlay.updatePlayTime(sessionSeconds: session, totalSeconds: total)
            gpgOverlay.updateGamepadState(connectedName: GamepadManager.shared.currentState?.name)
            gpgOverlay.updateMuteState(isAudioMuted)
            gpgOverlay.updateMouseLockState(isMouseLocked)
        } else {
            if wasMouseAimLockedBeforeOverlay {
                setMouseLocked(true)
                wasMouseAimLockedBeforeOverlay = false
            }
            // Keep the overlay badge in sync so the next open shows correct state.
            gpgOverlay.updateMouseLockState(isMouseLocked)
        }
        return !gpgOverlay.isHidden
    }

    var isGPGOverlayVisible: Bool {
        !gpgOverlay.isHidden
    }

    func setBackgroundThrottled(_ throttled: Bool) {
        isBackgroundThrottled = throttled
        if throttled {
            preferredFramesPerSecond = 15
        } else {
            preferredFramesPerSecond = targetRefreshRate
        }
    }

    func setTargetFPS(_ fps: Int) {
        targetRefreshRate = fps
        if !isBackgroundThrottled {
            preferredFramesPerSecond = fps
        }
    }

    func updateOrientation(isPortrait: Bool) {
        let isCurrentPortrait = currentResolution.height > currentResolution.width
        if isPortrait != isCurrentPortrait {
            currentResolution = FrameContract.Resolution(
                width: currentResolution.height,
                height: currentResolution.width
            )
            keymappingOverlay.updateResolution(currentResolution)
        }
        if let pkg = currentPackageName {
            var profile = AppProfileStore.loadProfile(for: pkg, appName: currentAppName ?? "")
            profile.orientation = isPortrait ? .portrait : .landscape
            AppProfileStore.saveProfile(profile)
        }
    }

    private func setupGamepadHandlers() {
        let gamepad = GamepadManager.shared
        gamepad.onControllerConnected = { [weak self] state in
            self?.onGamepadStatusChanged?(state)
            self?.gpgOverlay.updateGamepadState(connectedName: state.name)
        }
        gamepad.onControllerDisconnected = { [weak self] _ in
            self?.onGamepadStatusChanged?(nil)
            self?.gpgOverlay.updateGamepadState(connectedName: nil)
        }
        gamepad.onLeftThumbstickMoved = { [weak self] x, y in
            guard let self, self.isKeymapEnabled else { return }
            let dpad = self.keymappingOverlay.profile.dpad ?? KeymapDPad()
            if let touch = GamepadManager.virtualStickTouchPoint(
                stickX: x,
                stickY: y,
                centerX: dpad.normalizedCenterX,
                centerY: dpad.normalizedCenterY,
                radius: dpad.radius,
                sourceWidth: Int32(self.currentResolution.width),
                sourceHeight: Int32(self.currentResolution.height)
            ) {
                self.lastGamepadStickTouch = touch
                self.onTouchInput?(TouchInput(x: touch.x, y: touch.y, identifier: 15, phase: .contact))
            } else if let last = self.lastGamepadStickTouch {
                self.lastGamepadStickTouch = nil
                self.onTouchInput?(TouchInput(x: last.x, y: last.y, identifier: 15, phase: .release))
            }
        }
        gamepad.onButtonChanged = { [weak self] button, isPressed, _ in
            guard let self, self.isKeymapEnabled else { return }
            self.handleGamepadButton(button, isPressed: isPressed)
        }
    }

    private func handleGamepadButton(_ button: GamepadButton, isPressed: Bool) {
        switch button {
        case .dpadUp:
            gamepadDpadUpPressed = isPressed
            updateGamepadDpadTouch()
            return
        case .dpadDown:
            gamepadDpadDownPressed = isPressed
            updateGamepadDpadTouch()
            return
        case .dpadLeft:
            gamepadDpadLeftPressed = isPressed
            updateGamepadDpadTouch()
            return
        case .dpadRight:
            gamepadDpadRightPressed = isPressed
            updateGamepadDpadTouch()
            return
        default:
            break
        }

        let buttons = keymappingOverlay.profile.buttons
        let targetIndex: Int?
        switch button {
        case .buttonA, .rightTrigger: targetIndex = 0
        case .buttonB: targetIndex = buttons.count > 1 ? 1 : nil
        case .buttonX: targetIndex = buttons.count > 2 ? 2 : nil
        case .buttonY: targetIndex = buttons.count > 3 ? 3 : nil
        case .leftShoulder, .leftTrigger: targetIndex = buttons.count > 4 ? 4 : nil
        case .rightShoulder: targetIndex = buttons.count > 5 ? 5 : nil
        case .leftThumbstickButton: targetIndex = buttons.count > 6 ? 6 : nil
        case .rightThumbstickButton: targetIndex = buttons.count > 7 ? 7 : nil
        default: targetIndex = nil
        }

        if let idx = targetIndex, idx < buttons.count {
            let btn = buttons[idx]
            let coord = btn.screenCoordinate(
                sourceWidth: Int32(currentResolution.width),
                sourceHeight: Int32(currentResolution.height)
            )
            let id = Int32(200 + idx)
            onTouchInput?(TouchInput(x: coord.x, y: coord.y, identifier: id, phase: isPressed ? .contact : .release))
        }
    }

    private func updateGamepadDpadTouch() {
        guard isKeymapEnabled else { return }
        let dpad = keymappingOverlay.profile.dpad ?? KeymapDPad()
        if let pt = dpad.touchPoint(
            wPressed: gamepadDpadUpPressed,
            aPressed: gamepadDpadLeftPressed,
            sPressed: gamepadDpadDownPressed,
            dPressed: gamepadDpadRightPressed,
            sourceWidth: Int32(currentResolution.width),
            sourceHeight: Int32(currentResolution.height)
        ) {
            lastGamepadDpadTouch = pt
            onTouchInput?(TouchInput(x: pt.x, y: pt.y, identifier: 16, phase: .contact))
        } else if let pt = lastGamepadDpadTouch {
            lastGamepadDpadTouch = nil
            onTouchInput?(TouchInput(x: pt.x, y: pt.y, identifier: 16, phase: .release))
        }
    }

    @discardableResult
    func toggleMacroRecording() -> Bool {
        if isMacroPlaying { stopMacroPlayback() }
        isMacroRecording.toggle()
        if isMacroRecording {
            let pkg = currentPackageName ?? "default"
            activeMacroSequence = MacroSequence(
                name: "Macro_\(Int(Date().timeIntervalSince1970))",
                packageName: pkg,
                actions: []
            )
            lastMacroActionTimestamp = DispatchTime.now().uptimeNanoseconds
            onMacroStatusChanged?("Macro Recording Started")
        } else {
            if !activeMacroSequence.actions.isEmpty {
                MacroStore.saveMacro(activeMacroSequence)
                onMacroStatusChanged?("Macro Saved (\(activeMacroSequence.actions.count) steps)")
            } else {
                onMacroStatusChanged?("Macro Recording Cancelled")
            }
        }
        return isMacroRecording
    }

    @discardableResult
    func toggleMacroPlayback() -> Bool {
        if isMacroPlaying {
            stopMacroPlayback()
            onMacroStatusChanged?("Macro Playback Stopped")
            return false
        } else {
            let pkg = currentPackageName ?? "default"
            if let macro = MacroStore.listMacros(for: pkg).first ?? (activeMacroSequence.actions.isEmpty ? nil : activeMacroSequence) {
                playMacro(macro)
                return true
            } else {
                onMacroStatusChanged?("No Macros Recorded for App")
                return false
            }
        }
    }

    func playMacro(_ macro: MacroSequence) {
        stopMacroPlayback()
        guard !macro.actions.isEmpty else { return }
        isMacroPlaying = true
        onMacroStatusChanged?("Macro Playing: \(macro.name)")

        let queue = DispatchQueue(label: "com.macrodroid.macro.playback", qos: .userInteractive)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        var stepIndex = 0
        var loopCount = 0
        let actions = macro.actions
        let maxLoops = macro.repeatCount

        timer.setEventHandler { [weak self] in
            guard let self, self.isMacroPlaying else { return }
            if stepIndex < actions.count {
                let action = actions[stepIndex]
                Task { @MainActor in
                    self.executeMacroAction(action, in: macro)
                }
                stepIndex += 1
            } else {
                loopCount += 1
                if maxLoops > 0 && loopCount >= maxLoops {
                    Task { @MainActor in
                        self.stopMacroPlayback()
                        self.onMacroStatusChanged?("Macro Finished")
                    }
                } else {
                    stepIndex = 0
                }
            }
        }

        let interval = max(10, Int((Double(macro.intervalMS) / macro.speedMultiplier) / Double(max(1, actions.count))))
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(interval))
        timer.resume()
        macroPlaybackTimer = timer
    }

    func stopMacroPlayback() {
        isMacroPlaying = false
        macroPlaybackTimer?.cancel()
        macroPlaybackTimer = nil
    }

    private func executeMacroAction(_ action: MacroAction, in macro: MacroSequence) {
        if let coord = macro.resolvedCoordinate(
            action: action,
            sourceWidth: Int32(currentResolution.width),
            sourceHeight: Int32(currentResolution.height)
        ) {
            let phase: TouchPhase = action.type == .touchUp ? .release : .contact
            onTouchInput?(TouchInput(x: coord.x, y: coord.y, identifier: 0, phase: phase))
        } else if let key = action.keyString {
            onKeyboardInput?(key, nil)
        }
    }

    private func recordMacroTouch(event: NSEvent, type: MacroActionType) {
        guard isMacroRecording else { return }
        let location = convert(event.locationInWindow, from: nil)
        let mapper = ViewportMapper(
            sourceSize: CGSize(width: currentResolution.width, height: currentResolution.height),
            viewportSize: bounds.size
        )
        guard let source = mapper.sourcePoint(for: location) else { return }
        let normX = max(0.0, min(1.0, source.x / CGFloat(currentResolution.width)))
        let normY = max(0.0, min(1.0, 1.0 - (source.y / CGFloat(currentResolution.height))))
        let now = DispatchTime.now().uptimeNanoseconds
        let delayMS = lastMacroActionTimestamp > 0 ? Int((now - lastMacroActionTimestamp) / 1_000_000) : 0
        lastMacroActionTimestamp = now
        let action = MacroAction(
            type: type,
            timestampNanoseconds: now,
            normalizedX: normX,
            normalizedY: normY,
            delayAfterMS: delayMS
        )
        activeMacroSequence.actions.append(action)
    }

    private func recordMacroKey(event: NSEvent) {
        guard isMacroRecording else { return }
        if let chars = event.characters, !chars.isEmpty {
            let action = MacroAction(
                type: .keyPress,
                keyCode: event.keyCode,
                keyString: chars
            )
            activeMacroSequence.actions.append(action)
        }
    }

    @discardableResult
    func toggleMouseLock() -> Bool {
        setMouseLocked(!isMouseLocked)
        return isMouseLocked
    }

    func setMouseLocked(_ locked: Bool) {
        guard isMouseLocked != locked else { return }
        isMouseLocked = locked
        isSmartCursorReleased = false
        gpgOverlay.updateMouseLockState(locked)
        if locked {
            NSCursor.hide()
            CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
            if isKeymapEnabled && keymappingOverlay.profile.mouseAim != nil {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    keymappingOverlay.animator().alphaValue = 0.25
                }
            }
        } else {
            resetMouseAimTouch(aim: keymappingOverlay.profile.mouseAim)
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
            NSCursor.unhide()
            if isKeymapEnabled {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    keymappingOverlay.animator().alphaValue = CGFloat(keymappingOverlay.profile.overlayOpacity)
                }
            }
        }
    }

    /// The runtime collector owns Android SurfaceFlinger truth. This presenter never substitutes
    /// ingress or Metal presentation rates for actual guest frame production.
    func setGameFrameWindow(_ window: GameFrameTelemetryWindow?) {
        gameFrameWindow = window
        updatePerformanceOverlay()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let uploadedNewSource = uploadNewestFrameIfPossible()
        guard let slot = currentTextureSlot, let texture = textures[slot] else {
            updatePresentationSampleIfNeeded()
            return
        }
        guard let drawable = currentDrawable, let descriptor = currentRenderPassDescriptor else {
            hostPresentationTelemetry.recordDrawableMiss()
            updatePresentationSampleIfNeeded()
            return
        }
        guard let buffer = commandQueue.makeCommandBuffer() else {
            hostPresentationTelemetry.recordCommandBufferMiss()
            updatePresentationSampleIfNeeded()
            return
        }
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            hostPresentationTelemetry.recordEncoderMiss()
            updatePresentationSampleIfNeeded()
            return
        }

        let source = CGSize(width: texture.width, height: texture.height)
        let target = drawableSize
        let scale = min(target.width / source.width, target.height / source.height)
        let renderWidth = source.width * scale
        let renderHeight = source.height * scale
        encoder.setViewport(MTLViewport(
            originX: (target.width - renderWidth) / 2,
            originY: (target.height - renderHeight) / 2,
            width: renderWidth,
            height: renderHeight,
            znear: 0,
            zfar: 1
        ))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        let submittedMonotonicNS = DispatchTime.now().uptimeNanoseconds
        hostPresentationTelemetry.recordSubmitted(uniqueSourceUpload: uploadedNewSource)
        gpuState.beginPresentation(slot: slot)
        let state = gpuState
        let telemetry = hostPresentationTelemetry
        buffer.addCompletedHandler { commandBuffer in
            state.completePresentation(slot: slot)
            telemetry.recordCompletion(submittedMonotonicNS: submittedMonotonicNS, commandBuffer: commandBuffer)
        }
        buffer.present(drawable)
        buffer.commit()
        updatePresentationSampleIfNeeded()
    }

    override func mouseMoved(with event: NSEvent) {
        guard isMouseLocked,
              !isSmartCursorReleased,
              isKeymapEnabled,
              let aim = keymappingOverlay.profile.mouseAim else {
            super.mouseMoved(with: event)
            return
        }
        handleMouseAimMove(event: event, aim: aim)
    }

    private func handleMouseAimMove(event: NSEvent, aim: KeymapMouseAim) {
        guard currentResolution.width > 0, currentResolution.height > 0 else { return }
        let dx = event.deltaX * aim.sensitivity * 1.5
        let dy = event.deltaY * aim.sensitivity * 1.5
        guard abs(dx) > 0.001 || abs(dy) > 0.001 else { return }

        let centerX = Int32(aim.normalizedCenterX * Double(currentResolution.width))
        let centerY = Int32(aim.normalizedCenterY * Double(currentResolution.height))
        let maxStrokeRadius: CGFloat = 140.0

        let newOffsetX = currentAimStrokeOffset.x + dx
        let newOffsetY = currentAimStrokeOffset.y + dy
        let dist = hypot(newOffsetX, newOffsetY)

        if dist > maxStrokeRadius {
            if isAimTouchActive {
                let releaseX = Int32(max(0, min(Double(currentResolution.width - 1), Double(centerX) + currentAimStrokeOffset.x)))
                let releaseY = Int32(max(0, min(Double(currentResolution.height - 1), Double(centerY) + currentAimStrokeOffset.y)))
                onTouchInput?(TouchInput(x: releaseX, y: releaseY, identifier: 11, phase: .release))
            }
            currentAimStrokeOffset = .zero
            onTouchInput?(TouchInput(x: centerX, y: centerY, identifier: 11, phase: .contact))
            currentAimStrokeOffset = CGPoint(x: dx, y: dy)
            let moveX = Int32(max(0, min(Double(currentResolution.width - 1), Double(centerX) + dx)))
            let moveY = Int32(max(0, min(Double(currentResolution.height - 1), Double(centerY) + dy)))
            onTouchInput?(TouchInput(x: moveX, y: moveY, identifier: 11, phase: .contact))
            isAimTouchActive = true
        } else {
            currentAimStrokeOffset = CGPoint(x: newOffsetX, y: newOffsetY)
            let targetX = Int32(max(0, min(Double(currentResolution.width - 1), Double(centerX) + newOffsetX)))
            let targetY = Int32(max(0, min(Double(currentResolution.height - 1), Double(centerY) + newOffsetY)))
            onTouchInput?(TouchInput(x: targetX, y: targetY, identifier: 11, phase: .contact))
            isAimTouchActive = true
        }
    }

    private func resetMouseAimTouch(aim: KeymapMouseAim?) {
        if isAimTouchActive {
            let cx = Int32(aim.map { Int($0.normalizedCenterX * Double(currentResolution.width)) } ?? (currentResolution.width / 2))
            let cy = Int32(aim.map { Int($0.normalizedCenterY * Double(currentResolution.height)) } ?? (currentResolution.height / 2))
            let relX = Int32(max(0, min(Double(currentResolution.width - 1), Double(cx) + currentAimStrokeOffset.x)))
            let relY = Int32(max(0, min(Double(currentResolution.height - 1), Double(cy) + currentAimStrokeOffset.y)))
            onTouchInput?(TouchInput(x: relX, y: relY, identifier: 11, phase: .release))
            isAimTouchActive = false
            currentAimStrokeOffset = .zero
        }
        if isLeftClickFiring {
            stopLeftClickFire()
        }
        if isRightClickAiming {
            stopRightClickADS()
        }
    }

    private func resolveFireCoordinate(aim: KeymapMouseAim) -> TouchPoint {
        if let btn = keymappingOverlay.profile.buttons.first(where: {
            let name = ($0.label.isEmpty ? $0.key : $0.label).lowercased()
            return name.contains("fire") || name.contains("shoot") || name.contains("attack")
        }) {
            let coord = btn.screenCoordinate(
                sourceWidth: Int32(currentResolution.width),
                sourceHeight: Int32(currentResolution.height)
            )
            return TouchPoint(x: coord.x, y: coord.y)
        }
        let x = Int32(max(0, min(Double(currentResolution.width - 1), aim.normalizedFireX * Double(currentResolution.width))))
        let y = Int32(max(0, min(Double(currentResolution.height - 1), aim.normalizedFireY * Double(currentResolution.height))))
        return TouchPoint(x: x, y: y)
    }

    private func resolveADSCoordinate(aim: KeymapMouseAim) -> TouchPoint {
        if let btn = keymappingOverlay.profile.buttons.first(where: {
            let name = ($0.label.isEmpty ? $0.key : $0.label).lowercased()
            return name.contains("ads") || name.contains("scope") || name.contains("aim")
        }) {
            let coord = btn.screenCoordinate(
                sourceWidth: Int32(currentResolution.width),
                sourceHeight: Int32(currentResolution.height)
            )
            return TouchPoint(x: coord.x, y: coord.y)
        }
        let x = Int32(max(0, min(Double(currentResolution.width - 1), aim.normalizedADSX * Double(currentResolution.width))))
        let y = Int32(max(0, min(Double(currentResolution.height - 1), aim.normalizedADSY * Double(currentResolution.height))))
        return TouchPoint(x: x, y: y)
    }

    private func startLeftClickFire(aim: KeymapMouseAim) {
        let coord = resolveFireCoordinate(aim: aim)
        activeFireTouch = coord
        isLeftClickFiring = true
        onTouchInput?(TouchInput(x: coord.x, y: coord.y, identifier: 210, phase: .contact))
    }

    private func stopLeftClickFire() {
        guard isLeftClickFiring, let coord = activeFireTouch else { return }
        onTouchInput?(TouchInput(x: coord.x, y: coord.y, identifier: 210, phase: .release))
        activeFireTouch = nil
        isLeftClickFiring = false
    }

    private func startRightClickADS(aim: KeymapMouseAim) {
        let coord = resolveADSCoordinate(aim: aim)
        activeADSTouch = coord
        isRightClickAiming = true
        onTouchInput?(TouchInput(x: coord.x, y: coord.y, identifier: 211, phase: .contact))
    }

    private func stopRightClickADS() {
        guard isRightClickAiming, let coord = activeADSTouch else { return }
        onTouchInput?(TouchInput(x: coord.x, y: coord.y, identifier: 211, phase: .release))
        activeADSTouch = nil
        isRightClickAiming = false
    }

    private func toggleSmartCursorRelease(aim: KeymapMouseAim?) {
        isSmartCursorReleased.toggle()
        if isSmartCursorReleased {
            resetMouseAimTouch(aim: aim)
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
            NSCursor.unhide()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                keymappingOverlay.animator().alphaValue = CGFloat(keymappingOverlay.profile.overlayOpacity)
            }
        } else {
            NSCursor.hide()
            CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                keymappingOverlay.animator().alphaValue = 0.25
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if isGPGOverlayVisible {
            super.mouseDown(with: event)
            return
        }
        if isMouseLocked && !isSmartCursorReleased && isKeymapEnabled,
           let aim = keymappingOverlay.profile.mouseAim,
           aim.leftClickFire {
            startLeftClickFire(aim: aim)
            return
        }
        if isMacroRecording {
            recordMacroTouch(event: event, type: .touchDown)
        }
        sendTouch(event, isContact: true)
    }

    override func mouseDragged(with event: NSEvent) {
        if isGPGOverlayVisible {
            super.mouseDragged(with: event)
            return
        }
        if isMouseLocked && !isSmartCursorReleased && isKeymapEnabled,
           let aim = keymappingOverlay.profile.mouseAim {
            handleMouseAimMove(event: event, aim: aim)
            return
        }
        if isMacroRecording {
            recordMacroTouch(event: event, type: .touchMove)
        }
        sendTouch(event, isContact: true)
    }

    override func mouseUp(with event: NSEvent) {
        if isGPGOverlayVisible {
            super.mouseUp(with: event)
            return
        }
        if isLeftClickFiring {
            stopLeftClickFire()
            return
        }
        if isMacroRecording {
            recordMacroTouch(event: event, type: .touchUp)
        }
        sendTouch(event, isContact: false)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard !isGPGOverlayVisible else { return }
        if isMouseLocked && !isSmartCursorReleased && isKeymapEnabled,
           let aim = keymappingOverlay.profile.mouseAim,
           aim.rightClickADS {
            startRightClickADS(aim: aim)
            return
        }
        sendMouse(event, buttons: 2)
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard !isGPGOverlayVisible else { return }
        if isMouseLocked && !isSmartCursorReleased && isKeymapEnabled,
           let aim = keymappingOverlay.profile.mouseAim {
            handleMouseAimMove(event: event, aim: aim)
            return
        }
        sendMouse(event, buttons: 2)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard !isGPGOverlayVisible else { return }
        if isRightClickAiming {
            stopRightClickADS()
            return
        }
        sendMouse(event, buttons: 0)
    }

    override func scrollWheel(with event: NSEvent) {
        guard !isGPGOverlayVisible else { return }
        guard let point = androidPoint(for: event) else {
            super.scrollWheel(with: event)
            return
        }
        let dx = event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1.0 : 10.0)
        let dy = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1.0 : 10.0)
        guard abs(dx) > 0.5 || abs(dy) > 0.5 else { return }
        onScrollGesture?(point.x, point.y, dx, dy)
    }

    override func magnify(with event: NSEvent) {
        guard !isGPGOverlayVisible else { return }
        guard let point = androidPoint(for: event) else {
            super.magnify(with: event)
            return
        }
        let scale = event.magnification
        guard abs(scale) > 0.001 else { return }
        onPinchGesture?(point.x, point.y, scale)
    }

    private func handleKeymapKeyDown(event: NSEvent) -> Bool {
        guard isKeymapEnabled && !keymappingOverlay.isEditing else { return false }

        if let dpad = keymappingOverlay.profile.dpad {
            var matched = false
            if event.keyCode == dpad.wKeyCode {
                dpadWPressed = true
                matched = true
            } else if event.keyCode == dpad.aKeyCode {
                dpadAPressed = true
                matched = true
            } else if event.keyCode == dpad.sKeyCode {
                dpadSPressed = true
                matched = true
            } else if event.keyCode == dpad.dKeyCode {
                dpadDPressed = true
                matched = true
            }

            if matched {
                if let pt = dpad.touchPoint(
                    wPressed: dpadWPressed,
                    aPressed: dpadAPressed,
                    sPressed: dpadSPressed,
                    dPressed: dpadDPressed,
                    sourceWidth: Int32(currentResolution.width),
                    sourceHeight: Int32(currentResolution.height)
                ) {
                    lastDpadTouch = pt
                    onTouchInput?(TouchInput(x: pt.x, y: pt.y, identifier: 10, phase: .contact))
                }
                return true
            }
        }

        if let btn = keymappingOverlay.profile.buttons.first(where: { $0.keyCode == event.keyCode }) {
            let coord = btn.screenCoordinate(
                sourceWidth: Int32(currentResolution.width),
                sourceHeight: Int32(currentResolution.height)
            )
            activeKeymapTouches[btn.key] = coord
            let identifier = Int32(btn.keyCode) + 100
            onTouchInput?(TouchInput(x: coord.x, y: coord.y, identifier: identifier, phase: .contact))
            return true
        }

        return false
    }

    private func handleKeymapKeyUp(event: NSEvent) -> Bool {
        guard isKeymapEnabled && !keymappingOverlay.isEditing else { return false }

        if let dpad = keymappingOverlay.profile.dpad {
            var matched = false
            if event.keyCode == dpad.wKeyCode {
                dpadWPressed = false
                matched = true
            } else if event.keyCode == dpad.aKeyCode {
                dpadAPressed = false
                matched = true
            } else if event.keyCode == dpad.sKeyCode {
                dpadSPressed = false
                matched = true
            } else if event.keyCode == dpad.dKeyCode {
                dpadDPressed = false
                matched = true
            }

            if matched {
                if let pt = dpad.touchPoint(
                    wPressed: dpadWPressed,
                    aPressed: dpadAPressed,
                    sPressed: dpadSPressed,
                    dPressed: dpadDPressed,
                    sourceWidth: Int32(currentResolution.width),
                    sourceHeight: Int32(currentResolution.height)
                ) {
                    lastDpadTouch = pt
                    onTouchInput?(TouchInput(x: pt.x, y: pt.y, identifier: 10, phase: .contact))
                } else if let pt = lastDpadTouch {
                    lastDpadTouch = nil
                    onTouchInput?(TouchInput(x: pt.x, y: pt.y, identifier: 10, phase: .release))
                }
                return true
            }
        }

        if let btn = keymappingOverlay.profile.buttons.first(where: { $0.keyCode == event.keyCode }) {
            if let coord = activeKeymapTouches.removeValue(forKey: btn.key) {
                let identifier = Int32(btn.keyCode) + 100
                onTouchInput?(TouchInput(x: coord.x, y: coord.y, identifier: identifier, phase: .release))
            }
            return true
        }

        return false
    }

    override func keyDown(with event: NSEvent) {
        if !keymappingOverlay.isHidden {
            keymappingOverlay.highlight(event: event, isDown: true)
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Shift + Tab: Toggle In-Game Dashboard Overlay (Google Play Games PC standard)
        if modifiers.contains(.shift) && event.keyCode == 48 {
            _ = toggleGPGOverlay()
            return
        }

        // F10: Toggle Mouse Aim Lock
        if event.keyCode == 109 {
            onMouseLockToggleRequested?()
            return
        }

        // F11: Toggle Fullscreen
        if event.keyCode == 103 {
            onFullscreenRequested?()
            return
        }

        // Esc: Hierarchical dismissal (Overlay -> Keymap Editor -> Mouse Lock -> Android Back)
        if event.keyCode == 53 {
            if isGPGOverlayVisible {
                _ = toggleGPGOverlay()
                return
            }
            if isKeymapEditorActive {
                _ = toggleKeymapEditor()
                return
            }
            if isMouseLocked {
                setMouseLocked(false)
                return
            }
            onAndroidBackRequested?()
            return
        }

        if isGPGOverlayVisible {
            return
        }

        if modifiers.contains(.command) {
            super.keyDown(with: event)
            return
        }

        let aimConfig = keymappingOverlay.profile.mouseAim
        let isAimToggle = (aimConfig != nil && (event.keyCode == aimConfig?.toggleKeyCode || event.keyCode == 50))
        if isAimToggle {
            toggleMouseLock()
            return
        }

        if isMouseLocked && (aimConfig?.smartCursorRelease ?? true) && (event.keyCode == 48 || event.keyCode == 46) {
            toggleSmartCursorRelease(aim: aimConfig)
        }

        if isMacroRecording {
            recordMacroKey(event: event)
        }
        if handleKeymapKeyDown(event: event) {
            return
        }
        if isVietnameseIMEEnabled && keymappingOverlay.isHidden {
            interpretKeyEvents([event])
            return
        }
        if let key = Self.specialKey(for: event) {
            onKeyboardInput?(nil, key)
        } else if let text = event.characters, !text.isEmpty {
            onKeyboardInput?(text, nil)
        }
    }

    override func keyUp(with event: NSEvent) {
        if isGPGOverlayVisible {
            return
        }
        if !keymappingOverlay.isHidden {
            keymappingOverlay.highlight(event: event, isDown: false)
        }
        if handleKeymapKeyUp(event: event) {
            return
        }
        super.keyUp(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        let current = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if current.contains(.option) && !previousModifierFlags.contains(.option) && !current.contains(.command) && !isGPGOverlayVisible {
            onMouseLockToggleRequested?()
        }
        previousModifierFlags = current
        super.flagsChanged(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == [.command, .option] || modifiers == [.option, .command] {
            if let char = event.charactersIgnoringModifiers?.lowercased() {
                if char == "k" {
                    onKeymapEditorToggleRequested?()
                    return true
                } else if char == "r" {
                    onMacroRecordToggleRequested?()
                    return true
                } else if char == "p" {
                    onMacroPlayToggleRequested?()
                    return true
                }
            }
        }
        guard modifiers == .command, let char = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch char {
        case "f":
            onFullscreenRequested?()
            return true
        case "[":
            onAndroidBackRequested?()
            return true
        case "r":
            onRotateRequested?()
            return true
        case "s":
            onScreenshotRequested?()
            return true
        case "k":
            onKeymapToggleRequested?()
            return true
        case "m":
            onFreeformRequested?()
            return true
        case "o":
            onSharedFolderRequested?()
            return true
        case "i":
            onIMEToggleRequested?()
            return true
        case "t":
            onTaskSwitcherRequested?()
            return true
        case ",":
            onOpenSettingsRequested?()
            return true
        case "v":
            paste(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    func sendAndroidKey(_ key: String) {
        onKeyboardInput?(nil, key)
    }

    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        if let pasteHandler = onPasteInput {
            // Runtime clipboard sync is available — use the dedicated paste channel only.
            // Sending through onKeyboardInput as well would double-inject the text.
            pasteHandler(text)
        } else {
            // No runtime clipboard channel; fall back to keyboard simulation (max 1024 chars).
            onKeyboardInput?(String(text.prefix(1024)), nil)
        }
    }

    // MARK: - Drag & Drop File Sharing

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           urls.contains(where: { $0.isFileURL }) {
            dropOverlayView.isHidden = false
            return .copy
        }
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           urls.contains(where: { $0.isFileURL }) {
            return .copy
        }
        return []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropOverlayView.isHidden = true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        dropOverlayView.isHidden = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropOverlayView.isHidden = true
        let pboard = sender.draggingPasteboard
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let fileURLs = urls.filter { $0.isFileURL }
            if !fileURLs.isEmpty {
                onFilesDropped?(fileURLs)
                return true
            }
        }
        return false
    }

    @discardableResult
    private func uploadNewestFrameIfPossible() -> Bool {
        guard let frame = mailbox.latestFrame(after: lastPresentedSequence) ?? mailbox.takeLatest() else { return false }
        guard let slot = gpuState.availableUploadSlot(excluding: currentTextureSlot) else { return false }
        if textures[slot] == nil || textures[slot]?.width != frame.width || textures[slot]?.height != frame.height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm_srgb,
                width: frame.width,
                height: frame.height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .shared
            textures[slot] = device?.makeTexture(descriptor: descriptor)
            textures[slot]?.label = "Macrodroid Android frame \(slot)"
        }
        guard let texture = textures[slot] else { return false }
        frame.pixels.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, frame.width, frame.height),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: frame.width * FrameContract.bytesPerPixel
            )
        }
        currentTextureSlot = slot
        lastPresentedSequence = frame.sequence
        if currentResolution.width != frame.width || currentResolution.height != frame.height {
            currentResolution = FrameContract.Resolution(width: frame.width, height: frame.height)
            keymappingOverlay.updateResolution(currentResolution)
        }
        return true
    }

    private func androidPoint(for event: NSEvent) -> TouchPoint? {
        let location = convert(event.locationInWindow, from: nil)
        let mapper = ViewportMapper(
            sourceSize: CGSize(width: currentResolution.width, height: currentResolution.height),
            viewportSize: bounds.size
        )
        guard let source = mapper.sourcePoint(for: location) else { return nil }
        let x = Int32(max(0, min(currentResolution.width - 1, Int(source.x.rounded()))))
        let topOriginY = currentResolution.height - 1 - Int(source.y.rounded())
        let y = Int32(max(0, min(currentResolution.height - 1, topOriginY)))
        return TouchPoint(x: x, y: y)
    }

    private func sendTouch(_ event: NSEvent, isContact: Bool) {
        let point = androidPoint(for: event)
        let input = isContact
            ? primaryTouchSequence.contact(at: point)
            : primaryTouchSequence.release(at: point)
        guard let input else { return }
        onTouchInput?(input)
    }

    private func sendMouse(_ event: NSEvent, buttons: Int32) {
        guard let point = androidPoint(for: event) else { return }
        onMouseInput?(point.x, point.y, buttons)
    }

    private func updatePresentationSampleIfNeeded() {
        let now = CACurrentMediaTime()
        let elapsed = now - lastSampleTime
        guard elapsed >= 1 else { return }
        let total = gpuState.completedCount()
        let delta = total - lastSamplePresentationCount
        let presentationFPS = Double(delta) / elapsed
        let mailboxSnapshot = mailbox.snapshot()
        let receivedDelta = mailboxSnapshot.receivedFrames - lastSampleReceivedCount
        let sourceFPS = Double(receivedDelta) / elapsed
        lastSourceFPS = sourceFPS
        lastPresentationFPS = presentationFPS
        let sample = PresentationSample(
            presentedFrames: total,
            presentationFPS: presentationFPS,
            sourceFPS: sourceFPS,
            mailbox: mailboxSnapshot,
            lastPresentedSequence: lastPresentedSequence,
            sampledMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
        onPresentationSample?(sample)
        lastSamplePresentationCount = total
        lastSampleReceivedCount = mailboxSnapshot.receivedFrames
        lastSampleTime = now
        if let hostWindow = hostPresentationTelemetry.drainIfNeeded(nowMonotonicNS: DispatchTime.now().uptimeNanoseconds) {
            lastHostGPUTimeP95MS = hostWindow.p95GPUTimeMS
            onHostPresentationWindow?(hostWindow)
        }
        updatePerformanceOverlay()
    }

    private func updatePerformanceOverlay() {
        let guestFPS = gameFrameWindow?.effectiveFPS ?? 0
        let deliveredFPS = lastSourceFPS
        let displayFPS: Double
        if guestFPS > 0 {
            displayFPS = guestFPS
        } else if deliveredFPS > 0 {
            displayFPS = min(deliveredFPS, lastPresentationFPS > 0 ? lastPresentationFPS : deliveredFPS)
        } else if lastPresentationFPS > 0 && lastSampleReceivedCount > 0 {
            displayFPS = lastPresentationFPS
        } else {
            displayFPS = 0
        }
        onFPSChanged?(displayFPS)
        gpgOverlay.updateFPS(displayFPS)

        let guestLine: String
        if let gameFrameWindow, case .available = gameFrameWindow.status {
            let low = gameFrameWindow.onePercentLowFPS.map { String(format: "%.0f", $0) } ?? "—"
            let p99 = gameFrameWindow.p99MS.map { String(format: "%.1f", $0) } ?? "—"
            guestLine = String(format: "APP %.0f · 1%% %@ · P99 %@ms", gameFrameWindow.effectiveFPS, low, p99)
        } else {
            guestLine = "APP —"
        }
        let gpu = lastHostGPUTimeP95MS.map { String(format: "%.1f", $0) } ?? "—"
        fpsLabel.stringValue = String(
            format: "%@\nPIPE %.0f · MAC %.0f · GPU %@ms",
            guestLine,
            lastSourceFPS,
            lastPresentationFPS,
            gpu
        )
    }

    private func configureOverlays() {
        statusLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        statusLabel.alignment = .center
        statusLabel.maximumNumberOfLines = 3
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.wantsLayer = true
        statusLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        statusLabel.layer?.cornerRadius = 10
        statusLabel.isHidden = true
        addSubview(statusLabel)

        fpsLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        fpsLabel.textColor = .white
        fpsLabel.alignment = .right
        fpsLabel.maximumNumberOfLines = 2
        fpsLabel.translatesAutoresizingMaskIntoConstraints = false
        fpsLabel.wantsLayer = true
        fpsLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        fpsLabel.layer?.cornerRadius = 6
        fpsLabel.isHidden = true
        addSubview(fpsLabel)

        dropOverlayView.wantsLayer = true
        dropOverlayView.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.25).cgColor
        dropOverlayView.layer?.borderColor = NSColor.systemBlue.cgColor
        dropOverlayView.layer?.borderWidth = 3
        dropOverlayView.layer?.cornerRadius = 12
        dropOverlayView.translatesAutoresizingMaskIntoConstraints = false
        dropOverlayView.isHidden = true
        addSubview(dropOverlayView)

        dropLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        dropLabel.textColor = .white
        dropLabel.alignment = .center
        dropLabel.maximumNumberOfLines = 2
        dropLabel.translatesAutoresizingMaskIntoConstraints = false
        dropOverlayView.addSubview(dropLabel)

        keymappingOverlay.isHidden = true
        addSubview(keymappingOverlay)

        gpgOverlay.isHidden = true
        gpgOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gpgOverlay)

        gpgOverlay.onResumeRequested = { [weak self] in
            _ = self?.toggleGPGOverlay()
        }
        gpgOverlay.onRemapRequested = { [weak self] in
            _ = self?.toggleGPGOverlay()
            self?.onKeymapEditorToggleRequested?()
        }
        gpgOverlay.onToggleKeymapVisibilityRequested = { [weak self] in
            self?.onKeymapToggleRequested?()
        }
        gpgOverlay.onResetKeymapRequested = { [weak self] in
            self?.resetKeymapToDefaults()
        }
        gpgOverlay.onOpacityChanged = { [weak self] opacity in
            self?.keymappingOverlay.alphaValue = CGFloat(opacity)
        }
        gpgOverlay.onMouseLockRequested = { [weak self] in
            guard let self else { return }
            self.onMouseLockToggleRequested?()
            // Auto-dismiss the overlay when the user activates Aim Lock from the dashboard,
            // so they can immediately start aiming without manually closing the overlay.
            if self.isMouseLocked {
                _ = self.toggleGPGOverlay()
            }
        }
        gpgOverlay.onToggleMuteRequested = { [weak self] in
            guard let self else { return }
            self.isAudioMuted.toggle()
            self.gpgOverlay.updateMuteState(self.isAudioMuted)
            self.onAudioMuteToggleRequested?(self.isAudioMuted)
        }
        gpgOverlay.onFullscreenRequested = { [weak self] in
            self?.onFullscreenRequested?()
        }
        gpgOverlay.onRotateRequested = { [weak self] in
            self?.onRotateRequested?()
        }
        gpgOverlay.onFreeformRequested = { [weak self] in
            self?.onFreeformRequested?()
        }
        gpgOverlay.onScreenshotRequested = { [weak self] in
            self?.onScreenshotRequested?()
        }
        gpgOverlay.onSharedFolderRequested = { [weak self] in
            self?.onSharedFolderRequested?()
        }
        gpgOverlay.onSettingsRequested = { [weak self] in
            self?.onOpenSettingsRequested?()
        }
        gpgOverlay.onExitGameRequested = { [weak self] in
            self?.onExitGameRequested?()
        }
        gpgOverlay.onRefreshRateChanged = { [weak self] fps in
            self?.setTargetFPS(fps)
            if let pkg = self?.currentPackageName {
                var profile = AppProfileStore.loadProfile(for: pkg, appName: self?.currentAppName ?? "")
                if let newFPS = AppFrameRate(rawValue: fps) {
                    profile.targetFPS = newFPS
                    AppProfileStore.saveProfile(profile)
                }
            }
        }

        shutterFlashView.wantsLayer = true
        shutterFlashView.layer?.backgroundColor = NSColor.white.cgColor
        shutterFlashView.alphaValue = 0.0
        shutterFlashView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shutterFlashView)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.72),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            fpsLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            fpsLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            fpsLabel.widthAnchor.constraint(equalToConstant: 300),
            fpsLabel.heightAnchor.constraint(equalToConstant: 46),
            dropOverlayView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            dropOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            dropOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            dropOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            dropLabel.centerXAnchor.constraint(equalTo: dropOverlayView.centerXAnchor),
            dropLabel.centerYAnchor.constraint(equalTo: dropOverlayView.centerYAnchor),
            keymappingOverlay.topAnchor.constraint(equalTo: topAnchor),
            keymappingOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            keymappingOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            keymappingOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            gpgOverlay.topAnchor.constraint(equalTo: topAnchor),
            gpgOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            gpgOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            gpgOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            shutterFlashView.topAnchor.constraint(equalTo: topAnchor),
            shutterFlashView.bottomAnchor.constraint(equalTo: bottomAnchor),
            shutterFlashView.leadingAnchor.constraint(equalTo: leadingAnchor),
            shutterFlashView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    private static func makePipeline(device: MTLDevice) throws -> MTLRenderPipelineState {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct RasterData {
            float4 position [[position]];
            float2 textureCoordinate;
        };

        vertex RasterData macrodroid_vertex(uint vertexID [[vertex_id]]) {
            const float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
            // Metal's bottom screen edge must sample the bottom RGBA row.
            // The oversized triangle therefore maps bottom vertices to v=1.
            const float2 coordinates[3] = { float2(0.0, 1.0), float2(2.0, 1.0), float2(0.0, -1.0) };
            RasterData output;
            output.position = float4(positions[vertexID], 0.0, 1.0);
            output.textureCoordinate = coordinates[vertexID];
            return output;
        }

        fragment float4 macrodroid_fragment(RasterData input [[stage_in]], texture2d<float> frame [[texture(0)]]) {
            constexpr sampler sampleState(coord::normalized, address::clamp_to_edge, filter::linear);
            return frame.sample(sampleState, input.textureCoordinate);
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Macrodroid RGBA presenter"
        descriptor.vertexFunction = library.makeFunction(name: "macrodroid_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "macrodroid_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func specialKey(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 36, 76: return "Enter"
        case 48: return "Tab"
        case 51, 117: return "Backspace"
        case 53: return "GoBack"
        case 111: return "Power"
        case 115: return "GoHome"
        case 119: return "End"
        case 123: return "ArrowLeft"
        case 124: return "ArrowRight"
        case 125: return "ArrowDown"
        case 126: return "ArrowUp"
        default: return nil
        }
    }
}

// MARK: - NSTextInputClient (Vietnamese IME Direct Composing & Forwarding)

@MainActor extension EmbeddedEmulatorView: @preconcurrency NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let attrStr = string as? NSAttributedString {
            text = attrStr.string
        } else if let str = string as? String {
            text = str
        } else {
            return
        }
        markedTextStorage.mutableString.setString("")
        markedTextSelectionRange = NSRange(location: NSNotFound, length: 0)
        guard !text.isEmpty else { return }
        onKeyboardInput?(text, nil)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let str: String
        if let attrStr = string as? NSAttributedString {
            str = attrStr.string
        } else if let s = string as? String {
            str = s
        } else {
            str = ""
        }
        markedTextStorage.mutableString.setString(str)
        markedTextSelectionRange = selectedRange
    }

    func unmarkText() {
        let str = markedTextStorage.string
        if !str.isEmpty {
            onKeyboardInput?(str, nil)
        }
        markedTextStorage.mutableString.setString("")
        markedTextSelectionRange = NSRange(location: NSNotFound, length: 0)
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        if markedTextStorage.length > 0 {
            return NSRange(location: 0, length: markedTextStorage.length)
        }
        return NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool {
        markedTextStorage.length > 0
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard range.location != NSNotFound, range.location + range.length <= markedTextStorage.length else {
            return nil
        }
        actualRange?.pointee = range
        return markedTextStorage.attributedSubstring(from: range)
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.underlineStyle]
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let windowRect = window?.frame ?? .zero
        return NSRect(x: windowRect.midX, y: windowRect.midY, width: 0, height: 0)
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            onKeyboardInput?(nil, "Enter")
        case #selector(NSResponder.deleteBackward(_:)):
            onKeyboardInput?(nil, "Backspace")
        case #selector(NSResponder.deleteForward(_:)):
            onKeyboardInput?(nil, "Delete")
        case #selector(NSResponder.moveLeft(_:)):
            onKeyboardInput?(nil, "ArrowLeft")
        case #selector(NSResponder.moveRight(_:)):
            onKeyboardInput?(nil, "ArrowRight")
        case #selector(NSResponder.moveUp(_:)):
            onKeyboardInput?(nil, "ArrowUp")
        case #selector(NSResponder.moveDown(_:)):
            onKeyboardInput?(nil, "ArrowDown")
        case #selector(NSResponder.cancelOperation(_:)):
            onKeyboardInput?(nil, "Escape")
        case #selector(NSResponder.insertTab(_:)):
            onKeyboardInput?(nil, "Tab")
        default:
            super.doCommand(by: selector)
        }
    }
}
