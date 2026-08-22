import SwiftUI
import WickSync

/// Expandable list of pending sync conflicts. Item-content conflicts show
/// both pre-merge versions plus the merged result, with one-tap resolution
/// (keep local / keep Dropbox / keep merged); structural conflicts show a
/// summary and can only be dismissed.
struct SyncConflictResolutionList: View {
    @ObservedObject var engine: JournalSyncEngine
    let theme: PanelTheme
    let language: AppLanguage

    @State private var expandedConflictID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(
                    String(
                        format: L10n.string(.syncConflictNoticeFormat, language: language),
                        engine.pendingConflicts.count
                    )
                )
                .font(AppFont.preset(.caption))
                .foregroundStyle(theme.secondaryText)

                Spacer(minLength: 4)

                Button {
                    for conflict in engine.pendingConflicts {
                        engine.dismissConflict(id: conflict.id)
                    }
                } label: {
                    Text(L10n.string(.syncConflictDismissAll, language: language))
                        .font(AppFont.ui(12, weight: .medium, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.selectionAccent)
            }

            // Batch settle: most users treat one device as the source of truth,
            // so offer one-tap "keep this Mac / keep Dropbox" across every
            // conflict that carries both versions. Structural conflicts (no
            // meaningful choice) are untouched and stay in the list.
            let choiceConflicts = engine.pendingConflicts.filter(\.offersChoice)
            if !choiceConflicts.isEmpty {
                HStack(spacing: 6) {
                    batchButton(
                        title: L10n.string(.syncConflictKeepAllLocal, language: language)
                    ) {
                        for conflict in choiceConflicts {
                            engine.resolveConflict(id: conflict.id, resolution: .local)
                        }
                    }
                    batchButton(
                        title: L10n.string(.syncConflictKeepAllRemote, language: language)
                    ) {
                        for conflict in choiceConflicts {
                            engine.resolveConflict(id: conflict.id, resolution: .remote)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            ForEach(engine.pendingConflicts) { conflict in
                SyncConflictRow(
                    conflict: conflict,
                    isExpanded: expandedConflictID == conflict.id,
                    engine: engine,
                    theme: theme,
                    language: language
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        expandedConflictID = expandedConflictID == conflict.id ? nil : conflict.id
                    }
                }
            }
        }
    }

    private func batchButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.ui(11.5, weight: .medium, design: .rounded))
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(theme.palette.controlBackground.color.opacity(0.45))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(theme.palette.divider.color.opacity(0.8), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct SyncConflictRow: View {
    let conflict: SyncConflictRecord
    let isExpanded: Bool
    let engine: JournalSyncEngine
    let theme: PanelTheme
    let language: AppLanguage
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Text(conflict.dayKey)
                        .font(AppFont.ui(12.5, weight: .semibold, design: .rounded, monospacedDigit: true))
                        .foregroundStyle(theme.primaryText)

                    Text(kindText)
                        .font(AppFont.preset(.caption))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.down")
                        .font(AppFont.ui(9, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if conflict.offersChoice {
                    versionPreview(
                        title: L10n.string(.syncConflictLocalVersion, language: language),
                        entry: conflict.localEntry
                    )
                    versionPreview(
                        title: L10n.string(.syncConflictRemoteVersion, language: language),
                        entry: conflict.remoteEntry
                    )
                    versionPreview(
                        title: L10n.string(.syncConflictMergedVersion, language: language),
                        entry: conflict.mergedEntry
                    )

                    HStack(spacing: 6) {
                        choiceButton(
                            title: L10n.string(.syncConflictKeepLocal, language: language)
                        ) {
                            engine.resolveConflict(id: conflict.id, resolution: .local)
                        }
                        choiceButton(
                            title: L10n.string(.syncConflictKeepRemote, language: language)
                        ) {
                            engine.resolveConflict(id: conflict.id, resolution: .remote)
                        }
                        choiceButton(
                            title: L10n.string(.syncConflictKeepMerged, language: language)
                        ) {
                            engine.resolveConflict(id: conflict.id, resolution: .merged)
                        }
                    }
                } else {
                    Text(L10n.string(.syncConflictNoChoiceHint, language: language))
                        .font(AppFont.preset(.caption))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Spacer()
                        choiceButton(
                            title: L10n.string(.syncConflictDismiss, language: language)
                        ) {
                            engine.dismissConflict(id: conflict.id)
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(theme.palette.controlBackground.color.opacity(0.35))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(theme.palette.divider.color.opacity(0.75), lineWidth: 0.8)
        }
    }

    private var kindText: String {
        switch conflict.summary {
        case "item-content-conflict":
            return L10n.string(.syncConflictKindItem, language: language)
        case "delete-vs-edit":
            return L10n.string(.syncConflictKindDeleteEdit, language: language)
        case "deletion overridden by remote edit":
            return L10n.string(.syncConflictKindResurrect, language: language)
        default:
            return conflict.summary
        }
    }

    /// One version: label + title + up to three item preview lines
    /// (tag + first body line), then a "+N more" hint.
    private func versionPreview(title: String, entry: JournalEntry?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AppFont.paper(10.5, weight: .bold))
                .foregroundStyle(theme.tertiaryText)
                .tracking(0.4)

            if let entry {
                let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    Text(title)
                        .font(AppFont.ui(12, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                }

                let items = entry.items.filter { !$0.isEmpty }
                if items.isEmpty {
                    Text(L10n.string(.syncConflictEmptyVersion, language: language))
                        .font(AppFont.preset(.caption2))
                        .foregroundStyle(theme.tertiaryText)
                } else {
                    ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                        Text(itemPreview(item))
                            .font(AppFont.preset(.caption2))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                    if items.count > 3 {
                        Text(
                            String(
                                format: L10n.string(.syncConflictMoreItemsFormat, language: language),
                                items.count - 3
                            )
                        )
                        .font(AppFont.preset(.caption2))
                        .foregroundStyle(theme.tertiaryText)
                    }
                }
            } else {
                Text("-")
                    .font(AppFont.preset(.caption2))
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func itemPreview(_ item: JournalItem) -> String {
        let tag = item.tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = item.previewText
        if tag.isEmpty {
            return body
        }
        if body.isEmpty {
            return tag
        }
        return "\(tag) · \(body)"
    }

    private func choiceButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.ui(11.5, weight: .medium, design: .rounded))
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(theme.palette.controlBackground.color.opacity(0.45))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(theme.palette.divider.color.opacity(0.8), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
    }
}
