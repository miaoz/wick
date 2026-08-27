import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import WickSync

// MARK: - Images & transfer
//
// Image management + export/import/reveal, split out of the store god-file
// (DS-07). Pure behavior-preserving move.

extension JournalStore {
    // MARK: - Images

    /// The only image URL constructor in the app. Returns nil for any name
    /// that is not a safe single-level filename or that would resolve outside
    /// the images directory (a second boundary past model-level validation).
    func imageURL(for filename: String) -> URL? {
        guard JournalImageFilename.isValid(filename) else { return nil }
        let url = imagesDirectory.appendingPathComponent(filename)
        let standard = url.standardizedFileURL
        let imagesStandard = imagesDirectory.standardizedFileURL
        guard standard.path.hasPrefix(imagesStandard.path + "/") else { return nil }
        return url
    }

    func loadNSImage(filename: String) -> NSImage? {
        guard let url = imageURL(for: filename) else { return nil }
        return NSImage(contentsOf: url)
    }

    func loadThumbnail(filename: String, maxPixel: CGFloat = 320) -> NSImage? {
        guard let url = imageURL(for: filename) else { return nil }
        return JournalThumbnailCache.shared.thumbnail(
            filename: filename,
            url: url,
            maxPixel: maxPixel
        )
    }

    @discardableResult
    func addImage(
        from data: Data,
        to entryID: UUID,
        itemID: UUID,
        preferredExtension: String = "png"
    ) -> String? {
        guard !isReadOnlyDueToLoadFailure else { return nil }
        guard let entryIndex = entries.firstIndex(where: { $0.id == entryID }),
              let itemIndex = entries[entryIndex].items.firstIndex(where: { $0.id == itemID })
        else {
            return nil
        }

        let processed = JournalImageProcessing.process(data: data, preferredExtension: preferredExtension)
        let payload: Data
        let ext: String
        if let processed {
            payload = processed.data
            ext = processed.fileExtension
        } else {
            payload = data
            ext = sanitizedExtension(preferredExtension)
        }

        let filename = "\(UUID().uuidString).\(ext)"
        guard let destination = imageURL(for: filename) else { return nil }

        do {
            try payload.write(to: destination, options: .atomic)
        } catch {
            return nil
        }

        entries[entryIndex].items[itemIndex].imageFilenames.append(filename)
        entries[entryIndex].updatedAt = Date()
        persist()
        touchActiveJournalMetadata()
        return filename
    }

    @discardableResult
    func addImage(from fileURL: URL, to entryID: UUID, itemID: UUID) -> String? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        let ext = fileURL.pathExtension.isEmpty ? "png" : fileURL.pathExtension
        return addImage(from: data, to: entryID, itemID: itemID, preferredExtension: ext)
    }

    @discardableResult
    func addImage(from nsImage: NSImage, to entryID: UUID, itemID: UUID) -> String? {
        if let processed = JournalImageProcessing.process(nsImage: nsImage) {
            return addImage(
                from: processed.data,
                to: entryID,
                itemID: itemID,
                preferredExtension: processed.fileExtension
            )
        }
        guard let data = pngData(from: nsImage) else {
            return nil
        }
        return addImage(from: data, to: entryID, itemID: itemID, preferredExtension: "png")
    }

    func removeImage(filename: String, from entryID: UUID, itemID: UUID) {
        guard !isReadOnlyDueToLoadFailure else { return }
        guard let entryIndex = entries.firstIndex(where: { $0.id == entryID }),
              let itemIndex = entries[entryIndex].items.firstIndex(where: { $0.id == itemID })
        else {
            return
        }
        entries[entryIndex].items[itemIndex].imageFilenames.removeAll { $0 == filename }
        entries[entryIndex].updatedAt = Date()
        removeImageFile(filename)
        persist()
        touchActiveJournalMetadata()
    }

    func pasteImageFromClipboard(to entryID: UUID, itemID: UUID) -> Bool {
        let pasteboard = NSPasteboard.general

        if let image = NSImage(pasteboard: pasteboard) {
            return addImage(from: image, to: entryID, itemID: itemID) != nil
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]) as? [URL] {
            var added = false
            for url in urls {
                if addImage(from: url, to: entryID, itemID: itemID) != nil {
                    added = true
                }
            }
            return added
        }

        return false
    }

    // MARK: - Export / Import / Reveal

    func revealDataDirectoryInFinder() {
        NSWorkspace.shared.open(librariesRoot)
    }

    /// Exports the active journal's `journal.json` + `images/` into a zip at
    /// `destinationURL`. The export is consistent: editor drafts are flushed
    /// first, the frozen in-memory snapshot is encoded (never the possibly
    /// stale main file), and the destination is only replaced after the new
    /// archive is fully built.
    func exportArchive(to destinationURL: URL) async throws {
        // A load-failure read-only store has already emptied `entries`; encoding
        // that empty snapshot would atomically overwrite a previous good export.
        // "No writes while read-only" must cover the export artifact too.
        guard !isReadOnlyDueToLoadFailure else {
            throw JournalStoreError.exportFailed(
                "The journal is under read-only protection after a load failure; export is disabled."
            )
        }

        // 1. Unified flush protocol: editors commit drafts, then the store's
        // writer drains so the in-memory snapshot below is the final state.
        flushActiveJournalSession()

        // 2. Freeze identity + content on the main actor, then hand the heavy
        // encode/copy/ditto/replace to a background task (UI-06) so a large
        // journal does not freeze the menu-bar panel.
        let snapshot = JournalSnapshot(version: JournalSnapshot.currentVersion, entries: entries)
        let frozenImagesDirectory = imagesDirectory
        try await Self.performExport(
            snapshot: snapshot,
            imagesDirectory: frozenImagesDirectory,
            destinationURL: destinationURL
        )
    }

    /// Builds the export archive off the main thread: encode the frozen
    /// snapshot, copy images, run ditto, and atomically replace the target.
    nonisolated static func performExport(
        snapshot: JournalSnapshot,
        imagesDirectory: URL,
        destinationURL: URL
    ) async throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("WickExport-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempRoot) }
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let payloadDir = tempRoot.appendingPathComponent("Wick-Journal", isDirectory: true)
        try fileManager.createDirectory(at: payloadDir, withIntermediateDirectories: true)

        // 3. Encode the frozen in-memory snapshot into the temp payload.
        let data = try JournalSyncEncoding.encoder.encode(snapshot)
        try data.write(to: payloadDir.appendingPathComponent("journal.json"), options: .atomic)

        let imagesDest = payloadDir.appendingPathComponent("images", isDirectory: true)
        try fileManager.createDirectory(at: imagesDest, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: imagesDirectory.path) {
            let imageFiles = try fileManager.contentsOfDirectory(
                at: imagesDirectory,
                includingPropertiesForKeys: nil
            )
            for file in imageFiles where !file.hasDirectoryPath {
                try fileManager.copyItem(
                    at: file,
                    to: imagesDest.appendingPathComponent(file.lastPathComponent)
                )
            }
        }

        // 4. Build the archive to a temp file in the DESTINATION directory
        // (same volume), then atomically replace the target. A failed build or
        // a failed replace leaves the previous archive intact (AC-P1-07).
        let destDir = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        let tempZip = destDir.appendingPathComponent(".Wick-export-\(UUID().uuidString).tmp", isDirectory: false)
        defer { try? fileManager.removeItem(at: tempZip) }
        try runZip(sourceDirectory: payloadDir, destinationZip: tempZip)
        try replaceDestination(destinationURL, with: tempZip, fileManager: fileManager)
    }

    /// Atomic swap of the freshly built archive over the target. Wrapped so a
    /// deterministic failure can be injected for tests.
    nonisolated static func replaceDestination(_ destinationURL: URL, with tempZip: URL, fileManager: FileManager) throws {
        #if DEBUG
        if Self.failExportReplaceOverride {
            throw CocoaError(.fileWriteUnknown)
        }
        #endif
        _ = try fileManager.replaceItemAt(destinationURL, withItemAt: tempZip)
    }

    /// Imports a previously exported zip or a bare `journal.json` into the
    /// **active** journal, or (when the catalog itself is read-only) recovers
    /// the library with the imported content as its first journal.
    ///
    /// The input is fully validated BEFORE any read-only flag or file is
    /// touched; an invalid archive leaves the store and on-disk files exactly
    /// as they were (AC-P1-01). The unzip + decode run off the main thread so
    /// a large archive does not freeze the menu-bar panel (UI-06).
    func importArchive(from sourceURL: URL) async throws {
        // 1. Validate the input completely in a temp area — no state change.
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("WickImport-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempRoot) }
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let (snapshot, importedImages) = try await Self.prepareImport(
            from: sourceURL,
            tempRoot: tempRoot
        )

        // 2. If the LIBRARY is read-only, recover a real catalog first; only a
        //    durable catalog write lets the import proceed.
        if isCatalogReadOnly {
            try recoverCatalogForImport()
        }
        guard !isCatalogReadOnly else {
            throw JournalStoreError.catalogRecoveryFailed
        }

        // 3. Now the active journal is real and writable; clear content-level
        //    read-only and replace its data.
        isReadOnlyDueToLoadFailure = false
        loadFailureMessage = nil

        // Backup current store before replacing.
        if fileManager.fileExists(atPath: databaseURL.path) {
            Self.copyDatabaseToSidecarBackup(
                databaseURL: databaseURL,
                backupURL: backupURL,
                backupsDirectory: backupsDirectory,
                includeRolling: true,
                maxRollingBackups: maxRollingBackups
            )
            lastRollingBackupAt = Date()
        }

        // Replace images directory transactionally (DS-02): move the existing
        // images aside into a same-volume quarantine, copy the imported images
        // into a fresh directory, and only delete the quarantine once every
        // copy succeeded. If a copy fails, the quarantine is moved back, so an
        // interrupted import never loses the pre-existing images.
        var imagesQuarantine: URL?
        var imagesMovedAside = false
        if fileManager.fileExists(atPath: imagesDirectory.path) {
            let quarantine = journalDirectory.appendingPathComponent(
                ".WickImagesQuarantine-\(UUID().uuidString)", isDirectory: true
            )
            do {
                try fileManager.moveItem(at: imagesDirectory, to: quarantine)
                imagesQuarantine = quarantine
                imagesMovedAside = true
            } catch {
                // Can't move the old images aside; keep them and merge the
                // imported files instead of deleting anything.
                imagesQuarantine = nil
            }
        }

        do {
            try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            if let importedImages {
                let files = try fileManager.contentsOfDirectory(
                    at: importedImages,
                    includingPropertiesForKeys: nil
                )
                var copied = 0
                for file in files where !file.hasDirectoryPath {
                    #if DEBUG
                    if copied + 1 == Self.failImageCopyAtIndex {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    #endif
                    let dest = imagesDirectory.appendingPathComponent(file.lastPathComponent)
                    try fileManager.copyItem(at: file, to: dest)
                    copied += 1
                }
            }
        } catch {
            if imagesMovedAside {
                try? fileManager.removeItem(at: imagesDirectory)
                if let imagesQuarantine {
                    try? fileManager.moveItem(at: imagesQuarantine, to: imagesDirectory)
                }
            }
            throw error
        }

        if let imagesQuarantine {
            try? fileManager.removeItem(at: imagesQuarantine)
        }

        entries = snapshot.entries.sorted { $0.date > $1.date }
        selection = entries.first.map { .day($0.id) }
        isReadOnlyDueToLoadFailure = false
        loadFailureMessage = nil
        didRestoreFromBackup = false
        lastPersistError = nil
        JournalThumbnailCache.shared.removeAll()
        persist()
        touchActiveJournalMetadata()
    }

    /// Unzips (if needed), decodes and validates the import payload on a
    /// background thread. Throws before any store state is touched (AC-P1-01).
    nonisolated static func prepareImport(
        from sourceURL: URL,
        tempRoot: URL
    ) async throws -> (snapshot: JournalSnapshot, importedImages: URL?) {
        let fileManager = FileManager.default
        let jsonURL: URL
        let importedImages: URL?

        if sourceURL.pathExtension.lowercased() == "json" {
            jsonURL = sourceURL
            importedImages = nil
        } else {
            try runUnzip(zipURL: sourceURL, destinationDirectory: tempRoot)
            if let found = findJournalJSON(under: tempRoot) {
                jsonURL = found
            } else {
                throw JournalStoreError.importMissingJournalJSON
            }
            let siblingImages = jsonURL
                .deletingLastPathComponent()
                .appendingPathComponent("images", isDirectory: true)
            importedImages = fileManager.fileExists(atPath: siblingImages.path) ? siblingImages : nil
        }

        let data = try Data(contentsOf: jsonURL)
        let snapshot = try JournalSyncEncoding.decoder.decode(JournalSnapshot.self, from: data)
        guard snapshot.version <= JournalSnapshot.currentVersion else {
            throw JournalStoreError.unsupportedSnapshotVersion(snapshot.version)
        }
        return (snapshot, importedImages)
    }

    /// Forces a synchronous write of the in-memory snapshot (used on quit).
    func flushPendingWrites() {
        guard !isReadOnlyDueToLoadFailure else { return }
        persist()
        persistQueue.sync {}
    }

    /// Ask editors to commit drafts, then persist the active journal.
    func flushActiveJournalSession() {
        NotificationCenter.default.post(name: .wickWillFlushJournalDrafts, object: nil)
        flushPendingWrites()
    }

    /// Explicit user recovery. When the LIBRARY (catalog) is read-only, it
    /// quarantines the corrupt/newer-format catalog, seeds a fresh default
    /// journal in a REAL directory, writes the catalog, and only then exits
    /// read-only — throwing and rolling back if any step fails. When only the
    /// active journal's content failed to load, it clears that content-level
    /// read-only after moving the bad file aside.
    func abandonCorruptDatabaseAndStartFresh() throws {
        recoveryErrorMessage = nil
        if isCatalogReadOnly {
            do {
                try recoverCatalogFromScratch()
            } catch {
                recoveryErrorMessage = error.localizedDescription
                throw error
            }
            return
        }
        if fileManager.fileExists(atPath: databaseURL.path) {
            let quarantine = journalDirectory.appendingPathComponent(
                "journal.corrupt-\(Int(Date().timeIntervalSince1970)).json"
            )
            try? fileManager.moveItem(at: databaseURL, to: quarantine)
        }
        entries = []
        selection = nil
        isReadOnlyDueToLoadFailure = false
        loadFailureMessage = nil
        didRestoreFromBackup = false
        persist()
    }

    /// Rebuilds a healthy library after the user chooses to start fresh:
    /// quarantine the bad catalog, create a new UUID with real directories,
    /// write the catalog, and only leave read-only once the write succeeds.
    func recoverCatalogFromScratch() throws {
        let originalJournals = journals
        let originalActive = activeJournalID
        let originalSession = captureJournalSession()
        let quarantine = librariesRoot.appendingPathComponent(
            "catalog.corrupt-\(UUID().uuidString).json",
            isDirectory: false
        )
        if fileManager.fileExists(atPath: catalogURL.path) {
            try fileManager.moveItem(at: catalogURL, to: quarantine)
        }
        isCatalogReadOnly = false
        let info = JournalInfo(name: defaultJournalName())
        let dir = librariesRoot.appendingPathComponent(info.id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: dir.appendingPathComponent("images", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: dir.appendingPathComponent("backups", isDirectory: true),
            withIntermediateDirectories: true
        )
        journals = [info]
        activeJournalID = info.id
        bindPaths(for: info.id)
        resetSessionState()
        entries = []
        guard persistCatalog() else {
            // Roll back every in-memory and on-disk session component.
            try? fileManager.moveItem(at: quarantine, to: catalogURL)
            try? fileManager.removeItem(at: dir)
            isCatalogReadOnly = true
            journals = originalJournals
            activeJournalID = originalActive
            restoreJournalSession(originalSession)
            throw JournalStoreError.catalogRecoveryFailed
        }
        notifyActiveJournalChanged()
    }

    /// Catalog recovery used by import: same as `recoverCatalogFromScratch`,
    /// so the imported content lands in a real journal (never `_pending`).
    func recoverCatalogForImport() throws {
        try recoverCatalogFromScratch()
    }

}
