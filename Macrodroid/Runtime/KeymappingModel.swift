//
//  KeymappingModel.swift
//  Macrodroid
//

import CoreGraphics
import Foundation

// MARK: - Keymap Button

public struct KeymapButton: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var key: String
    public var keyCode: UInt16
    public var normalizedX: Double // 0.0 ... 1.0
    public var normalizedY: Double // 0.0 ... 1.0
    public var radius: Double
    public var label: String

    public init(
        id: UUID = UUID(),
        key: String,
        keyCode: UInt16,
        normalizedX: Double,
        normalizedY: Double,
        radius: Double = 24.0,
        label: String = ""
    ) {
        self.id = id
        self.key = key
        self.keyCode = keyCode
        self.normalizedX = max(0.0, min(1.0, normalizedX))
        self.normalizedY = max(0.0, min(1.0, normalizedY))
        self.radius = max(10.0, radius)
        self.label = label
    }

    public func screenCoordinate(sourceWidth: Int32, sourceHeight: Int32) -> (x: Int32, y: Int32) {
        let x = Int32((normalizedX * Double(sourceWidth)).rounded())
        let y = Int32((normalizedY * Double(sourceHeight)).rounded())
        return (x: max(0, min(sourceWidth, x)), y: max(0, min(sourceHeight, y)))
    }
}

// MARK: - Keymap D-Pad

public struct KeymapDPad: Codable, Sendable, Equatable {
    public var wKeyCode: UInt16
    public var aKeyCode: UInt16
    public var sKeyCode: UInt16
    public var dKeyCode: UInt16
    public var normalizedCenterX: Double
    public var normalizedCenterY: Double
    public var radius: Double

    public init(
        wKeyCode: UInt16 = 13, // W
        aKeyCode: UInt16 = 0,  // A
        sKeyCode: UInt16 = 1,  // S
        dKeyCode: UInt16 = 2,  // D
        normalizedCenterX: Double = 0.18,
        normalizedCenterY: Double = 0.72,
        radius: Double = 60.0
    ) {
        self.wKeyCode = wKeyCode
        self.aKeyCode = aKeyCode
        self.sKeyCode = sKeyCode
        self.dKeyCode = dKeyCode
        self.normalizedCenterX = max(0.0, min(1.0, normalizedCenterX))
        self.normalizedCenterY = max(0.0, min(1.0, normalizedCenterY))
        self.radius = max(20.0, radius)
    }

    public func touchPoint(
        wPressed: Bool,
        aPressed: Bool,
        sPressed: Bool,
        dPressed: Bool,
        sourceWidth: Int32,
        sourceHeight: Int32
    ) -> (x: Int32, y: Int32)? {
        guard wPressed || aPressed || sPressed || dPressed else { return nil }

        var dirX: Double = 0.0
        var dirY: Double = 0.0

        if wPressed { dirY -= 1.0 }
        if sPressed { dirY += 1.0 }
        if aPressed { dirX -= 1.0 }
        if dPressed { dirX += 1.0 }

        let length = hypot(dirX, dirY)
        guard length > 0.0 else { return nil }

        let normDirX = dirX / length
        let normDirY = dirY / length

        let centerX = normalizedCenterX * Double(sourceWidth)
        let centerY = normalizedCenterY * Double(sourceHeight)

        let targetX = centerX + (normDirX * radius)
        let targetY = centerY + (normDirY * radius)

        return (
            x: max(0, min(sourceWidth, Int32(targetX.rounded()))),
            y: max(0, min(sourceHeight, Int32(targetY.rounded())))
        )
    }
}

// MARK: - Keymap Mouse Aim

public struct KeymapMouseAim: Codable, Sendable, Equatable {
    public var toggleKeyCode: UInt16
    public var sensitivity: Double
    public var normalizedCenterX: Double
    public var normalizedCenterY: Double

    public init(
        toggleKeyCode: UInt16 = 58, // Left Option (⌥)
        sensitivity: Double = 1.0,
        normalizedCenterX: Double = 0.5,
        normalizedCenterY: Double = 0.5
    ) {
        self.toggleKeyCode = toggleKeyCode
        self.sensitivity = max(0.1, min(5.0, sensitivity))
        self.normalizedCenterX = max(0.0, min(1.0, normalizedCenterX))
        self.normalizedCenterY = max(0.0, min(1.0, normalizedCenterY))
    }
}

// MARK: - Keymap Profile

public struct KeymapProfile: Codable, Sendable, Equatable {
    public var packageName: String
    public var appName: String
    public var buttons: [KeymapButton]
    public var dpad: KeymapDPad?
    public var mouseAim: KeymapMouseAim?
    public var overlayOpacity: Double

    public init(
        packageName: String,
        appName: String,
        buttons: [KeymapButton] = [],
        dpad: KeymapDPad? = nil,
        mouseAim: KeymapMouseAim? = nil,
        overlayOpacity: Double = 0.75
    ) {
        self.packageName = packageName
        self.appName = appName
        self.buttons = buttons
        self.dpad = dpad
        self.mouseAim = mouseAim
        self.overlayOpacity = max(0.0, min(1.0, overlayOpacity))
    }

    public static func defaultPreset(package: String, appName: String) -> KeymapProfile {
        let defaultButtons = [
            KeymapButton(key: "SPACE", keyCode: 49, normalizedX: 0.88, normalizedY: 0.82, label: "Action"),
            KeymapButton(key: "Q", keyCode: 12, normalizedX: 0.78, normalizedY: 0.88, label: "Skill 1"),
            KeymapButton(key: "E", keyCode: 14, normalizedX: 0.82, normalizedY: 0.74, label: "Skill 2"),
            KeymapButton(key: "R", keyCode: 15, normalizedX: 0.90, normalizedY: 0.68, label: "Ultimate"),
            KeymapButton(key: "1", keyCode: 18, normalizedX: 0.70, normalizedY: 0.90, label: "Item 1"),
            KeymapButton(key: "2", keyCode: 19, normalizedX: 0.70, normalizedY: 0.80, label: "Item 2")
        ]
        return KeymapProfile(
            packageName: package,
            appName: appName,
            buttons: defaultButtons,
            dpad: KeymapDPad(),
            mouseAim: KeymapMouseAim(),
            overlayOpacity: 0.75
        )
    }

    public static func mobaPreset(package: String, appName: String) -> KeymapProfile {
        var profile = defaultPreset(package: package, appName: appName)
        profile.buttons.append(KeymapButton(key: "F", keyCode: 3, normalizedX: 0.94, normalizedY: 0.88, label: "Flash"))
        return profile
    }

    public static func fpsPreset(package: String, appName: String) -> KeymapProfile {
        let buttons = [
            KeymapButton(key: "SPACE", keyCode: 49, normalizedX: 0.92, normalizedY: 0.75, label: "Jump"),
            KeymapButton(key: "C", keyCode: 8, normalizedX: 0.85, normalizedY: 0.88, label: "Crouch"),
            KeymapButton(key: "R", keyCode: 15, normalizedX: 0.80, normalizedY: 0.70, label: "Reload"),
            KeymapButton(key: "F", keyCode: 3, normalizedX: 0.75, normalizedY: 0.60, label: "Interact"),
            KeymapButton(key: "SHIFT", keyCode: 56, normalizedX: 0.18, normalizedY: 0.55, label: "Sprint")
        ]
        return KeymapProfile(
            packageName: package,
            appName: appName,
            buttons: buttons,
            dpad: KeymapDPad(normalizedCenterX: 0.18, normalizedCenterY: 0.72, radius: 70.0),
            mouseAim: KeymapMouseAim(toggleKeyCode: 58, sensitivity: 1.2),
            overlayOpacity: 0.70
        )
    }
}

// MARK: - Keymap Profile Store

public enum KeymapProfileStore {
    public static var keymapsDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Macrodroid/Keymaps", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func profileURL(for package: String) -> URL {
        let safePkg = package.replacingOccurrences(of: "/", with: "_")
        return keymapsDirectory.appendingPathComponent("\(safePkg).json")
    }

    public static func loadProfile(for package: String, appName: String = "") -> KeymapProfile {
        let url = profileURL(for: package)
        if let data = try? Data(contentsOf: url),
           let profile = try? JSONDecoder().decode(KeymapProfile.self, from: data) {
            return profile
        }
        return KeymapProfile.defaultPreset(package: package, appName: appName)
    }

    public static func saveProfile(_ profile: KeymapProfile) {
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
