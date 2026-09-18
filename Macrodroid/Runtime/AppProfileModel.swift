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
    case ultrawide21x9 = "21:9 Ultrawide Gaming"

    public static let fhd1080p: AppResolution = .p1080
    public static let qhd1440p: AppResolution = .p1440
    public static let hd720p: AppResolution = .p720
    public static let uhd4k: AppResolution = .retina4K

    public var dimensions: (width: Int32, height: Int32) {
        switch self {
        case .p720: return (1280, 720)
        case .p1080: return (1920, 1080)
        case .p1440: return (2560, 1440)
        case .retina4K: return (3840, 2160)
        case .ultrawide21x9: return (2560, 1080)
        }
    }

    public func dimensions(for orientation: AppOrientation) -> (width: Int32, height: Int32) {
        let base = dimensions
        if orientation == .portrait {
            return (min(base.width, base.height), max(base.width, base.height))
        } else {
            return (max(base.width, base.height), min(base.width, base.height))
        }
    }
}

// MARK: - App Target Frame Rate

public enum AppFrameRate: Int, Codable, Sendable, CaseIterable {
    case fps30 = 30
    case fps60 = 60
    case fps90 = 90
    case fps120 = 120
    case fps144 = 144

    public var maxFPS: Int { rawValue }

    public var label: String {
        switch self {
        case .fps30: return "30 FPS (Battery Saver)"
        case .fps60: return "60 FPS (Standard Smooth)"
        case .fps90: return "90 FPS (High Refresh Gaming)"
        case .fps120: return "120 FPS (ProMotion Ultra)"
        case .fps144: return "144 FPS (Competitive eSports)"
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
    public var totalPlayTimeSeconds: Int
    public var lastPlayedDate: Date?

    public var effectiveResolution: AppResolution {
        get { resolution }
        set { resolution = newValue }
    }

    public var effectiveDimensions: CGSize {
        let base = resolution.dimensions(for: orientation)
        return CGSize(width: Double(base.width), height: Double(base.height))
    }

    public var formattedPlayTime: String {
        if totalPlayTimeSeconds < 60 {
            return totalPlayTimeSeconds > 0 ? "< 1m played" : "Not played yet"
        }
        let minutes = (totalPlayTimeSeconds / 60) % 60
        let hours = totalPlayTimeSeconds / 3600
        if hours > 0 {
            return "\(hours)h \(minutes)m played"
        } else {
            return "\(minutes)m played"
        }
    }

    public var formattedLastPlayed: String {
        guard let lastPlayedDate else { return "Never" }
        let calendar = Calendar.current
        if calendar.isDateInToday(lastPlayedDate) {
            let timeStr = DateFormatter.localizedString(from: lastPlayedDate, dateStyle: .none, timeStyle: .short)
            return "Today at \(timeStr)"
        } else if calendar.isDateInYesterday(lastPlayedDate) {
            return "Yesterday"
        } else {
            return DateFormatter.localizedString(from: lastPlayedDate, dateStyle: .medium, timeStyle: .none)
        }
    }

    public init(
        packageName: String,
        appName: String,
        orientation: AppOrientation = .auto,
        resolution: AppResolution = .p1080,
        targetFPS: AppFrameRate = .fps60,
        vCPU: Int = 6,
        ramMiB: Int = 5120,
        isVietnameseIMEEnabled: Bool = false,
        isKeymapEnabled: Bool = true,
        totalPlayTimeSeconds: Int = 0,
        lastPlayedDate: Date? = nil
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
        self.totalPlayTimeSeconds = max(0, totalPlayTimeSeconds)
        self.lastPlayedDate = lastPlayedDate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packageName = try container.decode(String.self, forKey: .packageName)
        appName = try container.decode(String.self, forKey: .appName)
        orientation = try container.decodeIfPresent(AppOrientation.self, forKey: .orientation) ?? .auto
        resolution = try container.decodeIfPresent(AppResolution.self, forKey: .resolution) ?? .p1080
        targetFPS = try container.decodeIfPresent(AppFrameRate.self, forKey: .targetFPS) ?? .fps60
        let rawVCPU = try container.decodeIfPresent(Int.self, forKey: .vCPU) ?? 6
        vCPU = max(2, min(8, rawVCPU))
        let rawRAM = try container.decodeIfPresent(Int.self, forKey: .ramMiB) ?? 5120
        ramMiB = max(2048, min(8192, rawRAM))
        isVietnameseIMEEnabled = try container.decodeIfPresent(Bool.self, forKey: .isVietnameseIMEEnabled) ?? false
        isKeymapEnabled = try container.decodeIfPresent(Bool.self, forKey: .isKeymapEnabled) ?? true
        totalPlayTimeSeconds = try container.decodeIfPresent(Int.self, forKey: .totalPlayTimeSeconds) ?? 0
        lastPlayedDate = try container.decodeIfPresent(Date.self, forKey: .lastPlayedDate)
    }

    public static func defaultProfile(for package: String, appName: String = "") -> AppProfile {
        let lower = (package + " " + appName).lowercased()
        let isPhoneApp = lower.contains("tiktok") || lower.contains("musically") ||
                         lower.contains("trill") || lower.contains("instagram") ||
                         lower.contains("threads") || lower.contains("snapchat") ||
                         lower.contains("zalo")

        if let preset = CommunityHub.preset(for: package) {
            return AppProfile(
                packageName: package,
                appName: appName.isEmpty ? preset.title : appName,
                orientation: preset.recommendedOrientation,
                resolution: preset.recommendedResolution,
                targetFPS: preset.recommendedFPS,
                vCPU: 6,
                ramMiB: 5120,
                isVietnameseIMEEnabled: false,
                isKeymapEnabled: !isPhoneApp && !preset.keymapProfile.buttons.isEmpty,
                totalPlayTimeSeconds: 0,
                lastPlayedDate: nil
            )
        }

        let orientation: AppOrientation = isPhoneApp ? .portrait : .landscape
        return AppProfile(
            packageName: package,
            appName: appName.isEmpty ? package : appName,
            orientation: orientation,
            resolution: .p1080,
            targetFPS: .fps60,
            vCPU: 6,
            ramMiB: 5120,
            isVietnameseIMEEnabled: false,
            isKeymapEnabled: !isPhoneApp,
            totalPlayTimeSeconds: 0,
            lastPlayedDate: nil
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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url),
           let profile = try? decoder.decode(AppProfile.self, from: data) {
            return profile
        }
        return AppProfile.defaultProfile(for: package, appName: appName)
    }

    public static func saveProfile(_ profile: AppProfile) {
        let url = profileURL(for: profile.packageName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(profile) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public static func deleteProfile(for package: String) {
        let url = profileURL(for: package)
        try? FileManager.default.removeItem(at: url)
    }
}
