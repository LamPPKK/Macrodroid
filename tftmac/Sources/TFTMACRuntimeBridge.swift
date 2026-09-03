import Foundation
import AppKit
import Combine

@MainActor
final class TFTMACRuntimeBridge: ObservableObject {
    enum Phase: String {
        case idle = "Ready"
        case starting = "Starting Android"
        case waitingForUnlock = "Unlock Android"
        case launchingGame = "Launching TFT"
        case running = "Running"
        case stopping = "Stopping"
        case failed = "Needs attention"
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var detail = "TFTMAC is ready."
    @Published private(set) var emulatorPID: pid_t?
    @Published private(set) var lastScreenshot: String?

    var onEmulatorReady: ((pid_t) -> Void)?
    var onRuntimeStopped: (() -> Void)?

    private let worker = DispatchQueue(label: "com.tftmac.runtime", qos: .userInitiated)
    private var stopping = false

    private var resources: URL {
        guard let url = Bundle.main.resourceURL else { fatalError("TFTMAC resources are missing") }
        return url
    }

    private var tool: URL {
        resources.appendingPathComponent("Tools/tftmac-direct-control.mjs")
    }

    private var node: URL? {
        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }

    private var adb: URL? {
        let candidates = [
            "/Volumes/MAC MINI M4/TFTMAC/Runtime/SDK/platform-tools/adb",
            "/Volumes/MAC MINI M4/TFTMAC/Runtime/sdk/platform-tools/adb"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }

    func start() {
        guard phase == .idle || phase == .failed else { return }
        stopping = false
        phase = .starting
        detail = "Starting the 5 GB TFTMAC runtime, logger, and Android guest…"

        worker.async { [weak self] in
            guard let self else { return }
            do {
                _ = try self.runTool("cleanup-tftmac-adb-residue")
                let start = try self.runTool("start-donor-control-5gb")
                let pid = self.extractPID(from: start)
                DispatchQueue.main.async {
                    if let pid {
                        self.emulatorPID = pid
                        self.onEmulatorReady?(pid)
                    }
                    self.phase = .launchingGame
                    self.detail = "Android is up. Launching official TFT…"
                }
                _ = try? self.runTool("preplay-optimize")
                try self.launchGameWithRetry()
                DispatchQueue.main.async {
                    self.phase = .running
                    self.detail = "TFTMAC · 1920×1080 · 60 Hz · 5 GB"
                }
            } catch {
                guard !self.stopping else { return }
                DispatchQueue.main.async {
                    self.phase = .failed
                    self.detail = error.localizedDescription
                }
            }
        }
    }

    func retryGameLaunch() {
        guard emulatorPID != nil else { start(); return }
        phase = .launchingGame
        detail = "Retrying TFT launch…"
        worker.async { [weak self] in
            guard let self else { return }
            do {
                try self.launchGameWithRetry()
                DispatchQueue.main.async {
                    self.phase = .running
                    self.detail = "TFTMAC · 1920×1080 · 60 Hz · 5 GB"
                }
            } catch {
                DispatchQueue.main.async {
                    self.phase = .failed
                    self.detail = error.localizedDescription
                }
            }
        }
    }

    func stop() {
        guard phase != .idle && phase != .stopping else { return }
        stopping = true
        phase = .stopping
        detail = "Sealing telemetry and shutting down Android…"
        worker.async { [weak self] in
            guard let self else { return }
            _ = try? self.runTool("stop")
            DispatchQueue.main.async {
                self.emulatorPID = nil
                self.phase = .idle
                self.detail = "TFTMAC is stopped."
                self.onRuntimeStopped?()
                self.stopping = false
            }
        }
    }

    func restartTFT() {
        phase = .launchingGame
        detail = "Refreshing only the TFT process…"
        worker.async { [weak self] in
            guard let self else { return }
            do {
                _ = try self.runTool("restart-game")
                DispatchQueue.main.async {
                    self.phase = .running
                    self.detail = "TFT restarted. Android and logging stayed active."
                }
            } catch {
                DispatchQueue.main.async {
                    self.phase = .failed
                    self.detail = error.localizedDescription
                }
            }
        }
    }

    func back() { key("KEYCODE_BACK", label: "Back") }
    func home() { key("KEYCODE_HOME", label: "Home") }
    func overview() { key("KEYCODE_APP_SWITCH", label: "Overview") }
    func volumeUp() { key("KEYCODE_VOLUME_UP", label: "Volume Up") }
    func volumeDown() { key("KEYCODE_VOLUME_DOWN", label: "Volume Down") }
    func mute() { key("KEYCODE_VOLUME_MUTE", label: "Mute") }

    func rotateLeft() { rotate(delta: 3) }
    func rotateRight() { rotate(delta: 1) }

    func screenshot() {
        worker.async { [weak self] in
            guard let self else { return }
            do {
                let adb = try self.requireADB()
                let guest = "/sdcard/Pictures/tftmac-screenshot.png"
                _ = try self.run(adb, ["-P", "5040", "-s", "emulator-5592", "shell", "screencap", "-p", guest])
                let pictures = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Pictures/TFTMAC", isDirectory: true)
                try FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)
                let formatter = ISO8601DateFormatter()
                let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let destination = pictures.appendingPathComponent("TFTMAC-\(stamp).png")
                _ = try self.run(adb, ["-P", "5040", "-s", "emulator-5592", "pull", guest, destination.path])
                _ = try? self.run(adb, ["-P", "5040", "-s", "emulator-5592", "shell", "rm", "-f", guest])
                DispatchQueue.main.async {
                    self.lastScreenshot = destination.path
                    self.detail = "Screenshot saved to Pictures/TFTMAC."
                }
            } catch {
                DispatchQueue.main.async { self.detail = error.localizedDescription }
            }
        }
    }

    func revealAndWakeAndroid() {
        worker.async { [weak self] in
            guard let self else { return }
            _ = try? self.runTool("wake-guest-screen")
        }
    }

    func stopSynchronouslyForTermination() {
        guard emulatorPID != nil || phase != .idle else { return }
        stopping = true
        _ = try? runTool("stop")
    }

    private func launchGameWithRetry() throws {
        var lastError: Error?
        for attempt in 0..<45 {
            if stopping { return }
            do {
                _ = try runTool("launch-game")
                return
            } catch {
                lastError = error
                let message = error.localizedDescription.lowercased()
                let likelyLocked = message.contains("locked") || message.contains("unlock") || message.contains("activity") || message.contains("launcher")
                DispatchQueue.main.async {
                    if likelyLocked {
                        self.phase = .waitingForUnlock
                        self.detail = "Unlock Android if the PIN screen is shown. TFTMAC will continue automatically."
                    } else {
                        self.phase = .launchingGame
                        self.detail = "Waiting for Riot/TFT to become launchable…"
                    }
                }
                if attempt == 0 { _ = try? runTool("wake-guest-screen") }
                Thread.sleep(forTimeInterval: 2.0)
            }
        }
        throw lastError ?? RuntimeError("TFT did not become launchable.")
    }

    private func key(_ keyCode: String, label: String) {
        worker.async { [weak self] in
            guard let self else { return }
            do {
                let adb = try self.requireADB()
                _ = try self.run(adb, ["-P", "5040", "-s", "emulator-5592", "shell", "input", "keyevent", keyCode])
                DispatchQueue.main.async { self.detail = label }
            } catch {
                DispatchQueue.main.async { self.detail = error.localizedDescription }
            }
        }
    }

    private func rotate(delta: Int) {
        worker.async { [weak self] in
            guard let self else { return }
            do {
                let adb = try self.requireADB()
                let raw = try self.run(adb, ["-P", "5040", "-s", "emulator-5592", "shell", "settings", "get", "system", "user_rotation"])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let current = Int(raw) ?? 1
                let next = (current + delta) % 4
                _ = try self.run(adb, ["-P", "5040", "-s", "emulator-5592", "shell", "settings", "put", "system", "accelerometer_rotation", "0"])
                _ = try self.run(adb, ["-P", "5040", "-s", "emulator-5592", "shell", "settings", "put", "system", "user_rotation", "\(next)"])
                DispatchQueue.main.async { self.detail = "Android rotation changed." }
            } catch {
                DispatchQueue.main.async { self.detail = error.localizedDescription }
            }
        }
    }

    private func extractPID(from jsonText: String) -> pid_t? {
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let value = object["emulatorPid"] as? NSNumber { return pid_t(value.int32Value) }
        if let value = object["emulatorPid"] as? Int { return pid_t(value) }
        return nil
    }

    private func runTool(_ action: String) throws -> String {
        guard let node else { throw RuntimeError("Node.js was not found at /opt/homebrew/bin/node.") }
        guard FileManager.default.fileExists(atPath: tool.path) else { throw RuntimeError("Bundled TFTMAC runtime controller is missing.") }
        var environment = ProcessInfo.processInfo.environment
        environment["TFTMAC_REPO_ROOT"] = resources.path
        environment["TFTMAC_NATIVE_FULLSCREEN"] = "1"
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            environment["TFTMAC_HOST_SCREEN_WIDTH"] = String(Int(screen.frame.width.rounded()))
            environment["TFTMAC_HOST_SCREEN_HEIGHT"] = String(Int(screen.frame.height.rounded()))
            environment["TFTMAC_HOST_BACKING_SCALE"] = String(format: "%.6f", screen.backingScaleFactor)
            environment["TFTMAC_NATIVE_CONTROL_WIDTH"] = String(Int(TFTMACWindowCoordinator.controlBarWidth.rounded()))
            environment["TFTMAC_NATIVE_TOPBAR_HEIGHT"] = String(Int(TFTMACWindowCoordinator.topBarHeight.rounded()))
        }
        return try run(node, [tool.path, action], environment: environment)
    }

    private func requireADB() throws -> URL {
        guard let adb else { throw RuntimeError("TFTMAC could not find the Android platform-tools runtime.") }
        return adb
    }

    private func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw RuntimeError(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "\(executable.lastPathComponent) exited with status \(process.terminationStatus)."
                : text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return text
    }
}

struct RuntimeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
