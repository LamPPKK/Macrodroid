//
//  HardwareCapabilityProbe.swift
//  Macrodroid
//
//  Detects the host Apple Silicon memory tier via sysctlbyname and returns
//  the most appropriate MacrodroidRuntimeProfile for the detected hardware.
//  No special entitlements or permissions are required.
//

import Darwin
import Foundation

// MARK: - Silicon Tier

/// Coarse-grained Apple Silicon tier derived exclusively from physical RAM
/// (the only reliable, permission-free signal on macOS).
///
/// - `ultraMax`: ≥ 64 GB — Mac Studio / Mac Pro M4 Max configurations
/// - `pro`: ≥ 24 GB — MacBook Pro M4 Pro / Mac Mini M4 Pro
/// - `standard`: ≥ 16 GB — MacBook Air / Mac Mini M4 base
/// - `compat`: < 16 GB — M1/M2/M3 base models or 8 GB configurations
enum SiliconTier: String, Sendable, Equatable, CaseIterable {
    case ultraMax = "ultra_max"
    case pro      = "pro"
    case standard = "standard"
    case compat   = "compat"

    /// Human-readable label shown in the Settings UI hardware-tier badge.
    var displayLabel: String {
        switch self {
        case .ultraMax: return "Ultra Max (≥ 64 GB)"
        case .pro:      return "Pro (≥ 24 GB)"
        case .standard: return "Standard (≥ 16 GB)"
        case .compat:   return "Compat (< 16 GB)"
        }
    }

    /// SF Symbol name suitable for a tier badge icon.
    var symbolName: String {
        switch self {
        case .ultraMax: return "bolt.fill"
        case .pro:      return "cpu.fill"
        case .standard: return "memorychip.fill"
        case .compat:   return "checkmark.seal"
        }
    }
}

// MARK: - HardwareCapabilityProbe

/// Probes the host hardware and recommends an optimised Android runtime profile.
///
/// ```swift
/// let probe = HardwareCapabilityProbe.current
/// let profile = probe.recommendedProfile
/// ```
struct HardwareCapabilityProbe: Sendable {

    // MARK: Interface

    /// Cached probe result for the current host.
    static let current: HardwareCapabilityProbe = {
        let physicalRAMBytes = HardwareCapabilityProbe.readPhysicalRAMBytes()
        let tier = HardwareCapabilityProbe.tier(for: physicalRAMBytes)
        return HardwareCapabilityProbe(physicalRAMBytes: physicalRAMBytes, tier: tier)
    }()

    /// Physical RAM installed in the host, in bytes.
    let physicalRAMBytes: UInt64

    /// Detected silicon tier.
    let tier: SiliconTier

    /// Physical RAM in gibibytes.
    var physicalRAMGiB: Double {
        Double(physicalRAMBytes) / (1024 * 1024 * 1024)
    }

    /// Returns a `MacrodroidRuntimeProfile` optimised for the detected tier.
    ///
    /// The profile is layered on top of `MacrodroidRuntimeProfile.playable`
    /// to inherit all proven baseline settings (GPU mode, ANGLE flags, etc.),
    /// only overriding the fields that benefit from extra host resources.
    var recommendedProfile: MacrodroidRuntimeProfile {
        switch tier {
        case .ultraMax:
            // 64 GB+ host: push to 8 vCPU, 8 GB guest RAM, 4 MB ASG write buffer
            return MacrodroidRuntimeProfile.playable
                .with(
                    vCPU: 8,
                    ramMiB: 8192,
                    refreshHz: 60,
                    asgDrawFlushInterval: 800,
                    microphoneEnabled: false,
                    dataDiskGB: 12
                )
                .withASGBuffers(writeBufferSize: 4_194_304, writeStepSize: 65_536, dataRingSize: 131_072)

        case .pro:
            // 24 GB+ host: 6 vCPU, 6 GB guest RAM, 2 MB ASG write buffer
            return MacrodroidRuntimeProfile.playable
                .with(
                    vCPU: 6,
                    ramMiB: 6144,
                    refreshHz: 60,
                    asgDrawFlushInterval: 800,
                    microphoneEnabled: false,
                    dataDiskGB: 8
                )
                .withASGBuffers(writeBufferSize: 2_097_152, writeStepSize: 32_768, dataRingSize: 65_536)

        case .standard:
            // 16 GB host: keep proven defaults (5 GB, 6 vCPU, 32 KB step)
            return MacrodroidRuntimeProfile.playable

        case .compat:
            // < 16 GB: reduce guest RAM to 4 GB, 4 vCPU to leave headroom for host
            return MacrodroidRuntimeProfile.playable
                .with(
                    vCPU: 4,
                    ramMiB: 4096,
                    refreshHz: 60,
                    asgDrawFlushInterval: 800,
                    microphoneEnabled: false,
                    dataDiskGB: 6
                )
                .withASGBuffers(writeBufferSize: 524_288, writeStepSize: 16_384, dataRingSize: 32_768)
        }
    }

    // MARK: Internal helpers

    /// Reads `hw.memsize` via `sysctlbyname` (no entitlements required).
    /// Returns 0 if the sysctl is unavailable.
    static func readPhysicalRAMBytes() -> UInt64 {
        var size = MemoryLayout<UInt64>.size
        var value: UInt64 = 0
        sysctlbyname("hw.memsize", &value, &size, nil, 0)
        return value
    }

    static func tier(for physicalRAMBytes: UInt64) -> SiliconTier {
        let gib = physicalRAMBytes / (1024 * 1024 * 1024)
        switch gib {
        case 64...:  return .ultraMax
        case 24...:  return .pro
        case 16...:  return .standard
        default:     return .compat
        }
    }
}

// MARK: - MacrodroidRuntimeProfile + ASG tuning helper

extension MacrodroidRuntimeProfile {
    /// Returns a copy with custom ASG buffer parameters.
    /// Used internally by `HardwareCapabilityProbe.recommendedProfile`.
    func withASGBuffers(
        writeBufferSize: Int,
        writeStepSize: Int,
        dataRingSize: Int
    ) -> MacrodroidRuntimeProfile {
        MacrodroidRuntimeProfile(
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
            asgWriteBufferSize: writeBufferSize,
            asgWriteStepSize: writeStepSize,
            asgDataRingSize: dataRingSize,
            asgDrawFlushInterval: asgDrawFlushInterval,
            controllerPort: controllerPort,
            angleEnabledFeatures: angleEnabledFeatures,
            angleDisabledFeatures: angleDisabledFeatures,
            experimentPreset: experimentPreset,
            microphoneEnabled: microphoneEnabled,
            dataDiskGB: dataDiskGB
        )
    }
}
