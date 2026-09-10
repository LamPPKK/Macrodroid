//
//  GamepadManager.swift
//  Macrodroid
//

import Foundation
import GameController

// MARK: - Gamepad Types

public enum GamepadType: String, Codable, Sendable {
    case dualSense = "PlayStation DualSense"
    case dualShock4 = "PlayStation DualShock 4"
    case xbox = "Xbox Wireless Controller"
    case switchPro = "Nintendo Switch Pro Controller"
    case mfi = "MFi Controller"
    case generic = "Generic Gamepad"

    public static func detect(from controller: GCController) -> GamepadType {
        let name = controller.vendorName?.lowercased() ?? ""
        if name.contains("dualsense") {
            return .dualSense
        } else if name.contains("dualshock") || name.contains("wireless controller") {
            return .dualShock4
        } else if name.contains("xbox") {
            return .xbox
        } else if name.contains("switch") || name.contains("pro controller") {
            return .switchPro
        } else if controller.extendedGamepad != nil {
            return .mfi
        }
        return .generic
    }
}

public enum GamepadButton: String, Codable, Sendable, CaseIterable {
    case buttonA = "A / Cross"
    case buttonB = "B / Circle"
    case buttonX = "X / Square"
    case buttonY = "Y / Triangle"
    case leftShoulder = "L1 / LB"
    case rightShoulder = "R1 / RB"
    case leftTrigger = "L2 / LT"
    case rightTrigger = "R2 / RT"
    case dpadUp = "D-Pad Up"
    case dpadDown = "D-Pad Down"
    case dpadLeft = "D-Pad Left"
    case dpadRight = "D-Pad Right"
    case leftThumbstickButton = "L3"
    case rightThumbstickButton = "R3"
    case options = "Options / Start"
    case menu = "Share / Back"
}

public struct GamepadState: Sendable, Equatable {
    public let name: String
    public let type: GamepadType
    public let batteryLevel: Float?
    public let isConnected: Bool

    public init(
        name: String,
        type: GamepadType,
        batteryLevel: Float? = nil,
        isConnected: Bool = true
    ) {
        self.name = name
        self.type = type
        self.batteryLevel = batteryLevel
        self.isConnected = isConnected
    }
}

// MARK: - Gamepad Manager

@MainActor
public final class GamepadManager {
    public static let shared = GamepadManager()

    public var onControllerConnected: ((GamepadState) -> Void)?
    public var onControllerDisconnected: ((String) -> Void)?
    public var onButtonChanged: ((GamepadButton, Bool, Float) -> Void)?
    public var onLeftThumbstickMoved: ((Float, Float) -> Void)?
    public var onRightThumbstickMoved: ((Float, Float) -> Void)?

    private(set) var activeController: GCController?
    private(set) var currentState: GamepadState?

    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    public init() {
        startMonitoring()
    }

    public func startMonitoring() {
        if let first = GCController.controllers().first {
            configureController(first)
        }

        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let controller = GCController.controllers().first {
                    self.configureController(controller)
                }
            }
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.handleControllerDisconnected()
            }
        }
    }

    public func stopMonitoring() {
        if let connectObserver {
            NotificationCenter.default.removeObserver(connectObserver)
        }
        if let disconnectObserver {
            NotificationCenter.default.removeObserver(disconnectObserver)
        }
        connectObserver = nil
        disconnectObserver = nil
        activeController = nil
        currentState = nil
    }

    private func configureController(_ controller: GCController) {
        activeController = controller
        let type = GamepadType.detect(from: controller)
        let name = controller.vendorName ?? type.rawValue
        let battery = controller.battery?.batteryLevel

        let state = GamepadState(name: name, type: type, batteryLevel: battery, isConnected: true)
        currentState = state
        onControllerConnected?(state)

        guard let extended = controller.extendedGamepad else { return }

        extended.valueChangedHandler = { [weak self] gamepad, element in
            guard let self else { return }
            self.handleGamepadElementChange(gamepad: gamepad, element: element)
        }
    }

    private func handleControllerDisconnected() {
        let remaining = GCController.controllers()
        if let current = activeController, !remaining.contains(current) {
            let name = currentState?.name ?? "Gamepad"
            activeController = nil
            currentState = nil
            onControllerDisconnected?(name)

            if let next = remaining.first {
                configureController(next)
            }
        } else if remaining.isEmpty {
            let name = currentState?.name ?? "Gamepad"
            activeController = nil
            currentState = nil
            onControllerDisconnected?(name)
        }
    }

    private func handleGamepadElementChange(gamepad: GCExtendedGamepad, element: GCControllerElement) {
        switch element {
        case gamepad.buttonA:
            onButtonChanged?(.buttonA, gamepad.buttonA.isPressed, gamepad.buttonA.value)
        case gamepad.buttonB:
            onButtonChanged?(.buttonB, gamepad.buttonB.isPressed, gamepad.buttonB.value)
        case gamepad.buttonX:
            onButtonChanged?(.buttonX, gamepad.buttonX.isPressed, gamepad.buttonX.value)
        case gamepad.buttonY:
            onButtonChanged?(.buttonY, gamepad.buttonY.isPressed, gamepad.buttonY.value)
        case gamepad.leftShoulder:
            onButtonChanged?(.leftShoulder, gamepad.leftShoulder.isPressed, gamepad.leftShoulder.value)
        case gamepad.rightShoulder:
            onButtonChanged?(.rightShoulder, gamepad.rightShoulder.isPressed, gamepad.rightShoulder.value)
        case gamepad.leftTrigger:
            onButtonChanged?(.leftTrigger, gamepad.leftTrigger.isPressed, gamepad.leftTrigger.value)
        case gamepad.rightTrigger:
            onButtonChanged?(.rightTrigger, gamepad.rightTrigger.isPressed, gamepad.rightTrigger.value)
        case gamepad.dpad.up:
            onButtonChanged?(.dpadUp, gamepad.dpad.up.isPressed, gamepad.dpad.up.value)
        case gamepad.dpad.down:
            onButtonChanged?(.dpadDown, gamepad.dpad.down.isPressed, gamepad.dpad.down.value)
        case gamepad.dpad.left:
            onButtonChanged?(.dpadLeft, gamepad.dpad.left.isPressed, gamepad.dpad.left.value)
        case gamepad.dpad.right:
            onButtonChanged?(.dpadRight, gamepad.dpad.right.isPressed, gamepad.dpad.right.value)
        case gamepad.leftThumbstick:
            let x = gamepad.leftThumbstick.xAxis.value
            let y = gamepad.leftThumbstick.yAxis.value
            onLeftThumbstickMoved?(x, y)
        case gamepad.rightThumbstick:
            let x = gamepad.rightThumbstick.xAxis.value
            let y = gamepad.rightThumbstick.yAxis.value
            onRightThumbstickMoved?(x, y)
        default:
            break
        }
    }

    // MARK: - Virtual Touch Calculations

    public nonisolated static func virtualStickTouchPoint(
        stickX: Float,
        stickY: Float,
        centerX: Double,
        centerY: Double,
        radius: Double,
        sourceWidth: Int32,
        sourceHeight: Int32,
        deadzone: Float = 0.15
    ) -> (x: Int32, y: Int32)? {
        let length = hypot(stickX, stickY)
        guard length >= deadzone else { return nil }

        let clampedLength = min(1.0, length)
        let normalizedDirX = Double(stickX / length)
        let normalizedDirY = Double(stickY / length)

        let targetX = (centerX * Double(sourceWidth)) + (normalizedDirX * Double(clampedLength) * radius)
        // In Android guest coordinates, Y=0 is top, so positive stickY (up) decreases Y.
        let targetY = (centerY * Double(sourceHeight)) - (normalizedDirY * Double(clampedLength) * radius)

        let clampedX = Int32(max(0, min(Double(sourceWidth), targetX.rounded())))
        let clampedY = Int32(max(0, min(Double(sourceHeight), targetY.rounded())))

        return (x: clampedX, y: clampedY)
    }
}
