//
//  CommunityHubModel.swift
//  Macrodroid
//

import Foundation

// MARK: - Community Game Preset

public struct CommunityGamePreset: Sendable, Identifiable {
    public let id: String
    public let packageName: String
    public let title: String
    public let genre: String
    public let recommendedResolution: AppResolution
    public let recommendedFPS: AppFrameRate
    public let recommendedOrientation: AppOrientation
    public let keymapProfile: KeymapProfile

    public init(
        id: String,
        packageName: String,
        title: String,
        genre: String,
        recommendedResolution: AppResolution = .p1080,
        recommendedFPS: AppFrameRate = .fps60,
        recommendedOrientation: AppOrientation = .landscape,
        keymapProfile: KeymapProfile
    ) {
        self.id = id
        self.packageName = packageName
        self.title = title
        self.genre = genre
        self.recommendedResolution = recommendedResolution
        self.recommendedFPS = recommendedFPS
        self.recommendedOrientation = recommendedOrientation
        self.keymapProfile = keymapProfile
    }
}

// MARK: - Community Hub Registry

public enum CommunityHub {
    public static let curatedPresets: [CommunityGamePreset] = [
        tftPreset,
        wildRiftPreset,
        genshinPreset,
        pubgPreset,
        tiktokPreset
    ]

    public static var tftPreset: CommunityGamePreset {
        let pkg = "com.riotgames.league.teamfighttactics"
        let buttons = [
            KeymapButton(key: "1", keyCode: 18, normalizedX: 0.28, normalizedY: 0.90, label: "Slot 1"),
            KeymapButton(key: "2", keyCode: 19, normalizedX: 0.40, normalizedY: 0.90, label: "Slot 2"),
            KeymapButton(key: "3", keyCode: 20, normalizedX: 0.52, normalizedY: 0.90, label: "Slot 3"),
            KeymapButton(key: "4", keyCode: 21, normalizedX: 0.64, normalizedY: 0.90, label: "Slot 4"),
            KeymapButton(key: "5", keyCode: 23, normalizedX: 0.76, normalizedY: 0.90, label: "Slot 5"),
            KeymapButton(key: "D", keyCode: 2, normalizedX: 0.12, normalizedY: 0.85, label: "Reroll"),
            KeymapButton(key: "F", keyCode: 3, normalizedX: 0.12, normalizedY: 0.72, label: "Level Up"),
            KeymapButton(key: "E", keyCode: 14, normalizedX: 0.88, normalizedY: 0.85, label: "Sell")
        ]
        let profile = KeymapProfile(
            packageName: pkg,
            appName: "Teamfight Tactics",
            buttons: buttons,
            dpad: nil,
            mouseAim: nil,
            overlayOpacity: 0.75
        )
        return CommunityGamePreset(
            id: "tft_pro",
            packageName: pkg,
            title: "Teamfight Tactics (TFT)",
            genre: "Auto-Battler",
            recommendedResolution: .p1080,
            recommendedFPS: .fps60,
            recommendedOrientation: .landscape,
            keymapProfile: profile
        )
    }

    public static var wildRiftPreset: CommunityGamePreset {
        let pkg = "com.riotgames.league.wildrift"
        let buttons = [
            KeymapButton(key: "Q", keyCode: 12, normalizedX: 0.75, normalizedY: 0.85, label: "Ability 1"),
            KeymapButton(key: "W", keyCode: 13, normalizedX: 0.80, normalizedY: 0.72, label: "Ability 2"),
            KeymapButton(key: "E", keyCode: 14, normalizedX: 0.87, normalizedY: 0.62, label: "Ability 3"),
            KeymapButton(key: "R", keyCode: 15, normalizedX: 0.94, normalizedY: 0.55, label: "Ultimate"),
            KeymapButton(key: "SPACE", keyCode: 49, normalizedX: 0.90, normalizedY: 0.85, label: "Attack"),
            KeymapButton(key: "D", keyCode: 2, normalizedX: 0.70, normalizedY: 0.70, label: "Flash"),
            KeymapButton(key: "F", keyCode: 3, normalizedX: 0.65, normalizedY: 0.82, label: "Ignite"),
            KeymapButton(key: "B", keyCode: 11, normalizedX: 0.55, normalizedY: 0.92, label: "Recall")
        ]
        let profile = KeymapProfile(
            packageName: pkg,
            appName: "League of Legends: Wild Rift",
            buttons: buttons,
            dpad: KeymapDPad(normalizedCenterX: 0.18, normalizedCenterY: 0.75, radius: 65.0),
            mouseAim: nil,
            overlayOpacity: 0.70
        )
        return CommunityGamePreset(
            id: "wildrift_moba",
            packageName: pkg,
            title: "League of Legends: Wild Rift",
            genre: "MOBA",
            recommendedResolution: .p1440,
            recommendedFPS: .fps120,
            recommendedOrientation: .landscape,
            keymapProfile: profile
        )
    }

    public static var genshinPreset: CommunityGamePreset {
        let pkg = "com.miHoYo.GenshinImpact"
        let buttons = [
            KeymapButton(key: "SPACE", keyCode: 49, normalizedX: 0.92, normalizedY: 0.82, label: "Jump"),
            KeymapButton(key: "E", keyCode: 14, normalizedX: 0.82, normalizedY: 0.75, label: "Elemental Skill"),
            KeymapButton(key: "Q", keyCode: 12, normalizedX: 0.75, normalizedY: 0.62, label: "Elemental Burst"),
            KeymapButton(key: "SHIFT", keyCode: 56, normalizedX: 0.94, normalizedY: 0.68, label: "Dash"),
            KeymapButton(key: "F", keyCode: 3, normalizedX: 0.68, normalizedY: 0.50, label: "Interact")
        ]
        let profile = KeymapProfile(
            packageName: pkg,
            appName: "Genshin Impact",
            buttons: buttons,
            dpad: KeymapDPad(normalizedCenterX: 0.18, normalizedCenterY: 0.72, radius: 70.0),
            mouseAim: KeymapMouseAim(toggleKeyCode: 58, sensitivity: 1.2),
            overlayOpacity: 0.65
        )
        return CommunityGamePreset(
            id: "genshin_rpg",
            packageName: pkg,
            title: "Genshin Impact",
            genre: "Action RPG",
            recommendedResolution: .p1080,
            recommendedFPS: .fps60,
            recommendedOrientation: .landscape,
            keymapProfile: profile
        )
    }

    public static var pubgPreset: CommunityGamePreset {
        let pkg = "com.tencent.ig"
        let buttons = [
            KeymapButton(key: "SPACE", keyCode: 49, normalizedX: 0.94, normalizedY: 0.75, label: "Jump"),
            KeymapButton(key: "C", keyCode: 8, normalizedX: 0.86, normalizedY: 0.88, label: "Crouch"),
            KeymapButton(key: "Z", keyCode: 6, normalizedX: 0.94, normalizedY: 0.88, label: "Prone"),
            KeymapButton(key: "R", keyCode: 15, normalizedX: 0.80, normalizedY: 0.70, label: "Reload"),
            KeymapButton(key: "F", keyCode: 3, normalizedX: 0.75, normalizedY: 0.55, label: "Loot")
        ]
        let profile = KeymapProfile(
            packageName: pkg,
            appName: "PUBG Mobile",
            buttons: buttons,
            dpad: KeymapDPad(normalizedCenterX: 0.18, normalizedCenterY: 0.70, radius: 65.0),
            mouseAim: KeymapMouseAim(toggleKeyCode: 58, sensitivity: 1.5),
            overlayOpacity: 0.65
        )
        return CommunityGamePreset(
            id: "pubg_fps",
            packageName: pkg,
            title: "PUBG Mobile",
            genre: "Battle Royale",
            recommendedResolution: .p1080,
            recommendedFPS: .fps60,
            recommendedOrientation: .landscape,
            keymapProfile: profile
        )
    }

    public static var tiktokPreset: CommunityGamePreset {
        let pkg = "com.zhiliaoapp.musically"
        let buttons = [
            KeymapButton(key: "S", keyCode: 1, normalizedX: 0.50, normalizedY: 0.80, label: "Next Video"),
            KeymapButton(key: "W", keyCode: 13, normalizedX: 0.50, normalizedY: 0.20, label: "Previous Video"),
            KeymapButton(key: "SPACE", keyCode: 49, normalizedX: 0.50, normalizedY: 0.50, label: "Like / Pause"),
            KeymapButton(key: "D", keyCode: 2, normalizedX: 0.90, normalizedY: 0.65, label: "Comments")
        ]
        let profile = KeymapProfile(
            packageName: pkg,
            appName: "TikTok",
            buttons: buttons,
            dpad: nil,
            mouseAim: nil,
            overlayOpacity: 0.50
        )
        return CommunityGamePreset(
            id: "tiktok_social",
            packageName: pkg,
            title: "TikTok",
            genre: "Social Video",
            recommendedResolution: .p1080,
            recommendedFPS: .fps60,
            recommendedOrientation: .portrait,
            keymapProfile: profile
        )
    }

    public static func preset(for package: String) -> CommunityGamePreset? {
        curatedPresets.first { $0.packageName == package }
    }
}

// MARK: - Macrodroid Bundle Format (.macrodroid)

public struct MacrodroidBundle: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let packageName: String
    public let appName: String
    public let exportedAt: Date
    public let keymap: KeymapProfile
    public let appProfile: AppProfile

    public init(
        packageName: String,
        appName: String,
        keymap: KeymapProfile,
        appProfile: AppProfile,
        exportedAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.packageName = packageName
        self.appName = appName
        self.exportedAt = exportedAt
        self.keymap = keymap
        self.appProfile = appProfile
    }

    public func export(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> MacrodroidBundle {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MacrodroidBundle.self, from: data)
    }
}
