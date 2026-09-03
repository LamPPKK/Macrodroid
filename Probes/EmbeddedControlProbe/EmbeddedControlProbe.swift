import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import SwiftProtobuf

// HISTORICAL DIAGNOSTIC ONLY.
// This probe starts the retired direct-control runtime and is intentionally not
// part of release verification. Native live acceptance is owned by TFTMAC.app.

struct ProbeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct ControlStart: Decodable {
    let sessionId: String
    let captureDir: String
    let samplerPid: Int32
    let emulatorPid: Int32
    let sdkRoot: String
    let avdHome: String?
    let embeddedControl: Bool?
}

struct DiscoveryRecord {
    let path: String
    let port: Int
    let token: String
}

@main
enum EmbeddedControlProbe {
    static func main() async {
        do {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let node = URL(fileURLWithPath: "/opt/homebrew/bin/node")
            let controlTool = root.appendingPathComponent("tools/tftmac-direct-control.mjs")
            guard FileManager.default.isExecutableFile(atPath: node.path) else { throw ProbeError("Node.js is unavailable") }
            guard FileManager.default.fileExists(atPath: controlTool.path) else { throw ProbeError("TFTMAC control tool is missing") }

            let startText = try run(node, [controlTool.path, "start-native-controller-probe"])
            let start = try JSONDecoder().decode(ControlStart.self, from: Data(startText.utf8))
            defer { _ = try? run(node, [controlTool.path, "stop"]) }

            guard start.embeddedControl == true else { throw ProbeError("Hidden embedded-control launch was not selected") }
            let discovery = try await waitForDiscovery(pid: start.emulatorPid, avdHome: start.avdHome, captureDir: start.captureDir)

            let transport = try HTTP2ClientTransport.Posix(
                target: .ipv4(address: "127.0.0.1", port: discovery.port),
                transportSecurity: .plaintext
            )
            let status: Android_Emulation_Control_EmulatorStatus = try await withGRPCClient(transport: transport) { grpc in
                let client = Android_Emulation_Control_EmulatorController.Client(wrapping: grpc)
                let request = GRPCCore.ClientRequest(
                    message: SwiftProtobuf.Google_Protobuf_Empty(),
                    metadata: ["authorization": "Bearer \(discovery.token)"]
                )
                return try await client.getStatus(
                    request: request,
                    serializer: GRPCProtobuf.ProtobufSerializer<SwiftProtobuf.Google_Protobuf_Empty>(),
                    deserializer: GRPCProtobuf.ProtobufDeserializer<Android_Emulation_Control_EmulatorStatus>()
                )
            }

            guard status.booted else { throw ProbeError("Authenticated getStatus reports Android not booted") }
            guard status.vmConfig.numberOfCpuCores == 6 else { throw ProbeError("Unexpected CPU count: \(status.vmConfig.numberOfCpuCores)") }
            let ramMiB = status.vmConfig.ramSizeBytes / 1024 / 1024
            guard ramMiB >= 5000 && ramMiB <= 5300 else { throw ProbeError("Unexpected guest RAM: \(ramMiB) MiB") }
            guard status.version.contains("37.1.11") else { throw ProbeError("Unexpected emulator version: \(status.version)") }

            let evidence: [String: Any] = [
                "schema": 1,
                "gate": 2,
                "result": "PASS",
                "hidden": true,
                "authenticatedGetStatus": true,
                "emulatorPid": start.emulatorPid,
                "avd": "TFT_Ultra_Tablet",
                "emulatorVersion": status.version,
                "booted": status.booted,
                "cpuCores": status.vmConfig.numberOfCpuCores,
                "ramMiB": ramMiB,
                "grpcPort": discovery.port,
                "discoveryRecord": discovery.path,
                "sessionId": start.sessionId,
                "captureDir": start.captureDir
            ]
            try writeJSON(evidence, to: root.appendingPathComponent("ssot/native-app-probe-results.json"))

            let authority: [String: Any] = [
                "schema": 1,
                "authority": "INSTALLED_EMULATOR_CONTROLLER",
                "emulatorVersion": status.version,
                "avd": "TFT_Ultra_Tablet",
                "authenticated": true,
                "loopbackOnly": true,
                "discoveryRecord": discovery.path,
                "tokenPersisted": false
            ]
            try writeJSON(authority, to: root.appendingPathComponent("ssot/emulator-controller-authority.json"))
            print("TFTMAC Gate 2: PASS")
        } catch {
            fputs("TFTMAC Gate 2: FAIL: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    static func waitForDiscovery(pid: Int32, avdHome: String?, captureDir: String) async throws -> DiscoveryRecord {
        var home = FileManager.default.homeDirectoryForCurrentUser
        if let marker = captureDir.range(of: "/Library/Application Support/TFTMAC/") {
            home = URL(fileURLWithPath: String(captureDir[..<marker.lowerBound]))
        }
        var candidates: [URL] = []
        if let avdHome { candidates.append(URL(fileURLWithPath: avdHome).appendingPathComponent("running/pid_\(pid).ini")) }
        candidates.append(home.appendingPathComponent(".android/avd/running/pid_\(pid).ini"))

        let emulatorLog = URL(fileURLWithPath: captureDir).appendingPathComponent("emulator.stdout.log")
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: emulatorLog.path),
               let log = try? String(contentsOf: emulatorLog, encoding: .utf8) {
                for line in log.split(whereSeparator: \.isNewline) {
                    let text = String(line)
                    if let range = text.range(of: "Advertising in:") {
                        let advertised = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
                        if !advertised.isEmpty {
                            let url = URL(fileURLWithPath: advertised)
                            if !candidates.contains(url) { candidates.append(url) }
                        }
                    }
                }
            }
            for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
                let values = parseINI(try String(contentsOf: candidate, encoding: .utf8))
                guard let rawPort = values["grpc.port"], let port = Int(rawPort), port > 0 else { continue }
                guard let token = values["grpc.token"], !token.isEmpty else { throw ProbeError("Emulator registration has no grpc.token at \(candidate.path)") }
                return DiscoveryRecord(path: candidate.path, port: port, token: token)
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw ProbeError("No emulator registration record appeared for PID \(pid)")
    }

    static func parseINI(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { result[pair[0].trimmingCharacters(in: .whitespaces)] = pair[1].trimmingCharacters(in: .whitespaces) }
        }
        return result
    }

    static func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    @discardableResult
    static func run(_ executable: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let outText = String(data: stdout, encoding: .utf8) ?? ""
        let errText = String(data: stderr, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else { throw ProbeError(errText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? outText : errText) }
        return outText
    }
}
