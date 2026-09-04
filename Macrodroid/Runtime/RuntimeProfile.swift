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

struct TFTMACRuntimeProfile: Codable, Equatable, Sendable {
    static let supportedVCPU = [4, 6, 8]
    static let supportedRAMMiB = [4096, 5120, 6144]
    static let supportedRefreshHz = [30, 60]
    static let supportedASGDrawFlushIntervals = [400, 800]

    static let playable = TFTMACRuntimeProfile(
        identifier: "tftmac_5gb_native_v1",
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
        experimentPreset: .control
    )

    private enum PreferenceKey {
        static let vCPU = "runtime.vcpu"
        static let ramMiB = "runtime.ramMiB"
        static let refreshHz = "runtime.refreshHz"
        static let asgDrawFlushInterval = "runtime.asgDrawFlushInterval"
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
        Self.playable.with(experimentPreset: RuntimeExperimentPreset.load(from: defaults))
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(vCPU, forKey: PreferenceKey.vCPU)
        defaults.set(ramMiB, forKey: PreferenceKey.ramMiB)
        defaults.set(refreshHz, forKey: PreferenceKey.refreshHz)
        defaults.set(asgDrawFlushInterval, forKey: PreferenceKey.asgDrawFlushInterval)
        experimentPreset.save(to: defaults)
    }

    func with(vCPU: Int, ramMiB: Int, refreshHz: Int, asgDrawFlushInterval: Int) -> Self {
        let safeVCPU = Self.supportedValue(vCPU, in: Self.supportedVCPU) ?? self.vCPU
        let safeRAM = Self.supportedValue(ramMiB, in: Self.supportedRAMMiB) ?? self.ramMiB
        let safeRefresh = Self.supportedValue(refreshHz, in: Self.supportedRefreshHz) ?? self.refreshHz
        let safeFlush = Self.supportedValue(
            asgDrawFlushInterval,
            in: Self.supportedASGDrawFlushIntervals
        ) ?? self.asgDrawFlushInterval
        let identifier = "tftmac_native_\(safeRAM)m_\(safeVCPU)c_\(safeRefresh)hz_flush\(safeFlush)"
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
            experimentPreset: experimentPreset
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
            experimentPreset: experimentPreset
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
