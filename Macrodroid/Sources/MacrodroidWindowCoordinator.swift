import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class TFTMACWindowCoordinator: ObservableObject {
    static let topBarHeight: CGFloat = 30
    static let controlBarWidth: CGFloat = 64

    @Published private(set) var immersive = false
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()

    private weak var bridge: TFTMACRuntimeBridge?
    private var shellWindow: NSWindow?
    private var topPanel: NSPanel?
    private var controlPanel: NSPanel?
    private var managedEmulatorPID: pid_t?
    private var attachTimer: Timer?

    init(bridge: TFTMACRuntimeBridge) {
        self.bridge = bridge
    }

    func installWindows() {
        guard shellWindow == nil else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let shell = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        shell.title = "TFTMAC"
        shell.backgroundColor = .black
        shell.isOpaque = true
        shell.hasShadow = false
        shell.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        shell.level = .normal
        shell.contentView = NSHostingView(rootView: TFTMACRootView(
            bridge: bridge!,
            coordinator: self
        ))
        shell.makeKeyAndOrderFront(nil)
        shellWindow = shell

        let top = NSPanel(
            contentRect: topFrame(for: screen),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureOverlay(top)
        top.contentView = NSHostingView(rootView: TFTMACTopBarView(
            bridge: bridge!,
            coordinator: self
        ))
        topPanel = top

        let controls = NSPanel(
            contentRect: controlFrame(for: screen),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureOverlay(controls)
        controls.contentView = NSHostingView(rootView: TFTMACControlBarView(
            bridge: bridge!,
            coordinator: self
        ))
        controlPanel = controls

        NSApp.activate(ignoringOtherApps: true)
    }

    func attachEmulator(pid: pid_t) {
        managedEmulatorPID = pid
        enterImmersiveMode()
        requestAccessibilityIfNeeded()
        positionEmulatorWindow()
        attachTimer?.invalidate()
        var remaining = 50
        attachTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                self.positionEmulatorWindow()
                remaining -= 1
                if remaining <= 0 { timer.invalidate() }
            }
        }
    }

    func detachEmulator() {
        managedEmulatorPID = nil
        attachTimer?.invalidate()
        attachTimer = nil
        leaveImmersiveMode()
    }

    func enterImmersiveMode() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        immersive = true
        shellWindow?.setFrame(screen.frame, display: true)
        shellWindow?.orderBack(nil)
        topPanel?.setFrame(topFrame(for: screen), display: true)
        topPanel?.orderFrontRegardless()
        controlPanel?.setFrame(controlFrame(for: screen), display: true)
        controlPanel?.orderFrontRegardless()
        NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
    }

    func leaveImmersiveMode() {
        immersive = false
        topPanel?.orderOut(nil)
        controlPanel?.orderOut(nil)
        NSApp.presentationOptions = []
        shellWindow?.level = .normal
        shellWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggleImmersiveMode() {
        immersive ? leaveImmersiveMode() : enterImmersiveMode()
        if immersive { positionEmulatorWindow() }
    }

    func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    func positionEmulatorWindow() {
        guard let pid = managedEmulatorPID,
              let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        accessibilityGranted = AXIsProcessTrusted()
        guard accessibilityGranted else { return }

        let appElement = AXUIElementCreateApplication(pid)
        var windowValue: CFTypeRef?
        let copyResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowValue
        )
        guard copyResult == .success,
              let windows = windowValue as? [AXUIElement],
              !windows.isEmpty else { return }

        // The Google emulator exposes more than one macOS window. The small
        // ~54x506 auxiliary window is its stock right-side toolbar; the large
        // titled window is the actual Android canvas. Never use windows.first.
        // Select the largest window as the game canvas and move every auxiliary
        // emulator window beyond the right edge so TFTMAC's native controls are
        // the only visible toolbar.
        func windowSize(_ element: AXUIElement) -> CGSize {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
                  let value else { return .zero }
            let axValue = value as! AXValue
            var size = CGSize.zero
            AXValueGetValue(axValue, .cgSize, &size)
            return size
        }
        let window = windows.max { lhs, rhs in
            let a = windowSize(lhs)
            let b = windowSize(rhs)
            return (a.width * a.height) < (b.width * b.height)
        }!

        for auxiliary in windows where CFEqual(auxiliary, window) == false {
            var hiddenPosition = CGPoint(x: screen.frame.maxX + 160, y: 0)
            if let p = AXValueCreate(.cgPoint, &hiddenPosition) {
                AXUIElementSetAttributeValue(auxiliary, kAXPositionAttribute as CFString, p)
            }
        }

        // AX coordinates are top-left based. The guest remains exactly
        // 1920x1080. Scale the *host canvas* with aspect-fill so no TFTMAC shell
        // background can remain visible around the game. Any excess is cropped
        // symmetrically, while Qt title chrome sits above the display and the
        // Google emulator toolbar sits beyond the right edge.
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? screen
        let guestWidth: CGFloat = 1920
        let guestHeight: CGFloat = 1080
        let chromeWidth: CGFloat = 72
        let chromeHeight: CGFloat = 38
        let scale = max(screen.frame.width / guestWidth, screen.frame.height / guestHeight)
        let canvasWidth = guestWidth * scale
        let canvasHeight = guestHeight * scale
        let cropX = max(0, (canvasWidth - screen.frame.width) / 2)
        let cropY = max(0, (canvasHeight - screen.frame.height) / 2)
        let axPosition = CGPoint(
            x: screen.frame.minX - cropX,
            y: primary.frame.height - screen.frame.maxY - chromeHeight - cropY
        )
        var position = axPosition
        var size = CGSize(width: canvasWidth + chromeWidth, height: canvasHeight + chromeHeight)
        if let p = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
        }
        if let s = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s)
        }
        AXUIElementSetAttributeValue(window, kAXTitleAttribute as CFString, "TFTMAC" as CFTypeRef)

        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])
        topPanel?.orderFrontRegardless()
        controlPanel?.orderFrontRegardless()
    }

    func quitApplication() {
        bridge?.stopSynchronouslyForTermination()
        NSApp.terminate(nil)
    }

    private func configureOverlay(_ panel: NSPanel) {
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    private func topFrame(for screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - Self.topBarHeight,
            width: screen.frame.width,
            height: Self.topBarHeight
        )
    }

    private func controlFrame(for screen: NSScreen) -> NSRect {
        let bottomInset: CGFloat = 4
        let topGap: CGFloat = 4
        return NSRect(
            x: screen.frame.maxX - Self.controlBarWidth,
            y: screen.frame.minY + bottomInset,
            width: Self.controlBarWidth,
            height: max(0, screen.frame.height - Self.topBarHeight - bottomInset - topGap)
        )
    }
}
