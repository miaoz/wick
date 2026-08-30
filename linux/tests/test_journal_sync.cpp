#include "FakeSyncBackend.h"
#include "JournalDayMerge.h"
#include "JournalModels.h"
#include "JournalSyncEncoding.h"
#include "JournalSyncEngine.h"
#include "JournalSyncState.h"

#include <openssl/sha.h>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <map>
#include <set>
#include <string>
#include <unistd.h>
#include <vector>

using namespace wick;

static int g_fails = 0;
static int g_passes = 0;

#define CHECK(cond)                                                                          \
    do {                                                                                     \
        if (!(cond)) {                                                                       \
            std::cerr << "FAIL " << __FILE__ << ":" << __LINE__ << " : " << #cond << "\n"; \
            ++g_fails;                                                                       \
        } else {                                                                             \
            ++g_passes;                                                                      \
        }                                                                                    \
    } while (0)

static std::filesystem::path makeTempDir(const char* prefix) {
    auto base = std::filesystem::temp_directory_path() / (std::string(prefix) + "XXXXXX");
    std::string tmpl = base.string();
    std::vector<char> buf(tmpl.begin(), tmpl.end());
    buf.push_back('\0');
    if (!mkdtemp(buf.data())) throw std::runtime_error("mkdtemp failed");
    return std::filesystem::path(buf.data());
}

static TimePoint t0() { return timeFromUnix(1'754'000'000); }
static TimePoint t1() { return timeFromUnix(1'754'001'000); }
static TimePoint t2() { return timeFromUnix(1'754'002'000); }

static TimePoint dateFromDayKey(const std::string& dayKey) {
    int Y = 0, M = 0, D = 0;
    std::sscanf(dayKey.c_str(), "%d-%d-%d", &Y, &M, &D);
    std::tm tm{};
    tm.tm_year = Y - 1900;
    tm.tm_mon = M - 1;
    tm.tm_mday = D;
    tm.tm_isdst = 0;
    return timeFromUnix(static_cast<std::int64_t>(timegm(&tm)));
}

static Uuid entryIDForDay(const std::string& dayKey) {
    unsigned char digest[SHA256_DIGEST_LENGTH];
    SHA256(reinterpret_cast<const unsigned char*>(dayKey.data()), dayKey.size(), digest);
    Uuid u;
    std::memcpy(u.bytes.data(), digest, 16);
    return u;
}

static JournalItem itemBody(const std::string& body) {
    JournalItem it;
    it.id = Uuid::generate();
    it.body = body;
    return it;
}

static JournalEntry makeEntry(const Uuid& id, const std::vector<JournalItem>& items,
                              const std::string& title = "",
                              TimePoint created = {}, TimePoint updated = {}) {
    JournalEntry e;
    e.id = id;
    e.date = t0();
    e.title = title;
    e.items = items;
    e.createdAt = created.time_since_epoch().count() == 0 ? t0() : created;
    e.updatedAt = updated.time_since_epoch().count() == 0 ? t1() : updated;
    return e;
}

class FakeLocalSource : public JournalLocalSource {
public:
    Uuid journalID;
    std::string journalName = "Test Journal";
    bool writable = true;
    std::map<std::string, JournalEntry> days;
    std::map<std::string, std::string> images;
    std::vector<std::string> removedDayKeys;
    int applyBatchCount = 0;
    int applyMutationCount = 0;

    explicit FakeLocalSource(Uuid id, std::string name = "Test Journal")
        : journalID(id), journalName(std::move(name)) {}

    std::optional<Uuid> syncJournalID() const override { return journalID; }
    std::string syncJournalName() const override { return journalName; }
    bool syncIsWritable() const override { return writable; }

    std::map<Uuid, JournalEntry> syncEntrySnapshots() override {
        std::map<Uuid, JournalEntry> out;
        for (const auto& [_, e] : days) out[e.id] = e;
        return out;
    }
    std::optional<JournalEntry> syncEntrySnapshot(const Uuid& entryID) override {
        for (const auto& [_, e] : days) {
            if (e.id == entryID) return e;
        }
        return std::nullopt;
    }
    void prepareForRemoteApply(const Uuid&) override {}

    std::set<Uuid> applySyncedChanges(const std::vector<JournalSyncMutation>& changes,
                                      const Uuid& jid) override {
        if (!(jid == journalID)) return {};
        ++applyBatchCount;
        applyMutationCount += static_cast<int>(changes.size());
        std::set<Uuid> applied;
        for (const auto& change : changes) {
            if (!localStillMatches(change.entryID, change.expectedLocalHash)) continue;
            if (change.kind == JournalSyncMutation::Kind::upsert) {
                days[JournalDayKey::make(change.entry.date, 0)] = change.entry;
            } else {
                for (auto it = days.begin(); it != days.end(); ++it) {
                    if (it->second.id == change.entryID) {
                        removedDayKeys.push_back(it->first);
                        days.erase(it);
                        break;
                    }
                }
            }
            applied.insert(change.entryID);
        }
        return applied;
    }
    void applySyncedEntry(const JournalEntry& entry, const Uuid& jid) override {
        if (!(jid == journalID)) return;
        days[JournalDayKey::make(entry.date, 0)] = entry;
    }
    void removeSyncedEntry(const Uuid& entryID, const Uuid& jid) override {
        if (!(jid == journalID)) return;
        for (auto it = days.begin(); it != days.end(); ++it) {
            if (it->second.id == entryID) {
                removedDayKeys.push_back(it->first);
                days.erase(it);
                return;
            }
        }
    }
    std::string applySyncedJournalName(const std::string& name, const Uuid& jid) override {
        if (!(jid == journalID)) return journalName;
        journalName = name;
        return name;
    }
    std::set<std::string> syncedImageFilenames() override {
        std::set<std::string> out;
        for (const auto& [_, e] : days) {
            for (const auto& item : e.items) {
                for (const auto& f : item.imageFilenames) out.insert(f);
            }
        }
        return out;
    }
    std::optional<std::string> syncedImageData(const std::string& filename) override {
        auto it = images.find(filename);
        if (it == images.end()) return std::nullopt;
        return it->second;
    }
    bool hasSyncedImage(const std::string& filename) override { return images.count(filename) > 0; }
    void storeSyncedImage(const std::string& filename, std::string_view data, const Uuid& jid) override {
        if (!(jid == journalID)) return;
        images[filename] = std::string(data);
    }

    std::optional<JournalTradingSnapshotDocument> tradingSnapshot;
    std::optional<JournalTradingSnapshotDocument> syncedTradingSnapshot(const Uuid& jid) override {
        if (!(jid == journalID)) return std::nullopt;
        return tradingSnapshot;
    }
    void applySyncedTradingSnapshot(const JournalTradingSnapshotDocument& doc, const Uuid& jid) override {
        if (!(jid == journalID)) return;
        tradingSnapshot = doc;
    }
    void removeSyncedTradingSnapshot(const Uuid& jid) override {
        if (!(jid == journalID)) return;
        tradingSnapshot = std::nullopt;
    }

private:
    bool localStillMatches(const Uuid& entryID, const std::optional<std::string>& expectedHash) {
        std::optional<JournalEntry> current;
        for (const auto& [_, e] : days) {
            if (e.id == entryID) { current = e; break; }
        }
        if (!expectedHash) return !current;
        if (!current) return false;
        return JournalSyncEncoding::contentHash(*current) == *expectedHash;
    }
};

struct Harness {
    std::filesystem::path tempRoot;
    FakeSyncBackend backend;
    Uuid journalID = Uuid::generate();

    Harness() { tempRoot = makeTempDir("wick-sync-"); }
    ~Harness() {
        std::error_code ec;
        std::filesystem::remove_all(tempRoot, ec);
    }

    FakeLocalSource makeSource(const std::string& name = "Test Journal") {
        return FakeLocalSource(journalID, name);
    }
    JournalSyncEngine makeEngine(FakeLocalSource& source, const std::string& stateDir, const std::string& device) {
        JournalSyncStateStore store(tempRoot / stateDir);
        return JournalSyncEngine(backend, source, device, store);
    }
    JournalEntry entry(const std::string& dayKey, const std::string& body, TimePoint updated = {}) {
        JournalEntry e;
        e.id = entryIDForDay(dayKey);
        e.date = dateFromDayKey(dayKey);
        e.items = {itemBody(body)};
        e.createdAt = t0();
        e.updatedAt = updated.time_since_epoch().count() == 0 ? t0() : updated;
        return e;
    }
    std::string dayPath(const std::string& dayKey) {
        return JournalSyncLayout::entryPath(journalID, entryIDForDay(dayKey));
    }
    JournalEntry decodeRemoteDay(const std::string& dayKey) {
        auto data = backend.fileData(dayPath(dayKey));
        if (!data) throw std::runtime_error("missing remote day " + dayKey);
        return JournalSyncEncoding::decodeEntry(*data);
    }
    JournalSyncManifest decodeRemoteManifest() {
        auto data = backend.fileData(JournalSyncLayout::manifestPath(journalID));
        if (!data) throw std::runtime_error("missing remote manifest");
        return decodeManifest(*data);
    }
};

// --- JournalDayMerge (JournalDayMergeTests.swift) ---

static void testMerge() {
    const Uuid entryID = Uuid::generate();
    auto entry = [&](std::vector<JournalItem> items, const std::string& title = "",
                     TimePoint created = {}, TimePoint updated = {}) {
        return makeEntry(entryID, items, title, created.time_since_epoch().count() == 0 ? t0() : created,
                         updated.time_since_epoch().count() == 0 ? t1() : updated);
    };

    {
        JournalItem x; x.id = Uuid::generate(); x.tag = "X";
        JournalItem y; y.id = Uuid::generate(); y.tag = "Y";
        auto result = JournalEntryMerge::merge(entry({x}), entry({y}));
        CHECK(result.merged.items.size() == 2);
        CHECK(result.losingItems.empty());
    }
    {
        JournalItem shared; shared.id = Uuid::generate(); shared.tag = "same"; shared.body = "b";
        auto result = JournalEntryMerge::merge(entry({shared}), entry({shared}));
        CHECK(result.merged.items.size() == 1);
        CHECK(result.losingItems.empty());
    }
    {
        Uuid id = Uuid::generate();
        JournalItem older; older.id = id; older.body = "older edit";
        JournalItem newer; newer.id = id; newer.body = "newer edit";
        auto local = entry({newer}, "", t0(), t2());
        auto remote = entry({older}, "", t0(), t1());
        auto result = JournalEntryMerge::merge(local, remote);
        CHECK(result.merged.items.front().body == "newer edit");
        CHECK(!result.losingItems.empty() && result.losingItems.front().body == "older edit");
    }
    {
        // Remote is newer: loser must stay the local copy (value, not a map ref).
        Uuid id = Uuid::generate();
        JournalItem older; older.id = id; older.body = "older edit";
        JournalItem newer; newer.id = id; newer.body = "newer edit";
        auto local = entry({older}, "", t0(), t1());
        auto remote = entry({newer}, "", t0(), t2());
        auto result = JournalEntryMerge::merge(local, remote);
        CHECK(result.merged.items.front().body == "newer edit");
        CHECK(!result.losingItems.empty() && result.losingItems.front().body == "older edit");
    }
    {
        auto later = t0() + std::chrono::seconds(86400);
        JournalEntry local; local.id = entryID; local.date = later; local.createdAt = t0(); local.updatedAt = t2();
        local.items = {JournalItem{Uuid::generate(), "", "", {}, std::nullopt}};
        JournalEntry remote; remote.id = entryID; remote.date = t0(); remote.createdAt = t0(); remote.updatedAt = t1();
        remote.items = {JournalItem{Uuid::generate(), "", "", {}, std::nullopt}};
        auto merged = JournalEntryMerge::merge(local, remote).merged;
        CHECK(merged.id == entryID);
        CHECK(unixFromTime(merged.date) == unixFromTime(later));
    }
    {
        auto local = entry({itemBody("x")}, "local title", t0(), t2());
        auto remote = entry({itemBody("x")}, "remote title", t0(), t1());
        auto result = JournalEntryMerge::merge(local, remote);
        CHECK(result.merged.title == "local title");
        CHECK(result.losingTitle && *result.losingTitle == "remote title");
    }
    {
        auto local = entry({itemBody("x")}, "", t0(), t2());
        auto remote = entry({itemBody("x")}, "theirs", t0(), t1());
        CHECK(JournalEntryMerge::merge(local, remote).merged.title == "theirs");
        CHECK(!JournalEntryMerge::merge(local, remote).losingTitle);
    }
    {
        JournalItem placeholder; placeholder.id = Uuid::generate();
        JournalItem real; real.id = Uuid::generate(); real.body = "content";
        auto result = JournalEntryMerge::merge(entry({placeholder}), entry({real}));
        CHECK(result.merged.items.size() == 1);
        CHECK(result.merged.items.front().body == "content");
    }
    {
        auto local = entry({itemBody("x")}, "", t1(), t1());
        auto remote = entry({itemBody("y")}, "", t0(), t2());
        auto merged = JournalEntryMerge::merge(local, remote).merged;
        CHECK(unixFromTime(merged.createdAt) == unixFromTime(t0()));
        CHECK(unixFromTime(merged.updatedAt) == unixFromTime(t2()));
    }
}

// --- Fake backend surface ---

static void testFakeBackend() {
    FakeSyncBackend b;
    CHECK(b.isAuthorized());
    CHECK(b.accountEmail() && *b.accountEmail() == "fake@example.com");
    CHECK(b.authorize() == "fake@example.com");

    auto [empty, cursor0] = b.listChanges(std::nullopt);
    CHECK(empty.empty());

    const std::string path = "/journals/abc/entries/x.json";
    const std::string rev1 = b.upload(path, "hello", std::nullopt);
    CHECK(rev1 == "r1");
    CHECK(b.hasFile(path));
    auto [data, rev] = b.download(path);
    CHECK(data == "hello");
    CHECK(rev == "r1");

    bool conflicted = false;
    try {
        b.upload(path, "other", std::nullopt);
    } catch (const SyncBackendError& e) {
        conflicted = e.kind == SyncBackendError::Kind::writeConflict;
    }
    CHECK(conflicted);

    conflicted = false;
    try {
        b.upload(path, "other", std::string("wrong"));
    } catch (const SyncBackendError& e) {
        conflicted = e.kind == SyncBackendError::Kind::writeConflict;
    }
    CHECK(conflicted);

    const std::string rev2 = b.upload(path, "world", rev1);
    CHECK(rev2 == "r2");
    CHECK(*b.fileData(path) == "world");

    auto [full, cursor1] = b.listChanges(std::nullopt);
    CHECK(full.size() == 1);
    CHECK(full[0].rev && *full[0].rev == "r2");
    CHECK(full[0].contentHash && *full[0].contentHash == dropboxStyleContentHash("world"));
    CHECK(*full[0].contentHash != JournalSyncEncoding::contentHash(std::string_view("world")));

    auto [delta, cursor2] = b.listChanges(cursor0);
    CHECK(delta.size() >= 2); // r1 then r2

    b.deletePath(path);
    CHECK(!b.hasFile(path));
    auto [afterDel, cursor3] = b.listChanges(cursor2);
    CHECK(afterDel.size() == 1);
    CHECK(afterDel[0].isDeleted);

    b.deletePath("/missing"); // already deleted
    b.signOut();
    CHECK(!b.isAuthorized());

    CHECK(dropboxStyleContentHash("") == "5df6e0e2761359d30a8275058e299fcc0381534545f55cf43e41983f5d4c9456");
    CHECK(JournalSyncEncoding::contentHash(std::string_view(""))
          == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
}

static void testFirstSyncUploadsManifestAndDays() {
    Harness h;
    auto source = h.makeSource();
    source.days["2026-08-01"] = h.entry("2026-08-01", "one");
    source.days["2026-08-02"] = h.entry("2026-08-02", "two");
    auto engine = h.makeEngine(source, "a", "A");
    engine.performSyncCycle();
    CHECK(engine.status() == JournalSyncEngine::Status::idle);
    CHECK(engine.lastSyncAt().has_value());
    CHECK(h.backend.hasFile(JournalSyncLayout::manifestPath(h.journalID)));
    CHECK(h.decodeRemoteDay("2026-08-01").items.front().body == "one");
    CHECK(h.decodeRemoteDay("2026-08-02").items.front().body == "two");
}

static void testSecondCycleIsNoOp() {
    Harness h;
    auto source = h.makeSource();
    source.days["2026-08-01"] = h.entry("2026-08-01", "one");
    auto engine = h.makeEngine(source, "a", "A");
    engine.performSyncCycle();
    const int uploads = h.backend.uploadCount;
    const int downloads = h.backend.downloadCount;
    engine.performSyncCycle();
    CHECK(h.backend.uploadCount == uploads);
    CHECK(h.backend.downloadCount == downloads);
}

static void testNeedsAuthWhenNotAuthorized() {
    Harness h;
    auto source = h.makeSource();
    source.days["2026-08-01"] = h.entry("2026-08-01", "one");
    h.backend.authorized = false;
    auto engine = h.makeEngine(source, "a", "A");
    engine.performSyncCycle();
    CHECK(engine.status() == JournalSyncEngine::Status::needsAuth);
    CHECK(!h.backend.hasFile(h.dayPath("2026-08-01")));
}

static void testReadOnlySourceNeverPushes() {
    Harness h;
    auto source = h.makeSource();
    source.days["2026-08-01"] = h.entry("2026-08-01", "one");
    source.writable = false;
    auto engine = h.makeEngine(source, "a", "A");
    engine.performSyncCycle();
    CHECK(engine.status() == JournalSyncEngine::Status::idle);
    CHECK(!h.backend.hasFile(h.dayPath("2026-08-01")));
}

static void testSecondDevicePullsDays() {
    Harness h;
    auto a = h.makeSource();
    a.days["2026-08-01"] = h.entry("2026-08-01", "from A");
    h.makeEngine(a, "a", "A").performSyncCycle();
    auto b = h.makeSource();
    auto engineB = h.makeEngine(b, "b", "B");
    engineB.performSyncCycle();
    CHECK(b.days.count("2026-08-01"));
    CHECK(b.days["2026-08-01"].items.front().body == "from A");
}

static void testEchoSuppression() {
    Harness h;
    auto a = h.makeSource();
    a.days["2026-08-01"] = h.entry("2026-08-01", "v1");
    auto engineA = h.makeEngine(a, "a", "A");
    engineA.performSyncCycle();
    for (int version = 2; version <= 4; ++version) {
        auto edited = a.days["2026-08-01"];
        edited.items[0].body = "v" + std::to_string(version);
        edited.updatedAt = t0() + std::chrono::seconds(version * 100);
        a.days["2026-08-01"] = edited;
        engineA.performSyncCycle();
    }
    CHECK(engineA.pendingConflicts().empty());
    CHECK(h.decodeRemoteDay("2026-08-01").items.front().body == "v4");
    CHECK(a.days["2026-08-01"].items.front().body == "v4");
    const int uploads = h.backend.uploadCount;
    const int downloads = h.backend.downloadCount;
    engineA.performSyncCycle();
    CHECK(h.backend.uploadCount == uploads);
    CHECK(h.backend.downloadCount == downloads);
}

static void testPullFixedPoint() {
    Harness h;
    auto a = h.makeSource();
    a.days["2026-08-01"] = h.entry("2026-08-01", "v1");
    h.makeEngine(a, "a", "A").performSyncCycle();
    auto b = h.makeSource();
    auto engineB = h.makeEngine(b, "b", "B");
    engineB.performSyncCycle();
    CHECK(b.days["2026-08-01"].items.front().body == "v1");
    const int uploads = h.backend.uploadCount;
    const int downloads = h.backend.downloadCount;
    engineB.performSyncCycle();
    h.makeEngine(a, "a", "A").performSyncCycle();
    engineB.performSyncCycle();
    CHECK(h.backend.uploadCount == uploads);
    CHECK(h.backend.downloadCount == downloads);
}

static void testNeverConflictWithSelf() {
    Harness h;
    auto a = h.makeSource();
    a.days["2026-08-01"] = h.entry("2026-08-01", "v1");
    auto engineA = h.makeEngine(a, "a", "A");
    engineA.performSyncCycle();
    auto edited = a.days["2026-08-01"];
    edited.items[0].body = "v2";
    edited.updatedAt = t0() + std::chrono::seconds(100);
    a.days["2026-08-01"] = edited;
    auto original = edited;
    original.items[0].body = "v1";
    original.updatedAt = t0();
    h.backend.seedFile(h.dayPath("2026-08-01"), JournalSyncEncoding::canonicalData(original));
    engineA.performSyncCycle();
    CHECK(engineA.pendingConflicts().empty());
    CHECK(h.decodeRemoteDay("2026-08-01").items.front().body == "v2");
}

static void testKeepBothUnion() {
    Harness h;
    JournalItem shared = itemBody("shared");
    auto a = h.makeSource();
    JournalEntry base;
    base.id = entryIDForDay("2026-08-01");
    base.date = dateFromDayKey("2026-08-01");
    base.items = {shared};
    base.createdAt = t0();
    base.updatedAt = t0();
    a.days["2026-08-01"] = base;
    auto engineA = h.makeEngine(a, "a", "A");
    engineA.performSyncCycle();
    auto b = h.makeSource();
    auto engineB = h.makeEngine(b, "b", "B");
    engineB.performSyncCycle();
    JournalItem itemY = itemBody("from A");
    JournalItem itemZ = itemBody("from B");
    a.days["2026-08-01"].items.push_back(itemY);
    a.days["2026-08-01"].updatedAt = t0() + std::chrono::seconds(100);
    b.days["2026-08-01"].items.push_back(itemZ);
    b.days["2026-08-01"].updatedAt = t0() + std::chrono::seconds(200);
    engineA.performSyncCycle();
    engineB.performSyncCycle();
    engineA.performSyncCycle();
    std::set<std::string> bodiesA, bodiesB, bodiesR;
    for (const auto& it : a.days["2026-08-01"].items) bodiesA.insert(it.body);
    for (const auto& it : b.days["2026-08-01"].items) bodiesB.insert(it.body);
    for (const auto& it : h.decodeRemoteDay("2026-08-01").items) bodiesR.insert(it.body);
    CHECK(bodiesA.count("shared") && bodiesA.count("from A") && bodiesA.count("from B"));
    CHECK(bodiesB == bodiesA);
    CHECK(bodiesR == bodiesA);
    CHECK(engineB.pendingConflicts().empty());
}

static void testSameItemConflictKeepNewer() {
    Harness h;
    Uuid itemID = Uuid::generate();
    auto a = h.makeSource();
    JournalEntry e;
    e.id = entryIDForDay("2026-08-01");
    e.date = dateFromDayKey("2026-08-01");
    JournalItem orig; orig.id = itemID; orig.body = "original";
    e.items = {orig};
    e.createdAt = t0();
    e.updatedAt = t0();
    a.days["2026-08-01"] = e;
    auto engineA = h.makeEngine(a, "a", "A");
    engineA.performSyncCycle();
    auto b = h.makeSource();
    auto engineB = h.makeEngine(b, "b", "B");
    engineB.performSyncCycle();
    a.days["2026-08-01"].items[0].body = "A edit";
    a.days["2026-08-01"].updatedAt = t0() + std::chrono::seconds(200);
    b.days["2026-08-01"].items[0].body = "B edit";
    b.days["2026-08-01"].updatedAt = t0() + std::chrono::seconds(100);
    engineA.performSyncCycle();
    engineB.performSyncCycle();
    CHECK(b.days["2026-08-01"].items.front().body == "A edit");
    CHECK(engineB.pendingConflicts().size() == 1);
    const auto& conflictPath = engineB.pendingConflicts().front().remotePath;
    auto payloadData = h.backend.fileData(conflictPath);
    CHECK(payloadData.has_value());
    auto payload = decodeConflictPayload(*payloadData);
    CHECK(!payload.losingItems.empty() && payload.losingItems.front().body == "B edit");
}

static void testDeletePropagatesViaTombstone() {
    Harness h;
    auto a = h.makeSource();
    a.days["2026-08-01"] = h.entry("2026-08-01", "doomed");
    auto engineA = h.makeEngine(a, "a", "A");
    engineA.performSyncCycle();
    auto b = h.makeSource();
    auto engineB = h.makeEngine(b, "b", "B");
    engineB.performSyncCycle();
    CHECK(b.days.count("2026-08-01"));
    a.days.erase("2026-08-01");
    engineA.performSyncCycle();
    CHECK(!h.backend.hasFile(h.dayPath("2026-08-01")));
    CHECK(h.backend.hasFile(JournalSyncLayout::entryTombstonePath(h.journalID, entryIDForDay("2026-08-01"))));
    engineB.performSyncCycle();
    CHECK(b.days.count("2026-08-01") == 0);
    CHECK(b.removedDayKeys.size() == 1 && b.removedDayKeys[0] == "2026-08-01");
}

static void testAcknowledgedTombstoneDeletesResurrectedDay() {
    Harness h;
    auto source = h.makeSource();
    source.days["2026-08-01"] = h.entry("2026-08-01", "original");
    auto engine = h.makeEngine(source, "a", "A");
    engine.performSyncCycle();
    source.days.erase("2026-08-01");
    engine.performSyncCycle();
    const auto tombPath = JournalSyncLayout::entryTombstonePath(h.journalID, entryIDForDay("2026-08-01"));
    CHECK(h.backend.hasFile(tombPath));
    auto stale = h.entry("2026-08-01", "stale client copy", t0() + std::chrono::seconds(100));
    h.backend.seedFile(h.dayPath("2026-08-01"), JournalSyncEncoding::canonicalData(stale));
    engine.performSyncCycle();
    CHECK(source.days.count("2026-08-01") == 0);
    CHECK(!h.backend.hasFile(h.dayPath("2026-08-01")));
    CHECK(h.backend.hasFile(tombPath));
}

static void testJournalDeletionPropagation() {
    Harness h;
    Uuid doomedID = Uuid::generate();
    FakeLocalSource a(doomedID, "Doomed");
    a.days["2026-08-01"] = h.entry("2026-08-01", "legacy");
    a.days["2026-08-01"].id = entryIDForDay("2026-08-01");
    auto engineA = h.makeEngine(a, "a", "A");
    // engine uses source.journalID which is doomedID, but harness.journalID is different.
    // Override: the engine syncs a.journalID.
    engineA.performSyncCycle();
    CHECK(h.backend.hasFile(JournalSyncLayout::manifestPath(doomedID)));
    a.journalID = h.journalID;
    a.days.clear();
    engineA.queueJournalDeletion(doomedID);
    engineA.performSyncCycle();
    CHECK(!h.backend.hasFile(JournalSyncLayout::manifestPath(doomedID)));
    CHECK(!h.backend.hasFile(JournalSyncLayout::entryPath(doomedID, entryIDForDay("2026-08-01"))));
    CHECK(h.backend.hasFile(JournalSyncLayout::journalTombstonePath(doomedID)));
}

static void testPeerAppliesRemoteJournalTombstone() {
    Harness h;
    Uuid doomedID = Uuid::generate();
    FakeLocalSource a(doomedID, "Doomed");
    a.days["2026-08-01"] = h.entry("2026-08-01", "legacy");
    h.makeEngine(a, "a", "A").performSyncCycle();
    auto b = h.makeSource();
    auto engineB = h.makeEngine(b, "b", "B");
    engineB.performSyncCycle();
    CHECK(engineB.discoveredJournals().size() == 1);
    CHECK(engineB.discoveredJournals().front().journalID == doomedID);
    a.journalID = h.journalID;
    a.days.clear();
    auto engineA = h.makeEngine(a, "a", "A");
    engineA.queueJournalDeletion(doomedID);
    engineA.performSyncCycle();
    engineB.performSyncCycle();
    CHECK(engineB.remoteJournalDeletions().size() == 1);
    CHECK(engineB.remoteJournalDeletions().front() == doomedID);
    engineB.acknowledgeRemoteJournalDeletion(doomedID);
    engineB.performSyncCycle();
    CHECK(engineB.discoveredJournals().empty());
}

static void testRenamePushesToOtherDevice() {
    Harness h;
    auto a = h.makeSource();
    auto engineA = h.makeEngine(a, "a", "A");
    engineA.performSyncCycle();
    auto b = h.makeSource();
    auto engineB = h.makeEngine(b, "b", "B");
    engineB.performSyncCycle();
    a.journalName = "Work Log";
    engineA.performSyncCycle();
    CHECK(h.decodeRemoteManifest().journalName == "Work Log");
    engineB.performSyncCycle();
    CHECK(b.journalName == "Work Log");
}

static void testRenameSyncConvergesWithoutEchoes() {
    Harness h;
    auto a = h.makeSource();
    auto engineA = h.makeEngine(a, "a", "A");
    engineA.performSyncCycle();
    auto b = h.makeSource();
    auto engineB = h.makeEngine(b, "b", "B");
    engineB.performSyncCycle();
    a.journalName = "Renamed";
    engineA.performSyncCycle();
    engineB.performSyncCycle();
    CHECK(b.journalName == "Renamed");
    const int uploads = h.backend.uploadCount;
    engineB.performSyncCycle();
    engineA.performSyncCycle();
    CHECK(h.backend.uploadCount == uploads);
}

static void testDoubleRenameLastPushWins() {
    Harness h;
    auto a = h.makeSource();
    auto engineA = h.makeEngine(a, "a", "A");
    engineA.performSyncCycle();
    auto b = h.makeSource();
    auto engineB = h.makeEngine(b, "b", "B");
    engineB.performSyncCycle();
    a.journalName = "A Name";
    b.journalName = "B Name";
    engineA.performSyncCycle();
    engineB.performSyncCycle();
    CHECK(b.journalName == "B Name");
    engineA.performSyncCycle();
    CHECK(a.journalName == "B Name");
}

static void testFreshImportAdoptsRemoteJournalName() {
    Harness h;
    auto a = h.makeSource();
    h.makeEngine(a, "a", "A").performSyncCycle();
    auto b = h.makeSource("Local Placeholder");
    auto engineB = h.makeEngine(b, "b", "B");
    engineB.performSyncCycle();
    CHECK(b.journalName == "Test Journal");
    const int uploads = h.backend.uploadCount;
    engineB.performSyncCycle();
    CHECK(h.backend.uploadCount == uploads);
}

static void testStatePersistsAcrossEngineInstances() {
    Harness h;
    auto source = h.makeSource();
    source.days["2026-08-01"] = h.entry("2026-08-01", "one");
    h.makeEngine(source, "shared", "A").performSyncCycle();
    const int uploads = h.backend.uploadCount;
    auto resumed = h.makeEngine(source, "shared", "A");
    resumed.performSyncCycle();
    CHECK(h.backend.uploadCount == uploads);
    CHECK(resumed.status() == JournalSyncEngine::Status::idle);
}

static void testExpiredCursorResetsAndRecovers() {
    Harness h;
    auto source = h.makeSource();
    source.days["2026-08-01"] = h.entry("2026-08-01", "one");
    auto engine = h.makeEngine(source, "a", "A");
    engine.performSyncCycle();
    h.backend.failNextIncremental = SyncBackendError::cursorExpired();
    engine.performSyncCycle();
    CHECK(engine.status() != JournalSyncEngine::Status::needsAuth);
    engine.performSyncCycle();
    CHECK(engine.status() == JournalSyncEngine::Status::idle);
    CHECK(h.backend.hasFile(h.dayPath("2026-08-01")));
}

static void testPathLayoutCopiedFromMac() {
    Uuid id = Uuid::parse("01234567-89AB-CDEF-0123-456789ABCDEF").value();
    CHECK(JournalSyncLayout::journalRoot(id) == "/journals/01234567-89ab-cdef-0123-456789abcdef");
    CHECK(JournalSyncLayout::manifestPath(id) == "/journals/01234567-89ab-cdef-0123-456789abcdef/manifest.json");
    Uuid e = Uuid::parse("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE").value();
    CHECK(JournalSyncLayout::entryPath(id, e)
          == "/journals/01234567-89ab-cdef-0123-456789abcdef/entries/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.json");
    CHECK(JournalSyncLayout::entryTombstonePath(id, e)
          == "/journals/01234567-89ab-cdef-0123-456789abcdef/entry-tombstones/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.json");
    CHECK(JournalSyncLayout::journalTombstonePath(id)
          == "/journal-tombstones-v2/01234567-89ab-cdef-0123-456789abcdef.json");
    CHECK(id.toString() == "01234567-89AB-CDEF-0123-456789ABCDEF");
}

static void testTradingSnapshotUploadsAndDownloadsBetweenPeers() {
    Harness h;
    auto a = h.makeSource();
    JournalTradingSnapshotDocument doc;
    doc.journalID = h.journalID;
    doc.venue = "binance";
    doc.accountLabel = "MockAccount";
    doc.fetchedAtMilliseconds = 1725000000000;
    doc.payload = "{\"positions\":[{\"symbol\":\"BTCUSDT\",\"side\":\"long\"}]}";
    a.tradingSnapshot = doc;

    auto engineA = h.makeEngine(a, "a", "A");
    engineA.performSyncCycle();

    const auto snapPath = JournalSyncLayout::tradingSnapshotPath(h.journalID);
    CHECK(h.backend.hasFile(snapPath));

    auto b = h.makeSource();
    auto engineB = h.makeEngine(b, "b", "B");
    engineB.performSyncCycle();

    CHECK(b.tradingSnapshot.has_value());
    CHECK(b.tradingSnapshot->journalID == h.journalID);
    CHECK(b.tradingSnapshot->venue == "binance");
    CHECK(b.tradingSnapshot->payload == doc.payload);
}

int main() {
    testMerge();
    testFakeBackend();
    testPathLayoutCopiedFromMac();
    testFirstSyncUploadsManifestAndDays();
    testSecondCycleIsNoOp();
    testNeedsAuthWhenNotAuthorized();
    testReadOnlySourceNeverPushes();
    testSecondDevicePullsDays();
    testEchoSuppression();
    testPullFixedPoint();
    testNeverConflictWithSelf();
    testKeepBothUnion();
    testSameItemConflictKeepNewer();
    testDeletePropagatesViaTombstone();
    testAcknowledgedTombstoneDeletesResurrectedDay();
    testJournalDeletionPropagation();
    testPeerAppliesRemoteJournalTombstone();
    testRenamePushesToOtherDevice();
    testRenameSyncConvergesWithoutEchoes();
    testDoubleRenameLastPushWins();
    testFreshImportAdoptsRemoteJournalName();
    testStatePersistsAcrossEngineInstances();
    testExpiredCursorResetsAndRecovers();
    testTradingSnapshotUploadsAndDownloadsBetweenPeers();

    std::cerr << "passed " << g_passes << "  failed " << g_fails << "\n";
    return g_fails ? 1 : 0;
}
