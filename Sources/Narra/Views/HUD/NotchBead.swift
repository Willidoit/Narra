import SwiftUI
import AppKit

// MARK: - Notch geometry

/// Resolves the screen's notch width (or a sensible pill width on screens
/// without a notch). Used by both `NotchBead` (capsule rendering) and the
/// HUD window placement code (window frame sizing).
enum NotchGeometry {

    /// Default pill width when no physical notch is present.
    static let nonNotchPillWidth: CGFloat = 200

    /// Returns the screen's notch width in points, or `nonNotchPillWidth`
    /// if the screen has no notch (external display, older MacBook).
    static func notchWidth(for screen: NSScreen) -> CGFloat {
        let top = screen.safeAreaInsets.top
        guard top > 0 else { return nonNotchPillWidth }
        // ponytail: notch width = screen width - usable auxiliary frame
        // width on either side of the notch. `auxiliaryTopRightArea` etc.
        // aren't public, so we fall back to the well-known 200pt for
        // current MacBook Pros. Bump per-model later if needed.
        return 200
    }
}

// MARK: - NotchBead

/// A small capsule that drops from underneath the system notch (or floats
/// near the top-center on non-notch displays). Shows a live waveform while
/// recording and reveals discard / accept buttons when reviewing.
struct NotchBead: View {
    @ObservedObject var viewModel: ContentViewModel
    @State private var open = false

    private let height: CGFloat = 28

    /// Collapsed width = the notch width itself, so the bead enters as a
    /// seamless extension of the system notch instead of a separate pill.
    private var collapsedWidth: CGFloat {
        NotchGeometry.notchWidth(for: NSScreen.main ?? NSScreen.screens[0])
    }

    private var targetWidth: CGFloat {
        let notchWidth = collapsedWidth
        switch viewModel.uiMode {
        case .reviewing:
            return notchWidth + 88
        case .recording:
            // Toggle recording shows cancel/confirm disks — needs the extra
            // width. Push-to-talk has no inline controls, so it stays at
            // notch width and reads as a hanging extension of the notch.
            return viewModel.isToggleRecording ? notchWidth + 88 : notchWidth
        case .processing:
            return notchWidth
        default:
            return collapsedWidth
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            beadCapsule
                .frame(width: open ? targetWidth : collapsedWidth, height: height)
                .animation(.spring(response: 0.45, dampingFraction: 0.80), value: targetWidth)
                .animation(.spring(response: 0.45, dampingFraction: 0.80), value: open)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.05)) {
                open = true
            }
        }
    }

    private var beadCapsule: some View {
        ZStack {
            beadBackground

            HStack(spacing: Spacing.sm) {
                switch viewModel.uiMode {
                case .recording where viewModel.isToggleRecording:
                    recordingCancelDisk(action: viewModel.discardRecording)
                        .accessibilityLabel("Discard recording")
                case .reviewing:
                    iconButton(symbol: "xmark",
                               tint: Palette.redInk,
                               action: viewModel.cancelReview)
                        .accessibilityLabel("Discard transcription")
                default:
                    EmptyView()
                }

                contentBody
                    .frame(maxWidth: .infinity)

                switch viewModel.uiMode {
                case .recording where viewModel.isToggleRecording:
                    recordingConfirmDisk(action: viewModel.stopAndReview)
                        .accessibilityLabel("Stop and review recording")
                case .reviewing:
                    iconButton(symbol: "checkmark",
                               tint: Palette.greenInk,
                               action: viewModel.acceptReview)
                        .accessibilityLabel("Paste transcription")
                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, Spacing.sm)
            .opacity(open ? 1 : 0)
            .animation(.easeOut(duration: 0.18).delay(0.20), value: open)
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        switch viewModel.uiMode {
        case .recording:
            WaveformView(levels: viewModel.audioLevels)
                .frame(height: 16)
        case .processing:
            ProgressView()
                .progressViewStyle(.linear)
                .tint(Palette.ink)
                .frame(maxWidth: 60)
        case .reviewing:
            WaveformView(levels: viewModel.audioLevels)
                .frame(height: 16)
                .opacity(0.5)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var beadBackground: some View {
        // Flat top so the bead reads as a hanging extension of the system
        // notch; rounded bottom so it still feels like glass. Top corners
        // are 0 even on non-notch displays — the look stays consistent.
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: height / 2,
            bottomTrailingRadius: height / 2,
            topTrailingRadius: 0,
            style: .continuous
        )
        if #available(macOS 26.0, *) {
            shape.fill(.black.opacity(0.85))
                .glassEffect(.regular, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(Color.black.opacity(0.70)))
                .overlay(shape.stroke(Color.white.opacity(0.10), lineWidth: 0.5))
        }
    }

    private func iconButton(symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    /// Recording-state cancel: solid dark-gray disk with a white X.
    private func recordingCancelDisk(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color(white: 0.18)))
        }
        .buttonStyle(.plain)
    }

    /// Recording-state confirm: soft glass-white disk with a gray checkmark.
    /// ponytail: white.opacity(0.92) + hairline stroke reads as "glass white"
    /// without needing a second .glassEffect layer (the bead already has one,
    /// and glass-on-glass is forbidden).
    private func recordingConfirmDisk(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(white: 0.25))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.92))
                        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
    }
}
