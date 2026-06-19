import SwiftUI

// MARK: - ModelsSection
//
// Replaces the older TranscriptionSection. Cloud/Local segmented control
// at the top; each provider is an inline accordion row with a radio dot
// on the right that toggles the active provider independent of expand.

struct ModelsSection: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var kind: ProviderKind = .cloud
    @State private var expandedID: ProviderID? = nil

    private var providers: [TranscriptionProvider] {
        TranscriptionProviderRegistry.all.filter { $0.kind == kind }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Picker("", selection: $kind) {
                Text("Cloud").tag(ProviderKind.cloud)
                Text("Local").tag(ProviderKind.local)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)

            VStack(spacing: Spacing.sm) {
                ForEach(providers) { provider in
                    ProviderAccordionRow(
                        provider: provider,
                        isExpanded: expandedID == provider.id,
                        isActive: settings.selectedProviderID == provider.id,
                        onToggleExpand: {
                            withAnimation(Motion.snappy) {
                                expandedID = (expandedID == provider.id) ? nil : provider.id
                            }
                        },
                        onActivate: { activate(provider) }
                    )
                }
            }
        }
        .onAppear {
            kind = TranscriptionProviderRegistry.provider(settings.selectedProviderID).kind
        }
    }

    private func activate(_ provider: TranscriptionProvider) {
        guard provider.status == .wired else { return }
        settings.selectedProviderID = provider.id
        if !provider.models.contains(where: { $0.id == settings.selectedModelID }) {
            settings.selectedModelID = provider.defaultModelID
        }
        AppServices.shared.orchestrator.setProvider(
            provider.id,
            model: settings.selectedModelID
        )
    }
}

// MARK: - ProviderAccordionRow

private struct ProviderAccordionRow: View {
    let provider: TranscriptionProvider
    let isExpanded: Bool
    let isActive: Bool
    let onToggleExpand: () -> Void
    let onActivate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                Divider().background(Color.white.opacity(0.08))
                expansionBody
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.md)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .stroke(Color.white.opacity(isActive ? 0.30 : 0.12), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: provider.kind == .cloud ? "cloud" : "internaldrive")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Palette.muted)
                .frame(width: 18)
            Text(provider.displayName)
                .font(Typography.sans(13, .medium))
                .foregroundStyle(provider.status == .stubbed ? Palette.muted : Palette.ink)
            if provider.status == .stubbed {
                Text("Coming soon")
                    .font(Typography.sans(10, .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
            }
            Spacer(minLength: 0)
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
            Button(action: onActivate) {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(isActive ? Palette.greenInk : Palette.muted)
            }
            .buttonStyle(.plain)
            .disabled(provider.status == .stubbed)
            .help(provider.status == .stubbed ? "Not yet available" : "Set as active provider")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleExpand)
    }

    @ViewBuilder
    private var expansionBody: some View {
        if provider.status == .stubbed {
            Text("Wiring for \(provider.displayName) lands in a later update.")
                .font(Typography.sans(11))
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if provider.requiresAPIKey {
            CloudProviderBody(provider: provider)
        } else {
            LocalProviderBody(provider: provider)
        }
    }
}

// MARK: - Cloud body

private struct CloudProviderBody: View {
    let provider: TranscriptionProvider
    @ObservedObject private var settings = AppSettings.shared
    @State private var keyDraft: String = ""
    @State private var savedKey: String = ""
    @State private var isValidated: Bool = false
    @State private var isValidating: Bool = false
    @State private var errorText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            EditorialSectionLabel(text: "API Key")
            SecureField("Paste API key", text: $keyDraft)
                .textFieldStyle(.plain)
                .font(Typography.mono(12))
                .foregroundStyle(Palette.ink)
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .onChange(of: keyDraft) { _, new in
                    // ponytail: editing the saved key invalidates the badge.
                    if new != savedKey {
                        isValidated = false
                        ValidationState.setValidated(provider.id, false)
                    }
                    errorText = nil
                }

            HStack(spacing: Spacing.sm) {
                if keyDraft != savedKey || savedKey.isEmpty {
                    primaryButton(title: "Save Key", system: "key.fill", action: saveKey)
                        .disabled(keyDraft.isEmpty)
                        .opacity(keyDraft.isEmpty ? 0.4 : 1)
                } else if !isValidated {
                    primaryButton(
                        title: isValidating ? "Validating…" : "Validate",
                        system: "checkmark.shield",
                        action: { Task { await validate() } }
                    )
                    .disabled(isValidating)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Validated")
                    }
                    .font(Typography.sans(12, .semibold))
                    .foregroundStyle(Palette.greenInk)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                            .fill(Palette.greenBg)
                    )
                }

                secondaryButton(title: "Clear", system: "trash", action: clearKey)
                    .disabled(savedKey.isEmpty && keyDraft.isEmpty)

                Spacer()
            }
            .animation(Motion.microFade, value: isValidated)
            .animation(Motion.microFade, value: keyDraft)

            if let err = errorText {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(err)
                }
                .font(Typography.sans(11))
                .foregroundStyle(Palette.redInk)
            }

            if provider.models.count > 1 {
                EditorialSectionLabel(text: "Model")
                Picker("", selection: modelBinding) {
                    ForEach(provider.models) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Palette.ink)
            }
        }
        .onAppear(perform: load)
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: {
                provider.models.contains(where: { $0.id == settings.selectedModelID })
                    ? settings.selectedModelID
                    : provider.defaultModelID
            },
            set: { newID in
                if settings.selectedProviderID == provider.id {
                    settings.selectedModelID = newID
                    AppServices.shared.orchestrator.setProvider(provider.id, model: newID)
                }
            }
        )
    }

    private func load() {
        let stored = KeychainService.load(for: provider.id) ?? ""
        savedKey = stored
        keyDraft = stored
        isValidated = !stored.isEmpty && ValidationState.isValidated(provider.id)
    }

    private func saveKey() {
        guard !keyDraft.isEmpty else { return }
        try? KeychainService.save(key: keyDraft, for: provider.id)
        savedKey = keyDraft
        isValidated = false
        ValidationState.setValidated(provider.id, false)
    }

    private func clearKey() {
        KeychainService.delete(for: provider.id)
        savedKey = ""
        keyDraft = ""
        isValidated = false
        errorText = nil
        ValidationState.setValidated(provider.id, false)
    }

    @MainActor
    private func validate() async {
        isValidating = true
        defer { isValidating = false }
        do {
            let ok = try await KeyValidator.validate(provider: provider.id, key: savedKey)
            isValidated = ok
            ValidationState.setValidated(provider.id, ok)
            errorText = ok ? nil : "Key rejected by \(provider.displayName)."
        } catch {
            isValidated = false
            errorText = error.localizedDescription
        }
    }

    private func primaryButton(title: String, system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: system)
                .font(Typography.sans(12, .medium))
                .foregroundStyle(Palette.canvas)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .fill(Palette.ink)
                )
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(title: String, system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: system)
                .font(Typography.sans(12, .medium))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Local body

private struct LocalProviderBody: View {
    let provider: TranscriptionProvider
    @ObservedObject private var settings = AppSettings.shared

    private var recommendedID: String? {
        HardwareProfile.current.recommendedModelID(for: provider.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if provider.models.count > 1 {
                EditorialSectionLabel(text: "Model")
                Picker("", selection: modelBinding) {
                    ForEach(provider.models) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Palette.ink)
            }
            if let rec = recommendedID,
               let recModel = provider.models.first(where: { $0.id == rec }) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Palette.greenInk)
                    Text("Recommended for your Mac: \(recModel.displayName)")
                        .font(Typography.sans(11))
                        .foregroundStyle(Palette.muted)
                }
            }
            Text(HardwareProfile.current.summary)
                .font(Typography.mono(10))
                .foregroundStyle(Palette.muted)
        }
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: {
                provider.models.contains(where: { $0.id == settings.selectedModelID })
                    ? settings.selectedModelID
                    : provider.defaultModelID
            },
            set: { newID in
                if settings.selectedProviderID == provider.id {
                    settings.selectedModelID = newID
                    AppServices.shared.orchestrator.setProvider(provider.id, model: newID)
                }
            }
        )
    }
}
