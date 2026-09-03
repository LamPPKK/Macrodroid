import AppKit
import ApplicationServices
import Darwin
import Foundation

private struct RelativePoint {
    let x: Double
    let y: Double

    init(_ value: String, option: String) throws {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let x = Double(parts[0]),
              let y = Double(parts[1]),
              (0.0 ... 1.0).contains(x),
              (0.0 ... 1.0).contains(y) else {
            throw BridgeError.invalidArgument("\(option): expected X,Y between 0 and 1")
        }
        self.x = x
        self.y = y
    }

    func pixels(width: Int, height: Int) -> (Int, Int) {
        (
            min(width - 1, max(0, Int((Double(width) * x).rounded()))),
            min(height - 1, max(0, Int((Double(height) * y).rounded())))
        )
    }
}

private enum BridgeError: Error, CustomStringConvertible {
    case invalidArgument(String)

    var description: String {
        switch self {
        case let .invalidArgument(message):
            return message
        }
    }
}

private struct Configuration {
    let targetPID: pid_t
    let targetBundleID: String
    let adbPath: String
    let adbPort: String
    let serial: String
    let width: Int
    let height: Int
    let diagnosticsEnabled: Bool
    let diagnosticsLog: String
    let shopPoint: RelativePoint
    let rerollPoint: RelativePoint
    let xpPoint: RelativePoint
    let traitsPoint: RelativePoint
    let itemsPoint: RelativePoint
    let damagePoint: RelativePoint
    let playersPoint: RelativePoint

    static func parse(_ arguments: [String]) throws -> Configuration {
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard option.hasPrefix("--"), index + 1 < arguments.count else {
                throw BridgeError.invalidArgument("unexpected argument: \(option)")
            }
            values[option] = arguments[index + 1]
            index += 2
        }

        func required(_ option: String) throws -> String {
            guard let value = values[option], !value.isEmpty else {
                throw BridgeError.invalidArgument("missing \(option)")
            }
            return value
        }

        guard let targetPID = pid_t(try required("--target-pid")), targetPID > 0 else {
            throw BridgeError.invalidArgument("--target-pid: expected a positive PID")
        }
        guard let width = Int(try required("--display-width")), width > 0,
              let height = Int(try required("--display-height")), height > 0 else {
            throw BridgeError.invalidArgument("display dimensions must be positive integers")
        }
        let diagnosticsValue = values["--diagnostics"] ?? "0"
        guard diagnosticsValue == "0" || diagnosticsValue == "1" else {
            throw BridgeError.invalidArgument("--diagnostics: expected 0 or 1")
        }

        return try Configuration(
            targetPID: targetPID,
            targetBundleID: values["--target-bundle-id"] ?? "",
            adbPath: required("--adb"),
            adbPort: required("--adb-port"),
            serial: required("--serial"),
            width: width,
            height: height,
            diagnosticsEnabled: diagnosticsValue == "1",
            diagnosticsLog: values["--diagnostics-log"] ?? "",
            shopPoint: RelativePoint(values["--shop-point"] ?? "0.96,0.93", option: "--shop-point"),
            rerollPoint: RelativePoint(values["--reroll-point"] ?? "0.955,0.79", option: "--reroll-point"),
            xpPoint: RelativePoint(values["--xp-point"] ?? "0.032,0.925", option: "--xp-point"),
            traitsPoint: RelativePoint(values["--traits-point"] ?? "0.029,0.04", option: "--traits-point"),
            itemsPoint: RelativePoint(values["--items-point"] ?? "0.059,0.04", option: "--items-point"),
            damagePoint: RelativePoint(values["--damage-point"] ?? "0.947,0.04", option: "--damage-point"),
            playersPoint: RelativePoint(values["--players-point"] ?? "0.975,0.04", option: "--players-point")
        )
    }
}

private enum Action: String {
    case shop
    case reroll
    case buyXP
    case toggleItemsAndTraits
    case togglePlayersAndDamage
}

private enum KeyboardBinding {
    // macOS hardware key codes are layout-independent: D, F, Tab and Space.
    static let reroll: UInt16 = 2
    static let buyXP: UInt16 = 3
    static let playersAndDamage: UInt16 = 9
    static let tab: UInt16 = 48
    static let shop: UInt16 = 49

    static func action(for keyCode: UInt16) -> Action? {
        switch keyCode {
        case shop:
            return .shop
        case reroll:
            return .reroll
        case buyXP:
            return .buyXP
        case playersAndDamage:
            return .togglePlayersAndDamage
        case tab:
            return .toggleItemsAndTraits
        default:
            return nil
        }
    }
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private final class ClickMarkerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.systemRed.withAlphaComponent(0.95).setStroke()
        let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3))
        ring.lineWidth = 3
        ring.stroke()

        NSColor.white.withAlphaComponent(0.95).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: bounds.midX - 2,
            y: bounds.midY - 2,
            width: 4,
            height: 4
        )).fill()
    }
}

private final class ClickMarker {
    private static let size = NSSize(width: 30, height: 30)
    private let panel: NSPanel
    private var generation = 0

    init() {
        _ = NSApplication.shared
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = ClickMarkerView(frame: NSRect(origin: .zero, size: Self.size))
    }

    func show(at point: NSPoint) {
        generation += 1
        let activeGeneration = generation
        panel.setFrameOrigin(NSPoint(
            x: point.x - Self.size.width / 2,
            y: point.y - Self.size.height / 2
        ))
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, generation == activeGeneration else {
                return
            }
            panel.orderOut(nil)
        }
    }
}

private final class InputDiagnostics {
    private struct Sample {
        let timestamp: UInt64
        let action: String
        let x: Int
        let y: Int
    }

    private let marker = ClickMarker()
    private let output: FileHandle
    private let ownsOutput: Bool
    private var samples: [Sample] = []
    private var gestureID = 0

    init(logPath: String) {
        if !logPath.isEmpty {
            let fileManager = FileManager.default
            let directory = URL(fileURLWithPath: logPath).deletingLastPathComponent().path
            do {
                try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
                if !fileManager.fileExists(atPath: logPath) {
                    guard fileManager.createFile(atPath: logPath, contents: nil) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                }
                guard let handle = FileHandle(forWritingAtPath: logPath) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                try handle.seekToEnd()
                output = handle
                ownsOutput = true
                return
            } catch {
                writeError("TFT input bridge: cannot open diagnostics log \(logPath): \(error)")
            }
        }

        output = FileHandle.standardError
        ownsOutput = false
    }

    deinit {
        if ownsOutput {
            try? output.close()
        }
    }

    func record(type: CGEventType, event: CGEvent) {
        let action: String
        switch type {
        case .leftMouseDown:
            gestureID += 1
            samples.removeAll(keepingCapacity: true)
            marker.show(at: NSEvent.mouseLocation)
            action = "down"
        case .leftMouseDragged:
            action = "drag"
        case .leftMouseUp:
            action = "up"
        default:
            return
        }

        let location = event.location
        samples.append(Sample(
            timestamp: event.timestamp,
            action: action,
            x: Int(location.x.rounded()),
            y: Int(location.y.rounded())
        ))

        if type == .leftMouseUp {
            flush()
        }
    }

    private func flush() {
        guard !samples.isEmpty else {
            return
        }
        let lines = samples.map { sample in
            "{\"gesture\":\(gestureID),\"host_ns\":\(sample.timestamp),\"action\":\"\(sample.action)\",\"x\":\(sample.x),\"y\":\(sample.y)}"
        }
        do {
            try output.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
            try output.synchronize()
        } catch {
            writeError("TFT input bridge: diagnostics write failed: \(error)")
        }
        samples.removeAll(keepingCapacity: true)
    }
}

private final class TapDispatcher {
    private let configuration: Configuration
    private let queue = DispatchQueue(label: "com.flashls1.tftmac.input-bridge.adb")
    private var process: Process?
    private var input: FileHandle?
    private var showTraitsNext = true
    private var showDamageNext = true

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    func warmUp() {
        queue.async { [self] in
            do {
                try ensureShell()
            } catch {
                writeError("TFT input bridge: ADB shell warm-up failed: \(error)")
                stopShell()
            }
        }
    }

    func send(_ action: Action) {
        queue.async { [self] in
            let point: RelativePoint
            switch action {
            case .shop:
                point = configuration.shopPoint
            case .reroll:
                point = configuration.rerollPoint
            case .buyXP:
                point = configuration.xpPoint
            case .toggleItemsAndTraits:
                point = showTraitsNext ? configuration.traitsPoint : configuration.itemsPoint
                showTraitsNext.toggle()
            case .togglePlayersAndDamage:
                point = showDamageNext ? configuration.damagePoint : configuration.playersPoint
                showDamageNext.toggle()
            }
            let (x, y) = point.pixels(width: configuration.width, height: configuration.height)

            do {
                try ensureShell()
                guard let input else {
                    return
                }
                try input.write(contentsOf: Data("input tap \(x) \(y)\n".utf8))
            } catch {
                writeError("TFT input bridge: ADB tap failed: \(error)")
                stopShell()
            }
        }
    }

    private func ensureShell() throws {
        if let process, process.isRunning, input != nil {
            return
        }

        stopShell()
        let process = Process()
        let stdin = Pipe()
        process.executableURL = URL(fileURLWithPath: configuration.adbPath)
        process.arguments = ["-P", configuration.adbPort, "-s", configuration.serial, "shell"]
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
        input = stdin.fileHandleForWriting
    }

    private func stopShell() {
        try? input?.close()
        input = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
    }
}

private enum ForegroundActivityState: Equatable {
    case unknown
    case gameplay
    case nonGameplay
}

private final class AndroidActivityMonitor {
    private static let gameplayActivity = "com.epicgames.unreal.GameActivity"
    private static let pollInterval: TimeInterval = 1
    private static let stateMaxAge: TimeInterval = 3

    private let configuration: Configuration
    private let queue = DispatchQueue(label: "com.flashls1.tftmac.input-bridge.activity")
    private let stateLock = NSLock()
    private var state = ForegroundActivityState.unknown
    private var stateUpdatedAt: TimeInterval = 0

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    func start() {
        queue.async { [self] in
            poll()
        }
    }

    // The event-tap callback must never wait for ADB or even for this lock. If a
    // poll is publishing a new value, user input is allowed through.
    var shouldIntercept: Bool {
        guard stateLock.try() else {
            return false
        }
        let currentState = state
        let stateAge = ProcessInfo.processInfo.systemUptime - stateUpdatedAt
        stateLock.unlock()
        return currentState == .gameplay && stateAge <= Self.stateMaxAge
    }

    fileprivate static func classify(dumpsysOutput: String) -> ForegroundActivityState {
        guard let line = dumpsysOutput.split(separator: "\n").first(where: {
            $0.contains("topResumedActivity=")
        }),
        let marker = line.range(of: "topResumedActivity=") else {
            return .unknown
        }

        let payload = line[marker.upperBound...]
        for rawToken in payload.split(whereSeparator: { $0.isWhitespace }) {
            let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: "{}(),"))
            guard let slash = token.firstIndex(of: "/") else {
                continue
            }
            let activity = String(token[token.index(after: slash)...])
            guard !activity.isEmpty else {
                return .unknown
            }
            return activity == gameplayActivity ? .gameplay : .nonGameplay
        }
        return .unknown
    }

    fileprivate func publish(_ newState: ForegroundActivityState) {
        stateLock.lock()
        state = newState
        stateUpdatedAt = ProcessInfo.processInfo.systemUptime
        stateLock.unlock()
    }

    private func poll() {
        publish(queryState())
        queue.asyncAfter(deadline: .now() + Self.pollInterval) { [self] in
            poll()
        }
    }

    private func queryState() -> ForegroundActivityState {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: configuration.adbPath)
        process.arguments = [
            "-P", configuration.adbPort,
            "-s", configuration.serial,
            "shell", "dumpsys activity activities 2>/dev/null | grep -m 1 'topResumedActivity='"
        ]
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .unknown
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            return .unknown
        }
        return Self.classify(dumpsysOutput: output)
    }
}

private final class InputBridge {
    private let configuration: Configuration
    private let dispatcher: TapDispatcher
    private let activityMonitor: AndroidActivityMonitor
    private let diagnostics: InputDiagnostics?
    private var eventTap: CFMachPort?

    init(configuration: Configuration) {
        self.configuration = configuration
        dispatcher = TapDispatcher(configuration: configuration)
        activityMonitor = AndroidActivityMonitor(configuration: configuration)
        diagnostics = configuration.diagnosticsEnabled
            ? InputDiagnostics(logPath: configuration.diagnosticsLog)
            : nil
    }

    func run() -> Never {
        activityMonitor.start()
        dispatcher.warmUp()
        requestAccessibilityIfNeeded()
        _ = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [configuration] _ in
            if Darwin.kill(configuration.targetPID, 0) != 0 && errno != EPERM {
                exit(EXIT_SUCCESS)
            }
        }

        while true {
            if Darwin.kill(configuration.targetPID, 0) != 0 && errno != EPERM {
                exit(EXIT_SUCCESS)
            }
            if installEventTap() {
                writeError("TFT input bridge: in GameActivity, Space=shop, D=reroll, F=buy XP, Tab=items/traits, V=players/damage; right click is blocked.")
                if configuration.diagnosticsEnabled {
                    let destination = configuration.diagnosticsLog.isEmpty
                        ? "stderr"
                        : configuration.diagnosticsLog
                    writeError("TFT input bridge: left-click diagnostics enabled; log=\(destination)")
                }
                CFRunLoopRun()
            }
            writeError("TFT input bridge: grant Accessibility access, then the bridge will retry.")
            Thread.sleep(forTimeInterval: 2)
        }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard isTFTFrontmost else {
            return Unmanaged.passUnretained(event)
        }

        if type == .leftMouseDown || type == .leftMouseUp || type == .leftMouseDragged {
            diagnostics?.record(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard activityMonitor.shouldIntercept else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return nil
        case .keyDown, .keyUp:
            guard let cocoaEvent = NSEvent(cgEvent: event) else {
                return Unmanaged.passUnretained(event)
            }
            let modifiers = cocoaEvent.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty else {
                return Unmanaged.passUnretained(event)
            }

            if let action = KeyboardBinding.action(for: cocoaEvent.keyCode),
               type == .keyDown,
               !cocoaEvent.isARepeat {
                dispatcher.send(action)
            }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private var isTFTFrontmost: Bool {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        if application.processIdentifier == configuration.targetPID {
            return true
        }
        return !configuration.targetBundleID.isEmpty
            && application.bundleIdentifier == configuration.targetBundleID
    }

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else {
            return
        }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    private func installEventTap() -> Bool {
        var eventTypes: [CGEventType] = [
            .keyDown, .keyUp,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged
        ]
        if configuration.diagnosticsEnabled {
            eventTypes += [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
        }
        let mask = eventTypes.reduce(CGEventMask(0)) { result, type in
            result | (CGEventMask(1) << type.rawValue)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: bridgeCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.eventTap = eventTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }
}

private func bridgeCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let bridge = Unmanaged<InputBridge>.fromOpaque(userInfo).takeUnretainedValue()
    return bridge.handle(type: type, event: event)
}

private func runSelfTest() throws {
    let configuration = try Configuration.parse([
        "--target-pid", "42",
        "--adb", "/tmp/adb",
        "--adb-port", "5038",
        "--serial", "emulator-5582",
        "--display-width", "2560",
        "--display-height", "1440",
        "--diagnostics", "1"
    ])
    let gameActivityOutput = """
        Display #0:
          topResumedActivity=ActivityRecord{abc123 u0 com.riotgames.league.teamfighttactics.pbe/com.epicgames.unreal.GameActivity t42}
        """
    let webViewOutput = """
        mResumedActivity: ActivityRecord{old u0 com.riotgames.league.teamfighttactics.pbe/com.epicgames.unreal.GameActivity t41}
        topResumedActivity=ActivityRecord{def456 u0 com.riotgames.league.teamfighttactics.pbe/com.riotgames.platformui.MobileFREWebViewActivity t42}
        """
    let monitor = AndroidActivityMonitor(configuration: configuration)

    guard KeyboardBinding.action(for: 49) == .shop,
          KeyboardBinding.action(for: 2) == .reroll,
          KeyboardBinding.action(for: 3) == .buyXP,
          KeyboardBinding.action(for: 9) == .togglePlayersAndDamage,
          KeyboardBinding.action(for: 48) == .toggleItemsAndTraits,
          configuration.diagnosticsEnabled,
          configuration.shopPoint.pixels(width: 2560, height: 1440) == (2458, 1339),
          configuration.rerollPoint.pixels(width: 2560, height: 1440) == (2445, 1138),
          configuration.xpPoint.pixels(width: 2560, height: 1440) == (82, 1332),
          configuration.traitsPoint.pixels(width: 2560, height: 1440) == (74, 58),
          configuration.itemsPoint.pixels(width: 2560, height: 1440) == (151, 58),
          configuration.damagePoint.pixels(width: 2560, height: 1440) == (2424, 58),
          configuration.playersPoint.pixels(width: 2560, height: 1440) == (2496, 58),
          AndroidActivityMonitor.classify(dumpsysOutput: gameActivityOutput) == .gameplay,
          AndroidActivityMonitor.classify(dumpsysOutput: webViewOutput) == .nonGameplay,
          AndroidActivityMonitor.classify(dumpsysOutput: "topResumedActivity=null") == .unknown,
          !monitor.shouldIntercept else {
        throw BridgeError.invalidArgument("self-test failed")
    }
    monitor.publish(.gameplay)
    guard monitor.shouldIntercept else {
        throw BridgeError.invalidArgument("self-test failed: gameplay gate is closed")
    }
    monitor.publish(.nonGameplay)
    guard !monitor.shouldIntercept else {
        throw BridgeError.invalidArgument("self-test failed: non-gameplay gate is open")
    }
    print("TFT input bridge self-test: OK")
}

do {
    if CommandLine.arguments.dropFirst() == ["--self-test"] {
        try runSelfTest()
        exit(EXIT_SUCCESS)
    }
    let configuration = try Configuration.parse(Array(CommandLine.arguments.dropFirst()))
    InputBridge(configuration: configuration).run()
} catch {
    writeError("TFT input bridge: \(error)")
    exit(EXIT_FAILURE)
}
