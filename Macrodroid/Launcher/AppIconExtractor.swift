//
//  AppIconExtractor.swift
//  Macrodroid
//

import AppKit
import Foundation

// MARK: - APK Metadata & Real Icon Extractor

public struct APKMetadataExtractor {
    public struct AppMetadata {
        public let packageName: String
        public let appName: String
        public let versionName: String
        public let iconData: Data?

        public init(packageName: String, appName: String, versionName: String, iconData: Data?) {
            self.packageName = packageName
            self.appName = appName
            self.versionName = versionName
            self.iconData = iconData
        }
    }

    public static func extract(from apkURL: URL, sdkRoot: URL?) -> AppMetadata {
        var packageName = apkURL.deletingPathExtension().lastPathComponent
        var appName = apkURL.deletingPathExtension().lastPathComponent
        let versionName = "1.0.0"
        var iconPathInAPK: String?

        // 1. Try finding aapt in sdkRoot/build-tools/*/aapt
        if let sdk = sdkRoot {
            let buildToolsDir = sdk.appendingPathComponent("build-tools")
            if let versions = try? FileManager.default.contentsOfDirectory(atPath: buildToolsDir.path) {
                let sortedVersions = versions.sorted().reversed()
                for v in sortedVersions {
                    let aaptURL = buildToolsDir.appendingPathComponent(v).appendingPathComponent("aapt")
                    if FileManager.default.isExecutableFile(atPath: aaptURL.path) {
                        let process = Process()
                        process.executableURL = aaptURL
                        process.arguments = ["dump", "badging", apkURL.path]
                        let pipe = Pipe()
                        process.standardOutput = pipe
                        process.standardError = Pipe()
                        if (try? process.run()) != nil {
                            process.waitUntilExit()
                            let outData = pipe.fileHandleForReading.readDataToEndOfFile()
                            let dump = String(decoding: outData, as: UTF8.self)

                            // Parse package: name='...'
                            if let pkgRange = dump.range(of: "package: name='") {
                                let remainder = dump[pkgRange.upperBound...]
                                if let endQuote = remainder.range(of: "'") {
                                    packageName = String(remainder[..<endQuote.lowerBound])
                                }
                            }

                            // Parse application-label:'...'
                            if let labelRange = dump.range(of: "application-label:'") {
                                let remainder = dump[labelRange.upperBound...]
                                if let endQuote = remainder.range(of: "'") {
                                    appName = String(remainder[..<endQuote.lowerBound])
                                }
                            }

                            // Parse highest density icon: 640 -> 480 -> 320 -> 240 -> 160 -> icon='
                            let iconKeys = [
                                "application-icon-640:'",
                                "application-icon-480:'",
                                "application-icon-320:'",
                                "application-icon-240:'",
                                "application-icon-160:'",
                                "icon='"
                            ]
                            for key in iconKeys {
                                if let r = dump.range(of: key) {
                                    let remainder = dump[r.upperBound...]
                                    if let quote = remainder.range(of: "'") {
                                        let candidate = String(remainder[..<quote.lowerBound])
                                        if candidate.hasSuffix(".png") || candidate.hasSuffix(".webp") {
                                            iconPathInAPK = candidate
                                            break
                                        }
                                    }
                                }
                            }
                        }
                        break
                    }
                }
            }
        }

        // 2. If aapt didn't yield a direct PNG, scan zip entries using /usr/bin/unzip -l
        if iconPathInAPK == nil || iconPathInAPK?.hasSuffix(".xml") == true {
            let listProcess = Process()
            listProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            listProcess.arguments = ["-l", apkURL.path]
            let listPipe = Pipe()
            listProcess.standardOutput = listPipe
            listProcess.standardError = Pipe()
            if (try? listProcess.run()) != nil {
                listProcess.waitUntilExit()
                let listData = listPipe.fileHandleForReading.readDataToEndOfFile()
                let listOutput = String(decoding: listData, as: UTF8.self)
                let lines = listOutput.components(separatedBy: .newlines)

                let densityPriority = ["xxxhdpi", "xxhdpi", "xhdpi", "hdpi", "mdpi", ""]
                var candidates: [(path: String, priority: Int)] = []
                for line in lines {
                    let parts = line.split(whereSeparator: \.isWhitespace)
                    if let path = parts.last.map(String.init), (path.hasSuffix(".png") || path.hasSuffix(".webp")) {
                        let lower = path.lowercased()
                        if lower.contains("app_icon") || lower.contains("ic_launcher") || lower.contains("icon") || lower.contains("logo") {
                            var p = 0
                            if !lower.contains("background") && !lower.contains("monochrome") {
                                p += 200
                            }
                            for (idx, d) in densityPriority.enumerated() {
                                if !d.isEmpty && lower.contains(d) {
                                    p += 100 - idx
                                    break
                                }
                            }
                            candidates.append((path, p))
                        }
                    }
                }
                candidates.sort { $0.priority > $1.priority }
                iconPathInAPK = candidates.first?.path
            }
        }

        // 3. Extract icon bytes using /usr/bin/unzip -p <apkPath> <iconPath>
        var iconData: Data?
        if let iconPath = iconPathInAPK {
            let extractProcess = Process()
            extractProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            extractProcess.arguments = ["-p", apkURL.path, iconPath]
            let extractPipe = Pipe()
            extractProcess.standardOutput = extractPipe
            extractProcess.standardError = Pipe()
            if (try? extractProcess.run()) != nil {
                extractProcess.waitUntilExit()
                let data = extractPipe.fileHandleForReading.readDataToEndOfFile()
                if !data.isEmpty {
                    iconData = data
                }
            }
        }

        return AppMetadata(
            packageName: packageName,
            appName: appName,
            versionName: versionName,
            iconData: iconData
        )
    }
}

// MARK: - AppIconExtractor

public enum AppIconExtractor {
    public static var iconsDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Macrodroid/Icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func iconURL(for package: String) -> URL {
        iconsDirectory.appendingPathComponent("\(package).png")
    }

    public static func hasCachedIcon(for package: String) -> Bool {
        let url = iconURL(for: package)
        return FileManager.default.fileExists(atPath: url.path)
    }

    @MainActor
    public static func cachedIcon(for package: String) -> NSImage? {
        let url = iconURL(for: package)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
    }

    public static func parsePackageLine(from line: String) -> (package: String, remoteApkPath: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let clean = trimmed.hasPrefix("package:") ? String(trimmed.dropFirst(8)) : trimmed
        guard let eqIndex = clean.lastIndex(of: "=") else { return nil }

        let apkPath = String(clean[..<eqIndex]).trimmingCharacters(in: .whitespaces)
        let pkg = String(clean[clean.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)

        guard !pkg.isEmpty, !apkPath.isEmpty, pkg.contains(".") else { return nil }
        return (package: pkg, remoteApkPath: apkPath)
    }

    public static func discoverInstalledPackages(adbURL: URL) async -> [(package: String, remoteApkPath: String)] {
        await Task.detached { () -> [(package: String, remoteApkPath: String)] in
            let process = Process()
            process.executableURL = adbURL
            process.arguments = ["-P", "5038", "-s", "emulator-5582", "shell", "pm", "list", "packages", "-3", "-f"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self)
                return output.components(separatedBy: .newlines).compactMap { parsePackageLine(from: $0) }
            } catch {
                return []
            }
        }.value
    }

    @MainActor
    public static func extractAndCacheIcon(
        for package: String,
        remoteApkPath: String? = nil,
        adbURL: URL?,
        sdkRootURL: URL?
    ) async -> NSImage? {
        if let cached = cachedIcon(for: package) {
            return cached
        }
        guard let adb = adbURL else { return nil }

        let iconData = await Task.detached { () -> Data? in
            var apkRemote = remoteApkPath
            if apkRemote == nil {
                let pathProcess = Process()
                pathProcess.executableURL = adb
                pathProcess.arguments = ["-P", "5038", "-s", "emulator-5582", "shell", "pm", "path", package]
                let pathPipe = Pipe()
                pathProcess.standardOutput = pathPipe
                pathProcess.standardError = Pipe()
                if (try? pathProcess.run()) != nil {
                    pathProcess.waitUntilExit()
                    let data = pathPipe.fileHandleForReading.readDataToEndOfFile()
                    let out = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let firstLine = out.components(separatedBy: .newlines).first, firstLine.hasPrefix("package:") {
                        apkRemote = String(firstLine.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                    }
                }
            }

            guard let remote = apkRemote, !remote.isEmpty else { return nil }

            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent("macrodroid_icon_\(UUID().uuidString).apk")
            defer { try? FileManager.default.removeItem(at: tempFile) }

            let pullProcess = Process()
            pullProcess.executableURL = adb
            pullProcess.arguments = ["-P", "5038", "-s", "emulator-5582", "pull", remote, tempFile.path]
            pullProcess.standardOutput = Pipe()
            pullProcess.standardError = Pipe()
            guard (try? pullProcess.run()) != nil else { return nil }
            pullProcess.waitUntilExit()

            guard FileManager.default.fileExists(atPath: tempFile.path) else { return nil }

            let meta = APKMetadataExtractor.extract(from: tempFile, sdkRoot: sdkRootURL)
            guard let data = meta.iconData, !data.isEmpty else { return nil }

            let saveURL = iconURL(for: package)
            try? data.write(to: saveURL)

            return data
        }.value

        guard let data = iconData else { return nil }
        return NSImage(data: data)
    }
}
