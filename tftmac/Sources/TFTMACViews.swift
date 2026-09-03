import SwiftUI

struct TFTMACRootView: View {
    @ObservedObject var bridge: TFTMACRuntimeBridge
    @ObservedObject var coordinator: TFTMACWindowCoordinator

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(
                colors: [Color(red: 0.035, green: 0.055, blue: 0.075), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 22) {
                Spacer()
                TFTMACLogo(size: 112)
                Text("TFTMAC")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .tracking(2)
                Text(bridge.phase.rawValue)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(statusColor)
                Text(bridge.detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                HStack(spacing: 12) {
                    if bridge.phase == .idle || bridge.phase == .failed {
                        Button("Start TFTMAC") { bridge.start() }
                            .buttonStyle(TFTMACPrimaryButtonStyle())
                    }
                    if bridge.phase == .waitingForUnlock || bridge.phase == .failed {
                        Button("Retry TFT") { bridge.retryGameLaunch() }
                            .buttonStyle(TFTMACSecondaryButtonStyle())
                    }
                    if bridge.emulatorPID != nil {
                        Button("Stop") { bridge.stop() }
                            .buttonStyle(TFTMACSecondaryButtonStyle())
                    }
                }
                if !coordinator.accessibilityGranted && bridge.emulatorPID != nil {
                    Button("Enable Fullscreen Window Control") {
                        coordinator.requestAccessibilityIfNeeded()
                        coordinator.positionEmulatorWindow()
                    }
                    .buttonStyle(TFTMACSecondaryButtonStyle())
                    Text("Allow TFTMAC in Privacy & Security → Accessibility to hide the Google window chrome automatically.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 16) {
                    Label("1920 × 1080", systemImage: "rectangle.inset.filled")
                    Label("60 Hz", systemImage: "speedometer")
                    Label("5 GB", systemImage: "memorychip")
                    Label("CoreAudio", systemImage: "speaker.wave.2.fill")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.bottom, 28)
            }
            .foregroundStyle(.white)
            .padding(40)
        }
    }

    private var statusColor: Color {
        switch bridge.phase {
        case .running: return .green
        case .failed: return .orange
        case .waitingForUnlock: return .yellow
        default: return Color(red: 0.35, green: 0.75, blue: 1.0)
        }
    }
}

struct TFTMACTopBarView: View {
    @ObservedObject var bridge: TFTMACRuntimeBridge
    @ObservedObject var coordinator: TFTMACWindowCoordinator

    var body: some View {
        HStack(spacing: 8) {
            TFTMACLogo(size: 20)
            Text("TFTMAC")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(1)
            Circle()
                .fill(bridge.phase == .running ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .padding(.leading, 6)
            Text(bridge.phase.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("1920 × 1080")
            Divider().frame(height: 15)
            Text("60 FPS")
            Divider().frame(height: 15)
            Text("5 GB")
            Divider().frame(height: 15)
            Button {
                coordinator.toggleImmersiveMode()
            } label: {
                Image(systemName: coordinator.immersive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(TFTMACToolButtonStyle())
            .help(coordinator.immersive ? "Leave fullscreen" : "Fullscreen")
            Button {
                bridge.stop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(TFTMACToolButtonStyle())
            .help("Stop TFTMAC")
            Button {
                coordinator.quitApplication()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(TFTMACToolButtonStyle())
            .help("Quit TFTMAC")
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.92))
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
    }
}

struct TFTMACControlBarView: View {
    @ObservedObject var bridge: TFTMACRuntimeBridge
    @ObservedObject var coordinator: TFTMACWindowCoordinator

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 820
            VStack(spacing: compact ? 3 : 5) {
                Spacer(minLength: compact ? 18 : 34)
                control("Back", "chevron.left", compact: compact, bridge.back)
                control("Home", "house.fill", compact: compact, bridge.home)
                control("Overview", "square.on.square", compact: compact, bridge.overview)
                separator
                control("Rotate L", "rotate.left", compact: compact, bridge.rotateLeft)
                control("Rotate R", "rotate.right", compact: compact, bridge.rotateRight)
                separator
                control("Vol +", "speaker.plus.fill", compact: compact, bridge.volumeUp)
                control("Vol −", "speaker.minus.fill", compact: compact, bridge.volumeDown)
                control("Mute", "speaker.slash.fill", compact: compact, bridge.mute)
                separator
                control("Shot", "camera.fill", compact: compact, bridge.screenshot)
                control("TFT", "arrow.clockwise", compact: compact, bridge.restartTFT)
                separator
                control("Fit", "rectangle.inset.filled", compact: compact, coordinator.positionEmulatorWindow)
                control("Exit", "rectangle.portrait.and.arrow.right", compact: compact, coordinator.leaveImmersiveMode)
                Spacer(minLength: compact ? 14 : 24)
            }
            .padding(.horizontal, 5)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
    }

    private var separator: some View {
        Rectangle()
            .fill(.white.opacity(0.13))
            .frame(height: 1)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
    }

    private func control(_ title: String, _ symbol: String, compact: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: compact ? 2 : 3) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 14 : 15, weight: .semibold))
                    .frame(height: compact ? 15 : 17)
                Text(title)
                    .font(.system(size: compact ? 7.5 : 8.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 34 : 40)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.065)))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

struct TFTMACLogo: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.05, green: 0.18, blue: 0.24), Color(red: 0.02, green: 0.06, blue: 0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .stroke(Color(red: 0.25, green: 0.72, blue: 0.82).opacity(0.55), lineWidth: max(1, size * 0.018))
            Text("T")
                .font(.system(size: size * 0.59, weight: .black, design: .serif))
                .foregroundStyle(LinearGradient(
                    colors: [Color(red: 0.95, green: 0.76, blue: 0.32), Color(red: 0.62, green: 0.39, blue: 0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.5), radius: size * 0.1, y: size * 0.04)
    }
}

struct TFTMACPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 22)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.35, green: 0.80, blue: 0.95).opacity(configuration.isPressed ? 0.75 : 1)))
    }
}

struct TFTMACSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(configuration.isPressed ? 0.16 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.15)))
    }
}

struct TFTMACToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(.white.opacity(configuration.isPressed ? 0.16 : 0.07)))
    }
}
