import CryptoKit
import XCTest
@testable import WickSync

// MARK: - Fakes

/// Dropbox's documented `content_hash` algorithm: SHA-256 per 4 MB block, the
/// raw digests concatenated, SHA-256 of the result. Deliberately DIFFERENT
/// from Wick's canonical plain SHA-256 - the engine must never depend on the
/// two conventions being comparable (the exact regression this fake guards:
/// locally computed hashes compared against backend metadata hashes).
func DropboxStyleContentHash(_ data: Data) -> String {
    let blockSize = 4 * 1024 * 1024
    var digests = Data()
    var offset = 0
    while offset < data.count {
        let end = min(offset + blockSize, data.count)
        digests.append(Data(SHA256.hash(data: data[offset..<end])))
        offset = end
    }
    if digests.isEmpty {
        digests.append(Data(SHA256.hash(data: data)))
    }
    return SHA256.hash(data: digests).map { String(format: "%02x", $0) }.joined()
}

/// In-memory Dropbox stand-in. One instance shared between engines simulates
/// the server two devices talk to - including the delta echo of the device's
/// own uploads, which the real backend also reports back.
@MainActor
final class FakeSyncBackend: JournalSyncBackend {
    private struct StoredFile {
        var data: Data
        var rev: String
    }

    private var files: [String: StoredFile] = [:]
    private var changeLog: [(version: Int, meta: RemoteFileMeta)] = []
    private var revCounter = 0
    private var version = 0

    var authorized = true
    var uploadCount = 0
    var downloadCount = 0
    /// When set, incremental listings throw this error once.
    var failNextIncremental: SyncBackendError?
    /// Fires once at the start of `listChanges`, so a test can switch the
    /// active journal mid-cycle after the engine has already captured an id.
    var onListChanges: (() -> Void)?

    var isAuthorized: Bool { authorized }
    var accountEmail: String? { authorized ? "fake@example.com" : nil }

    func authorize() async throws -> String { "fake@example.com" }
    func signOut() { authorized = false }

    func listChanges(since cursor: String?) async throws -> (entries: [RemoteFileMeta], cursor: String) {
        onListChanges?()
        onListChanges = nil
        if let cursor {
            if let error = failNextIncremental {
                failNextIncremental = nil
                throw error
            }
            let sinceVersion = Int(cursor.dropFirst()) ?? 0
            let metas = changeLog.filter { $0.version > sinceVersion }.map(\.meta)
            return (metas, "v\(version)")
        }
        let metas = files.map { path, file in
            RemoteFileMeta(path: path, rev: file.rev, contentHash: DropboxStyleContentHash(file.data))
        }
        return (metas, "v\(version)")
    }

    func download(path: String) async throws -> (data: Data, rev: String) {
        downloadCount += 1
        guard let file = files[path.lowercased()] else {
            throw SyncBackendError.server(status: 409, message: "path/not_found/")
        }
        return (file.data, file.rev)
    }

    @discardableResult
    func upload(path: String, data: Data, ifRev: String?) async throws -> String {
        uploadCount += 1
        let key = path.lowercased()
        if let existing = files[key] {
            guard let ifRev, ifRev == existing.rev else {
                throw SyncBackendError.writeConflict(path: key)
            }
        }
        revCounter += 1
        let rev = "r\(revCounter)"
        files[key] = StoredFile(data: data, rev: rev)
        log(path: key, meta: RemoteFileMeta(path: key, rev: rev, contentHash: DropboxStyleContentHash(data)))
        return rev
    }

    func delete(path: String) async throws {
        let key = path.lowercased()
        // Dropbox deletes folders recursively; mirror that (used for journal
        // roots) alongside plain file deletion.
        let doomed = files.keys.filter { $0 == key || $0.hasPrefix(key + "/") }
        guard !doomed.isEmpty else { return }
        for existing in doomed {
            files.removeValue(forKey: existing)
            log(path: existing, meta: RemoteFileMeta(path: existing, rev: nil, contentHash: nil, isDeleted: true))
        }
    }

    // Test helpers

    func fileData(_ path: String) -> Data? { files[path.lowercased()]?.data }
    func hasFile(_ path: String) -> Bool { files[path.lowercased()] != nil }
    func allPaths() -> [String] { files.keys.sorted() }

    /// Seeds a file bypassing sync semantics (simulates a foreign writer).
    func seedFile(_ path: String, data: Data) {
        revCounter += 1
        let rev = "r\(revCounter)"
        let key = path.lowercased()
        files[key] = StoredFile(data: data, rev: rev)
        log(path: key, meta: RemoteFileMeta(path: key, rev: rev, contentHash: DropboxStyleContentHash(data)))
    }

    private func log(path: String, meta: RemoteFileMeta) {
        version += 1
        changeLog.append((version: version, meta: meta))
    }
}

@MainActor
final class FakeLocalSource: JournalLocalSource {
    var journalID: UUID
    var journalName: String
    var writable = true
    var days: [String: JournalEntry] = [:]
    var images: [String: Data] = [:]
    var removedDayKeys: [String] = []
    /// Fires on the engine's freshness re-check - the even-numbered
    /// `syncDaySnapshots()` call (each cycle takes one decision snapshot at
    /// start, then at most one freshness check before applying). Simulates a
    /// user edit landing mid-cycle, after the decision snapshot but before
    /// remote content applies.
    var mutateOnFreshnessCheck: ((inout [String: JournalEntry]) -> Void)?
    private var snapshotCount = 0

    init(journalID: UUID, name: String = "Test Journal") {
        self.journalID = journalID
        self.journalName = name
    }

    var syncJournalID: UUID? { journalID }
    var syncJournalName: String { journalName }
    var syncIsWritable: Bool { writable }

    func syncDaySnapshots() -> [String: JournalEntry] {
        snapshotCount += 1
        if snapshotCount.isMultiple(of: 2), let mutate = mutateOnFreshnessCheck {
            mutateOnFreshnessCheck = nil
            mutate(&days)
        }
        return days
    }
    func applySyncedEntry(_ entry: JournalEntry, journalID: UUID) {
        guard journalID == self.journalID else { return }
        days[entry.dayKey] = entry
    }
    func removeSyncedDay(dayKey: String, journalID: UUID) {
        guard journalID == self.journalID else { return }
        days.removeValue(forKey: dayKey)
        removedDayKeys.append(dayKey)
    }

    @discardableResult
    func applySyncedJournalName(_ name: String, journalID: UUID) -> String {
        guard journalID == self.journalID else { return journalName }
        journalName = name
        return name
    }

    func syncedImageFilenames() -> Set<String> { Set(days.values.flatMap(\.allImageFilenames)) }
    func syncedImageData(filename: String) -> Data? { images[filename] }
    func hasSyncedImage(filename: String) -> Bool { images[filename] != nil }
    func storeSyncedImage(filename: String, data: Data, journalID: UUID) {
        guard journalID == self.journalID else { return }
        images[filename] = data
    }
}

// MARK: - Tests

@MainActor
final class JournalSyncEngineTests: XCTestCase {
    private var tempRoot: URL!
    private var backend: FakeSyncBackend!
    private let journalID = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_754_000_000)

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("WickSyncEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        backend = FakeSyncBackend()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
        backend = nil
    }

    // MARK: helpers

    private func makeSource(name: String = "Test Journal") -> FakeLocalSource {
        FakeLocalSource(journalID: journalID, name: name)
    }

    private func makeEngine(source: FakeLocalSource, stateDir: String, device: String) -> JournalSyncEngine {
        let store = JournalSyncStateStore(directory: tempRoot.appendingPathComponent(stateDir, isDirectory: true))
        return JournalSyncEngine(backend: backend, localSource: source, deviceID: device, stateStore: store)
    }

    private func entry(dayKey: String, body: String, updatedAt: Date? = nil) -> JournalEntry {
        JournalEntry(
            date: t0,
            dayKey: dayKey,
            items: [JournalItem(body: body)],
            createdAt: t0,
            updatedAt: updatedAt ?? t0
        )
    }

    private func dayPath(_ dayKey: String) -> String {
        JournalSyncLayout.dayPath(for: journalID, dayKey: dayKey)
    }

    private func decodeRemoteDay(_ dayKey: String) throws -> JournalEntry {
        let data = try XCTUnwrap(backend.fileData(dayPath(dayKey)))
        return try JournalSyncEncoding.decoder.decode(JournalEntry.self, from: data)
    }

    // MARK: basics

    func testFirstSyncUploadsManifestAndDays() async throws {
        let source = makeSource()
        source.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "one")
        source.days["2026-08-02"] = entry(dayKey: "2026-08-02", body: "two")
        let engine = makeEngine(source: source, stateDir: "a", device: "A")

        await engine.performSyncCycle()

        XCTAssertEqual(engine.status, .idle)
        XCTAssertNotNil(engine.lastSyncAt)
        XCTAssertTrue(backend.hasFile(JournalSyncLayout.manifestPath(for: journalID)))
        XCTAssertEqual(try decodeRemoteDay("2026-08-01").items.first?.body, "one")
        XCTAssertEqual(try decodeRemoteDay("2026-08-02").items.first?.body, "two")
    }

    func testSecondCycleIsNoOp() async {
        let source = makeSource()
        source.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "one")
        let engine = makeEngine(source: source, stateDir: "a", device: "A")

        await engine.performSyncCycle()
        let uploads = backend.uploadCount
        let downloads = backend.downloadCount
        await engine.performSyncCycle()

        XCTAssertEqual(backend.uploadCount, uploads, "idle second cycle must not upload")
        XCTAssertEqual(backend.downloadCount, downloads, "idle second cycle must not download")
    }

    func testNeedsAuthWhenNotAuthorized() async {
        let source = makeSource()
        source.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "one")
        backend.authorized = false
        let engine = makeEngine(source: source, stateDir: "a", device: "A")

        await engine.performSyncCycle()

        XCTAssertEqual(engine.status, .needsAuth)
        XCTAssertFalse(backend.hasFile(dayPath("2026-08-01")))
    }

    func testReadOnlySourceNeverPushes() async {
        let source = makeSource()
        source.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "one")
        source.writable = false
        let engine = makeEngine(source: source, stateDir: "a", device: "A")

        await engine.performSyncCycle()

        XCTAssertEqual(engine.status, .idle)
        XCTAssertFalse(backend.hasFile(dayPath("2026-08-01")))
    }

    // MARK: two-device flows

    func testSecondDevicePullsDays() async {
        let a = makeSource()
        a.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "from A")
        await makeEngine(source: a, stateDir: "a", device: "A").performSyncCycle()

        let b = makeSource()
        let engineB = makeEngine(source: b, stateDir: "b", device: "B")
        await engineB.performSyncCycle()

        XCTAssertEqual(b.days["2026-08-01"]?.items.first?.body, "from A")
    }

    func testLocalEditPushesToOtherDevice() async {
        let a = makeSource()
        a.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "v1")
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()

        let b = makeSource()
        let engineB = makeEngine(source: b, stateDir: "b", device: "B")
        await engineB.performSyncCycle()

        // A edits locally, then both sync in turn.
        var edited = a.days["2026-08-01"]!
        edited.items[0].body = "v2"
        edited.updatedAt = t0.addingTimeInterval(100)
        a.days["2026-08-01"] = edited
        await engineA.performSyncCycle()
        await engineB.performSyncCycle()

        XCTAssertEqual(b.days["2026-08-01"]?.items.first?.body, "v2")
    }

    func testConcurrentDifferentItemsMergeAsUnion() async throws {
        let sharedItem = JournalItem(body: "shared")
        let a = makeSource()
        a.days["2026-08-01"] = JournalEntry(date: t0, dayKey: "2026-08-01", items: [sharedItem], createdAt: t0, updatedAt: t0)
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()

        let b = makeSource()
        let engineB = makeEngine(source: b, stateDir: "b", device: "B")
        await engineB.performSyncCycle()

        // Both devices add different items while "offline" from each other.
        let itemY = JournalItem(body: "from A")
        let itemZ = JournalItem(body: "from B")
        a.days["2026-08-01"]!.items.append(itemY)
        a.days["2026-08-01"]!.updatedAt = t0.addingTimeInterval(100)
        b.days["2026-08-01"]!.items.append(itemZ)
        b.days["2026-08-01"]!.updatedAt = t0.addingTimeInterval(200)

        await engineA.performSyncCycle() // pushes X+Y
        await engineB.performSyncCycle() // merges X+Z with X+Y → union
        await engineA.performSyncCycle() // pulls union

        let expected = Set([sharedItem.id, itemY.id, itemZ.id])
        XCTAssertEqual(Set(b.days["2026-08-01"]!.items.map(\.id)), expected)
        XCTAssertEqual(Set(a.days["2026-08-01"]!.items.map(\.id)), expected)
        XCTAssertEqual(Set(try decodeRemoteDay("2026-08-01").items.map(\.id)), expected)
        XCTAssertTrue(engineB.pendingConflicts.isEmpty)
    }

    func testSameItemConflictKeepsNewerAndArchivesLoser() async throws {
        let itemID = UUID()
        let a = makeSource()
        a.days["2026-08-01"] = JournalEntry(
            date: t0,
            dayKey: "2026-08-01",
            items: [JournalItem(id: itemID, body: "original")],
            createdAt: t0,
            updatedAt: t0
        )
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()

        let b = makeSource()
        let engineB = makeEngine(source: b, stateDir: "b", device: "B")
        await engineB.performSyncCycle()

        // Both edit the SAME item; A is newer.
        a.days["2026-08-01"]!.items[0].body = "A edit"
        a.days["2026-08-01"]!.updatedAt = t0.addingTimeInterval(200)
        b.days["2026-08-01"]!.items[0].body = "B edit"
        b.days["2026-08-01"]!.updatedAt = t0.addingTimeInterval(100)

        await engineA.performSyncCycle() // pushes A edit
        await engineB.performSyncCycle() // merge: A wins, B's copy archived

        XCTAssertEqual(b.days["2026-08-01"]?.items.first?.body, "A edit")
        XCTAssertEqual(engineB.pendingConflicts.count, 1)

        let conflictPath = try XCTUnwrap(engineB.pendingConflicts.first?.remotePath)
        let payloadData = try XCTUnwrap(backend.fileData(conflictPath))
        let payload = try JournalSyncEncoding.decoder.decode(JournalConflictPayload.self, from: payloadData)
        XCTAssertEqual(payload.losingItems.first?.body, "B edit")
    }

    // MARK: single-writer seamlessness (echo / hash-convention regressions)

    /// The reported bug: the operator types on one machine while the others
    /// stay idle. The delta echo of the device's own previous upload (whose
    /// backend content_hash can never match a locally computed one) must
    /// never read as a remote change - no self-merge, no conflict records,
    /// just the next version pushed.
    func testOwnUploadEchoWhileEditingNeverConflicts() async throws {
        let a = makeSource()
        a.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "v1")
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()

        // Keep editing across several cycles; every cycle's delta contains
        // the echo of the previous own push.
        for version in 2...4 {
            var edited = a.days["2026-08-01"]!
            edited.items[0].body = "v\(version)"
            edited.updatedAt = t0.addingTimeInterval(Double(version) * 100)
            a.days["2026-08-01"] = edited
            await engineA.performSyncCycle()
        }

        XCTAssertEqual(engineA.pendingConflicts.count, 0, "own-upload echo must never conflict")
        XCTAssertEqual(try decodeRemoteDay("2026-08-01").items.first?.body, "v4")
        XCTAssertEqual(a.days["2026-08-01"]?.items.first?.body, "v4")

        // And the day settles: further idle cycles do nothing at all.
        let uploads = backend.uploadCount
        let downloads = backend.downloadCount
        await engineA.performSyncCycle()
        XCTAssertEqual(backend.uploadCount, uploads)
        XCTAssertEqual(backend.downloadCount, downloads)
    }

    /// A device that pulls a day lands on a fixed point: the applied content
    /// re-hashes to the recorded baseline, so an online-but-idle peer never
    /// re-pushes (or otherwise churns) content it just pulled.
    func testPulledDayIsFixedPointIdlePeerNeverPushesBack() async {
        let a = makeSource()
        a.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "v1")
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()

        let b = makeSource()
        let engineB = makeEngine(source: b, stateDir: "b", device: "B")
        await engineB.performSyncCycle()
        XCTAssertEqual(b.days["2026-08-01"]?.items.first?.body, "v1")

        let uploads = backend.uploadCount
        let downloads = backend.downloadCount
        await engineB.performSyncCycle()
        await engineA.performSyncCycle()
        await engineB.performSyncCycle()
        XCTAssertEqual(backend.uploadCount, uploads, "idle peer must never re-push pulled content")
        XCTAssertEqual(backend.downloadCount, downloads)
    }

    /// A peer relaying this device's own pushed content back verbatim (e.g.
    /// an old build re-uploading identical bytes under a fresh rev) is not a
    /// conflict: the self-merge guard recognizes the content as our own and
    /// converges by re-pushing local.
    func testOwnContentRelayedBackByPeerDoesNotConflict() async throws {
        let a = makeSource()
        a.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "v1")
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()

        // A keeps editing...
        var edited = a.days["2026-08-01"]!
        edited.items[0].body = "v2"
        edited.updatedAt = t0.addingTimeInterval(100)
        a.days["2026-08-01"] = edited

        // ...while a peer relays A's exact v1 bytes under a fresh rev.
        var original = edited
        original.items[0].body = "v1"
        original.updatedAt = t0
        backend.seedFile(dayPath("2026-08-01"), data: try JournalSyncEncoding.canonicalData(for: original))

        await engineA.performSyncCycle()

        XCTAssertEqual(engineA.pendingConflicts.count, 0, "own content returning must not conflict")
        XCTAssertEqual(try decodeRemoteDay("2026-08-01").items.first?.body, "v2")
    }

    /// Remote applies are freshness-guarded: a day the user edited after the
    /// cycle's snapshot must not be overwritten by a pull - the pull aborts,
    /// and the next cycle merges the fresher local content properly.
    func testPullSkipsDayChangedAfterCycleSnapshot() async throws {
        let a = makeSource()
        a.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "from A")
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()

        let b = makeSource()
        let engineB = makeEngine(source: b, stateDir: "b", device: "B")
        await engineB.performSyncCycle() // B at baseline

        // B commits a local edit mid-cycle - after the engine took its
        // snapshot, before the pull applies.
        b.mutateOnFreshnessCheck = { days in
            var mid = days["2026-08-01"]!
            mid.items.append(JournalItem(body: "B mid-cycle"))
            mid.updatedAt = self.t0.addingTimeInterval(100)
            days["2026-08-01"] = mid
        }
        // A pushed something new, so B has a remote change to pull.
        var edited = a.days["2026-08-01"]!
        edited.items.append(JournalItem(body: "A new"))
        edited.updatedAt = t0.addingTimeInterval(50)
        a.days["2026-08-01"] = edited
        await engineA.performSyncCycle()

        await engineB.performSyncCycle()

        // The mid-cycle edit survived the pull (no clobber, no conflict).
        XCTAssertEqual(
            Set(b.days["2026-08-01"]?.items.map(\.body) ?? []),
            ["from A", "B mid-cycle"],
            "mid-cycle edit must not be clobbered by the pull"
        )
        XCTAssertEqual(engineB.pendingConflicts.count, 0)

        // The next cycle converges both sides as a clean union.
        await engineB.performSyncCycle()
        XCTAssertEqual(
            Set(try decodeRemoteDay("2026-08-01").items.map(\.body)),
            ["from A", "A new", "B mid-cycle"]
        )
        XCTAssertEqual(
            Set(b.days["2026-08-01"]?.items.map(\.body) ?? []),
            ["from A", "A new", "B mid-cycle"]
        )
    }

    // MARK: conflict resolution (keep local / remote / merged)

    private func makeResolvableConflict() async throws -> (
        a: FakeLocalSource, engineA: JournalSyncEngine,
        b: FakeLocalSource, engineB: JournalSyncEngine, extraItemID: UUID
    ) {
        let itemID = UUID()
        let a = makeSource()
        a.days["2026-08-01"] = JournalEntry(
            date: t0,
            dayKey: "2026-08-01",
            items: [JournalItem(id: itemID, body: "original")],
            createdAt: t0,
            updatedAt: t0
        )
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()

        let b = makeSource()
        let engineB = makeEngine(source: b, stateDir: "b", device: "B")
        await engineB.performSyncCycle()

        // Both edit the same item (A newer, so A wins the merge); B also has
        // a local-only extra item so the three versions stay distinguishable.
        a.days["2026-08-01"]!.items[0].body = "A edit"
        a.days["2026-08-01"]!.updatedAt = t0.addingTimeInterval(200)
        let extraItem = JournalItem(body: "B extra")
        b.days["2026-08-01"]!.items[0].body = "B edit"
        b.days["2026-08-01"]!.items.append(extraItem)
        b.days["2026-08-01"]!.updatedAt = t0.addingTimeInterval(100)

        await engineA.performSyncCycle()
        await engineB.performSyncCycle() // conflict recorded on B
        return (a, engineA, b, engineB, extraItem.id)
    }

    private func bodies(_ source: FakeLocalSource) -> Set<String> {
        Set((source.days["2026-08-01"]?.items ?? []).map(\.body))
    }

    /// Two devices that both hold a pending conflict record for the SAME day
    /// (each recorded one while being the "second syncer" in a different
    /// divergence round) — the state the user calls "各自保留".
    private func makeDualConflictFixture() async throws -> (
        a: FakeLocalSource, engineA: JournalSyncEngine,
        b: FakeLocalSource, engineB: JournalSyncEngine
    ) {
        let itemID = UUID()
        let a = makeSource()
        let b = makeSource()
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        let engineB = makeEngine(source: b, stateDir: "b", device: "B")

        a.days["2026-08-01"] = JournalEntry(
            date: t0,
            dayKey: "2026-08-01",
            items: [JournalItem(id: itemID, body: "v1")],
            createdAt: t0,
            updatedAt: t0
        )
        b.days["2026-08-01"] = a.days["2026-08-01"]!
        await engineA.performSyncCycle()
        await engineB.performSyncCycle()

        // Round 1 — B pushes first, so A is the second syncer and records a conflict.
        a.days["2026-08-01"]!.items[0].body = "A1"
        a.days["2026-08-01"]!.updatedAt = t0.addingTimeInterval(100)
        b.days["2026-08-01"]!.items[0].body = "B1"
        b.days["2026-08-01"]!.updatedAt = t0.addingTimeInterval(200)
        await engineB.performSyncCycle() // push B1
        await engineA.performSyncCycle() // A merges -> conflict on A

        // Round 2 — A pushes first, so B is the second syncer and records a conflict.
        a.days["2026-08-01"]!.items[0].body = "A2"
        a.days["2026-08-01"]!.updatedAt = t0.addingTimeInterval(250)
        b.days["2026-08-01"]!.items[0].body = "B2"
        b.days["2026-08-01"]!.updatedAt = t0.addingTimeInterval(300)
        await engineA.performSyncCycle() // push A2
        await engineB.performSyncCycle() // B merges -> conflict on B

        return (a, engineA, b, engineB)
    }

    // MARK: two-device resolution must converge, not multiply

    func testResolvingKeepRemoteOnBothDevicesConvergesWithoutReconflict() async throws {
        let f = try await makeDualConflictFixture()
        XCTAssertEqual(f.engineA.pendingConflicts.count, 1)
        XCTAssertEqual(f.engineB.pendingConflicts.count, 1)

        // The user resolves every conflict on A, then on B, both with
        // "keep remote" — this used to re-merge and spawn a fresh conflict.
        for conflict in f.engineA.pendingConflicts {
            f.engineA.resolveConflict(id: conflict.id, resolution: .remote)
        }
        await f.engineA.performSyncCycle()
        for conflict in f.engineB.pendingConflicts {
            f.engineB.resolveConflict(id: conflict.id, resolution: .remote)
        }
        await f.engineB.performSyncCycle()

        XCTAssertTrue(f.engineA.pendingConflicts.isEmpty, "A resolving keep-remote must not spawn a fresh conflict")
        XCTAssertTrue(f.engineB.pendingConflicts.isEmpty, "B resolving keep-remote must not spawn a fresh conflict")
        // Both devices and the remote converge to the current remote content.
        XCTAssertEqual(f.a.days["2026-08-01"]?.items.first?.body, "B2")
        XCTAssertEqual(f.b.days["2026-08-01"]?.items.first?.body, "B2")
        XCTAssertEqual(try decodeRemoteDay("2026-08-01").items.first?.body, "B2")
    }

    func testResolvingKeepRemoteOnAPropagatesAndPeerAutoClears() async throws {
        let f = try await makeDualConflictFixture()

        // Only A resolves (keep remote); B later syncs without touching its own
        // record. The settlement marker makes B auto-clear its stale record and
        // adopt the settled day — no manual clearing on B.
        for conflict in f.engineA.pendingConflicts {
            f.engineA.resolveConflict(id: conflict.id, resolution: .remote)
        }
        await f.engineA.performSyncCycle()
        XCTAssertTrue(f.engineA.pendingConflicts.isEmpty)

        await f.engineB.performSyncCycle()
        XCTAssertEqual(f.b.days["2026-08-01"]?.items.first?.body, "B2")
        XCTAssertTrue(f.engineB.pendingConflicts.isEmpty, "peer must auto-clear its stale record")
    }

    func testResolvingKeepLocalPropagatesWithoutReconflict() async throws {
        let f = try await makeDualConflictFixture()

        // A adopts B's latest first (fresh rev baseline), then keeps its OWN
        // older version from the conflict record.
        await f.engineA.performSyncCycle()
        XCTAssertEqual(f.a.days["2026-08-01"]?.items.first?.body, "B2")

        let record = try XCTUnwrap(f.engineA.pendingConflicts.first)
        f.engineA.resolveConflict(id: record.id, resolution: .local)
        XCTAssertTrue(f.engineA.pendingConflicts.isEmpty)

        await f.engineA.performSyncCycle()
        XCTAssertTrue(f.engineA.pendingConflicts.isEmpty, "keep-local must not spawn a fresh conflict")
        XCTAssertEqual(f.a.days["2026-08-01"]?.items.first?.body, "A1")
        XCTAssertEqual(try decodeRemoteDay("2026-08-01").items.first?.body, "A1")

        await f.engineB.performSyncCycle()
        XCTAssertEqual(f.b.days["2026-08-01"]?.items.first?.body, "A1")
    }

    func testResolvingKeepLocalOnBothDevicesConvergesToLastWriter() async throws {
        let f = try await makeDualConflictFixture()

        // Both devices keep their OWN versions — the settlement pushes use the
        // fresh rev from each cycle's listing, so they settle sequentially
        // (last writer wins) without spawning fresh conflicts.
        for conflict in f.engineA.pendingConflicts {
            f.engineA.resolveConflict(id: conflict.id, resolution: .local)
        }
        await f.engineA.performSyncCycle()
        for conflict in f.engineB.pendingConflicts {
            f.engineB.resolveConflict(id: conflict.id, resolution: .local)
        }
        await f.engineB.performSyncCycle()
        await f.engineA.performSyncCycle()

        XCTAssertTrue(f.engineA.pendingConflicts.isEmpty)
        XCTAssertTrue(f.engineB.pendingConflicts.isEmpty)
        // Last writer (B) wins and the other device adopts it.
        XCTAssertEqual(f.b.days["2026-08-01"]?.items.first?.body, "B2")
        XCTAssertEqual(f.a.days["2026-08-01"]?.items.first?.body, "B2")
        XCTAssertEqual(try decodeRemoteDay("2026-08-01").items.first?.body, "B2")
    }

    func testResolvingKeepMergedOnBothDevicesConvergesWithoutReconflict() async throws {
        let f = try await makeDualConflictFixture()

        // keep-merged writes nothing — the merge is already applied and on
        // Dropbox — so both devices just clear their notice and adopt whatever
        // the remote holds. No fresh conflict can come from this path.
        for conflict in f.engineA.pendingConflicts {
            f.engineA.resolveConflict(id: conflict.id, resolution: .merged)
        }
        for conflict in f.engineB.pendingConflicts {
            f.engineB.resolveConflict(id: conflict.id, resolution: .merged)
        }
        await f.engineA.performSyncCycle()
        await f.engineB.performSyncCycle()

        XCTAssertTrue(f.engineA.pendingConflicts.isEmpty)
        XCTAssertTrue(f.engineB.pendingConflicts.isEmpty)
        XCTAssertEqual(f.a.days["2026-08-01"]?.items.first?.body, "B2")
        XCTAssertEqual(f.b.days["2026-08-01"]?.items.first?.body, "B2")
        XCTAssertEqual(try decodeRemoteDay("2026-08-01").items.first?.body, "B2")
    }

    /// The app's real usage model: one person operates one device at a time
    /// while the others stay online and idle (their local content equals their
    /// baseline, so they pull rather than re-merge). An idle peer must adopt the
    /// operator's settled day and never accumulate fresh conflict records.
    func testOnlineIdlePeerAdoptsSettlementWithoutMultiplyingConflicts() async throws {
        let f = try await makeDualConflictFixture()

        // Operator resolves every conflict on A with keep remote.
        for conflict in f.engineA.pendingConflicts {
            f.engineA.resolveConflict(id: conflict.id, resolution: .remote)
        }
        await f.engineA.performSyncCycle()

        // B stays online and idle for several sync cycles.
        for _ in 0..<5 {
            await f.engineB.performSyncCycle()
            await f.engineA.performSyncCycle()
        }

        XCTAssertTrue(f.engineA.pendingConflicts.isEmpty)
        // B's stale record is auto-cleared by A's settlement marker — nothing
        // lingers and nothing multiplies.
        XCTAssertTrue(f.engineB.pendingConflicts.isEmpty, "idle peer must auto-clear, never accumulate")
        // Both devices converge on the remote's content (B's latest).
        XCTAssertEqual(f.a.days["2026-08-01"]?.items.first?.body, "B2")
        XCTAssertEqual(f.b.days["2026-08-01"]?.items.first?.body, "B2")
    }

    func testPeerAutoClearsStaleRecordAfterKeepLocalSettlement() async throws {
        let f = try await makeDualConflictFixture()
        XCTAssertEqual(f.engineB.pendingConflicts.count, 1)

        // Operator keeps A's own version; the pushed content + marker reach B.
        for conflict in f.engineA.pendingConflicts {
            f.engineA.resolveConflict(id: conflict.id, resolution: .local)
        }
        await f.engineA.performSyncCycle()
        await f.engineB.performSyncCycle()

        XCTAssertTrue(f.engineB.pendingConflicts.isEmpty, "peer must auto-clear its stale record")
        XCTAssertEqual(f.b.days["2026-08-01"]?.items.first?.body, "A1")
        XCTAssertEqual(try decodeRemoteDay("2026-08-01").items.first?.body, "A1")
    }

    func testKeepMergedResolutionUploadsSettlementMarker() async throws {
        let f = try await makeDualConflictFixture()

        for conflict in f.engineA.pendingConflicts {
            f.engineA.resolveConflict(id: conflict.id, resolution: .merged)
        }
        await f.engineA.performSyncCycle()

        // A uploaded a marker so peers can drop their stale reminder once the
        // day is at the settled (merged) version.
        let markers = backend.allPaths().filter {
            JournalSyncLayout.isSettlementPath($0, journalID: journalID)
        }
        XCTAssertEqual(markers.count, 1, "keep-merged must upload one settlement marker")
    }

    func testStaleSettlementMarkerDoesNotClearFreshRecord() async throws {
        let f = try await makeDualConflictFixture()
        XCTAssertEqual(f.engineB.pendingConflicts.count, 1)

        // A marker whose hash matches nothing on the remote (a settlement for a
        // different version of the day) must not clear B's record.
        let stale = JournalSettlementMarker(
            dayKey: "2026-08-01",
            settledHash: "deadbeefdeadbeef",
            deviceID: "X",
            stamp: Date()
        )
        let data = try JournalSyncEncoding.encoder.encode(stale)
        backend.seedFile(
            JournalSyncLayout.settlementPath(for: journalID, dayKey: "2026-08-01", stamp: Date()),
            data: data
        )

        await f.engineB.performSyncCycle()
        XCTAssertEqual(f.engineB.pendingConflicts.count, 1, "mismatched marker must not clear the record")
    }

    func testConflictRecordCarriesAllThreeVersions() async throws {
        let fixture = try await makeResolvableConflict()

        let record = try XCTUnwrap(fixture.engineB.pendingConflicts.first)
        XCTAssertTrue(record.offersChoice)
        XCTAssertEqual(record.localEntry?.items.map(\.body), ["B edit", "B extra"])
        XCTAssertEqual(record.remoteEntry?.items.map(\.body), ["A edit"])
        XCTAssertEqual(record.mergedEntry?.items.map(\.body), ["A edit", "B extra"])
    }

    func testResolveConflictKeepLocalPushesLocalVersion() async throws {
        let fixture = try await makeResolvableConflict()
        let record = try XCTUnwrap(fixture.engineB.pendingConflicts.first)

        fixture.engineB.resolveConflict(id: record.id, resolution: .local)

        XCTAssertTrue(fixture.engineB.pendingConflicts.isEmpty)
        XCTAssertEqual(bodies(fixture.b), ["B edit", "B extra"])
        // The resolution propagates: B pushes, A pulls.
        await fixture.engineB.performSyncCycle()
        XCTAssertEqual(
            Set(try decodeRemoteDay("2026-08-01").items.map(\.body)),
            ["B edit", "B extra"]
        )
        await fixture.engineA.performSyncCycle()
        XCTAssertEqual(bodies(fixture.a), ["B edit", "B extra"])
    }

    func testResolveConflictKeepRemoteAdoptsLiveRemote() async throws {
        let fixture = try await makeResolvableConflict()
        let record = try XCTUnwrap(fixture.engineB.pendingConflicts.first)
        let archivePath = record.remotePath
        XCTAssertTrue(backend.hasFile(archivePath))

        fixture.engineB.resolveConflict(id: record.id, resolution: .remote)

        XCTAssertTrue(fixture.engineB.pendingConflicts.isEmpty)
        // "keep remote" adopts the live remote — here the merge already applied
        // and uploaded, so the union stays (nothing stale is resurrected).
        await fixture.engineB.performSyncCycle()
        XCTAssertEqual(
            Set(try decodeRemoteDay("2026-08-01").items.map(\.body)),
            ["A edit", "B extra"]
        )
        XCTAssertEqual(bodies(fixture.b), ["A edit", "B extra"])
    }

    func testDismissConflictDeletesRemoteArchiveOnNextCycle() async throws {
        let fixture = try await makeResolvableConflict()
        let record = try XCTUnwrap(fixture.engineB.pendingConflicts.first)
        XCTAssertTrue(backend.hasFile(record.remotePath))

        fixture.engineB.dismissConflict(id: record.id)

        // Archive lives until the next cycle settles the deletion.
        XCTAssertTrue(backend.hasFile(record.remotePath))
        await fixture.engineB.performSyncCycle()
        XCTAssertFalse(backend.hasFile(record.remotePath))
    }

    func testResolvedConflictArchiveDeletedOnNextCycle() async throws {
        let fixture = try await makeResolvableConflict()
        let record = try XCTUnwrap(fixture.engineB.pendingConflicts.first)

        fixture.engineB.resolveConflict(id: record.id, resolution: .local)
        await fixture.engineB.performSyncCycle()

        XCTAssertFalse(backend.hasFile(record.remotePath))
        // The chosen day content is unaffected by the archive cleanup.
        XCTAssertEqual(
            Set(try decodeRemoteDay("2026-08-01").items.map(\.body)),
            ["B edit", "B extra"]
        )
    }

    func testResolveConflictKeepMergedOnlyClearsNotice() async throws {
        let fixture = try await makeResolvableConflict()
        let record = try XCTUnwrap(fixture.engineB.pendingConflicts.first)

        fixture.engineB.resolveConflict(id: record.id, resolution: .merged)

        XCTAssertTrue(fixture.engineB.pendingConflicts.isEmpty)
        XCTAssertEqual(bodies(fixture.b), ["A edit", "B extra"])
        await fixture.engineB.performSyncCycle()
        XCTAssertEqual(
            Set(try decodeRemoteDay("2026-08-01").items.map(\.body)),
            ["A edit", "B extra"]
        )
    }

    func testDeletePropagatesViaTombstone() async {
        let a = makeSource()
        a.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "doomed")
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()

        let b = makeSource()
        let engineB = makeEngine(source: b, stateDir: "b", device: "B")
        await engineB.performSyncCycle()
        XCTAssertNotNil(b.days["2026-08-01"])

        // A deletes the day and syncs: remote file gone, tombstone written.
        a.days.removeValue(forKey: "2026-08-01")
        await engineA.performSyncCycle()
        XCTAssertFalse(backend.hasFile(dayPath("2026-08-01")))
        XCTAssertTrue(backend.hasFile(JournalSyncLayout.tombstonePath(for: journalID, dayKey: "2026-08-01")))

        await engineB.performSyncCycle()
        XCTAssertNil(b.days["2026-08-01"])
        XCTAssertEqual(b.removedDayKeys, ["2026-08-01"])
    }

    func testDeleteVsRemoteEditResurrectsAndRecordsConflict() async {
        let a = makeSource()
        a.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "v1")
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()

        let b = makeSource()
        let engineB = makeEngine(source: b, stateDir: "b", device: "B")
        await engineB.performSyncCycle()

        // A deletes offline; B edits offline; B syncs first.
        a.days.removeValue(forKey: "2026-08-01")
        var edited = b.days["2026-08-01"]!
        edited.items[0].body = "B edit"
        edited.updatedAt = t0.addingTimeInterval(100)
        b.days["2026-08-01"] = edited
        await engineB.performSyncCycle()

        // A's deletion loses: the day comes back with B's content.
        await engineA.performSyncCycle()
        XCTAssertEqual(a.days["2026-08-01"]?.items.first?.body, "B edit")
        XCTAssertEqual(engineA.pendingConflicts.count, 1)
    }

    func testEditVsTombstoneEditWins() async throws {
        let a = makeSource()
        a.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "v1")
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()

        let b = makeSource()
        let engineB = makeEngine(source: b, stateDir: "b", device: "B")
        await engineB.performSyncCycle()

        // B edits offline; A deletes and syncs; B syncs after.
        var edited = b.days["2026-08-01"]!
        edited.items[0].body = "B edit"
        edited.updatedAt = t0.addingTimeInterval(100)
        b.days["2026-08-01"] = edited
        a.days.removeValue(forKey: "2026-08-01")
        await engineA.performSyncCycle()

        await engineB.performSyncCycle()
        // B's edit wins: day restored remotely, tombstone cleared.
        XCTAssertEqual(try decodeRemoteDay("2026-08-01").items.first?.body, "B edit")
        XCTAssertFalse(backend.hasFile(JournalSyncLayout.tombstonePath(for: journalID, dayKey: "2026-08-01")))

        // A then pulls the resurrected day back.
        await engineA.performSyncCycle()
        XCTAssertEqual(a.days["2026-08-01"]?.items.first?.body, "B edit")
    }

    func testRemoteFileVanishingWithoutTombstoneIsReuploaded() async throws {
        let a = makeSource()
        a.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "precious")
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()

        // Someone deletes the file out-of-band (no tombstone) — the engine
        // must treat that as an accident and restore it, never mirror it.
        try await backend.delete(path: dayPath("2026-08-01"))
        await engineA.performSyncCycle()

        XCTAssertEqual(a.days["2026-08-01"]?.items.first?.body, "precious")
        XCTAssertEqual(try decodeRemoteDay("2026-08-01").items.first?.body, "precious")
    }

    // MARK: images

    func testImagesUploadAndDownloadToOtherDevice() async {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        let item = JournalItem(body: "with image", imageFilenames: ["PHOTO.PNG"])
        let a = makeSource()
        a.days["2026-08-01"] = JournalEntry(date: t0, dayKey: "2026-08-01", items: [item], createdAt: t0, updatedAt: t0)
        a.images["PHOTO.PNG"] = imageData
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()

        XCTAssertTrue(backend.hasFile(JournalSyncLayout.imagePath(for: journalID, filename: "PHOTO.PNG")))

        let b = makeSource()
        let engineB = makeEngine(source: b, stateDir: "b", device: "B")
        await engineB.performSyncCycle()

        XCTAssertEqual(b.images["PHOTO.PNG"], imageData)
    }

    // MARK: robustness

    func testNewerRemoteManifestBlocksSync() async throws {
        let manifest = JournalSyncManifest(
            formatVersion: 99,
            journalID: journalID,
            journalName: "Future",
            createdAt: t0,
            deviceID: "elsewhere"
        )
        backend.seedFile(
            JournalSyncLayout.manifestPath(for: journalID),
            data: try JournalSyncEncoding.encoder.encode(manifest)
        )
        let source = makeSource()
        source.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "held back")
        let engine = makeEngine(source: source, stateDir: "a", device: "A")

        await engine.performSyncCycle()

        if case .error(let message) = engine.status {
            XCTAssertTrue(message.contains("v99"))
        } else {
            XCTFail("expected error status, got \(engine.status)")
        }
        XCTAssertFalse(backend.hasFile(dayPath("2026-08-01")))
    }

    func testExpiredCursorResetsAndRecovers() async {
        let source = makeSource()
        source.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "one")
        let engine = makeEngine(source: source, stateDir: "a", device: "A")
        await engine.performSyncCycle()

        backend.failNextIncremental = .cursorExpired
        await engine.performSyncCycle()
        // The reset cycle schedules a relist; the next cycle recovers cleanly.
        XCTAssertNotEqual(engine.status, .needsAuth)

        await engine.performSyncCycle()
        XCTAssertEqual(engine.status, .idle)
        XCTAssertTrue(backend.hasFile(dayPath("2026-08-01")))
    }

    func testStatePersistsAcrossEngineInstances() async {
        let source = makeSource()
        source.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "one")
        await makeEngine(source: source, stateDir: "shared", device: "A").performSyncCycle()
        let uploads = backend.uploadCount

        // A fresh engine over the same state directory must resume, not restart.
        let resumed = makeEngine(source: source, stateDir: "shared", device: "A")
        await resumed.performSyncCycle()

        XCTAssertEqual(backend.uploadCount, uploads)
        XCTAssertEqual(resumed.status, .idle)
    }

    func testJournalSwitchAbortsCycleWithoutWrites() async {
        let source = makeSource()
        source.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "one")
        let engine = makeEngine(source: source, stateDir: "a", device: "A")
        await engine.performSyncCycle()

        // Simulate the user switching journals: same source object, new ID.
        let otherID = UUID()
        source.journalID = otherID
        source.days = [:]
        await engine.performSyncCycle()

        // The new journal gets its own fresh remote root; nothing from the old
        // journal leaks into it.
        XCTAssertEqual(engine.status, .idle)
        XCTAssertFalse(backend.hasFile(JournalSyncLayout.dayPath(for: otherID, dayKey: "2026-08-01")))
        XCTAssertTrue(backend.hasFile(JournalSyncLayout.manifestPath(for: otherID)))
    }

    /// Rename journal A, then switch to empty journal B *during* the cycle that
    /// is still running for A. B must not inherit A's name or A's days, and A's
    /// remote days must not be tombstoned as if B's emptiness were A's deletion.
    func testMidCycleSwitchDoesNotImportPreviousJournal() async throws {
        let source = makeSource(name: "trading")
        source.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "btc")
        source.days["2026-08-02"] = entry(dayKey: "2026-08-02", body: "eth")
        let engine = makeEngine(source: source, stateDir: "a", device: "A")
        await engine.performSyncCycle()
        XCTAssertTrue(backend.hasFile(dayPath("2026-08-01")))

        source.journalName = "币安手工"
        let otherID = UUID()
        backend.onListChanges = {
            source.journalID = otherID
            source.journalName = "test"
            source.days = [:]
        }
        await engine.performSyncCycle()

        XCTAssertEqual(source.journalName, "test")
        XCTAssertTrue(source.days.isEmpty, "the newly opened journal must stay empty")
        XCTAssertTrue(backend.hasFile(dayPath("2026-08-01")), "the previous journal's remote days must remain")
        XCTAssertTrue(backend.hasFile(dayPath("2026-08-02")))
        XCTAssertFalse(
            backend.hasFile(JournalSyncLayout.dayPath(for: otherID, dayKey: "2026-08-01")),
            "the previous journal's days must not be pushed under the new id"
        )

        // A subsequent cycle for the empty journal still must not pull A's days.
        await engine.performSyncCycle()
        XCTAssertTrue(source.days.isEmpty)
        XCTAssertEqual(source.journalName, "test")
    }

    // MARK: discovery

    func testDiscoversOtherJournalsManifests() async throws {
        // Another device's journal exists on the remote.
        let otherID = UUID()
        let otherManifest = JournalSyncManifest(
            formatVersion: 1,
            journalID: otherID,
            journalName: "Mac 13 Journal",
            createdAt: t0,
            deviceID: "B"
        )
        backend.seedFile(
            JournalSyncLayout.manifestPath(for: otherID),
            data: try JournalSyncEncoding.encoder.encode(otherManifest)
        )

        let source = makeSource()
        let engine = makeEngine(source: source, stateDir: "a", device: "A")
        await engine.performSyncCycle()

        XCTAssertEqual(engine.discoveredJournals.count, 1)
        XCTAssertEqual(engine.discoveredJournals.first?.journalID, otherID)
        XCTAssertEqual(engine.discoveredJournals.first?.journalName, "Mac 13 Journal")

        // Discovery is cached in state: a fresh engine instance over the same
        // state dir republishes it without re-downloading.
        let downloads = backend.downloadCount
        let resumed = makeEngine(source: source, stateDir: "a", device: "A")
        await resumed.performSyncCycle()
        XCTAssertEqual(resumed.discoveredJournals.count, 1)
        XCTAssertEqual(backend.downloadCount, downloads)
    }

    func testActiveJournalManifestIsNotReportedAsDiscovered() async {
        let source = makeSource()
        let engine = makeEngine(source: source, stateDir: "a", device: "A")
        await engine.performSyncCycle()
        XCTAssertTrue(engine.discoveredJournals.isEmpty)
    }

    func testDiscoveredRecordPrunedWhenManifestVanishes() async throws {
        let otherID = UUID()
        let manifest = JournalSyncManifest(
            formatVersion: 1,
            journalID: otherID,
            journalName: "Gone Soon",
            createdAt: t0,
            deviceID: "B"
        )
        let manifestPath = JournalSyncLayout.manifestPath(for: otherID)
        backend.seedFile(manifestPath, data: try JournalSyncEncoding.encoder.encode(manifest))

        let source = makeSource()
        let engine = makeEngine(source: source, stateDir: "a", device: "A")
        await engine.performSyncCycle()
        XCTAssertEqual(engine.discoveredJournals.count, 1)

        try await backend.delete(path: manifestPath)
        await engine.performSyncCycle()
        XCTAssertTrue(engine.discoveredJournals.isEmpty)
    }

    // MARK: journal deletion propagation

    func testLocalJournalDeletionUploadsTombstoneAndCleansFolder() async {
        let doomedID = UUID()
        let a = FakeLocalSource(journalID: doomedID, name: "Doomed")
        a.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "legacy")
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()
        XCTAssertTrue(backend.hasFile(JournalSyncLayout.manifestPath(for: doomedID)))

        // The user deletes the journal (the store switches the active one
        // first); the deletion must propagate to the remote.
        a.journalID = journalID
        a.days = [:]
        engineA.queueJournalDeletion(doomedID)
        await engineA.performSyncCycle()

        XCTAssertFalse(backend.hasFile(JournalSyncLayout.manifestPath(for: doomedID)))
        XCTAssertFalse(backend.hasFile(JournalSyncLayout.dayPath(for: doomedID, dayKey: "2026-08-01")))
        XCTAssertTrue(backend.hasFile(JournalSyncLayout.journalTombstonePath(for: doomedID)))
    }

    func testPeerAppliesRemoteJournalTombstoneAndDropsDiscovery() async {
        let doomedID = UUID()
        let a = FakeLocalSource(journalID: doomedID, name: "Doomed")
        a.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "legacy")
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()

        // B (on its own journal) discovers the doomed journal's manifest.
        let b = makeSource()
        let engineB = makeEngine(source: b, stateDir: "b", device: "B")
        await engineB.performSyncCycle()
        XCTAssertEqual(engineB.discoveredJournals.map(\.journalID), [doomedID])

        // A deletes the journal; the tombstone reaches B on its next cycle.
        a.journalID = journalID
        a.days = [:]
        engineA.queueJournalDeletion(doomedID)
        await engineA.performSyncCycle()

        await engineB.performSyncCycle()
        XCTAssertTrue(engineB.discoveredJournals.isEmpty, "tombstoned journal must vanish from discovery")
        XCTAssertEqual(engineB.remoteJournalDeletions, [doomedID])

        engineB.acknowledgeRemoteJournalDeletion(doomedID)
        XCTAssertEqual(engineB.remoteJournalDeletions, [])

        // And it stays gone - nothing resurfaces on later cycles.
        await engineB.performSyncCycle()
        XCTAssertTrue(engineB.discoveredJournals.isEmpty)
    }

    func testFreshDeviceSkipsTombstonedJournalInDiscovery() async throws {
        let deadID = UUID()
        let manifest = JournalSyncManifest(
            formatVersion: 1,
            journalID: deadID,
            journalName: "Deleted",
            createdAt: t0,
            deviceID: "X"
        )
        backend.seedFile(
            JournalSyncLayout.manifestPath(for: deadID),
            data: try JournalSyncEncoding.encoder.encode(manifest)
        )
        backend.seedFile(
            JournalSyncLayout.journalTombstonePath(for: deadID),
            data: try JournalSyncEncoding.encoder.encode(
                JournalDeletionTombstone(journalID: deadID, deletedAt: Date(), deviceID: "X")
            )
        )

        let source = makeSource()
        let engine = makeEngine(source: source, stateDir: "a", device: "A")
        await engine.performSyncCycle()

        XCTAssertTrue(engine.discoveredJournals.isEmpty, "a tombstoned journal is deleted, not adoptable")
        XCTAssertEqual(engine.remoteJournalDeletions, [deadID])
    }

    func testDeletionQueueIgnoresJournalsWithoutRemotePresence() async {
        let source = makeSource()
        let engine = makeEngine(source: source, stateDir: "a", device: "A")
        engine.queueJournalDeletion(UUID())
        await engine.performSyncCycle()

        XCTAssertFalse(
            backend.allPaths().contains { $0.hasPrefix("/journal-tombstones/") },
            "never-synced journals must not leave remote tombstones"
        )
    }

    func testJournalTombstoneGarbageCollectedAfterRetention() async throws {
        let deadID = UUID()
        let stale = JournalDeletionTombstone(
            journalID: deadID,
            deletedAt: Date().addingTimeInterval(-(JournalSyncLayout.tombstoneRetention + 24 * 3600)),
            deviceID: "X"
        )
        backend.seedFile(
            JournalSyncLayout.journalTombstonePath(for: deadID),
            data: try JournalSyncEncoding.encoder.encode(stale)
        )

        let source = makeSource()
        let engine = makeEngine(source: source, stateDir: "a", device: "A")
        await engine.performSyncCycle()

        XCTAssertFalse(backend.hasFile(JournalSyncLayout.journalTombstonePath(for: deadID)))
    }

    func testResurrectedFolderOfTombstonedJournalIsCleanedAgain() async throws {
        let deadID = UUID()
        backend.seedFile(
            JournalSyncLayout.journalTombstonePath(for: deadID),
            data: try JournalSyncEncoding.encoder.encode(
                JournalDeletionTombstone(journalID: deadID, deletedAt: Date(), deviceID: "X")
            )
        )
        let source = makeSource()
        let engine = makeEngine(source: source, stateDir: "a", device: "A")
        await engine.performSyncCycle() // tombstone detected (published, unacked)

        // A racing push re-creates a file under the deleted journal's folder.
        let strayPath = JournalSyncLayout.manifestPath(for: deadID)
        backend.seedFile(strayPath, data: Data("{}".utf8))

        await engine.performSyncCycle()
        XCTAssertFalse(backend.hasFile(strayPath), "tombstoned folders must not linger")
        XCTAssertTrue(backend.hasFile(JournalSyncLayout.journalTombstonePath(for: deadID)))
    }

    // MARK: re-import baseline reset

    /// Characterizes the hazard `resetSyncState` exists to prevent: importing
    /// a journal whose stale state file survived — "empty local" reads as
    /// "deleted everywhere" and the engine tombstones the remote content.
    func testStaleStateAfterLocalWipeTombstonesRemote() async throws {
        let source = makeSource()
        source.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "precious")
        await makeEngine(source: source, stateDir: "a", device: "A").performSyncCycle()

        // Journal wiped locally (e.g. deleted); a new engine resumes over the
        // SAME state directory — exactly what re-importing must NOT do.
        let wiped = makeSource()
        let resumed = makeEngine(source: wiped, stateDir: "a", device: "A")
        await resumed.performSyncCycle()

        XCTAssertTrue(
            backend.hasFile(JournalSyncLayout.tombstonePath(for: journalID, dayKey: "2026-08-01")),
            "stale baseline turns an empty local copy into a delete propagation"
        )
        XCTAssertFalse(backend.hasFile(dayPath("2026-08-01")))
    }

    /// The intended re-import flow: reset the baseline, then sync — the empty
    /// local copy pulls remote content down instead of deleting it.
    func testResetSyncStateMakesReimportPullInsteadOfDelete() async throws {
        let source = makeSource()
        source.days["2026-08-01"] = entry(dayKey: "2026-08-01", body: "precious")
        let engine = makeEngine(source: source, stateDir: "a", device: "A")
        await engine.performSyncCycle()

        let wiped = makeSource()
        let reimported = makeEngine(source: wiped, stateDir: "a", device: "A")
        reimported.resetSyncState(for: journalID)
        await reimported.performSyncCycle()

        XCTAssertEqual(wiped.days["2026-08-01"]?.items.first?.body, "precious")
        XCTAssertTrue(backend.hasFile(dayPath("2026-08-01")))
        XCTAssertFalse(backend.hasFile(JournalSyncLayout.tombstonePath(for: journalID, dayKey: "2026-08-01")))
    }

    // MARK: journal name sync

    private func decodeRemoteManifest() throws -> JournalSyncManifest {
        let data = try XCTUnwrap(backend.fileData(JournalSyncLayout.manifestPath(for: journalID)))
        return try JournalSyncEncoding.decoder.decode(JournalSyncManifest.self, from: data)
    }

    private func makeStateStore(_ stateDir: String) -> JournalSyncStateStore {
        JournalSyncStateStore(directory: tempRoot.appendingPathComponent(stateDir, isDirectory: true))
    }

    func testRenamePushesToOtherDevice() async throws {
        let a = makeSource()
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()
        let b = makeSource()
        let engineB = makeEngine(source: b, stateDir: "b", device: "B")
        await engineB.performSyncCycle()

        a.journalName = "Work Log"
        await engineA.performSyncCycle()
        XCTAssertEqual(try decodeRemoteManifest().journalName, "Work Log")

        await engineB.performSyncCycle()
        XCTAssertEqual(b.journalName, "Work Log")
    }

    func testRenameSyncConvergesWithoutEchoes() async {
        let a = makeSource()
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()
        let b = makeSource()
        let engineB = makeEngine(source: b, stateDir: "b", device: "B")
        await engineB.performSyncCycle()

        a.journalName = "Renamed"
        await engineA.performSyncCycle()
        await engineB.performSyncCycle()
        XCTAssertEqual(b.journalName, "Renamed")

        // Once converged, further cycles touch nothing.
        let uploads = backend.uploadCount
        await engineB.performSyncCycle()
        await engineA.performSyncCycle()
        XCTAssertEqual(backend.uploadCount, uploads, "converged names must not re-upload")
    }

    func testDoubleRenameResolvesLastPushWins() async {
        let a = makeSource()
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()
        let b = makeSource()
        let engineB = makeEngine(source: b, stateDir: "b", device: "B")
        await engineB.performSyncCycle()

        // Both rename while "offline" from each other; B pushes last and wins.
        a.journalName = "A Name"
        b.journalName = "B Name"
        await engineA.performSyncCycle()
        await engineB.performSyncCycle()
        XCTAssertEqual(b.journalName, "B Name")

        await engineA.performSyncCycle()
        XCTAssertEqual(a.journalName, "B Name")
    }

    func testFreshImportAdoptsRemoteJournalName() async {
        let a = makeSource()
        let engineA = makeEngine(source: a, stateDir: "a", device: "A")
        await engineA.performSyncCycle()

        // A device adopting the journal under a placeholder name follows the
        // remote manifest instead of pushing its placeholder back.
        let b = makeSource(name: "Local Placeholder")
        let engineB = makeEngine(source: b, stateDir: "b", device: "B")
        await engineB.performSyncCycle()
        XCTAssertEqual(b.journalName, "Test Journal")

        let uploads = backend.uploadCount
        await engineB.performSyncCycle()
        XCTAssertEqual(backend.uploadCount, uploads, "adopted name must become a stable baseline")
    }

    /// State files written before journal names synced carry no name baseline.
    /// Seeded from the remote manifest, a rename the old app never pushed reads
    /// as a local change and propagates on the first post-upgrade cycle.
    func testLegacyStateWithoutNameBaselinePushesUnpropagatedRename() async throws {
        let a = makeSource()
        let storeA = makeStateStore("a")
        await makeEngine(source: a, stateDir: "a", device: "A").performSyncCycle()

        var legacy = storeA.load(for: journalID)
        legacy.manifestName = nil
        storeA.save(legacy, for: journalID)
        a.journalName = "Renamed Before Upgrade"

        let upgraded = makeEngine(source: a, stateDir: "a", device: "A")
        await upgraded.performSyncCycle()

        XCTAssertEqual(try decodeRemoteManifest().journalName, "Renamed Before Upgrade")

        let uploads = backend.uploadCount
        await upgraded.performSyncCycle()
        XCTAssertEqual(backend.uploadCount, uploads, "seeded baseline must settle after the push")
    }

    /// The other legacy edge: a peer on an OLD build never rewrote manifests,
    /// so a manifest that moved since the baseline was recorded can only come
    /// from a rename-capable device — the upgraded peer's name wins over the
    /// stale local one.
    func testLegacyDeviceAdoptsRenamePushedByUpgradedPeer() async throws {
        let a = makeSource()
        let storeA = makeStateStore("a")
        await makeEngine(source: a, stateDir: "a", device: "A").performSyncCycle()
        let b = makeSource()
        let storeB = makeStateStore("b")
        await makeEngine(source: b, stateDir: "b", device: "B").performSyncCycle()

        // Roll both back to legacy state files (no name baseline).
        var legacyA = storeA.load(for: journalID)
        legacyA.manifestName = nil
        storeA.save(legacyA, for: journalID)
        var legacyB = storeB.load(for: journalID)
        legacyB.manifestName = nil
        storeB.save(legacyB, for: journalID)

        // A renamed while on the old app; upgrading pushes the rename.
        a.journalName = "New Name"
        await makeEngine(source: a, stateDir: "a", device: "A").performSyncCycle()

        // B (still holding the old name) upgrades after the push: the remote
        // manifest moved, so B adopts instead of pushing its stale name back.
        await makeEngine(source: b, stateDir: "b", device: "B").performSyncCycle()
        XCTAssertEqual(b.journalName, "New Name")
    }
}
