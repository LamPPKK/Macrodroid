//
//  FreeformTaskManager.swift
//  Macrodroid
//

import Foundation

public struct AndroidTaskRecord: Sendable, Hashable, Identifiable {
    public let id: Int
    public let package: String
    public let activity: String
    public let isFreeform: Bool
    public let label: String

    public init(id: Int, package: String, activity: String, isFreeform: Bool = false, label: String? = nil) {
        self.id = id
        self.package = package
        self.activity = activity
        self.isFreeform = isFreeform
        if let label, !label.isEmpty {
            self.label = label
        } else {
            let lastComponent = package.components(separatedBy: ".").last ?? package
            self.label = lastComponent.capitalized
        }
    }
}

public enum FreeformTaskManager {
    public static func parseTasks(from output: String) -> [AndroidTaskRecord] {
        var tasks: [AndroidTaskRecord] = []
        var seenIds = Set<Int>()

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Pattern 1: "* Task{... #12 type=standard A=com.example.app ...}"
            if trimmed.contains("Task{") && trimmed.contains("#") {
                if let hashRange = trimmed.range(of: "#") {
                    let afterHash = trimmed[hashRange.upperBound...]
                    let idString = afterHash.prefix(while: { $0.isNumber })
                    if let taskId = Int(idString), !seenIds.contains(taskId) {
                        var pkg = ""
                        var act = ""
                        if let aRange = trimmed.range(of: "A=") {
                            let afterA = trimmed[aRange.upperBound...]
                            let component = String(afterA.prefix(while: { !$0.isWhitespace && $0 != "}" }))
                            if component.contains("/") {
                                let parts = component.components(separatedBy: "/")
                                pkg = parts.first ?? ""
                                act = parts.count > 1 ? parts[1] : ""
                            } else {
                                pkg = component
                            }
                        }
                        if !pkg.isEmpty {
                            let isFreeform = trimmed.contains("windowingMode=freeform") || trimmed.contains("mode=5")
                            seenIds.insert(taskId)
                            tasks.append(AndroidTaskRecord(id: taskId, package: pkg, activity: act, isFreeform: isFreeform))
                        }
                    }
                }
            }

            // Pattern 2: "Task id #12: com.example.app/com.example.app.MainActivity"
            // or "taskId=12: com.example.app"
            if trimmed.localizedCaseInsensitiveContains("task id #") || trimmed.localizedCaseInsensitiveContains("taskid=") {
                let lower = trimmed.lowercased()
                let marker = lower.contains("task id #") ? "task id #" : "taskid="
                if let range = lower.range(of: marker) {
                    let afterMarker = trimmed[range.upperBound...]
                    let idString = afterMarker.prefix(while: { $0.isNumber })
                    if let taskId = Int(idString), !seenIds.contains(taskId) {
                        if let colonRange = afterMarker.range(of: ":") {
                            let rawComponent = String(afterMarker[colonRange.upperBound...])
                                .trimmingCharacters(in: .whitespaces)
                                .components(separatedBy: .whitespaces).first ?? ""
                            let pkg: String
                            let act: String
                            if rawComponent.contains("/") {
                                let parts = rawComponent.components(separatedBy: "/")
                                pkg = parts[0]
                                act = parts.count > 1 ? parts[1] : ""
                            } else {
                                pkg = rawComponent
                                act = ""
                            }
                            if !pkg.isEmpty && pkg.contains(".") {
                                seenIds.insert(taskId)
                                let isFreeform = trimmed.contains("freeform")
                                tasks.append(AndroidTaskRecord(id: taskId, package: pkg, activity: act, isFreeform: isFreeform))
                            }
                        }
                    }
                }
            }
        }

        return tasks
    }

    public static func launchInFreeformArguments(component: String) -> [String] {
        ["shell", "am", "start", "-n", component, "--windowingMode", "5"]
    }

    public static func launchInFreeformArguments(package: String) -> [String] {
        ["shell", "monkey", "-p", package, "-c", "android.intent.category.LAUNCHER", "1"]
    }

    public static func forceStopArguments(package: String) -> [String] {
        ["shell", "am", "force-stop", package]
    }
}
