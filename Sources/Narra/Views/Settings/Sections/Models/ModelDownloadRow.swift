import SwiftUI

// MARK: - ModelDownloadRow
//
// One row per ProviderModel inside the local-provider expansion in
// Settings. Renders the model name, an approximate file size, a status
// pill, and the action cluster (Download / Cancel / Delete). While the
// model is downloading, a thin linear progress bar sits under the row
// with the live percentage on the right.
//
// All states are derived from ModelDownloadCoordinator so the row is
// purely observational — no local state.

struct ModelDownloadRow: View {
    let providerID: ProviderID
    let model: ProviderModel
    @ObservedObject var coordinator: ModelDownloadCoordinator

    private var state: ModelDownloadCoordinator.State {
        coordinator.state(for: providerID, modelID: model.id)
    }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Text(model.displayName)
                    .font(Typography.sans(13, .medium))
                    .foregroundStyle(Palette.ink)

                Spacer(minLength: Spacing.sm)

                statusPill
                actionCluster
            }

            if case .downloading(let frac) = state {
                ProgressView(value: frac)
                    .progressViewStyle(.linear)
                    .tint(Palette.greenInk)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Status pill

    @ViewBuilder
    private var statusPill: some View {
        switch state {
        case .idle:
            pill(
                text: "Not downloaded · \(sizeText)",
                foreground: Palette.muted,
                background: Color.white.opacity(0.05)
            )
        case .downloading(let frac):
            pill(
                text: "Downloading · \(Int(frac * 100))%",
                foreground: Palette.greenInk,
                background: Palette.greenBg
            )
        case .ready:
            pill(
                text: "Downloaded · \(sizeText)",
                foreground: Palette.greenInk,
                background: Palette.greenBg
            )
        case .failed:
            pill(
                text: "Failed — retry",
                foreground: Palette.redInk,
                background: Palette.redBg
            )
        }
    }

    private func pill(text: String, foreground: Color, background: Color) -> some View {
        Text(text)
            .font(Typography.mono(10))
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous).fill(background)
            )
    }

    private var sizeText: String {
        guard let bytes = model.approxBytes, bytes > 0 else { return "—" }
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = [.useMB, .useGB]
        fmt.countStyle = .file
        return fmt.string(fromByteCount: bytes)
    }

    // MARK: - Action cluster

    @ViewBuilder
    private var actionCluster: some View {
        switch state {
        case .idle:
            PillButton(title: "Download", systemImage: "arrow.down.circle", style: .filled) {
                coordinator.download(providerID: providerID, modelID: model.id)
            }
        case .downloading:
            PillButton(title: "Cancel", systemImage: "xmark", style: .outline) {
                coordinator.cancel(providerID: providerID, modelID: model.id)
            }
        case .ready:
            PillButton(title: "Delete", systemImage: "trash", style: .outline) {
                coordinator.delete(providerID: providerID, modelID: model.id)
            }
        case .failed:
            PillButton(title: "Retry", systemImage: "arrow.clockwise", style: .filled) {
                coordinator.download(providerID: providerID, modelID: model.id)
            }
        }
    }
}
