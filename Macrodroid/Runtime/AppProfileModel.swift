//
//  AppProfileModel.swift
//  Macrodroid
//

import Foundation

// MARK: - App Orientation

public enum AppOrientation: String, Codable, Sendable, CaseIterable {
    case auto = "Auto Detect"
    case landscape = "Landscape (16:9)"
    case portrait = "Portrait (9:16)"
    case freeform = "Freeform (Desktop)"

    public var aspectRatio: (width: CGFloat, height: CGFloat)? {
        switch self {
        case .auto: return nil
        case .landscape: return (16.0, 9.0)
        case .portrait: return (9.0, 16.0)
        case .freeform: return nil
        }
    }
}

// MARK: - App Resolution

public enum AppResolution: String, Codable, Sendable, CaseIterable {
    case p720 = "720p HD"
    case p1080 = "1080p Full HD"
    case p1440 = "1440p 2K QHD"
    case retina4K = "4K / Retina Ultra"

    public var dimensions: (width: Int32, height: Int32) {
        switch self {
        case .p720: return (1280, 720)
        case .p1080: return (1920, 1080)
        case .p1440: return (2560, 1440)
        case .retina4K: return (3840, 2160)
        }
    }
}

// MARK: - App Target Frame Rate

public enum AppFrameRate: Int, Codable, Sendable, CaseIterable {
    case fps30 = 30
    case fps60 = 60
    case fps120 = 120

    public var maxFPS: Int { rawValue }

    public var label: String {
        switch self {
        case .fps30: return "30 FPS (Battery Saver)"
        case .fps60: return "60 FPS (Standard Smooth)"
        case .fps120: return "120 FPS (ProMotion Ultra)"
        }
    }
}

// MARK: - App Profile

public struct AppProfile: Codable, Sendable, Equatable {
    public var packageName: String
    public var appName: String
    public var orientation: AppOrientation
    public var resolution: AppResolution
    public var targetFPS: AppFrameRate
    public var vCPU: Int
    public var ramMiB: Int
    public var isVietnameseIMEEnabled: Bool
    public var isKeymapEnabled: Bool

    public init(
        packageName: String,
        appName: String,
        orientation: AppOrientation = .auto,
        resolution: AppResolution = .p1080,
        targetFPS: AppFrameRate = .fps60,
        vCPU: Int = 6,
        ramMiB: Int = 5120,
        isVietnameseIMEEnabled: Bool = false,
        isKeymapEnabled: Bool = true
    ) {
        self.packageName = packageName
        self.appName = appName
        self.orientation = orientation
        self.resolution = resolution
        self.targetFPS = targetFPS
        self.vCPU = max(2, min(8, vCPU))
        self.ramMiB = max(2048, min(8192, ramMiB))
        self.isVietnameseIMEEnabled = isVietnameseIMEEnabled
        self.isKeymapEnabled = isKeymapEnabled
    }

    public static func defaultProfile(for package: String, appName: String = "") -> AppProfile {
        // Automatically default phone-centric apps (TikTok, Instagram, etc.) to Portrait
        let lower = (package + " " + appName).lowercased()
        let isPhoneApp = lower.contains("tiktok") || lower.contains("musically") ||
                         lower.contains("instagram") || lower.contains("threads") ||
                         lower.contains("snapchat") || lower.contains("zalo")

        let orientation: AppOrientation = isPhoneApp ? .portrait : .landscape
        return AppProfile(
            packageName: package,
            appName: appName.isEmpty ? package : appName,
            orientation: orientation,
            resolution: .p1080,
            targetFPS: .fps60,
            vCPU: 6,
            ramMiB: 5120,
            isVietnameseIMEEnabled: isPhoneApp,
            isKeymapEnabled: !isPhoneApp
        )
    }
}

// MARK: - App Profile Store

public enum AppProfileStore {
    public static var profilesDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Macrodroid/Profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func profileURL(for package: String) -> URL {
        let safePkg = package.replacingOccurrences(of: "/", with: "_")
        return profilesDirectory.appendingPathComponent("\(safePkg).json")
    }

    public static func loadProfile(for package: String, appName: String = "") -> AppProfile {
        let url = profileURL(for: package)
        if let data = try? Data(contentsOf: url),
           let profile = try? JSONDecoder().decode(AppProfile.self, from: data) {
            return profile
        }
        return AppProfile.defaultProfile(for: package, appName: appName)
    }

    public static func saveProfile(_ profile: AppProfile) {
        let url = profileURL(for: profile.packageName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(profile) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public static func deleteProfile(for package: String) {
        let url = profileURL(for: package)
        try? FileManager.default.removeItem(at: url)
    }
}
