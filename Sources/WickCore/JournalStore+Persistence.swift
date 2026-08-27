import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import WickSync

// MARK: - Persistence (active journal)
//
// Active-journal write path, split out of the store god-file (DS-07). Pure
// behavior-preserving move.

extension JournalStore {
    // MARK: - Persistence (active journal)

    func ensureDirectories() {
        try? fileManager.createDirectory(at: journalDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
    }

    func load() {
        isReadOnlyDueToLoadFailure = false
        loadFailureMessage = nil
        // Note: `didRestoreFromBackup` is intentionally NOT reset here — a
        // catalog restore (set by `applyCatalog`) must survive the active
        // journal load that follows in bootstrap. `resetSessionState` /
        // `createJournal` clear it on navigation.
        ensureDirectories()

        guard fileManager.fileExists(atPath: databaseURL.path) else {
            // Try backup if primary missing.
            if let restored = loadSnapshot(from: backupURL) {
                entries = restored.entries.sorted { $0.date > $1.date }
                selection = entries.first.map { .day($0.id) }
                didRestoreFromBackup = true
                persist()
                return
            }
            entries = []
            selection = nil
            return
        }

        do {
            let data = try Data(contentsOf: databaseURL)
            let snapshot = try decoder.decode(JournalSnapshot.self, from: data)
            // Newer format (written by a newer app on another device): go read-only
            // rather than strip unknown fields by re-encoding and persisting.
            guard snapshot.version <= JournalSnapshot.currentVersion else {
                entries = []
                selection = nil
                isReadOnlyDueToLoadFailure = true
                loadFailureMessage = L10n.string(
                    .journalNewerVersionRequired,
                    language: AppSettings.shared.language
                )
                return
            }
            entries = snapshot.entries.sorted { $0.date > $1.date }
            selection = entries.first.map { .day($0.id) }
        } catch {
            NSLog("Wick journal load failed: \(error.localizedDescription)")
            if let restored = loadSnapshot(from: backupURL) {
                entries = restored.entries.sorted { $0.date > $1.date }
                selection = entries.first.map { .day($0.id) }
                didRestoreFromBackup = true
                // Quarantine corrupt primary, then rewrite from backup.
                let quarantine = journalDirectory.appendingPathComponent(
                    "journal.corrupt-\(Int(Date().timeIntervalSince1970)).json"
                )
                try? fileManager.moveItem(at: databaseURL, to: quarantine)
                isReadOnlyDueToLoadFailure = false
                persist()
                return
            }

            // Do not clear on-disk file. Block writes.
            entries = []
            selection = nil
            isReadOnlyDueToLoadFailure = true
            loadFailureMessage = loadFailureMessage(for: error)
        }
    }

    func loadFailureMessage(for error: Error) -> String {
        if error is JournalImageFilename.InvalidReference {
            return L10n.string(.journalUnsafeImageReferences, language: AppSettings.shared.language)
        }
        return error.localizedDescription
    }

    func loadSnapshot(from url: URL) -> JournalSnapshot? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try decoder.decode(JournalSnapshot.self, from: data)
            // Treat newer-format files as unreadable so restore paths never
            // re-encode (and strip) data written by a newer app version.
            guard snapshot.version <= JournalSnapshot.currentVersion else { return nil }
            return snapshot
        } catch {
            return nil
        }
    }

    func persist() {
        guard !persistBlocked else { return }
        guard !isReadOnlyDueToLoadFailure else {
            return
        }
        ensureDirectories()
        entriesDidMutate.send()

        persistCount += 1
        persistGeneration += 1
        let generation = persistGeneration
        let snapshot = JournalSnapshot(version: JournalSnapshot.currentVersion, entries: entries)
        let databaseURL = self.databaseURL
        let backupURL = self.backupURL
        let backupsDirectory = self.backupsDirectory
        let maxRollingBackups = self.maxRollingBackups
        let fileExists = fileManager.fileExists(atPath: databaseURL.path)
        let shouldRoll: Bool
        if let last = lastRollingBackupAt {
            shouldRoll = Date().timeIntervalSince(last) >= 60 * 30
        } else {
            shouldRoll = true
        }
        if fileExists, shouldRoll {
            lastRollingBackupAt = Date()
        }

        let snapshotCopy = snapshot
        let copyExistingToBackup = fileExists
        let includeRolling = fileExists && shouldRoll

        // XCTest reloads the file immediately; keep that path synchronous.
        if NSClassFromString("XCTestCase") != nil {
            let error = Self.writeSnapshot(
                snapshotCopy,
                to: databaseURL,
                backupURL: backupURL,
                backupsDirectory: backupsDirectory,
                copyExistingToBackup: copyExistingToBackup,
                includeRolling: includeRolling,
                maxRollingBackups: maxRollingBackups
            )
            applyPersistResult(error, generation: generation)
            return
        }

        persistQueue.async { [weak self] in
            let error = Self.writeSnapshot(
                snapshotCopy,
                to: databaseURL,
                backupURL: backupURL,
                backupsDirectory: backupsDirectory,
                copyExistingToBackup: copyExistingToBackup,
                includeRolling: includeRolling,
                maxRollingBackups: maxRollingBackups
            )
            DispatchQueue.main.async {
                self?.applyPersistResult(error, generation: generation)
            }
        }
    }

    func applyPersistResult(_ error: String?, generation: UInt64) {
        guard generation == persistGeneration else { return }
        if let error {
            lastPersistError = error
            NSLog("Wick journal persist failed: \(error)")
        } else if lastPersistError != nil {
            lastPersistError = nil
        }
    }

    /// Encode + atomic write off the main thread. Encoding options stay
    /// `prettyPrinted + sortedKeys` to match `JournalSyncEncoding` (P3).
    /// Does **not** re-decode the previous file to decide whether to copy `.bak`.
    nonisolated static func writeSnapshot(
        _ snapshot: JournalSnapshot,
        to databaseURL: URL,
        backupURL: URL,
        backupsDirectory: URL,
        copyExistingToBackup: Bool,
        includeRolling: Bool,
        maxRollingBackups: Int
    ) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            if copyExistingToBackup {
                Self.copyDatabaseToSidecarBackup(
                    databaseURL: databaseURL,
                    backupURL: backupURL,
                    backupsDirectory: backupsDirectory,
                    includeRolling: includeRolling,
                    maxRollingBackups: maxRollingBackups
                )
            }
            let data = try encoder.encode(snapshot)
            try data.write(to: databaseURL, options: .atomic)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    nonisolated static func copyDatabaseToSidecarBackup(
        databaseURL: URL,
        backupURL: URL,
        backupsDirectory: URL,
        includeRolling: Bool,
        maxRollingBackups: Int
    ) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: databaseURL.path) else { return }
        try? fileManager.removeItem(at: backupURL)
        try? fileManager.copyItem(at: databaseURL, to: backupURL)

        guard includeRolling else { return }
        try? fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "journal-\(formatter.string(from: Date())).json"
        let rolling = backupsDirectory.appendingPathComponent(name)
        try? fileManager.copyItem(at: databaseURL, to: rolling)
        Self.pruneRollingBackups(in: backupsDirectory, keeping: maxRollingBackups)
    }

    nonisolated static func pruneRollingBackups(in backupsDirectory: URL, keeping maxRollingBackups: Int) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let jsons = files.filter { $0.pathExtension.lowercased() == "json" }
        let sorted = jsons.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        }
        for obsolete in sorted.dropFirst(maxRollingBackups) {
            try? fileManager.removeItem(at: obsolete)
        }
    }

    func removeImageFile(_ filename: String) {
        guard let url = imageURL(for: filename) else { return }
        try? fileManager.removeItem(at: url)
        JournalThumbnailCache.shared.invalidate(filename: filename)
    }

    func sanitizedExtension(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let allowed = Set(["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp"])
        if allowed.contains(trimmed) {
            return trimmed == "jpeg" ? "jpg" : trimmed
        }
        return "png"
    }

    func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }

    nonisolated static func findJournalJSON(under directory: URL) -> URL? {
        let fm = FileManager.default
        if let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for case let file as URL in enumerator {
                if file.lastPathComponent == "journal.json" {
                    return file
                }
            }
        }
        return nil
    }

    nonisolated static func runZip(sourceDirectory: URL, destinationZip: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", sourceDirectory.path, destinationZip.path]
        let err = Pipe()
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw JournalStoreError.exportFailed(message)
        }
    }

    nonisolated static func runUnzip(zipURL: URL, destinationDirectory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, destinationDirectory.path]
        let err = Pipe()
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw JournalStoreError.importFailed(message)
        }
    }
}
