#include "JournalSyncState.h"
#include "JournalSyncEncoding.h"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <ctime>
#include <fstream>

namespace wick {
using json = nlohmann::json;

std::string asciiLower(std::string s) {
    for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return s;
}

std::string JournalSyncLayout::formatUtcStamp(TimePoint tp) {
    const std::time_t t = std::chrono::system_clock::to_time_t(tp);
    std::tm tm{};
    gmtime_r(&t, &tm);
    char buf[32];
    std::strftime(buf, sizeof(buf), "%Y%m%d-%H%M%S", &tm);
    return buf;
}

std::string JournalSyncLayout::journalRoot(const Uuid& journalID) {
    return "/journals/" + journalID.toLowerString();
}
std::string JournalSyncLayout::manifestPath(const Uuid& journalID) {
    return journalRoot(journalID) + "/manifest.json";
}
std::string JournalSyncLayout::entryPath(const Uuid& journalID, const Uuid& entryID) {
    return journalRoot(journalID) + "/entries/" + entryID.toLowerString() + ".json";
}
std::string JournalSyncLayout::imagePath(const Uuid& journalID, const std::string& filename) {
    return journalRoot(journalID) + "/images/" + filename;
}
std::string JournalSyncLayout::tradingSnapshotPath(const Uuid& journalID) {
    return journalRoot(journalID) + "/trading/snapshot.json";
}
std::string JournalSyncLayout::tradingSnapshotTombstonePath(const Uuid& journalID) {
    return journalRoot(journalID) + "/trading/deleted.json";
}
std::string JournalSyncLayout::entryTombstonePath(const Uuid& journalID, const Uuid& entryID) {
    return journalRoot(journalID) + "/entry-tombstones/" + entryID.toLowerString() + ".json";
}
std::string JournalSyncLayout::journalTombstonePath(const Uuid& journalID) {
    return "/journal-tombstones-v2/" + journalID.toLowerString() + ".json";
}

std::optional<Uuid> JournalSyncLayout::journalTombstoneID(const std::string& path) {
    static const std::string prefix = "/journal-tombstones-v2/";
    static const std::string suffix = ".json";
    if (path.size() < prefix.size() + suffix.size()) return std::nullopt;
    if (path.compare(0, prefix.size(), prefix) != 0) return std::nullopt;
    if (path.compare(path.size() - suffix.size(), suffix.size(), suffix) != 0) return std::nullopt;
    return Uuid::parse(path.substr(prefix.size(), path.size() - prefix.size() - suffix.size()));
}

std::string JournalSyncLayout::settlementPath(const Uuid& journalID, const Uuid& entryID,
                                             TimePoint stamp, const Uuid& uniqueID) {
    const std::string suffix = uniqueID.toString().substr(0, 8);
    return journalRoot(journalID) + "/settlements/" + entryID.toLowerString() + "-"
        + formatUtcStamp(stamp) + "-" + suffix + ".json";
}

std::optional<Uuid> JournalSyncLayout::settlementEntryID(const std::string& path, const Uuid& journalID) {
    const std::string prefix = journalRoot(journalID) + "/settlements/";
    static const std::string suffix = ".json";
    if (path.size() < prefix.size() + suffix.size() + 36) return std::nullopt;
    if (path.compare(0, prefix.size(), prefix) != 0) return std::nullopt;
    if (path.compare(path.size() - suffix.size(), suffix.size(), suffix) != 0) return std::nullopt;
    const std::string name = path.substr(prefix.size(), path.size() - prefix.size() - suffix.size());
    if (name.size() <= 36) return std::nullopt;
    return Uuid::parse(name.substr(0, 36));
}

bool JournalSyncLayout::isSettlementPath(const std::string& path, const Uuid& journalID) {
    const std::string prefix = journalRoot(journalID) + "/settlements/";
    return path.size() >= prefix.size() + 5
        && path.compare(0, prefix.size(), prefix) == 0
        && path.size() >= 5 && path.compare(path.size() - 5, 5, ".json") == 0;
}

std::string JournalSyncLayout::conflictPath(const Uuid& journalID, const Uuid& entryID,
                                           TimePoint stamp, const Uuid& uniqueID) {
    const std::string suffix = uniqueID.toString().substr(0, 8);
    return journalRoot(journalID) + "/conflicts/" + entryID.toLowerString() + "-"
        + formatUtcStamp(stamp) + "-" + suffix + ".json";
}

std::optional<Uuid> JournalSyncLayout::entryIDFromEntryPath(const std::string& path, const Uuid& journalID) {
    const std::string prefix = journalRoot(journalID) + "/entries/";
    static const std::string suffix = ".json";
    if (path.size() < prefix.size() + suffix.size()) return std::nullopt;
    if (path.compare(0, prefix.size(), prefix) != 0) return std::nullopt;
    if (path.compare(path.size() - suffix.size(), suffix.size(), suffix) != 0) return std::nullopt;
    return Uuid::parse(path.substr(prefix.size(), path.size() - prefix.size() - suffix.size()));
}

namespace {

json requireObj(std::string_view text) {
    json j = json::parse(text.begin(), text.end());
    if (!j.is_object()) throw DecodeError("expected object");
    return j;
}

std::string requireStr(const json& j, const char* key) {
    if (!j.contains(key) || !j.at(key).is_string()) throw DecodeError(std::string("missing string ") + key);
    return j.at(key).get<std::string>();
}

int requireInt(const json& j, const char* key) {
    if (!j.contains(key) || !j.at(key).is_number_integer()) throw DecodeError(std::string("missing int ") + key);
    return j.at(key).get<int>();
}

Uuid requireUuid(const json& j, const char* key) {
    auto u = Uuid::parse(requireStr(j, key));
    if (!u) throw DecodeError(std::string("bad uuid ") + key);
    return *u;
}

TimePoint requireDate(const json& j, const char* key) {
    return parseIso8601(requireStr(j, key));
}

} // namespace

std::string encodeManifest(const JournalSyncManifest& m) {
    json j = {
        {"createdAt", formatIso8601(m.createdAt)},
        {"deviceID", m.deviceID},
        {"formatVersion", m.formatVersion},
        {"journalID", m.journalID.toString()},
        {"journalName", m.journalName},
    };
    return j.dump(2);
}

JournalSyncManifest decodeManifest(std::string_view text) {
    const json j = requireObj(text);
    JournalSyncManifest m;
    m.formatVersion = requireInt(j, "formatVersion");
    m.journalID = requireUuid(j, "journalID");
    m.journalName = requireStr(j, "journalName");
    m.createdAt = requireDate(j, "createdAt");
    m.deviceID = requireStr(j, "deviceID");
    return m;
}

std::string encodeTombstone(const JournalTombstone& t) {
    json j = {
        {"deletedAt", formatIso8601(t.deletedAt)},
        {"deviceID", t.deviceID},
        {"entryID", t.entryID.toString()},
        {"formatVersion", t.formatVersion},
    };
    return j.dump(2);
}

JournalTombstone decodeTombstone(std::string_view text) {
    const json j = requireObj(text);
    JournalTombstone t;
    t.formatVersion = j.contains("formatVersion") ? requireInt(j, "formatVersion") : JournalSyncLayout::formatVersion;
    t.entryID = requireUuid(j, "entryID");
    t.deletedAt = requireDate(j, "deletedAt");
    t.deviceID = requireStr(j, "deviceID");
    return t;
}

std::string encodeJournalDeletionTombstone(const JournalDeletionTombstone& t) {
    json j = {
        {"deletedAt", formatIso8601(t.deletedAt)},
        {"deviceID", t.deviceID},
        {"journalID", t.journalID.toString()},
        {"schemaVersion", t.schemaVersion},
    };
    return j.dump(2);
}

JournalDeletionTombstone decodeJournalDeletionTombstone(std::string_view text) {
    const json j = requireObj(text);
    JournalDeletionTombstone t;
    t.schemaVersion = j.contains("schemaVersion") ? requireInt(j, "schemaVersion") : 1;
    t.journalID = requireUuid(j, "journalID");
    t.deletedAt = requireDate(j, "deletedAt");
    t.deviceID = requireStr(j, "deviceID");
    return t;
}

std::string encodeSettlementMarker(const JournalSettlementMarker& m) {
    json j = {
        {"deviceID", m.deviceID},
        {"entryID", m.entryID.toString()},
        {"settledHash", m.settledHash},
        {"stamp", formatIso8601(m.stamp)},
    };
    return j.dump(2);
}

JournalSettlementMarker decodeSettlementMarker(std::string_view text) {
    const json j = requireObj(text);
    JournalSettlementMarker m;
    m.entryID = requireUuid(j, "entryID");
    m.settledHash = requireStr(j, "settledHash");
    m.deviceID = requireStr(j, "deviceID");
    m.stamp = requireDate(j, "stamp");
    return m;
}

std::string encodeConflictPayload(const JournalConflictPayload& p) {
    json items = json::array();
    for (const auto& it : p.losingItems) {
        items.push_back(json::parse(JournalSyncEncoding::encode(it)));
    }
    json j = {
        {"detectedAt", formatIso8601(p.detectedAt)},
        {"deviceID", p.deviceID},
        {"entryID", p.entryID.toString()},
        {"losingItems", items},
        {"reason", p.reason},
    };
    if (p.losingTitle) j["losingTitle"] = *p.losingTitle;
    return j.dump(2);
}

JournalConflictPayload decodeConflictPayload(std::string_view text) {
    const json j = requireObj(text);
    JournalConflictPayload p;
    p.entryID = requireUuid(j, "entryID");
    p.detectedAt = requireDate(j, "detectedAt");
    p.deviceID = requireStr(j, "deviceID");
    p.reason = requireStr(j, "reason");
    if (j.contains("losingTitle") && j.at("losingTitle").is_string()) {
        p.losingTitle = j.at("losingTitle").get<std::string>();
    }
    if (j.contains("losingItems") && j.at("losingItems").is_array()) {
        for (const auto& it : j.at("losingItems")) {
            p.losingItems.push_back(JournalSyncEncoding::decodeItem(it.dump()));
        }
    }
    return p;
}

namespace {

json encodeEntryState(const EntrySyncState& s) {
    json j = json::object();
    if (s.localHash) j["localHash"] = *s.localHash;
    if (s.remoteRev) j["remoteRev"] = *s.remoteRev;
    if (s.remoteContentHash) j["remoteContentHash"] = *s.remoteContentHash;
    if (s.tombstoneRev) j["tombstoneRev"] = *s.tombstoneRev;
    if (s.tombstoneDeletedAt) j["tombstoneDeletedAt"] = formatIso8601(*s.tombstoneDeletedAt);
    j["pushedHashes"] = s.pushedHashes;
    if (s.settlement) {
        json st = json::object();
        switch (s.settlement->kind) {
        case EntrySettlementKind::pushSettled:
            st["pushSettled"] = json{{"_0", s.settlement->hash}};
            break;
        case EntrySettlementKind::adoptRemote:
            st["adoptRemote"] = json::object();
            break;
        case EntrySettlementKind::markSettled:
            st["markSettled"] = json{{"_0", s.settlement->hash}};
            break;
        default:
            break;
        }
        if (!st.empty()) j["settlement"] = st;
    }
    return j;
}

EntrySyncState decodeEntryState(const json& j) {
    EntrySyncState s;
    if (!j.is_object()) return s;
    if (j.contains("localHash") && j["localHash"].is_string()) s.localHash = j["localHash"].get<std::string>();
    if (j.contains("remoteRev") && j["remoteRev"].is_string()) s.remoteRev = j["remoteRev"].get<std::string>();
    if (j.contains("remoteContentHash") && j["remoteContentHash"].is_string())
        s.remoteContentHash = j["remoteContentHash"].get<std::string>();
    if (j.contains("tombstoneRev") && j["tombstoneRev"].is_string())
        s.tombstoneRev = j["tombstoneRev"].get<std::string>();
    if (j.contains("tombstoneDeletedAt") && j["tombstoneDeletedAt"].is_string())
        s.tombstoneDeletedAt = parseIso8601(j["tombstoneDeletedAt"].get<std::string>());
    if (j.contains("pushedHashes") && j["pushedHashes"].is_array()) {
        for (const auto& h : j["pushedHashes"]) {
            if (h.is_string()) s.pushedHashes.push_back(h.get<std::string>());
        }
    }
    if (j.contains("settlement") && j["settlement"].is_object()) {
        const auto& st = j["settlement"];
        if (st.contains("pushSettled")) {
            std::string hash;
            if (st["pushSettled"].is_object() && st["pushSettled"].contains("_0"))
                hash = st["pushSettled"]["_0"].get<std::string>();
            else if (st["pushSettled"].is_string())
                hash = st["pushSettled"].get<std::string>();
            s.settlement = EntrySettlement::pushSettled(hash);
        } else if (st.contains("adoptRemote")) {
            s.settlement = EntrySettlement::adoptRemote();
        } else if (st.contains("markSettled")) {
            std::string hash;
            if (st["markSettled"].is_object() && st["markSettled"].contains("_0"))
                hash = st["markSettled"]["_0"].get<std::string>();
            else if (st["markSettled"].is_string())
                hash = st["markSettled"].get<std::string>();
            s.settlement = EntrySettlement::markSettled(hash);
        }
    } else if (j.contains("settledPushHash") && j["settledPushHash"].is_string()) {
        s.settlement = EntrySettlement::pushSettled(j["settledPushHash"].get<std::string>());
    } else if (j.contains("settleAdoptRemote") && j["settleAdoptRemote"].is_boolean()
               && j["settleAdoptRemote"].get<bool>()) {
        s.settlement = EntrySettlement::adoptRemote();
    } else if (j.contains("settleMarkHash") && j["settleMarkHash"].is_string()) {
        s.settlement = EntrySettlement::markSettled(j["settleMarkHash"].get<std::string>());
    }
    return s;
}

json encodeConflict(const SyncConflictRecord& r) {
    json j = {
        {"id", r.id.toString()},
        {"entryID", r.entryID.toString()},
        {"displayDay", r.displayDay},
        {"remotePath", r.remotePath},
        {"summary", r.summary},
        {"detectedAt", formatIso8601(r.detectedAt)},
    };
    if (r.localEntry) j["localEntry"] = json::parse(JournalSyncEncoding::encode(*r.localEntry));
    if (r.remoteEntry) j["remoteEntry"] = json::parse(JournalSyncEncoding::encode(*r.remoteEntry));
    if (r.mergedEntry) j["mergedEntry"] = json::parse(JournalSyncEncoding::encode(*r.mergedEntry));
    return j;
}

SyncConflictRecord decodeConflict(const json& j) {
    SyncConflictRecord r;
    if (j.contains("id") && j["id"].is_string()) {
        if (auto u = Uuid::parse(j["id"].get<std::string>())) r.id = *u;
    }
    if (j.contains("entryID") && j["entryID"].is_string()) {
        if (auto u = Uuid::parse(j["entryID"].get<std::string>())) r.entryID = *u;
    }
    if (j.contains("displayDay") && j["displayDay"].is_string()) r.displayDay = j["displayDay"].get<std::string>();
    if (j.contains("remotePath") && j["remotePath"].is_string()) r.remotePath = j["remotePath"].get<std::string>();
    if (j.contains("summary") && j["summary"].is_string()) r.summary = j["summary"].get<std::string>();
    if (j.contains("detectedAt") && j["detectedAt"].is_string())
        r.detectedAt = parseIso8601(j["detectedAt"].get<std::string>());
    if (j.contains("localEntry") && j["localEntry"].is_object())
        r.localEntry = JournalSyncEncoding::decodeEntry(j["localEntry"].dump());
    if (j.contains("remoteEntry") && j["remoteEntry"].is_object())
        r.remoteEntry = JournalSyncEncoding::decodeEntry(j["remoteEntry"].dump());
    if (j.contains("mergedEntry") && j["mergedEntry"].is_object())
        r.mergedEntry = JournalSyncEncoding::decodeEntry(j["mergedEntry"].dump());
    return r;
}

json encodeState(const JournalSyncState& s) {
    json remote = json::object();
    for (const auto& [path, rec] : s.remoteFiles) {
        json r = {{"rev", rec.rev}};
        if (rec.contentHash) r["contentHash"] = *rec.contentHash;
        remote[path] = r;
    }
    json entries = json::object();
    for (const auto& [id, st] : s.entries) entries[id.toString()] = encodeEntryState(st);
    json conflicts = json::array();
    for (const auto& c : s.pendingConflicts) conflicts.push_back(encodeConflict(c));
    json discovered = json::object();
    for (const auto& [k, rec] : s.discoveredJournals) {
        discovered[k] = {
            {"manifest", json::parse(encodeManifest(rec.manifest))},
            {"manifestRev", rec.manifestRev},
        };
    }
    json j = {
        {"remoteFiles", remote},
        {"entries", entries},
        {"pendingConflicts", conflicts},
        {"pendingConflictCleanups", s.pendingConflictCleanups},
        {"discoveredJournals", discovered},
    };
    if (s.cursor) j["cursor"] = *s.cursor;
    if (s.manifestRev) j["manifestRev"] = *s.manifestRev;
    if (s.manifestFormatVersion) j["manifestFormatVersion"] = *s.manifestFormatVersion;
    if (s.manifestName) j["manifestName"] = *s.manifestName;
    if (s.lastSyncAt) j["lastSyncAt"] = formatIso8601(*s.lastSyncAt);
    if (s.tradingSnapshotRev) j["tradingSnapshotRev"] = *s.tradingSnapshotRev;
    if (s.tradingSnapshotFetchedAtMilliseconds) j["tradingSnapshotFetchedAtMilliseconds"] = *s.tradingSnapshotFetchedAtMilliseconds;
    if (s.tradingSnapshotTombstoneRev) j["tradingSnapshotTombstoneRev"] = *s.tradingSnapshotTombstoneRev;
    if (s.tradingSnapshotDeletedAtMilliseconds) j["tradingSnapshotDeletedAtMilliseconds"] = *s.tradingSnapshotDeletedAtMilliseconds;
    return j;
}

JournalSyncState decodeState(const json& j) {
    JournalSyncState s;
    if (!j.is_object()) return s;
    if (j.contains("cursor") && j["cursor"].is_string()) s.cursor = j["cursor"].get<std::string>();
    if (j.contains("remoteFiles") && j["remoteFiles"].is_object()) {
        for (auto it = j["remoteFiles"].begin(); it != j["remoteFiles"].end(); ++it) {
            RemoteFileRecord rec;
            rec.rev = it.value().value("rev", "");
            if (it.value().contains("contentHash") && it.value()["contentHash"].is_string())
                rec.contentHash = it.value()["contentHash"].get<std::string>();
            s.remoteFiles[it.key()] = rec;
        }
    }
    if (j.contains("entries") && j["entries"].is_object()) {
        for (auto it = j["entries"].begin(); it != j["entries"].end(); ++it) {
            auto id = Uuid::parse(it.key());
            if (!id) continue;
            s.entries[*id] = decodeEntryState(it.value());
        }
    }
    if (j.contains("pendingConflicts") && j["pendingConflicts"].is_array()) {
        for (const auto& c : j["pendingConflicts"]) s.pendingConflicts.push_back(decodeConflict(c));
    }
    if (j.contains("pendingConflictCleanups") && j["pendingConflictCleanups"].is_array()) {
        for (const auto& p : j["pendingConflictCleanups"]) {
            if (p.is_string()) s.pendingConflictCleanups.push_back(p.get<std::string>());
        }
    }
    if (j.contains("manifestRev") && j["manifestRev"].is_string()) s.manifestRev = j["manifestRev"].get<std::string>();
    if (j.contains("manifestFormatVersion") && j["manifestFormatVersion"].is_number_integer())
        s.manifestFormatVersion = j["manifestFormatVersion"].get<int>();
    if (j.contains("manifestName") && j["manifestName"].is_string())
        s.manifestName = j["manifestName"].get<std::string>();
    if (j.contains("lastSyncAt") && j["lastSyncAt"].is_string())
        s.lastSyncAt = parseIso8601(j["lastSyncAt"].get<std::string>());
    if (j.contains("tradingSnapshotRev") && j["tradingSnapshotRev"].is_string())
        s.tradingSnapshotRev = j["tradingSnapshotRev"].get<std::string>();
    if (j.contains("tradingSnapshotFetchedAtMilliseconds") && j["tradingSnapshotFetchedAtMilliseconds"].is_number_integer())
        s.tradingSnapshotFetchedAtMilliseconds = j["tradingSnapshotFetchedAtMilliseconds"].get<std::int64_t>();
    if (j.contains("tradingSnapshotTombstoneRev") && j["tradingSnapshotTombstoneRev"].is_string())
        s.tradingSnapshotTombstoneRev = j["tradingSnapshotTombstoneRev"].get<std::string>();
    if (j.contains("tradingSnapshotDeletedAtMilliseconds") && j["tradingSnapshotDeletedAtMilliseconds"].is_number_integer())
        s.tradingSnapshotDeletedAtMilliseconds = j["tradingSnapshotDeletedAtMilliseconds"].get<std::int64_t>();
    if (j.contains("discoveredJournals") && j["discoveredJournals"].is_object()) {
        for (auto it = j["discoveredJournals"].begin(); it != j["discoveredJournals"].end(); ++it) {
            DiscoveredJournalRecord rec;
            if (it.value().contains("manifest"))
                rec.manifest = decodeManifest(it.value()["manifest"].dump());
            rec.manifestRev = it.value().value("manifestRev", "");
            s.discoveredJournals[it.key()] = rec;
        }
    }
    return s;
}

json encodeDevice(const JournalDeviceSyncState& s) {
    json pending = json::array();
    for (const auto& t : s.pendingJournalDeletions)
        pending.push_back(json::parse(encodeJournalDeletionTombstone(t)));
    json unacked = json::array();
    for (const auto& id : s.unackedRemoteDeletions) unacked.push_back(id.toString());
    json processed = json::array();
    for (const auto& id : s.processedJournalTombstones) processed.push_back(id.toString());
    json pendingTrading = json::array();
    for (const auto& t : s.pendingTradingSnapshotDeletions) {
        pendingTrading.push_back(json{
            {"journalID", t.journalID.toString()},
            {"deletedAtMilliseconds", t.deletedAtMilliseconds},
            {"deviceID", t.deviceID}
        });
    }
    return json{
        {"pendingJournalDeletions", pending},
        {"unackedRemoteDeletions", unacked},
        {"processedJournalTombstones", processed},
        {"pendingTradingSnapshotDeletions", pendingTrading},
    };
}

JournalDeviceSyncState decodeDevice(const json& j) {
    JournalDeviceSyncState s;
    if (!j.is_object()) return s;
    if (j.contains("pendingJournalDeletions") && j["pendingJournalDeletions"].is_array()) {
        for (const auto& t : j["pendingJournalDeletions"])
            s.pendingJournalDeletions.push_back(decodeJournalDeletionTombstone(t.dump()));
    }
    if (j.contains("unackedRemoteDeletions") && j["unackedRemoteDeletions"].is_array()) {
        for (const auto& id : j["unackedRemoteDeletions"]) {
            if (id.is_string()) {
                if (auto u = Uuid::parse(id.get<std::string>())) s.unackedRemoteDeletions.push_back(*u);
            }
        }
    }
    if (j.contains("processedJournalTombstones") && j["processedJournalTombstones"].is_array()) {
        for (const auto& id : j["processedJournalTombstones"]) {
            if (id.is_string()) {
                if (auto u = Uuid::parse(id.get<std::string>())) s.processedJournalTombstones.push_back(*u);
            }
        }
    }
    if (j.contains("pendingTradingSnapshotDeletions") && j["pendingTradingSnapshotDeletions"].is_array()) {
        for (const auto& t : j["pendingTradingSnapshotDeletions"]) {
            if (!t.is_object()) continue;
            JournalTradingSnapshotTombstone tomb;
            if (t.contains("journalID") && t["journalID"].is_string()) {
                if (auto u = Uuid::parse(t["journalID"].get<std::string>())) tomb.journalID = *u;
            }
            if (t.contains("deletedAtMilliseconds") && t["deletedAtMilliseconds"].is_number_integer()) {
                tomb.deletedAtMilliseconds = t["deletedAtMilliseconds"].get<std::int64_t>();
            }
            if (t.contains("deviceID") && t["deviceID"].is_string()) {
                tomb.deviceID = t["deviceID"].get<std::string>();
            }
            s.pendingTradingSnapshotDeletions.push_back(tomb);
        }
    }
    return s;
}

} // namespace

bool JournalDeviceSyncState::isTombstoned(const Uuid& journalID) const {
    for (const auto& id : processedJournalTombstones) if (id == journalID) return true;
    for (const auto& id : unackedRemoteDeletions) if (id == journalID) return true;
    for (const auto& t : pendingJournalDeletions) if (t.journalID == journalID) return true;
    return false;
}

void appendUniqueHash(std::vector<std::string>& hashes, const std::string& hash, int limit) {
    if (hashes.empty() || hashes.back() != hash) hashes.push_back(hash);
    if (static_cast<int>(hashes.size()) > limit) {
        hashes.erase(hashes.begin(), hashes.begin() + (static_cast<int>(hashes.size()) - limit));
    }
}

JournalSyncStateStore::JournalSyncStateStore(std::filesystem::path directory)
    : directory_(std::move(directory)) {}

std::filesystem::path JournalSyncStateStore::stateURL(const Uuid& journalID) const {
    return directory_ / (journalID.toLowerString() + "-v2.json");
}

bool JournalSyncStateStore::stateExists(const Uuid& journalID) const {
    std::error_code ec;
    return std::filesystem::exists(stateURL(journalID), ec);
}

JournalSyncState JournalSyncStateStore::load(const Uuid& journalID) const {
    auto data = readFileBytes(stateURL(journalID));
    if (!data) return {};
    try {
        return decodeState(json::parse(*data));
    } catch (...) {
        return {};
    }
}

void JournalSyncStateStore::save(const JournalSyncState& state, const Uuid& journalID) const {
    try {
        std::error_code ec;
        std::filesystem::create_directories(directory_, ec);
        const std::string body = encodeState(state).dump(2);
        atomicWriteFile(stateURL(journalID), body);
    } catch (...) {
        std::fprintf(stderr, "Wick sync state save failed\n");
    }
}

void JournalSyncStateStore::clear(const Uuid& journalID) const {
    std::error_code ec;
    std::filesystem::remove(stateURL(journalID), ec);
}

std::filesystem::path JournalSyncStateStore::deviceStateURL() const {
    return directory_ / "device-v2.json";
}

JournalDeviceSyncState JournalSyncStateStore::loadDeviceState() const {
    auto data = readFileBytes(deviceStateURL());
    if (!data) return {};
    try {
        return decodeDevice(json::parse(*data));
    } catch (...) {
        return {};
    }
}

void JournalSyncStateStore::saveDeviceState(const JournalDeviceSyncState& state) const {
    try {
        std::error_code ec;
        std::filesystem::create_directories(directory_, ec);
        atomicWriteFile(deviceStateURL(), encodeDevice(state).dump(2));
    } catch (...) {
        std::fprintf(stderr, "Wick sync device state save failed\n");
    }
}

} // namespace wick
