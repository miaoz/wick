import SwiftUI

/// Settings for the per-journal exchange binding. The journal is chosen in
/// this panel; it is not implied by whichever book is open in the editor.
struct ExchangeSettingsContent: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var coordinator = ExchangePositionCoordinator.shared
    @ObservedObject private var journalStore = JournalStore.shared
    let theme: PanelTheme
    let language: AppLanguage

    @State private var targetJournalID: UUID?
    @State private var venue: ExchangeVenue = .binance
    @State private var apiKeyDraft = ""
    @State private var secretDraft = ""
    @State private var passphraseDraft = ""
    @State private var addressDraft = ""
    @State private var showDisconnectConfirm = false

    private var targetJournal: JournalInfo? {
        if let targetJournalID,
           let match = journalStore.journals.first(where: { $0.id == targetJournalID })
        {
            return match
        }
        return journalStore.journals.first
    }

    private var isTargetConfigured: Bool {
        guard let id = targetJournal?.id else { return false }
        return coordinator.isConfigured(for: id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            journalPicker

            if isTargetConfigured {
                connectedContent
            } else {
                setupContent
            }
        }
        .onAppear {
            if targetJournalID == nil {
                targetJournalID = journalStore.activeJournalID ?? journalStore.journals.first?.id
            }
        }
        .onChange(of: journalStore.journals.map(\.id)) { ids in
            if let targetJournalID, !ids.contains(targetJournalID) {
                self.targetJournalID = journalStore.activeJournalID ?? ids.first
            }
        }
        .confirmationDialog(
            L10n.string(.exchangeDisconnectConfirmTitle, language: language),
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.string(.exchangeDisconnect, language: language), role: .destructive) {
                if let id = targetJournal?.id {
                    coordinator.disconnect(journalID: id)
                }
            }
            Button(L10n.string(.cancel, language: language), role: .cancel) {}
        } message: {
            Text(L10n.string(.exchangeDisconnectConfirmBody, language: language))
        }
    }

    private var journalPicker: some View {
        HStack(spacing: 8) {
            Text(L10n.string(.exchangeJournal, language: language))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 88, alignment: .leading)
            Picker("", selection: Binding(
                get: { targetJournal?.id },
                set: { targetJournalID = $0 }
            )) {
                ForEach(journalStore.journals) { journal in
                    Text(journal.name).tag(Optional(journal.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    // MARK: - Setup

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string(.exchangeExplanation, language: language))
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            venuePicker

            switch venue {
            case .hyperliquid:
                credentialField(
                    title: L10n.string(.exchangeWalletAddress, language: language),
                    text: $addressDraft
                )
                Text(L10n.string(.exchangeHyperliquidHint, language: language))
                    .font(.caption2)
                    .foregroundStyle(theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            case .okx:
                credentialField(
                    title: L10n.string(.exchangeApiKey, language: language),
                    text: $apiKeyDraft
                )
                credentialField(
                    title: L10n.string(.exchangeSecretKey, language: language),
                    text: $secretDraft,
                    secure: true
                )
                credentialField(
                    title: L10n.string(.exchangePassphrase, language: language),
                    text: $passphraseDraft,
                    secure: true
                )
                Text(L10n.string(.exchangeOKXHint, language: language))
                    .font(.caption2)
                    .foregroundStyle(theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            case .binance:
                credentialField(
                    title: L10n.string(.exchangeApiKey, language: language),
                    text: $apiKeyDraft
                )
                credentialField(
                    title: L10n.string(.exchangeSecretKey, language: language),
                    text: $secretDraft,
                    secure: true
                )
            }

            saveButton

            Text(L10n.string(.exchangeReadonlyHint, language: language))
                .font(.caption2)
                .foregroundStyle(theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)

            statusFooter
        }
    }

    private var venuePicker: some View {
        HStack(spacing: 8) {
            ForEach(ExchangeVenue.allCases) { option in
                let selected = venue == option
                Button {
                    venue = option
                } label: {
                    Text(venueTitle(option))
                        .font(.system(size: 12, weight: selected ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(selected ? theme.primaryText : theme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? theme.selectionBackground : theme.controlBackground)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    selected ? theme.selectionAccent.opacity(0.45) : theme.controlBorder,
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func venueTitle(_ venue: ExchangeVenue) -> String {
        switch venue {
        case .binance: return L10n.string(.exchangeVenueBinance, language: language)
        case .okx: return L10n.string(.exchangeVenueOKX, language: language)
        case .hyperliquid: return L10n.string(.exchangeVenueHyperliquid, language: language)
        }
    }

    private var canSave: Bool {
        switch venue {
        case .hyperliquid:
            return HyperliquidInfoClient.normalizedAddress(addressDraft) != nil
        case .okx:
            return !apiKeyDraft.isEmpty && !secretDraft.isEmpty && !passphraseDraft.isEmpty
        case .binance:
            return !apiKeyDraft.isEmpty && !secretDraft.isEmpty
        }
    }

    private var saveButton: some View {
        Button {
            guard let journalID = targetJournal?.id else { return }
            switch venue {
            case .binance:
                coordinator.saveAndSyncBinance(
                    apiKey: apiKeyDraft,
                    secret: secretDraft,
                    journalID: journalID
                )
            case .okx:
                coordinator.saveAndSyncOKX(
                    apiKey: apiKeyDraft,
                    secret: secretDraft,
                    passphrase: passphraseDraft,
                    journalID: journalID
                )
            case .hyperliquid:
                coordinator.saveAndSyncHyperliquid(address: addressDraft, journalID: journalID)
            }
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
        .disabled(coordinator.isSyncing || !canSave || targetJournal == nil)
        .opacity(canSave && targetJournal != nil ? 1 : 0.55)
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
                .frame(width: 88, alignment: .leading)
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
            if let binding = targetJournal?.exchangeBinding {
                HStack {
                    Text(venueTitle(binding.venue))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                    Spacer()
                    Text(binding.accountLabel)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Text(windowHint)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            statusFooter

            actionButton(
                title: L10n.string(.exchangeSyncNow, language: language),
                systemImage: "arrow.triangle.2.circlepath"
            ) {
                if let id = targetJournal?.id {
                    coordinator.syncNow(journalID: id)
                }
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

    private var windowHint: String {
        switch targetJournal?.exchangeBinding?.venue {
        case .okx:
            return L10n.string(.exchangeOKXHint, language: language)
        case .hyperliquid:
            return L10n.string(.exchangeHyperliquidHint, language: language)
        default:
            return L10n.string(.exchangeWindowHint, language: language)
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
        } else if let id = targetJournal?.id,
                  let fetchedAt = coordinator.lastFetchedAt(for: id) {
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
