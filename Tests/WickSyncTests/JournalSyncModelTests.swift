import XCTest
@testable import WickSync

final class JournalSyncModelTests: XCTestCase {
    private var decoder: JSONDecoder { JournalSyncEncoding.decoder }
    private var encoder: JSONEncoder { JournalSyncEncoding.encoder }

    // MARK: - dayKey

    func testDayKeyFormatIsGregorianLocalDate() {
        let epoch = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(JournalDayKey.make(from: epoch, timeZone: .gmt), "1970-01-01")
        // 16:30 UTC is still the same Gregorian day in GMT, the next one in GMT+14.
        let evening = Date(timeIntervalSince1970: 60_000)
        XCTAssertEqual(JournalDayKey.make(from: evening, timeZone: .gmt), "1970-01-01")
        let zonePlus14 = TimeZone(secondsFromGMT: 14 * 3600)!
        XCTAssertEqual(JournalDayKey.make(from: evening, timeZone: zonePlus14), "1970-01-02")
    }

    func testExplicitDayKeySurvivesRoundTrip() throws {
        // Whole-second dates: ISO-8601 encoding drops fractional seconds.
        let stamp = Date(timeIntervalSince1970: 1_754_000_000)
        let entry = JournalEntry(
            date: stamp,
            dayKey: "2026-08-06",
            title: "Keyed",
            createdAt: stamp,
            updatedAt: stamp
        )
        let data = try encoder.encode(entry)
        let decoded = try decoder.decode(JournalEntry.self, from: data)
        XCTAssertEqual(decoded.dayKey, "2026-08-06")
        XCTAssertEqual(decoded, entry)
    }

    func testLegacyEntryWithoutDayKeyDerivesFromDate() throws {
        let json = """
        {"id":"\(UUID().uuidString)","date":"2026-01-15T12:00:00Z","title":"Legacy",\
        "items":[{"id":"\(UUID().uuidString)","tag":"","body":"b","imageFilenames":[]}],\
        "createdAt":"2026-01-15T12:00:00Z","updatedAt":"2026-01-15T12:00:00Z"}
        """
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z"))
        let decoded = try decoder.decode(JournalEntry.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.dayKey, JournalDayKey.make(from: date))
        XCTAssertTrue(decoded.dayKey.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil)
    }

    // MARK: - JournalImageFilename

    func testImageFilenameAcceptsSafeNames() {
        let safe = [
            "\(UUID().uuidString).png",
            "\(UUID().uuidString).JPG",
            "\(UUID().uuidString).PNG",
            "a b.png",
            "photo 1.heic",
            "image-2026.png",
            "01234567-89AB-CDEF-0123-456789ABCDEF.jpg"
        ]
        for name in safe {
            XCTAssertTrue(JournalImageFilename.isValid(name), "expected safe: \(name)")
        }
    }

    func testImageFilenameRejectsUnsafeNames() {
        let unsafe = [
            "../x",
            "../../catalog.json",
            "a/b.png",
            "a\\b.png",
            ".",
            "..",
            "",
            "x\0.png",
            "..\\x",
            "/etc/passwd",
            "images/../escape.png"
        ]
        for name in unsafe {
            XCTAssertFalse(JournalImageFilename.isValid(name), "expected unsafe: \(name)")
        }
    }

    func testImageFilenameValidationIsSharedRuleSource() {
        // Both stores must agree: the rule lives here in WickSync so macOS and
        // iOS share exactly one implementation (compile-time guarantee).
        XCTAssertEqual(JournalImageFilename.isValid("ok.png"), true)
        XCTAssertEqual(JournalImageFilename.isValid("../escape.png"), false)
        XCTAssertThrowsError(try JournalImageFilename.validateAll(["ok.png", "../escape.png"]))
    }

    func testDecodeRejectsEntryWithUnsafeImageReference() throws {
        let json = """
        {"id":"\(UUID().uuidString)","date":"2026-01-15T00:00:00Z","title":"t",\
        "items":[{"id":"\(UUID().uuidString)","tag":"","body":"b","imageFilenames":["../escape.png"]}],\
        "createdAt":"2026-01-15T00:00:00Z","updatedAt":"2026-01-15T00:00:00Z"}
        """
        XCTAssertThrowsError(try decoder.decode(JournalEntry.self, from: Data(json.utf8))) { error in
            XCTAssertTrue(error is JournalImageFilename.InvalidReference)
        }
    }

    func testDecodeAcceptsEntryWithSafeImageReference() throws {
        let json = """
        {"id":"\(UUID().uuidString)","date":"2026-01-15T00:00:00Z","title":"t",\
        "items":[{"id":"\(UUID().uuidString)","tag":"","body":"b","imageFilenames":["abc 1.png"]}],\
        "createdAt":"2026-01-15T00:00:00Z","updatedAt":"2026-01-15T00:00:00Z"}
        """
        let entry = try decoder.decode(JournalEntry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.items.first?.imageFilenames, ["abc 1.png"])
    }

    // MARK: - JournalCatalogLoader matrix (AC-P1-02 / AC-P0-01)

    private func writeCatalog(_ json: String, to url: URL) throws {
        try Data(json.utf8).write(to: url, options: .atomic)
    }

    private func makeCatalogLoaderDir() throws -> (root: URL, primary: URL, backup: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WickCatalogLoader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (
            root,
            root.appendingPathComponent("catalog.json", isDirectory: false),
            root.appendingPathComponent("catalog.json.bak", isDirectory: false)
        )
    }

    private func validCatalogJSON() -> String {
        let info = journalInfoJSON()
        return "{\"version\":1,\"activeJournalID\":\"\(UUID().uuidString)\",\"journals\":[\(info)]}"
    }

    private func journalInfoJSON() -> String {
        "{\"id\":\"\(UUID().uuidString)\",\"name\":\"Diary\",\"createdAt\":\"2026-01-01T00:00:00Z\",\"updatedAt\":\"2026-01-01T00:00:00Z\"}"
    }

    func testCatalogLoaderMatrix() throws {
        func load(_ p: URL?, _ b: URL?) -> JournalCatalogLoader.Outcome {
            JournalCatalogLoader.load(
                primaryURL: p ?? URL(fileURLWithPath: "/nonexistent-primary"),
                backupURL: b ?? URL(fileURLWithPath: "/nonexistent-backup"),
                currentVersion: 1
            )
        }
        let dir = try makeCatalogLoaderDir()
        defer { try? FileManager.default.removeItem(at: dir.root) }

        // Neither exists -> missing (only case that may first-create).
        var result = load(nil, nil)
        XCTAssertEqual(result, .missing)

        // Primary missing + valid backup -> restoredFromBackup.
        try writeCatalog(validCatalogJSON(), to: dir.backup)
        result = load(nil, dir.backup)
        if case .restoredFromBackup = result {} else { XCTFail("expected restoredFromBackup, got \(result)") }

        // Primary missing + corrupt backup -> corrupt (not fresh install).
        try writeCatalog("{", to: dir.backup)
        result = load(nil, dir.backup)
        XCTAssertEqual(result, .corrupt)

        // Primary missing + future backup -> unsupportedVersion.
        try writeCatalog("{\"version\":99,\"activeJournalID\":\"\(UUID().uuidString)\",\"journals\":[]}", to: dir.backup)
        result = load(nil, dir.backup)
        XCTAssertEqual(result, .unsupportedVersion(99))

        // Valid primary wins regardless of backup.
        try writeCatalog(validCatalogJSON(), to: dir.primary)
        result = load(dir.primary, dir.backup)
        if case .loaded = result {} else { XCTFail("expected loaded, got \(result)") }

        // Corrupt primary + valid backup -> restoredFromBackup.
        try writeCatalog("{", to: dir.primary)
        try writeCatalog(validCatalogJSON(), to: dir.backup)
        result = load(dir.primary, dir.backup)
        if case .restoredFromBackup = result {} else { XCTFail("expected restoredFromBackup, got \(result)") }

        // Corrupt primary + corrupt backup -> corrupt (never degrade to fresh).
        try writeCatalog("{", to: dir.primary)
        try writeCatalog("{", to: dir.backup)
        result = load(dir.primary, dir.backup)
        XCTAssertEqual(result, .corrupt)

        // Future primary is authoritative even with a valid backup.
        try writeCatalog("{\"version\":99,\"activeJournalID\":\"\(UUID().uuidString)\",\"journals\":[]}", to: dir.primary)
        try writeCatalog(validCatalogJSON(), to: dir.backup)
        result = load(dir.primary, dir.backup)
        XCTAssertEqual(result, .unsupportedVersion(99))
    }

    func testCatalogLoaderClassifiesEmptyAsCorruptNotMissing() throws {
        let dir = try makeCatalogLoaderDir()
        defer { try? FileManager.default.removeItem(at: dir.root) }
        try writeCatalog("{\"version\":1,\"activeJournalID\":\"\(UUID().uuidString)\",\"journals\":[]}", to: dir.primary)
        let result = JournalCatalogLoader.load(
            primaryURL: dir.primary,
            backupURL: dir.backup,
            currentVersion: 1
        )
        XCTAssertEqual(result, .corrupt, "an empty library must not degrade into a fresh install")
    }

    // MARK: - Canonical encoding / content hash

    func testCanonicalEncodingIsDeterministicAcrossRoundTrip() throws {
        var review = JournalReview(verdict: .correct, note: "n")
        review.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let item = JournalItem(tag: "BTC", body: "line1\nline2", imageFilenames: ["a.png"], review: review)
        let entry = JournalEntry(
            date: Date(timeIntervalSince1970: 1_754_000_000),
            title: "Deterministic",
            items: [item],
            createdAt: Date(timeIntervalSince1970: 1_754_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_754_100_000)
        )

        let first = try JournalSyncEncoding.canonicalData(for: entry)
        let second = try JournalSyncEncoding.canonicalData(for: entry)
        XCTAssertEqual(first, second)

        let decoded = try decoder.decode(JournalEntry.self, from: first)
        let reencoded = try JournalSyncEncoding.canonicalData(for: decoded)
        XCTAssertEqual(first, reencoded, "decode→encode must be byte-stable or hashes flap")
    }

    func testContentHashMatchesSHA256KnownVector() {
        // Plain SHA-256 of empty input - Wick's canonical convention.
        XCTAssertEqual(
            JournalSyncEncoding.contentHash(of: Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    func testBackendContentHashConventionNeverMatchesCanonicalHash() {
        // Dropbox's content_hash hashes the concatenated per-block SHA-256
        // digests (hash-of-hashes) and therefore NEVER equals the plain
        // SHA-256 of the same bytes - for empty input the two vectors differ.
        // The sync engine must never cross-compare the conventions; remote
        // change detection uses file revs (see JournalSyncEngineTests).
        XCTAssertEqual(
            DropboxStyleContentHash(Data()),
            "5df6e0e2761359d30a8275058e299fcc0381534545f55cf43e41983f5d4c9456"
        )
        XCTAssertNotEqual(DropboxStyleContentHash(Data()), JournalSyncEncoding.contentHash(of: Data()))
    }

    // MARK: - Sync state (legacy migration)

    func testLegacyDaySyncStateDecodesIntoSettlementEnum() throws {
        let pushSettled = try decoder.decode(
            DaySyncState.self,
            from: Data(#"{"localHash":"h1","remoteRev":"r1","settledPushHash":"chosen"}"#.utf8)
        )
        XCTAssertEqual(pushSettled.settlement, .pushSettled("chosen"))
        XCTAssertEqual(pushSettled.pushedHashes, [])

        let adopter = try decoder.decode(
            DaySyncState.self,
            from: Data(#"{"localHash":"h1","settleAdoptRemote":true}"#.utf8)
        )
        XCTAssertEqual(adopter.settlement, .adoptRemote)

        let marker = try decoder.decode(
            DaySyncState.self,
            from: Data(#"{"localHash":"h1","settleMarkHash":"hm"}"#.utf8)
        )
        XCTAssertEqual(marker.settlement, .markSettled("hm"))

        // Round-trip drops the legacy keys and keeps the migrated settlement.
        let decoded = try decoder.decode(DaySyncState.self, from: try encoder.encode(pushSettled))
        XCTAssertEqual(decoded, pushSettled)
    }
}
