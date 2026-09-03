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

@MainActor
final class EmbeddedEmulatorView: MTKView, MTKViewDelegate {
    var onTouchInput: ((TouchInput) -> Void)?
    var onMouseInput: ((Int32, Int32, Int32) -> Void)?
    var onKeyboardInput: ((String?, String?) -> Void)?
    var onPresentationSample: ((PresentationSample) -> Void)?
    var onHostPresentationWindow: ((HostPresentationWindow) -> Void)?

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

    init(frame: NSRect, mailbox: LatestFrameMailbox) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("TFTMAC requires Metal on Apple Silicon")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("TFTMAC could not create its persistent Metal command queue")
        }
        self.mailbox = mailbox
        self.commandQueue = commandQueue
        do {
            pipeline = try Self.makePipeline(device: device)
        } catch {
            fatalError("TFTMAC could not create its native frame pipeline: \(error.localizedDescription)")
        }
        super.init(frame: frame, device: device)
        framebufferOnly = true
        colorPixelFormat = .bgra8Unorm_srgb
        preferredFramesPerSecond = 60
        enableSetNeedsDisplay = false
        isPaused = false
        clearColor = MTLClearColorMake(0.015, 0.018, 0.025, 1.0)
        delegate = self
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

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            super.keyDown(with: event)
            return
        }
        if let key = Self.specialKey(for: event) {
            onKeyboardInput?(nil, key)
        } else if let text = event.characters, !text.isEmpty {
            onKeyboardInput?(text, nil)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        onKeyboardInput?(String(text.prefix(1024)), nil)
    }

    @discardableResult
    private func uploadNewestFrameIfPossible() -> Bool {
        guard let frame = mailbox.takeLatest() else { return false }
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
            textures[slot]?.label = "TFTMAC Android frame \(slot)"
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
        let guestLine: String
        if let gameFrameWindow, case .available = gameFrameWindow.status {
            let low = gameFrameWindow.onePercentLowFPS.map { String(format: "%.0f", $0) } ?? "—"
            let p99 = gameFrameWindow.p99MS.map { String(format: "%.1f", $0) } ?? "—"
            guestLine = String(format: "TFT %.0f · 1%% %@ · P99 %@ms", gameFrameWindow.effectiveFPS, low, p99)
        } else {
            guestLine = "TFT —"
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
        addSubview(fpsLabel)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.72),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            fpsLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            fpsLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            fpsLabel.widthAnchor.constraint(equalToConstant: 300),
            fpsLabel.heightAnchor.constraint(equalToConstant: 46)
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

        vertex RasterData tftmac_vertex(uint vertexID [[vertex_id]]) {
            const float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
            // Metal's bottom screen edge must sample the bottom RGBA row.
            // The oversized triangle therefore maps bottom vertices to v=1.
            const float2 coordinates[3] = { float2(0.0, 1.0), float2(2.0, 1.0), float2(0.0, -1.0) };
            RasterData output;
            output.position = float4(positions[vertexID], 0.0, 1.0);
            output.textureCoordinate = coordinates[vertexID];
            return output;
        }

        fragment float4 tftmac_fragment(RasterData input [[stage_in]], texture2d<float> frame [[texture(0)]]) {
            constexpr sampler sampleState(coord::normalized, address::clamp_to_edge, filter::linear);
            return frame.sample(sampleState, input.textureCoordinate);
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "TFTMAC RGBA presenter"
        descriptor.vertexFunction = library.makeFunction(name: "tftmac_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "tftmac_fragment")
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
