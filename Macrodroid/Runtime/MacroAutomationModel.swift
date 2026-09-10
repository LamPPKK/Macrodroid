//
//  MacroAutomationModel.swift
//  Macrodroid
//

import Foundation

// MARK: - Macro Action Types

public enum MacroActionType: String, Codable, Sendable {
    case touchDown = "touch_down"
    case touchMove = "touch_move"
    case touchUp = "touch_up"
    case keyPress = "key_press"
    case delay = "delay"
}

public struct MacroAction: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let type: MacroActionType
    public let timestampNanoseconds: UInt64
    public var normalizedX: Double?
    public var normalizedY: Double?
    public var keyCode: UInt16?
    public var keyString: String?
    public var delayAfterMS: Int?

    public init(
        id: UUID = UUID(),
        type: MacroActionType,
        timestampNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds,
        normalizedX: Double? = nil,
        normalizedY: Double? = nil,
        keyCode: UInt16? = nil,
        keyString: String? = nil,
        delayAfterMS: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.timestampNanoseconds = timestampNanoseconds
        self.normalizedX = normalizedX.map { max(0.0, min(1.0, $0)) }
        self.normalizedY = normalizedY.map { max(0.0, min(1.0, $0)) }
        self.keyCode = keyCode
        self.keyString = keyString
        self.delayAfterMS = delayAfterMS
    }
}

// MARK: - Macro Sequence

public struct MacroSequence: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var packageName: String
    public var createdAt: Date
    public var actions: [MacroAction]
    public var repeatCount: Int
    public var intervalMS: Int
    public var speedMultiplier: Double
    public var enableHumanJitter: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        packageName: String,
        createdAt: Date = Date(),
        actions: [MacroAction] = [],
        repeatCount: Int = 1,
        intervalMS: Int = 500,
        speedMultiplier: Double = 1.0,
        enableHumanJitter: Bool = true
    ) {
        self.id = id
        self.name = name
        self.packageName = packageName
        self.createdAt = createdAt
        self.actions = actions
        self.repeatCount = max(0, repeatCount)
        self.intervalMS = max(0, intervalMS)
        self.speedMultiplier = max(0.25, min(5.0, speedMultiplier))
        self.enableHumanJitter = enableHumanJitter
    }

    /// Computes touch coordinate with optional anti-detection human variance jitter.
    public func resolvedCoordinate(
        action: MacroAction,
        sourceWidth: Int32,
        sourceHeight: Int32
    ) -> (x: Int32, y: Int32)? {
        guard let normX = action.normalizedX, let normY = action.normalizedY else { return nil }
        var targetX = normX * Double(sourceWidth)
        var targetY = normY * Double(sourceHeight)

        if enableHumanJitter && action.type != .delay {
            // Subtle random offset between -2.0 and +2.0 pixels
            let jitterX = Double.random(in: -2.0...2.0)
            let jitterY = Double.random(in: -2.0...2.0)
            targetX += jitterX
            targetY += jitterY
        }

        let clampedX = Int32(max(0, min(Double(sourceWidth), targetX.rounded())))
        let clampedY = Int32(max(0, min(Double(sourceHeight), targetY.rounded())))
        return (x: clampedX, y: clampedY)
    }
}

// MARK: - Macro Store

public enum MacroStore {
    public static var macrosDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Macrodroid/Macros", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func packageDirectory(for package: String) -> URL {
        let safePkg = package.replacingOccurrences(of: "/", with: "_")
        let dir = macrosDirectory.appendingPathComponent(safePkg, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func listMacros(for package: String) -> [MacroSequence] {
        let dir = packageDirectory(for: package)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }

        var results: [MacroSequence] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let macro = try? decoder.decode(MacroSequence.self, from: data) {
                results.append(macro)
            }
        }
        return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func saveMacro(_ macro: MacroSequence) {
        let dir = packageDirectory(for: macro.packageName)
        let safeName = macro.name.replacingOccurrences(of: "/", with: "_")
        let fileURL = dir.appendingPathComponent("\(safeName).json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(macro) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public static func deleteMacro(name: String, for package: String) {
        let dir = packageDirectory(for: package)
        let safeName = name.replacingOccurrences(of: "/", with: "_")
        let fileURL = dir.appendingPathComponent("\(safeName).json")
        try? FileManager.default.removeItem(at: fileURL)
    }
}
