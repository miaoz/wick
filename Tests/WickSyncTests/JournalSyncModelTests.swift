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
