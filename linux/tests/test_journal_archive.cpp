#include "JournalArchive.h"
#include "JournalModels.h"
#include "JournalStore.h"
#include "JournalSyncEncoding.h"

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
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

static void testAttachRejectsPathTraversal() {
    auto root = makeTempDir("WickAttachTrav-");
    JournalFileStore store(root);
    store.ensureDirectories();
    auto entry = makeDeterministicEntry();
    entry.items.front().imageFilenames.clear();
    store.entries = {entry};
    store.persist();

    CHECK(!store.imageURL("../escape.png"));
    CHECK(!store.imageURL("..\\escape.png"));
    CHECK(!store.imageURL("/etc/passwd"));
    CHECK(!store.imageURL("a/b.png"));

    auto src = root / "src";
    std::filesystem::create_directories(src);
    writeText(src / "photo.png", "PNG-BYTES");
    auto name = store.addImageFromFile(entry.id, entry.items.front().id, src / "photo.png");
    CHECK(name.has_value());
    CHECK(JournalImageFilename::isValid(*name));
    CHECK(name->find("..") == std::string::npos);
    CHECK(name->size() > 36 && (*name)[36] == '.');
    CHECK(Uuid::parse(name->substr(0, 36)).has_value());
    CHECK(store.imageURL(*name).has_value());
    CHECK(readText(*store.imageURL(*name)) == "PNG-BYTES");
    CHECK(!std::filesystem::exists(root / "escape.png"));

    auto name2 = store.addImage(entry.id, entry.items.front().id, "GIF-BYTES", "../escape.png");
    CHECK(name2.has_value());
    CHECK(*name2 != "../escape.png");
    CHECK(JournalImageFilename::isValid(*name2));
    CHECK(name2->ends_with(".png"));

    std::filesystem::remove_all(root);
}

static void testZipRoundTripSnapshotWithOneImage() {
    auto root = makeTempDir("WickZipRt-");
    JournalFileStore store(root);
    store.ensureDirectories();
    auto entry = makeDeterministicEntry();
    store.entries = {entry};
    writeText(store.imagesDirectory() / "a.png", "PNG-ONE");
    store.persist();

    const auto zip = root / "export.zip";
    auto err = store.exportArchive(zip);
    CHECK(!err.has_value());
    CHECK(std::filesystem::exists(zip));

    auto unpacked = makeTempDir("WickZipUnpack-");
    auto unzipErr = extractZipFile(zip, unpacked);
    CHECK(!unzipErr.has_value());
    auto found = findJournalJSON(unpacked);
    CHECK(found.has_value());
    CHECK(found->parent_path().filename() == kExportPayloadDirectory);
    CHECK(std::filesystem::exists(found->parent_path() / "images" / "a.png"));
    CHECK(readText(found->parent_path() / "images" / "a.png") == "PNG-ONE");

    auto dest = makeTempDir("WickZipImport-");
    JournalFileStore imported(dest);
    imported.ensureDirectories();
    writeText(imported.databaseURL(), "SHOULD-BE-REPLACED");
    writeText(imported.imagesDirectory() / "old.png", "OLD");
    auto impErr = imported.importArchive(zip);
    CHECK(!impErr.has_value());
    CHECK(imported.entries.size() == 1);
    CHECK(imported.entries.front().id == entry.id);
    CHECK(!imported.entries.front().items.empty());
    CHECK(imported.entries.front().items.front().imageFilenames == std::vector<std::string>{"a.png"});
    CHECK(readText(imported.imagesDirectory() / "a.png") == "PNG-ONE");
    CHECK(!std::filesystem::exists(imported.imagesDirectory() / "old.png"));
    CHECK(readText(imported.databaseURL()).find("Deterministic") != std::string::npos);

    std::filesystem::remove_all(root);
    std::filesystem::remove_all(unpacked);
    std::filesystem::remove_all(dest);
}

static void testCorruptZipAndMissingJsonDoNotClobber() {
    auto root = makeTempDir("WickZipFail-");
    JournalFileStore store(root);
    store.ensureDirectories();
    auto entry = makeDeterministicEntry();
    store.entries = {entry};
    writeText(store.imagesDirectory() / "a.png", "KEEP-ME");
    store.persist();
    const auto originalJson = readText(store.databaseURL());
    const auto originalImage = readText(store.imagesDirectory() / "a.png");

    writeText(root / "corrupt.zip", "this is not a zip");
    auto corruptErr = store.importArchive(root / "corrupt.zip");
    CHECK(corruptErr.has_value());
    CHECK(readText(store.databaseURL()) == originalJson);
    CHECK(readText(store.imagesDirectory() / "a.png") == originalImage);
    CHECK(!store.isReadOnlyDueToLoadFailure);

    std::vector<ZipEntry> emptyPayload;
    emptyPayload.push_back(ZipEntry{"Wick-Journal/readme.txt", "no journal here"});
    const auto missing = root / "missing.json.zip";
    auto zipErr = writeZipFile(missing, emptyPayload);
    CHECK(!zipErr.has_value());
    auto missingErr = store.importArchive(missing);
    CHECK(missingErr.has_value());
    CHECK(*missingErr == "importMissingJournalJSON");
    CHECK(readText(store.databaseURL()) == originalJson);
    CHECK(readText(store.imagesDirectory() / "a.png") == originalImage);

    const std::string badJson =
        "{\"version\":2,\"entries\":[{\"id\":\"" + entry.id.toString()
        + "\",\"date\":\"2026-01-15T00:00:00Z\",\"title\":\"t\","
          "\"items\":[{\"id\":\"" + entry.items.front().id.toString()
        + "\",\"tag\":\"\",\"body\":\"b\",\"imageFilenames\":[\"../escape.png\"]}],"
          "\"createdAt\":\"2026-01-15T00:00:00Z\",\"updatedAt\":\"2026-01-15T00:00:00Z\"}]}";
    std::vector<ZipEntry> unsafePayload{
        ZipEntry{"Wick-Journal/journal.json", badJson},
        ZipEntry{"Wick-Journal/images/a.png", "X"},
    };
    const auto unsafeZip = root / "unsafe.zip";
    CHECK(!writeZipFile(unsafeZip, unsafePayload).has_value());
    auto unsafeErr = store.importArchive(unsafeZip);
    CHECK(unsafeErr.has_value());
    CHECK(readText(store.databaseURL()) == originalJson);
    CHECK(readText(store.imagesDirectory() / "a.png") == originalImage);

    store.isReadOnlyDueToLoadFailure = true;
    auto exportErr = store.exportArchive(root / "blocked.zip");
    CHECK(exportErr.has_value());
    CHECK(!std::filesystem::exists(root / "blocked.zip"));

    std::filesystem::remove_all(root);
}

int main() {
    testAttachRejectsPathTraversal();
    testZipRoundTripSnapshotWithOneImage();
    testCorruptZipAndMissingJsonDoNotClobber();

    std::cout << g_passes << " passed, " << g_fails << " failed\n";
    return g_fails == 0 ? 0 : 1;
}
