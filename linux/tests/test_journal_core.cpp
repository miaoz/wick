#include "JournalCatalog.h"
#include "JournalModels.h"
#include "JournalPaths.h"
#include "JournalStore.h"
#include "JournalSyncEncoding.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>
#include <unistd.h>
#include <variant>

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
    if (!mkdtemp(buf.data())) {
        throw std::runtime_error("mkdtemp failed");
    }
    return std::filesystem::path(buf.data());
}

static void writeText(const std::filesystem::path& p, std::string_view s) {
    std::filesystem::create_directories(p.parent_path());
    std::ofstream out(p, std::ios::binary | std::ios::trunc);
    out.write(s.data(), static_cast<std::streamsize>(s.size()));
}

static std::string readText(const std::filesystem::path& p) {
    auto b = readFileBytes(p);
    return b ? *b : std::string();
}

static Uuid mustUuid(const char* s) {
    auto u = Uuid::parse(s);
    if (!u) throw std::runtime_error("bad uuid fixture");
    return *u;
}

static std::string journalInfoJSON() {
    return std::string("{\"id\":\"") + Uuid::generate().toString()
        + "\",\"name\":\"Diary\",\"createdAt\":\"2026-01-01T00:00:00Z\","
          "\"updatedAt\":\"2026-01-01T00:00:00Z\"}";
}

static std::string validCatalogJSON() {
    return std::string("{\"version\":1,\"activeJournalID\":\"") + Uuid::generate().toString()
        + "\",\"journals\":[" + journalInfoJSON() + "]}";
}

static JournalEntry makeDeterministicEntry() {
    JournalReview review;
    review.verdict = JournalReviewVerdict::correct;
    review.note = "n";
    review.createdAt = timeFromUnix(1'700'000'000);
    review.updatedAt = timeFromUnix(1'700'000'000);

    JournalItem item;
    item.id = mustUuid("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");
    item.tag = "BTC";
    item.body = "line1\nline2";
    item.imageFilenames = {"a.png"};
    item.review = review;

    JournalEntry entry;
    entry.id = mustUuid("11111111-2222-3333-4444-555555555555");
    entry.date = timeFromUnix(1'754'000'000);
    entry.title = "Deterministic";
    entry.items = {item};
    entry.createdAt = timeFromUnix(1'754'000'000);
    entry.updatedAt = timeFromUnix(1'754'100'000);
    return entry;
}

static void testImageFilenameAcceptsSafeNames() {
    const std::vector<std::string> safe = {
        Uuid::generate().toString() + ".png",
        Uuid::generate().toString() + ".JPG",
        Uuid::generate().toString() + ".PNG",
        "a b.png",
        "photo 1.heic",
        "image-2026.png",
        "01234567-89AB-CDEF-0123-456789ABCDEF.jpg",
    };
    for (const auto& name : safe) {
        CHECK(JournalImageFilename::isValid(name));
    }
}

static void testImageFilenameRejectsUnsafeNames() {
    const std::vector<std::string> unsafe = {
        "../x",
        "../../catalog.json",
        "a/b.png",
        "a\\b.png",
        ".",
        "..",
        "",
        std::string("x\0.png", 6),
        "..\\x",
        "/etc/passwd",
        "images/../escape.png",
    };
    for (const auto& name : unsafe) {
        CHECK(!JournalImageFilename::isValid(name));
    }
}

static void testDecodeRejectsUnsafeImageReference() {
    const std::string json =
        "{\"id\":\"" + Uuid::generate().toString()
        + "\",\"date\":\"2026-01-15T00:00:00Z\",\"title\":\"t\","
          "\"items\":[{\"id\":\""
        + Uuid::generate().toString()
        + "\",\"tag\":\"\",\"body\":\"b\",\"imageFilenames\":[\"../escape.png\"]}],"
          "\"createdAt\":\"2026-01-15T00:00:00Z\",\"updatedAt\":\"2026-01-15T00:00:00Z\"}";
    bool threw = false;
    try {
        (void)JournalSyncEncoding::decodeEntry(json);
    } catch (const JournalImageFilename::InvalidReference& e) {
        threw = true;
        CHECK(e.filename == "../escape.png");
    } catch (...) {
        threw = true;
        std::cerr << "FAIL: ../escape.png threw wrong type\n";
        ++g_fails;
    }
    CHECK(threw);
}

static void testDecodeAcceptsSafeImageReference() {
    const std::string json =
        "{\"id\":\"" + Uuid::generate().toString()
        + "\",\"date\":\"2026-01-15T00:00:00Z\",\"title\":\"t\","
          "\"items\":[{\"id\":\""
        + Uuid::generate().toString()
        + "\",\"tag\":\"\",\"body\":\"b\",\"imageFilenames\":[\"abc 1.png\"]}],"
          "\"createdAt\":\"2026-01-15T00:00:00Z\",\"updatedAt\":\"2026-01-15T00:00:00Z\"}";
    const auto entry = JournalSyncEncoding::decodeEntry(json);
    CHECK(!entry.items.empty());
    CHECK(entry.items.front().imageFilenames == std::vector<std::string>{"abc 1.png"});
}

static void testLegacyDayKeyIsIgnoredAndNotReencoded() {
    const std::string json =
        "{\"id\":\"" + Uuid::generate().toString()
        + "\",\"date\":\"2026-01-15T12:00:00Z\",\"dayKey\":\"2099-12-31\",\"title\":\"Legacy\","
          "\"items\":[{\"id\":\""
        + Uuid::generate().toString()
        + "\",\"tag\":\"\",\"body\":\"b\",\"imageFilenames\":[]}],"
          "\"createdAt\":\"2026-01-15T12:00:00Z\",\"updatedAt\":\"2026-01-15T12:00:00Z\"}";
    const auto decoded = JournalSyncEncoding::decodeEntry(json);
    const auto reencoded = JournalSyncEncoding::encode(decoded);
    CHECK(reencoded.find("dayKey") == std::string::npos);
    CHECK(decoded.title == "Legacy");
}

static void testDayKeyFormatIsGregorianLocalDate() {
    const auto epoch = timeFromUnix(0);
    CHECK(JournalDayKey::make(epoch, 0) == "1970-01-01");
    const auto evening = timeFromUnix(60'000);
    CHECK(JournalDayKey::make(evening, 0) == "1970-01-01");
    CHECK(JournalDayKey::make(evening, 14 * 3600) == "1970-01-02");
}

static void testCatalogLoaderMatrix() {
    auto root = makeTempDir("WickCatalogLoader-");
    auto primary = root / "catalog.json";
    auto backup = root / "catalog.json.bak";
    auto load = [&](bool hasP, bool hasB) {
        return JournalCatalogLoader::load(
            hasP ? primary : std::filesystem::path("/nonexistent-primary"),
            hasB ? backup : std::filesystem::path("/nonexistent-backup"),
            1);
    };

    auto r = load(false, false);
    CHECK(std::holds_alternative<JournalCatalogLoader::Missing>(r));

    writeText(backup, validCatalogJSON());
    r = load(false, true);
    CHECK(std::holds_alternative<JournalCatalogLoader::RestoredFromBackup>(r));

    writeText(backup, "{");
    r = load(false, true);
    CHECK(std::holds_alternative<JournalCatalogLoader::Corrupt>(r));

    writeText(backup, std::string("{\"version\":99,\"activeJournalID\":\"")
                          + Uuid::generate().toString() + "\",\"journals\":[]}");
    r = load(false, true);
    CHECK(std::holds_alternative<JournalCatalogLoader::UnsupportedVersion>(r));
    if (auto* u = std::get_if<JournalCatalogLoader::UnsupportedVersion>(&r)) {
        CHECK(u->version == 99);
    }

    writeText(primary, validCatalogJSON());
    r = load(true, true);
    CHECK(std::holds_alternative<JournalCatalogLoader::Loaded>(r));

    writeText(primary, "{");
    writeText(backup, validCatalogJSON());
    r = load(true, true);
    CHECK(std::holds_alternative<JournalCatalogLoader::RestoredFromBackup>(r));

    writeText(primary, "{");
    writeText(backup, "{");
    r = load(true, true);
    CHECK(std::holds_alternative<JournalCatalogLoader::Corrupt>(r));

    writeText(primary, std::string("{\"version\":99,\"activeJournalID\":\"")
                           + Uuid::generate().toString() + "\",\"journals\":[]}");
    writeText(backup, validCatalogJSON());
    r = load(true, true);
    CHECK(std::holds_alternative<JournalCatalogLoader::UnsupportedVersion>(r));
    if (auto* u = std::get_if<JournalCatalogLoader::UnsupportedVersion>(&r)) {
        CHECK(u->version == 99);
    }

    std::filesystem::remove_all(root);
}

static void testEmptyCatalogJournalsIsCorrupt() {
    auto root = makeTempDir("WickCatalogEmpty-");
    auto primary = root / "catalog.json";
    auto backup = root / "catalog.json.bak";
    writeText(primary, std::string("{\"version\":1,\"activeJournalID\":\"")
                           + Uuid::generate().toString() + "\",\"journals\":[]}");
    auto r = JournalCatalogLoader::load(primary, backup, 1);
    CHECK(std::holds_alternative<JournalCatalogLoader::Corrupt>(r));
    std::filesystem::remove_all(root);
}

static void testCanonicalEncodingIsDeterministicAcrossRoundTrip() {
    const auto entry = makeDeterministicEntry();
    const auto first = JournalSyncEncoding::canonicalData(entry);
    const auto second = JournalSyncEncoding::canonicalData(entry);
    CHECK(first == second);

    const auto decoded = JournalSyncEncoding::decodeEntry(first);
    const auto reencoded = JournalSyncEncoding::canonicalData(decoded);
    CHECK(first == reencoded);

    // Swift pretty-print contract.
    CHECK(first.find("\" : ") != std::string::npos);
    CHECK(first.find("dayKey") == std::string::npos);
    CHECK(first.find("\"review\"") != std::string::npos);
    // Optional omitted when nil: encode a clone without review.
    auto noReview = entry;
    noReview.items[0].review.reset();
    const auto bare = JournalSyncEncoding::encode(noReview);
    CHECK(bare.find("\"review\"") == std::string::npos);

    // Colon spacing is space-before-colon, not Qt's `"key":`.
    CHECK(first.find("\"title\" : ") != std::string::npos);

    // Swift Foundation UUID.uuidString is uppercase dashed; decoder accepts both.
    CHECK(first.find("11111111-2222-3333-4444-555555555555") != std::string::npos);
    CHECK(first.find("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") != std::string::npos);
    CHECK(first.find("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee") == std::string::npos);
}


static void testEncodeDoesNotEscapeSlashes() {
    JournalEntry e;
    e.id = mustUuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    e.date = timeFromUnix(0);
    e.title = "";
    e.createdAt = timeFromUnix(0);
    e.updatedAt = timeFromUnix(0);
    JournalItem item;
    item.id = mustUuid("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    item.body = "https://example.com/a";
    e.items = {item};
    const auto json = JournalSyncEncoding::encode(e);
    CHECK(json.find("https://example.com/a") != std::string::npos);
    CHECK(json.find("https:\\/\\/example.com\\/a") == std::string::npos);
}

static void testContentHashMatchesSHA256KnownVector() {
    CHECK(JournalSyncEncoding::contentHash(std::string_view{})
          == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
}

static void testPrettyPrintWhitespace() {
    JournalEntry e;
    e.id = mustUuid("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    e.date = timeFromUnix(0);
    e.title = "";
    e.createdAt = timeFromUnix(0);
    e.updatedAt = timeFromUnix(0);
    JournalItem item;
    item.id = mustUuid("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    e.items = {item};
    const auto json = JournalSyncEncoding::encode(e);
    CHECK(json.find("\"imageFilenames\" : [\n") != std::string::npos);
    // Nested empty array: "[\n\n" + parent-indent + "]" (Swift JSONWriter).
    CHECK(json.find("\"imageFilenames\" : [\n\n      ]") != std::string::npos);
}

static JournalEntry sampleLoadedEntry(const char* id, std::int64_t date) {
    JournalEntry e;
    e.id = mustUuid(id);
    e.date = timeFromUnix(date);
    e.title = "t";
    e.createdAt = timeFromUnix(date);
    e.updatedAt = timeFromUnix(date);
    JournalItem item;
    item.id = mustUuid("cccccccc-cccc-cccc-cccc-cccccccccccc");
    item.body = "hello";
    e.items = {item};
    return e;
}

static void testTruncatedPrimaryValidBakRestores() {
    auto root = makeTempDir("WickJournalRestore-");
    JournalFileStore store(root);
    store.ensureDirectories();

    JournalSnapshot snap;
    snap.version = 2;
    snap.entries = {sampleLoadedEntry("dddddddd-dddd-dddd-dddd-dddddddddddd", 1'700'000'000)};
    const auto good = JournalSyncEncoding::encode(snap);
    writeText(store.backupURL(), good);
    writeText(store.databaseURL(), "{");
    const auto bakBefore = readText(store.backupURL());

    store.load();
    CHECK(store.didRestoreFromBackup);
    CHECK(!store.isReadOnlyDueToLoadFailure);
    CHECK(store.entries.size() == 1);
    CHECK(store.entries[0].title == "t");
    // Bak must still be the good snapshot, not the truncated `{`.
    CHECK(readText(store.backupURL()) == bakBefore);
    // Primary rewritten from restored entries.
    CHECK(readText(store.databaseURL()).find("hello") != std::string::npos);
    // Corrupt primary quarantined.
    bool foundQuarantine = false;
    for (const auto& ent : std::filesystem::directory_iterator(root)) {
        if (ent.path().filename().string().rfind("journal.corrupt-", 0) == 0) {
            foundQuarantine = true;
            CHECK(readText(ent.path()) == "{");
        }
    }
    CHECK(foundQuarantine);
    std::filesystem::remove_all(root);
}

static void testTruncatedPrimaryNoBakSetsReadOnly() {
    auto root = makeTempDir("WickJournalRO-");
    JournalFileStore store(root);
    store.ensureDirectories();
    writeText(store.databaseURL(), "{");
    store.load();
    CHECK(store.isReadOnlyDueToLoadFailure);
    CHECK(!store.didRestoreFromBackup);
    CHECK(store.entries.empty());
    CHECK(readText(store.databaseURL()) == "{");
    CHECK(!std::filesystem::exists(store.backupURL()));
    store.entries.push_back(sampleLoadedEntry("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee", 1));
    store.persist(); // no-op
    CHECK(readText(store.databaseURL()) == "{");
    CHECK(!std::filesystem::exists(store.backupURL()));
    std::filesystem::remove_all(root);
}

static void testUnsupportedVersionDoesNotConsultBak() {
    auto root = makeTempDir("WickJournalV3-");
    JournalFileStore store(root);
    store.ensureDirectories();
    JournalSnapshot good;
    good.version = 2;
    good.entries = {sampleLoadedEntry("ffffffff-ffff-ffff-ffff-ffffffffffff", 1'700'000'000)};
    writeText(store.backupURL(), JournalSyncEncoding::encode(good));
    writeText(store.databaseURL(),
              "{\n  \"entries\" : [\n\n  ],\n  \"version\" : 3\n}");
    const auto bakBefore = readText(store.backupURL());
    const auto primaryBefore = readText(store.databaseURL());
    store.load();
    CHECK(store.isReadOnlyDueToLoadFailure);
    CHECK(store.entries.empty());
    CHECK(!store.didRestoreFromBackup);
    CHECK(readText(store.backupURL()) == bakBefore);
    CHECK(readText(store.databaseURL()) == primaryBefore);
    store.persist();
    CHECK(readText(store.databaseURL()) == primaryBefore);
    std::filesystem::remove_all(root);
}

static void testMissingPrimaryValidBakRestoresAndRewrites() {
    auto root = makeTempDir("WickJournalMissingP-");
    JournalFileStore store(root);
    store.ensureDirectories();
    JournalSnapshot good;
    good.version = 2;
    good.entries = {sampleLoadedEntry("aaaaaaaa-0000-0000-0000-000000000001", 50)};
    writeText(store.backupURL(), JournalSyncEncoding::encode(good));
    store.load();
    CHECK(store.didRestoreFromBackup);
    CHECK(!store.isReadOnlyDueToLoadFailure);
    CHECK(store.entries.size() == 1);
    CHECK(std::filesystem::exists(store.databaseURL()));
    CHECK(readText(store.databaseURL()).find("hello") != std::string::npos);
    std::filesystem::remove_all(root);
}

static void testMissingPrimaryNoBakIsWritableEmpty() {
    auto root = makeTempDir("WickJournalFresh-");
    JournalFileStore store(root);
    store.load();
    CHECK(!store.isReadOnlyDueToLoadFailure);
    CHECK(store.entries.empty());
    store.entries.push_back(sampleLoadedEntry("aaaaaaaa-0000-0000-0000-000000000002", 1));
    store.persist();
    CHECK(std::filesystem::exists(store.databaseURL()));
    CHECK(readText(store.databaseURL()).find("hello") != std::string::npos);
    std::filesystem::remove_all(root);
}

static void testPersistCopiesBakBeforeOverwrite() {
    auto root = makeTempDir("WickJournalBak-");
    JournalFileStore store(root);
    store.entries.push_back(sampleLoadedEntry("aaaaaaaa-0000-0000-0000-000000000003", 10));
    store.persist();
    const auto first = readText(store.databaseURL());
    store.entries[0].title = "changed";
    store.persist();
    CHECK(readText(store.backupURL()) == first);
    CHECK(readText(store.databaseURL()).find("changed") != std::string::npos);
    std::filesystem::remove_all(root);
}

static void testUnsafeImageInSnapshotIsCorrupt() {
    auto root = makeTempDir("WickJournalUnsafe-");
    JournalFileStore store(root);
    store.ensureDirectories();
    const std::string bad =
        "{\"version\":2,\"entries\":[{\"id\":\"" + Uuid::generate().toString()
        + "\",\"date\":\"2026-01-15T00:00:00Z\",\"title\":\"t\","
          "\"items\":[{\"id\":\""
        + Uuid::generate().toString()
        + "\",\"tag\":\"\",\"body\":\"b\",\"imageFilenames\":[\"../escape.png\"]}],"
          "\"createdAt\":\"2026-01-15T00:00:00Z\",\"updatedAt\":\"2026-01-15T00:00:00Z\"}]}";
    writeText(store.databaseURL(), bad);
    store.load();
    CHECK(store.isReadOnlyDueToLoadFailure);
    CHECK(store.entries.empty());
    CHECK(readText(store.databaseURL()) == bad);
    std::filesystem::remove_all(root);
}

static void testPathsLayout() {
    auto paths = JournalPaths::inRoot("/tmp/wick-test-root");
    auto id = mustUuid("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");
    CHECK(paths.catalogURL() == std::filesystem::path("/tmp/wick-test-root/catalog.json"));
    CHECK(paths.catalogBackupURL()
          == std::filesystem::path("/tmp/wick-test-root/catalog.json.bak"));
    CHECK(paths.journalJSON(id).filename() == "journal.json");
    CHECK(paths.journalBackup(id).filename() == "journal.json.bak");
    CHECK(paths.backupsDirectory(id).filename() == "backups");
    CHECK(paths.imagesDirectory(id).filename() == "images");
    CHECK(paths.journalDirectory(id).filename() == id.toString());
}

static void testOmitExchangeBinding() {
    JournalInfo info;
    info.id = Uuid::generate();
    info.name = "Diary";
    info.createdAt = timeFromUnix(0);
    info.updatedAt = timeFromUnix(0);
    const auto json = JournalSyncEncoding::encode(info);
    CHECK(json.find("exchangeBinding") == std::string::npos);
    info.exchangeBinding = JournalExchangeBinding{ExchangeVenue::okx, "OKX"};
    const auto json2 = JournalSyncEncoding::encode(info);
    CHECK(json2.find("\"venue\" : \"okx\"") != std::string::npos);
}


static void testMissingCatalogBootstrapCreatesDefaultDiary() {
    auto root = makeTempDir("WickBootstrap-");
    auto paths = JournalPaths::inRoot(root);
    auto outcome = JournalCatalogLoader::load(paths.catalogURL(), paths.catalogBackupURL(), 1);
    CHECK(std::holds_alternative<JournalCatalogLoader::Missing>(outcome));

    JournalInfo info;
    info.id = Uuid::generate();
    info.name = "日记";
    info.createdAt = timeFromUnix(1'700'000'000);
    info.updatedAt = info.createdAt;
    JournalCatalogSnapshot catalog;
    catalog.version = 1;
    catalog.activeJournalID = info.id;
    catalog.journals = {info};
    CHECK(persistCatalog(root, catalog));

    paths.ensureJournalDirectories(info.id);
    JournalFileStore store(paths.journalDirectory(info.id));
    store.ensureDirectories();
    store.entries.clear();
    store.persist();

    CHECK(std::filesystem::exists(paths.catalogURL()));
    CHECK(std::filesystem::exists(paths.journalJSON(info.id)));
    const auto folder = paths.journalDirectory(info.id).filename().string();
    CHECK(folder == info.id.toString());
    for (char c : folder) {
        if (c >= 'a' && c <= 'f') {
            std::cerr << "FAIL: uuid folder not uppercase: " << folder << "\n";
            ++g_fails;
            break;
        }
    }
    auto loaded = JournalCatalogLoader::load(paths.catalogURL(), paths.catalogBackupURL(), 1);
    CHECK(std::holds_alternative<JournalCatalogLoader::Loaded>(loaded));
    std::filesystem::remove_all(root);
}

static void testEntryCountOnDiskIsReadOnly() {
    auto root = makeTempDir("WickEntryCount-");
    auto dir = root / "journal";
    CHECK(JournalFileStore::entryCountOnDisk(dir) == 0);

    JournalFileStore store(dir);
    store.ensureDirectories();
    JournalEntry second = makeDeterministicEntry();
    second.id = Uuid::generate();
    store.entries = {makeDeterministicEntry(), second};
    store.persist();
    CHECK(JournalFileStore::entryCountOnDisk(dir) == 2);

    const auto primary = readText(dir / "journal.json");
    CHECK(!primary.empty());
    writeText(dir / "journal.json", "{not-json");
    writeText(dir / "journal.json.bak", primary);
    CHECK(JournalFileStore::entryCountOnDisk(dir) == 2);
    CHECK(readText(dir / "journal.json") == "{not-json");

    std::filesystem::remove_all(root);
}

static void testCorruptCatalogIsNotRewritten() {
    auto root = makeTempDir("WickBootstrapCorrupt-");
    auto paths = JournalPaths::inRoot(root);
    const std::string junk = "{not-json";
    writeText(paths.catalogURL(), junk);
    auto outcome = JournalCatalogLoader::load(paths.catalogURL(), paths.catalogBackupURL(), 1);
    CHECK(std::holds_alternative<JournalCatalogLoader::Corrupt>(outcome));
    CHECK(readText(paths.catalogURL()) == junk);
    CHECK(!std::filesystem::exists(paths.catalogBackupURL()));
    std::filesystem::remove_all(root);
}

static void testReorderJournalsPersists() {
    auto root = makeTempDir("WickReorder-");
    auto paths = JournalPaths::inRoot(root);

    JournalInfo a;
    a.id = Uuid::generate();
    a.name = "A";
    a.createdAt = timeFromUnix(1'700'000'000);
    a.updatedAt = a.createdAt;

    JournalInfo b;
    b.id = Uuid::generate();
    b.name = "B";
    b.createdAt = timeFromUnix(1'700'000'000);
    b.updatedAt = b.createdAt;

    JournalInfo c;
    c.id = Uuid::generate();
    c.name = "C";
    c.createdAt = timeFromUnix(1'700'000'000);
    c.updatedAt = c.createdAt;

    JournalCatalogSnapshot catalog;
    catalog.version = 1;
    catalog.activeJournalID = a.id;
    catalog.journals = {a, b, c};
    CHECK(persistCatalog(root, catalog));

    // Reorder: move C (index 2) to index 0 -> C, A, B
    auto moving = catalog.journals[2];
    catalog.journals.erase(catalog.journals.begin() + 2);
    catalog.journals.insert(catalog.journals.begin() + 0, moving);
    CHECK(persistCatalog(root, catalog));

    auto outcome = JournalCatalogLoader::load(paths.catalogURL(), paths.catalogBackupURL(), 1);
    CHECK(std::holds_alternative<JournalCatalogLoader::Loaded>(outcome));
    auto loaded = std::get<JournalCatalogLoader::Loaded>(outcome).catalog;
    CHECK(loaded.journals.size() == 3);
    CHECK(loaded.journals[0].name == "C");
    CHECK(loaded.journals[1].name == "A");
    CHECK(loaded.journals[2].name == "B");
    CHECK(loaded.activeJournalID == a.id);

    std::filesystem::remove_all(root);
}

int main() {
    testImageFilenameAcceptsSafeNames();
    testImageFilenameRejectsUnsafeNames();
    testDecodeRejectsUnsafeImageReference();
    testDecodeAcceptsSafeImageReference();
    testLegacyDayKeyIsIgnoredAndNotReencoded();
    testDayKeyFormatIsGregorianLocalDate();
    testCatalogLoaderMatrix();
    testEmptyCatalogJournalsIsCorrupt();
    testCanonicalEncodingIsDeterministicAcrossRoundTrip();
    testEncodeDoesNotEscapeSlashes();
    testContentHashMatchesSHA256KnownVector();
    testPrettyPrintWhitespace();
    testTruncatedPrimaryValidBakRestores();
    testTruncatedPrimaryNoBakSetsReadOnly();
    testUnsupportedVersionDoesNotConsultBak();
    testMissingPrimaryValidBakRestoresAndRewrites();
    testMissingPrimaryNoBakIsWritableEmpty();
    testPersistCopiesBakBeforeOverwrite();
    testUnsafeImageInSnapshotIsCorrupt();
    testPathsLayout();
    testOmitExchangeBinding();
    testMissingCatalogBootstrapCreatesDefaultDiary();
    testEntryCountOnDiskIsReadOnly();
    testCorruptCatalogIsNotRewritten();
    testReorderJournalsPersists();

    std::cout << g_passes << " passed, " << g_fails << " failed\n";
    return g_fails == 0 ? 0 : 1;
}
