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

        label.stringValue = key
        label.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
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
        let normX = max(0.0, min(1.0, midX / parent.bounds.width))
        let normY = max(0.0, min(1.0, 1.0 - (midY / parent.bounds.height)))
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

        layoutBadges()
    }

    override func layout() {
        super.layout()
        layoutBadges()
    }

    private func layoutBadges() {
        let mapper = ViewportMapper(
            sourceSize: CGSize(width: FrameContract.width, height: FrameContract.height),
            viewportSize: bounds.size
        )
        let displayedRect = mapper.displayedRect
        guard displayedRect.width > 0, displayedRect.height > 0 else { return }

        for (_, badge) in badges {
            let badgeSize: CGFloat = badge.keyIdentifier == "SPACE" ? 72 : 36
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
    var onKeymapEditorToggleRequested: (() -> Void)?

    var isKeymapEnabled = true
    var isVietnameseIMEEnabled = true
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
    private var activeKeymapTouches: [String: (x: Int32, y: Int32)] = [:]
    private(set) var currentPackageName: String?
    private(set) var currentAppName: String?

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
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
    }

    func setTargetFPS(_ fps: Int) {
        preferredFramesPerSecond = fps
    }

    @discardableResult
    func toggleMouseLock() -> Bool {
        setMouseLocked(!isMouseLocked)
        return isMouseLocked
    }

    func setMouseLocked(_ locked: Bool) {
        guard isMouseLocked != locked else { return }
        isMouseLocked = locked
        if locked {
            NSCursor.hide()
            CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
        } else {
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
            NSCursor.unhide()
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

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendTouch(event, isContact: true)
    }
    override func mouseDragged(with event: NSEvent) { sendTouch(event, isContact: true) }
    override func mouseUp(with event: NSEvent) { sendTouch(event, isContact: false) }
    override func rightMouseDown(with event: NSEvent) { sendMouse(event, buttons: 2) }
    override func rightMouseDragged(with event: NSEvent) { sendMouse(event, buttons: 2) }
    override func rightMouseUp(with event: NSEvent) { sendMouse(event, buttons: 0) }

    override func scrollWheel(with event: NSEvent) {
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
                    sourceWidth: Int32(FrameContract.width),
                    sourceHeight: Int32(FrameContract.height)
                ) {
                    lastDpadTouch = pt
                    onTouchInput?(TouchInput(x: pt.x, y: pt.y, identifier: 10, phase: .contact))
                }
                return true
            }
        }

        if let btn = keymappingOverlay.profile.buttons.first(where: { $0.keyCode == event.keyCode }) {
            let coord = btn.screenCoordinate(
                sourceWidth: Int32(FrameContract.width),
                sourceHeight: Int32(FrameContract.height)
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
                    sourceWidth: Int32(FrameContract.width),
                    sourceHeight: Int32(FrameContract.height)
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
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            super.keyDown(with: event)
            return
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
        if current.contains(.option) && !previousModifierFlags.contains(.option) {
            onMouseLockToggleRequested?()
        }
        previousModifierFlags = current
        super.flagsChanged(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == [.command, .option] || modifiers == [.option, .command] {
            if let char = event.charactersIgnoringModifiers?.lowercased(), char == "k" {
                onKeymapEditorToggleRequested?()
                return true
            }
        }
        guard modifiers == .command, let char = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch char {
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
        case "v":
            paste(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        onPasteInput?(text)
        onKeyboardInput?(String(text.prefix(1024)), nil)
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
        if textures[slot] == nil {
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
        return true
    }

    private func androidPoint(for event: NSEvent) -> TouchPoint? {
        let location = convert(event.locationInWindow, from: nil)
        let mapper = ViewportMapper(
            sourceSize: CGSize(width: FrameContract.width, height: FrameContract.height),
            viewportSize: bounds.size
        )
        guard let source = mapper.sourcePoint(for: location) else { return nil }
        let x = Int32(max(0, min(FrameContract.width - 1, Int(source.x.rounded()))))
        let topOriginY = FrameContract.height - 1 - Int(source.y.rounded())
        let y = Int32(max(0, min(FrameContract.height - 1, topOriginY)))
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
