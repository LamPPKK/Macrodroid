//
//  ImageHealthMonitor.swift
//  Macrodroid
//
//  Pre-launch health checks and post-shutdown maintenance for the Android
//  Virtual Device image files. Runs entirely out-of-band from the emulator
//  gRPC session, so it never blocks the frame pipeline.
//

import CryptoKit
import Foundation

// MARK: - Data models

/// Disk usage sample retrieved from a running guest via ADB shell.
struct DiskUsageSample: Sendable, Equatable {
    /// Used space in /data partition, in MiB.
    let usedMiB: Int
    /// Total space in /data partition, in MiB.
    let totalMiB: Int

    /// Fraction of /data partition in use, 0.0–1.0.
    var usedFraction: Double {
        guard totalMiB > 0 else { return 0 }
        return Double(usedMiB) / Double(totalMiB)
    }

    /// True when more than 80 % of the data partition is consumed.
    var isNearlyFull: Bool { usedFraction > 0.80 }
}

/// Summary of pre-launch image health checks.
struct ImageHealthReport: Sendable {
    /// Size of the `userdata-qemu.img` file on the host, in gigabytes.
    let userdataImageSizeGB: Double
    /// Whether the `snapshots/` directory is absent or appears intact.
    let snapshotHealthy: Bool
    /// Paths to snapshot directories or files that are suspected corrupted.
    let corruptedSnapshotPaths: [URL]
    /// Non-fatal advisory messages.
    let warnings: [String]

    /// `true` when no actionable problems are detected.
    var isHealthy: Bool {
        corruptedSnapshotPaths.isEmpty && warnings.isEmpty
    }

    /// Human-readable summary for display in the Settings sheet.
    var summary: String {
        var lines: [String] = []
        lines.append(String(format: "Userdata image: %.1f GB on disk", userdataImageSizeGB))
        if snapshotHealthy {
            lines.append("Snapshots: healthy (cold-boot enforced)")
        } else {
            lines.append("Snapshots: \(corruptedSnapshotPaths.count) suspect file(s) detected")
        }
        if !warnings.isEmpty {
            lines.append("Warnings: " + warnings.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - ImageHealthMonitor

/// Monitors and maintains the Android Virtual Device image files.
///
/// All methods are `async` so they can safely be called from any concurrency
/// context without blocking the main actor.
actor ImageHealthMonitor {

    // MARK: Interface

    init() {}

    /// Runs health checks before the emulator is launched.
    ///
    /// - Parameter avdDirectory: The `.avd` directory (e.g., `~/.android/avd/TFT_Ultra_Tablet.avd`).
    /// - Returns: An `ImageHealthReport` describing the current state of the virtual disk images.
    func runPreLaunchChecks(avdDirectory: URL) async -> ImageHealthReport {
        let manager = FileManager.default
        var warnings: [String] = []

        // 1. Measure userdata-qemu.img size
        let userdataURL = avdDirectory.appendingPathComponent("userdata-qemu.img")
        var userdataSizeGB: Double = 0
        if let attrs = try? manager.attributesOfItem(atPath: userdataURL.path),
           let bytes = attrs[.size] as? Int64 {
            userdataSizeGB = Double(bytes) / (1024 * 1024 * 1024)
            if userdataSizeGB > 20 {
                warnings.append(String(format: "userdata-qemu.img is %.1f GB — consider reclaiming space", userdataSizeGB))
            }
        } else {
            warnings.append("userdata-qemu.img not found — first launch will create it")
        }

        // 2. Check for unexpected snapshot directories / files
        let corruptedPaths = detectCorruptedSnapshots(avdDirectory: avdDirectory)
        let snapshotHealthy = corruptedPaths.isEmpty

        if !snapshotHealthy {
            warnings.append("\(corruptedPaths.count) suspect snapshot file(s) found — these may cause instability")
        }

        return ImageHealthReport(
            userdataImageSizeGB: userdataSizeGB,
            snapshotHealthy: snapshotHealthy,
            corruptedSnapshotPaths: corruptedPaths,
            warnings: warnings
        )
    }

    /// Cleans up stale residue after a clean emulator shutdown.
    ///
    /// Safe to call even if the emulator is not running; it only removes
    /// known-safe ephemeral files and never touches `userdata-qemu.img`.
    ///
    /// - Parameter avdDirectory: The `.avd` directory for the active AVD.
    func runPostShutdownMaintenance(avdDirectory: URL) async {
        let manager = FileManager.default

        // Remove leftover emulator lock files that can prevent restart
        let lockFiles = [
            "hardware-qemu.ini.lock",
            "multiinstance.lock"
        ]
        for name in lockFiles {
            let url = avdDirectory.appendingPathComponent(name)
            if manager.fileExists(atPath: url.path) {
                try? manager.removeItem(at: url)
            }
        }

        // Remove empty or zero-byte snapshot refs indicating a failed Quick Boot
        let corruptedPaths = detectCorruptedSnapshots(avdDirectory: avdDirectory)
        for path in corruptedPaths {
            try? manager.removeItem(at: path)
        }
    }

    /// Returns paths to snapshot entries that appear corrupted or unexpectedly present.
    ///
    /// Because Macrodroid enforces `fastboot.forceColdBoot=yes`, no valid snapshot
    /// should exist. Any snapshot directory or `.snap` file is therefore suspect.
    ///
    /// - Parameter avdDirectory: The `.avd` directory to inspect.
    /// - Returns: Array of `URL`s that should be removed.
    func detectCorruptedSnapshots(avdDirectory: URL) -> [URL] {
        let manager = FileManager.default
        var suspect: [URL] = []

        // Snapshots live in <avd>/snapshots/
        let snapshotsDir = avdDirectory.appendingPathComponent("snapshots", isDirectory: true)
        if manager.fileExists(atPath: snapshotsDir.path) {
            if let contents = try? manager.contentsOfDirectory(
                at: snapshotsDir,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]
            ) {
                for item in contents {
                    let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if isDir {
                        // Snapshot subdirectory — check for non-trivial size
                        if let enumerator = manager.enumerator(at: item, includingPropertiesForKeys: [.fileSizeKey]) {
                            var totalSize: Int64 = 0
                            for case let fileURL as URL in enumerator {
                                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                                totalSize += Int64(size)
                            }
                            // Any snapshot > 1 MB is suspect (header-only snapshots are ~0 bytes)
                            if totalSize > 1_048_576 {
                                suspect.append(item)
                            }
                        }
                    }
                }
            }
        }

        // Legacy .snap files in the avd root
        if let rootContents = try? manager.contentsOfDirectory(at: avdDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for item in rootContents where item.pathExtension == "snap" {
                suspect.append(item)
            }
        }

        return suspect
    }

    // MARK: - ADB disk usage sampling

    /// Samples `/data` partition usage from the running guest using ADB `df`.
    ///
    /// - Parameters:
    ///   - adb: Path to the `adb` binary.
    ///   - adbPort: ADB server port (default 5038).
    ///   - serial: Emulator ADB serial (default `emulator-5582`).
    /// - Returns: A `DiskUsageSample` or `nil` if ADB is unavailable or the guest is not ready.
    func sampleDiskUsage(
        via adb: URL,
        adbPort: Int = 5038,
        serial: String = "emulator-5582"
    ) async -> DiskUsageSample? {
        guard let result = try? runADB(
            adb,
            port: adbPort,
            serial: serial,
            args: ["shell", "df", "/data"],
            timeout: 8
        ), result.status == 0 else { return nil }

        return parseDFOutput(result.output)
    }

    // MARK: Private helpers

    private func runADB(
        _ adb: URL,
        port: Int,
        serial: String,
        args: [String],
        timeout: TimeInterval
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = adb
        process.arguments = ["-P", "\(port)", "-s", serial] + args
        var env = ProcessInfo.processInfo.environment
        env["ANDROID_ADB_SERVER_PORT"] = "\(port)"
        env.removeValue(forKey: "ADB_VENDOR_KEYS")
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// Parses the output of `adb shell df /data` into a `DiskUsageSample`.
    ///
    /// Expected format (POSIX `df`):
    /// ```
    /// Filesystem     1K-blocks    Used Available Use% Mounted on
    /// /data           8388608  2097152   6291456  25% /data
    /// ```
    func parseDFOutput(_ output: String) -> DiskUsageSample? {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        for line in lines where line.contains("/data") && !line.hasPrefix("Filesystem") {
            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.count >= 4,
                  let totalKiB = Int(tokens[1]),
                  let usedKiB = Int(tokens[2]) else { continue }
            return DiskUsageSample(
                usedMiB: usedKiB / 1024,
                totalMiB: totalKiB / 1024
            )
        }
        return nil
    }
}
