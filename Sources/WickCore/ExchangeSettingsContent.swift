import SwiftUI

/// Settings content for the Binance position integration. Two states, mirroring
/// the Dropbox sync section: a credential form while not connected, and a
/// status/refresh/disconnect block once enabled. Auth failures drop back to
/// the form (with the error shown) so a mistyped key can be fixed in place.
struct ExchangeSettingsContent: View {
    // Observed directly (not via environment) so `isEnabled` flips - which
    // read AppSettings - always re-render this view.
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var coordinator = ExchangePositionCoordinator.shared
    let theme: PanelTheme
    let language: AppLanguage

    @State private var apiKeyDraft = ""
    @State private var secretDraft = ""
    @State private var showDisconnectConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if coordinator.isEnabled {
                connectedContent
            } else {
                setupContent
            }
        }
        .confirmationDialog(
            L10n.string(.exchangeDisconnectConfirmTitle, language: language),
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.string(.exchangeDisconnect, language: language), role: .destructive) {
                coordinator.disconnect()
            }
            Button(L10n.string(.cancel, language: language), role: .cancel) {}
        } message: {
            Text(L10n.string(.exchangeDisconnectConfirmBody, language: language))
        }
    }

    // MARK: - Setup (no working credentials yet)

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string(.exchangeExplanation, language: language))
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            credentialField(
                title: L10n.string(.exchangeApiKey, language: language),
                text: $apiKeyDraft
            )
            credentialField(
                title: L10n.string(.exchangeSecretKey, language: language),
                text: $secretDraft,
                secure: true
            )

            saveButton

            Text(L10n.string(.exchangeReadonlyHint, language: language))
                .font(.caption2)
                .foregroundStyle(theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)

            statusFooter
        }
    }

    private var saveButton: some View {
        Button {
            coordinator.saveAndSync(apiKey: apiKeyDraft, secret: secretDraft)
            // Keep the drafts: on auth failure they stay editable; a later
            // successful sync swaps the whole block to the connected state.
        } label: {
            HStack {
                if coordinator.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(
                    coordinator.isSyncing
                        ? L10n.string(.exchangeSyncing, language: language)
                        : L10n.string(.exchangeSaveAndSync, language: language)
                )
                .font(.system(size: 14, weight: .medium, design: .rounded))
                Spacer(minLength: 8)
            }
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.controlBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(theme.controlBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(coordinator.isSyncing || apiKeyDraft.isEmpty || secretDraft.isEmpty)
        .opacity(apiKeyDraft.isEmpty || secretDraft.isEmpty ? 0.55 : 1)
    }

    private func credentialField(
        title: String,
        text: Binding<String>,
        secure: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 74, alignment: .leading)
            Group {
                if secure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
            .autocorrectionDisabled()
        }
    }

    // MARK: - Connected

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string(.exchangeWindowHint, language: language))
                .font(.caption)
                .foregroundStyle(theme.secondaryText)

            statusFooter

            actionButton(
                title: L10n.string(.exchangeSyncNow, language: language),
                systemImage: "arrow.triangle.2.circlepath"
            ) {
                coordinator.syncNow()
            }
            .disabled(coordinator.isSyncing)

            actionButton(
                title: L10n.string(.exchangeDisconnect, language: language),
                systemImage: "link"
            ) {
                showDisconnectConfirm = true
            }
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                Spacer(minLength: 8)
            }
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.controlBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(theme.controlBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status

    @ViewBuilder
    private var statusFooter: some View {
        if coordinator.isSyncing {
            Text(L10n.string(.exchangeSyncing, language: language))
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        } else if let error = coordinator.lastError {
            Text(error.text(language: language))
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        } else if let fetchedAt = coordinator.snapshot?.fetchedAt {
            HStack {
                Text(L10n.string(.exchangeLastSync, language: language))
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                Text(fetchedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(theme.primaryText)
            }
        }
    }
}
