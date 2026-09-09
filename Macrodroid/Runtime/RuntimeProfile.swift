import CryptoKit
import Foundation

/// A named, reversible experiment selection. The runtime treats `control` as
/// the normal launch contract; a non-control value must be explicitly applied
/// and recorded by the launch transaction.
enum RuntimeExperimentPreset: String, CaseIterable, Codable, Sendable {
    case control
    case combatLatencyA = "combat_latency_a"
    case retiredHomeRunA = "home_run_a"

    private static let preferenceKey = "runtime.experimentPreset"
    static let baselineEmulatorFeatures = [
        "GLESDynamicVersion",
        "Vulkan",
        "GuestAngle",
        "-GLPipeChecksum",
        "VulkanBatchedDescriptorSetUpdate",
        "AsyncComposeSupport",
        "VirtioGpuFenceContexts"
    ]
    static let selectableCases: [Self] = [.control, .combatLatencyA]

    var displayName: String {
        switch self {
        case .control: "Control (Proven Baseline)"
        case .combatLatencyA: "Combat Latency A"
        case .retiredHomeRunA: "Retired — Performance Mode Beta"
        }
    }

    var detail: String {
        switch self {
        case .control:
            "Uses High / 60 FPS / Performance Mode OFF and the proven emulator settings."
        case .combatLatencyA:
            "Keeps the complete Control graphics stack and requests user-interactive macOS scheduling for the emulator launch."
        case .retiredHomeRunA:
            "Historical receipt only. Riot Performance Mode Beta is rejected and cannot be selected for a new launch."
        }
    }

    var requiresManualPerformanceModeBetaConfirmation: Bool {
        self == .retiredHomeRunA
    }

    var isActiveCandidate: Bool {
        self == .combatLatencyA
    }

    var requestsHostLatencyQoS: Bool {
        self == .combatLatencyA
    }

    var emulatorFeatureAdditions: [String] {
        switch self {
        case .control, .combatLatencyA: []
        case .retiredHomeRunA: ["NativeTextureDecompression", "NoDelayCloseColorBuffer"]
        }
    }

    func effectiveEmulatorFeatures(
        baseline: [String] = RuntimeExperimentPreset.baselineEmulatorFeatures
    ) -> [String] {
        baseline + emulatorFeatureAdditions.filter { !baseline.contains($0) }
    }

    func configurationReceipt(
        baselineFeatures: [String] = RuntimeExperimentPreset.baselineEmulatorFeatures
    ) -> RuntimeExperimentConfigurationReceipt {
        let configuration: [String: Any] = [
            "emulator_features": effectiveEmulatorFeatures(baseline: baselineFeatures),
            "host_qos_requested": requestsHostLatencyQoS ? "user_interactive" : "default",
            "preset": rawValue,
            "requires_manual_performance_mode_beta_confirmation": requiresManualPerformanceModeBetaConfirmation,
            "schema": 2
        ]
        let data = (try? JSONSerialization.data(withJSONObject: configuration, options: [.sortedKeys])) ?? Data()
        return RuntimeExperimentConfigurationReceipt(
            canonicalJSON: String(decoding: data, as: UTF8.self),
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let rawValue = defaults.string(forKey: preferenceKey),
              let preset = Self(rawValue: rawValue),
              Self.selectableCases.contains(preset) else {
            return .control
        }
        return preset
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
    }
}

struct RuntimeExperimentConfigurationReceipt: Sendable, Equatable {
    let canonicalJSON: String
    let sha256: String
}

public enum EngineLaunchPolicy: String, CaseIterable, Codable, Sendable {
    case alwaysBackground = "always_background"
    case onDemand = "on_demand"

    public static let preferenceKey = "macrodroid.engine_launch_policy"

    public var displayName: String {
        switch self {
        case .alwaysBackground:
            return "Chạy ngầm liên tục (Always in Background)"
        case .onDemand:
            return "Chạy khi ấn app (On-Demand)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .alwaysBackground:
            return "Chạy ngầm (Always Warm)"
        case .onDemand:
            return "Chạy khi mở app (On-Demand)"
        }
    }

    public var detail: String {
        switch self {
        case .alwaysBackground:
            return "Android engine tự động khởi động ngầm khi mở Macrodroid. Mở game/app tức thì không có độ trễ."
        case .onDemand:
            return "Chỉ khởi động máy ảo khi bạn bấm mở ứng dụng. Tiết kiệm tài nguyên CPU, RAM và pin khi ở chế độ chờ."
        }
    }

    public static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let raw = defaults.string(forKey: preferenceKey),
              let policy = Self(rawValue: raw) else {
            return .alwaysBackground
        }
        return policy
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
    }
}

public enum EngineCloseBehavior: String, CaseIterable, Codable, Sendable {
    case keepWarm = "keep_warm"
    case stopEngine = "stop_engine"

    public static let preferenceKey = "macrodroid.engine_close_behavior"

    public var displayName: String {
        switch self {
        case .keepWarm:
            return "Giữ Engine chạy ngầm (Keep Warm)"
        case .stopEngine:
            return "Tắt Engine khi đóng app (Stop Engine)"
        }
    }

    public var detail: String {
        switch self {
        case .keepWarm:
            return "Đóng cửa sổ app nhưng giữ engine chạy ngầm để mở app tiếp theo tức thì."
        case .stopEngine:
            return "Tắt hoàn toàn máy ảo khi đóng cửa sổ app để giải phóng toàn bộ RAM và CPU."
        }
    }

    public static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let raw = defaults.string(forKey: preferenceKey),
              let behavior = Self(rawValue: raw) else {
            return .keepWarm
        }
        return behavior
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
    }
}

public enum NotificationPreferences {
    public static let mirroringEnabledKey = "macrodroid.notifications.mirroring_enabled"
    public static let filterSystemKey = "macrodroid.notifications.filter_system"

    public static func isMirroringEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: mirroringEnabledKey) as? Bool ?? true
    }

    public static func setMirroringEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: mirroringEnabledKey)
    }

    public static func isSystemFilterEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: filterSystemKey) as? Bool ?? true
    }

    public static func setSystemFilterEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: filterSystemKey)
    }
}

public struct GuestNotificationRecord: Sendable, Equatable {
    public let key: String
    public let packageName: String
    public let title: String
    public let text: String
    public let appDisplayName: String?
    public let timestamp: Date
    public let importance: Int

    public var appName: String {
        appDisplayName ?? packageName.components(separatedBy: ".").last?.capitalized ?? packageName
    }

    public var isSystemPackage: Bool {
        AndroidNotificationParser.isSystemPackage(packageName)
    }

    public init(
        key: String,
        packageName: String,
        title: String,
        text: String,
        appDisplayName: String? = nil,
        timestamp: Date = Date(),
        importance: Int = 3
    ) {
        self.key = key
        self.packageName = packageName
        self.title = title
        self.text = text
        self.appDisplayName = appDisplayName
        self.timestamp = timestamp
        self.importance = importance
    }
}

public enum AndroidNotificationParser {
    public static func isSystemPackage(_ package: String) -> Bool {
        let lower = package.lowercased()
        return lower == "android" ||
               lower == "com.android.systemui" ||
               lower == "com.google.android.gms" ||
               lower.hasPrefix("com.android.server") ||
               lower.hasPrefix("com.android.providers") ||
               lower == "com.google.android.apps.nexuslauncher"
    }

    public static func parseNotificationKeys(from listOutput: String) -> [String] {
        listOutput.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let colonIdx = trimmed.firstIndex(of: ":") {
                let candidate = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                return candidate.isEmpty ? nil : candidate
            }
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    public static func parseNotificationRecord(key: String, output: String) -> GuestNotificationRecord? {
        parseDetails(from: output, key: key)
    }

    public static func parseKey(_ key: String) -> (userId: Int, packageName: String, id: String)? {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        let userId = Int(parts[0]) ?? 0
        let pkg = String(parts[1])
        let id = String(parts[2])
        return (userId, pkg, id)
    }

    public static func parseDetails(from output: String, key: String) -> GuestNotificationRecord? {
        guard let keyInfo = parseKey(key) else { return nil }
        var title = ""
        var text = ""
        var substName: String?
        var importance = 3

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("android.title=") {
                if let extracted = extractStringValue(from: line) {
                    title = extracted
                }
            } else if line.hasPrefix("android.text=") {
                if let extracted = extractStringValue(from: line) {
                    text = extracted
                }
            } else if line.hasPrefix("android.bigText=") {
                if let extracted = extractStringValue(from: line), !extracted.isEmpty {
                    text = extracted
                }
            } else if line.hasPrefix("android.substName=") {
                substName = extractStringValue(from: line)
            } else if line.hasPrefix("importance=") {
                if let imp = line.dropFirst("importance=".count).split(separator: " ").first.flatMap({ Int($0) }) {
                    importance = imp
                }
            }
        }

        guard !title.isEmpty || !text.isEmpty else { return nil }
        return GuestNotificationRecord(
            key: key,
            packageName: keyInfo.packageName,
            title: title.isEmpty ? (substName ?? keyInfo.packageName) : title,
            text: text,
            appDisplayName: substName,
            timestamp: Date(),
            importance: importance
        )
    }

    private static func extractStringValue(from line: String) -> String? {
        guard let openIdx = line.firstIndex(of: "("),
              let closeIdx = line.lastIndex(of: ")"),
              openIdx < closeIdx else {
            return nil
        }
        let content = String(line[line.index(after: openIdx)..<closeIdx])
        return content.trimmingCharacters(in: .whitespaces)
    }
}

struct MacrodroidRuntimeProfile: Codable, Equatable, Sendable {
    static let supportedVCPU = [4, 6, 8]
    static let supportedRAMMiB = [4096, 5120, 6144, 8192]
    static let supportedRefreshHz = [30, 60, 120]
    static let supportedASGDrawFlushIntervals = [400, 800, 1600]

    static let playable = MacrodroidRuntimeProfile(
        identifier: "macrodroid_5gb_native_v1",
        width: 1920,
        height: 1080,
        densityDPI: 320,
        refreshHz: 60,
        vCPU: 6,
        ramMiB: 5120,
        gpuMode: "host",
        audioBackend: "coreaudio",
        graphicsTransport: "virtio-gpu-asg",
        asgWriteBufferSize: 1_048_576,
        asgWriteStepSize: 16_384,
        asgDataRingSize: 32_768,
        asgDrawFlushInterval: 800,
        controllerPort: 8554,
        angleEnabledFeatures: "exposeNonConformantExtensionsAndVersions:exposeES32ForTesting",
        angleDisabledFeatures: "preferSubmitAtFBOBoundary",
        experimentPreset: .control,
        microphoneEnabled: false
    )

    private enum PreferenceKey {
        static let vCPU = "runtime.vcpu"
        static let ramMiB = "runtime.ramMiB"
        static let refreshHz = "runtime.refreshHz"
        static let asgDrawFlushInterval = "runtime.asgDrawFlushInterval"
        static let microphoneEnabled = "runtime.microphoneEnabled"
    }

    let identifier: String
    let width: Int
    let height: Int
    let densityDPI: Int
    let refreshHz: Int
    let vCPU: Int
    let ramMiB: Int
    let gpuMode: String
    let audioBackend: String
    let graphicsTransport: String
    let asgWriteBufferSize: Int
    let asgWriteStepSize: Int
    let asgDataRingSize: Int
    let asgDrawFlushInterval: Int
    let controllerPort: Int
    let angleEnabledFeatures: String
    let angleDisabledFeatures: String
    let experimentPreset: RuntimeExperimentPreset
    let microphoneEnabled: Bool

    var effectiveEmulatorFeatures: [String] {
        experimentPreset.effectiveEmulatorFeatures()
    }

    var experimentConfigurationReceipt: RuntimeExperimentConfigurationReceipt {
        let configuration: [String: Any] = [
            "angle_disabled_features": angleDisabledFeatures,
            "angle_enabled_features": angleEnabledFeatures,
            "asg_data_ring_size": asgDataRingSize,
            "asg_draw_flush_interval_us": asgDrawFlushInterval,
            "asg_write_buffer_size": asgWriteBufferSize,
            "asg_write_step_size": asgWriteStepSize,
            "audio_backend": audioBackend,
            "controller_port": controllerPort,
            "density_dpi": densityDPI,
            "emulator_features": effectiveEmulatorFeatures,
            "game_mode_eligible": true,
            "gpu_mode": gpuMode,
            "graphics_transport": graphicsTransport,
            "height": height,
            "host_qos_requested": experimentPreset.requestsHostLatencyQoS ? "user_interactive" : "default",
            "microphone_enabled": microphoneEnabled,
            "moltenvk_fast_math": true,
            "moltenvk_max_active_command_buffers": 64,
            "moltenvk_synchronous_queue_submits": false,
            "preset": experimentPreset.rawValue,
            "ram_mib": ramMiB,
            "refresh_hz": refreshHz,
            "requires_manual_performance_mode_beta_confirmation": experimentPreset.requiresManualPerformanceModeBetaConfirmation,
            "schema": 2,
            "tft_frame_rate_cap": 60,
            "tft_graphics_quality": "high",
            "tft_performance_mode_beta_expected": false,
            "vcpu": vCPU,
            "width": width
        ]
        let data = (try? JSONSerialization.data(withJSONObject: configuration, options: [.sortedKeys])) ?? Data()
        return RuntimeExperimentConfigurationReceipt(
            canonicalJSON: String(decoding: data, as: UTF8.self),
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    /// Hash of every locked comparison value with the experiment intervention
    /// normalized to Control. Candidate runs can only pair with a Control run
    /// carrying this same identity.
    var comparisonConfigurationSHA256: String {
        with(experimentPreset: .control).experimentConfigurationReceipt.sha256
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        let preset = RuntimeExperimentPreset.load(from: defaults)
        let vCPU = defaults.object(forKey: PreferenceKey.vCPU) as? Int ?? Self.playable.vCPU
        let ramMiB = defaults.object(forKey: PreferenceKey.ramMiB) as? Int ?? Self.playable.ramMiB
        let refreshHz = defaults.object(forKey: PreferenceKey.refreshHz) as? Int ?? Self.playable.refreshHz
        let asgDrawFlushInterval = defaults.object(forKey: PreferenceKey.asgDrawFlushInterval) as? Int ?? Self.playable.asgDrawFlushInterval
        let microphoneEnabled = defaults.object(forKey: PreferenceKey.microphoneEnabled) as? Bool ?? Self.playable.microphoneEnabled
        return Self.playable
            .with(
                vCPU: vCPU,
                ramMiB: ramMiB,
                refreshHz: refreshHz,
                asgDrawFlushInterval: asgDrawFlushInterval,
                microphoneEnabled: microphoneEnabled
            )
            .with(experimentPreset: preset)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(vCPU, forKey: PreferenceKey.vCPU)
        defaults.set(ramMiB, forKey: PreferenceKey.ramMiB)
        defaults.set(refreshHz, forKey: PreferenceKey.refreshHz)
        defaults.set(asgDrawFlushInterval, forKey: PreferenceKey.asgDrawFlushInterval)
        defaults.set(microphoneEnabled, forKey: PreferenceKey.microphoneEnabled)
        experimentPreset.save(to: defaults)
    }

    func with(
        vCPU: Int,
        ramMiB: Int,
        refreshHz: Int,
        asgDrawFlushInterval: Int,
        microphoneEnabled: Bool? = nil
    ) -> Self {
        let safeVCPU = Self.supportedValue(vCPU, in: Self.supportedVCPU) ?? self.vCPU
        let safeRAM = Self.supportedValue(ramMiB, in: Self.supportedRAMMiB) ?? self.ramMiB
        let safeRefresh = Self.supportedValue(refreshHz, in: Self.supportedRefreshHz) ?? self.refreshHz
        let safeFlush = Self.supportedValue(
            asgDrawFlushInterval,
            in: Self.supportedASGDrawFlushIntervals
        ) ?? self.asgDrawFlushInterval
        let identifier = "macrodroid_native_\(safeRAM)m_\(safeVCPU)c_\(safeRefresh)hz_flush\(safeFlush)"
        return Self(
            identifier: identifier,
            width: width,
            height: height,
            densityDPI: densityDPI,
            refreshHz: safeRefresh,
            vCPU: safeVCPU,
            ramMiB: safeRAM,
            gpuMode: gpuMode,
            audioBackend: audioBackend,
            graphicsTransport: graphicsTransport,
            asgWriteBufferSize: asgWriteBufferSize,
            asgWriteStepSize: asgWriteStepSize,
            asgDataRingSize: asgDataRingSize,
            asgDrawFlushInterval: safeFlush,
            controllerPort: controllerPort,
            angleEnabledFeatures: angleEnabledFeatures,
            angleDisabledFeatures: angleDisabledFeatures,
            experimentPreset: experimentPreset,
            microphoneEnabled: microphoneEnabled ?? self.microphoneEnabled
        )
    }

    func with(microphoneEnabled: Bool) -> Self {
        Self(
            identifier: identifier,
            width: width,
            height: height,
            densityDPI: densityDPI,
            refreshHz: refreshHz,
            vCPU: vCPU,
            ramMiB: ramMiB,
            gpuMode: gpuMode,
            audioBackend: audioBackend,
            graphicsTransport: graphicsTransport,
            asgWriteBufferSize: asgWriteBufferSize,
            asgWriteStepSize: asgWriteStepSize,
            asgDataRingSize: asgDataRingSize,
            asgDrawFlushInterval: asgDrawFlushInterval,
            controllerPort: controllerPort,
            angleEnabledFeatures: angleEnabledFeatures,
            angleDisabledFeatures: angleDisabledFeatures,
            experimentPreset: experimentPreset,
            microphoneEnabled: microphoneEnabled
        )
    }

    func with(experimentPreset: RuntimeExperimentPreset) -> Self {
        let baseIdentifier = identifier.components(separatedBy: "_preset_").first ?? identifier
        let identifier = experimentPreset == .control
            ? baseIdentifier
            : "\(baseIdentifier)_preset_\(experimentPreset.rawValue)"
        return Self(
            identifier: identifier,
            width: width,
            height: height,
            densityDPI: densityDPI,
            refreshHz: refreshHz,
            vCPU: vCPU,
            ramMiB: ramMiB,
            gpuMode: gpuMode,
            audioBackend: audioBackend,
            graphicsTransport: graphicsTransport,
            asgWriteBufferSize: asgWriteBufferSize,
            asgWriteStepSize: asgWriteStepSize,
            asgDataRingSize: asgDataRingSize,
            asgDrawFlushInterval: asgDrawFlushInterval,
            controllerPort: controllerPort,
            angleEnabledFeatures: angleEnabledFeatures,
            angleDisabledFeatures: angleDisabledFeatures,
            experimentPreset: experimentPreset,
            microphoneEnabled: microphoneEnabled
        )
    }

    private static func supportedValue(_ candidate: Int, in allowed: [Int]) -> Int? {
        allowed.contains(candidate) ? candidate : nil
    }
}

struct GuestPowerState: Equatable, Sendable {
    let isPowered: Bool
    let stayOn: Bool
    let wakefulness: String

    var isGameplayReady: Bool {
        isPowered && stayOn && wakefulness.caseInsensitiveCompare("Awake") == .orderedSame
    }

    static func parse(_ dumpsysPower: String) -> Self? {
        guard let powered = boolean(named: "mIsPowered", in: dumpsysPower),
              let stayOn = boolean(named: "mStayOn", in: dumpsysPower),
              let wakefulness = value(named: "mWakefulness", in: dumpsysPower) else {
            return nil
        }
        return Self(isPowered: powered, stayOn: stayOn, wakefulness: wakefulness)
    }

    private static func boolean(named key: String, in text: String) -> Bool? {
        guard let raw = value(named: key, in: text) else { return nil }
        switch raw.lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    private static func value(named key: String, in text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix("\(key)=") }?
            .dropFirst(key.count + 1)
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)
    }
}

struct HostSchedulingReceipt: Equatable, Sendable {
    let requested: String
    let setResult: Int
    let effective: String
    let relativePriority: Int

    var userInteractiveVerified: Bool {
        requested == "user_interactive" && setResult == 0 && effective == "user_interactive"
    }

    static func parse(_ hostOutput: String) -> Self? {
        let fields = Dictionary(uniqueKeysWithValues: hostOutput.split(whereSeparator: \.isNewline).compactMap { line -> (String, String)? in
            let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2, pair[0].hasPrefix("TFTMAC_HOST_QOS_") else { return nil }
            return (pair[0], pair[1])
        })
        guard let requested = fields["TFTMAC_HOST_QOS_REQUESTED"],
              let setResultText = fields["TFTMAC_HOST_QOS_SET_RESULT"],
              let setResult = Int(setResultText),
              let effective = fields["TFTMAC_HOST_QOS_EFFECTIVE"],
              let priorityText = fields["TFTMAC_HOST_QOS_RELATIVE_PRIORITY"],
              let relativePriority = Int(priorityText) else {
            return nil
        }
        return Self(
            requested: requested,
            setResult: setResult,
            effective: effective,
            relativePriority: relativePriority
        )
    }
}

typealias TFTMACRuntimeProfile = MacrodroidRuntimeProfile
