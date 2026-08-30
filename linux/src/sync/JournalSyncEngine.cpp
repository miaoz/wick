#include "JournalSyncEngine.h"

#include "Crypto.h"
#include "JournalDayMerge.h"
#include "JournalSyncEncoding.h"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <cstdio>

namespace wick {

namespace {

std::string encodeTradingSnapshotDocument(const JournalTradingSnapshotDocument &doc) {
    nlohmann::json j;
    j["formatVersion"] = doc.formatVersion;
    j["journalID"] = doc.journalID.toString();
    j["venue"] = doc.venue;
    j["accountLabel"] = doc.accountLabel;
    j["fetchedAtMilliseconds"] = doc.fetchedAtMilliseconds;
    j["payload"] = base64Encode(reinterpret_cast<const unsigned char*>(doc.payload.data()), doc.payload.size());
    return j.dump();
}

std::optional<JournalTradingSnapshotDocument> decodeTradingSnapshotDocument(std::string_view jsonStr) {
    try {
        const auto j = nlohmann::json::parse(jsonStr);
        JournalTradingSnapshotDocument doc;
        doc.formatVersion = j.value("formatVersion", 1);
        if (const auto id = Uuid::parse(j.value("journalID", "")))
            doc.journalID = *id;
        doc.venue = j.value("venue", "");
        doc.accountLabel = j.value("accountLabel", "");
        doc.fetchedAtMilliseconds = j.value("fetchedAtMilliseconds", static_cast<std::int64_t>(0));
        if (j.contains("payload")) {
            if (j["payload"].is_string()) {
                const std::string rawPayload = j["payload"].get<std::string>();
                doc.payload = base64Decode(rawPayload);
                if (doc.payload.empty() && !rawPayload.empty()) {
                    doc.payload = rawPayload;
                }
            } else if (j["payload"].is_object() || j["payload"].is_array()) {
                doc.payload = j["payload"].dump();
            }
        }
        return doc;
    } catch (...) {
        return std::nullopt;
    }
}

} // namespace

JournalSyncEngine::JournalSyncEngine(JournalSyncBackend& backend,
                                     JournalLocalSource& localSource,
                                     std::string deviceID,
                                     JournalSyncStateStore stateStore)
    : backend_(backend)
    , localSource_(localSource)
    , deviceID_(std::move(deviceID))
    , stateStore_(std::move(stateStore))
    , deviceState_(stateStore_.loadDeviceState()) {}

void JournalSyncEngine::syncOnce() { performSyncCycle(); }

void JournalSyncEngine::performSyncCycle() {
    if (isSyncing_) {
        pendingSync_ = true;
        return;
    }
    isSyncing_ = true;
    struct SyncGuard {
        JournalSyncEngine* e;
        ~SyncGuard() {
            e->isSyncing_ = false;
            if (e->pendingSync_) {
                e->pendingSync_ = false;
                e->performSyncCycle();
            }
        }
    } guard{this};

    auto journalID = localSource_.syncJournalID();
    if (!journalID) {
        status_ = Status::idle;
        return;
    }
    if (!stateJournalID_ || !(*stateJournalID_ == *journalID)) {
        state_ = stateStore_.load(*journalID);
        stateJournalID_ = *journalID;
        publishFromState();
    }
    if (!backend_.isAuthorized()) {
        status_ = Status::needsAuth;
        return;
    }
    if (!localSource_.syncIsWritable()) {
        status_ = Status::idle;
        return;
    }

    status_ = Status::syncing;
    try {
        syncCycleBody(*journalID);
        state_.lastSyncAt = std::chrono::system_clock::now();
        status_ = Status::idle;
    } catch (const JournalSyncError& e) {
        if (e.kind == JournalSyncError::Kind::journalSwitched) {
            status_ = Status::idle;
        } else if (e.kind == JournalSyncError::Kind::unsupportedRemoteFormat
                   || e.kind == JournalSyncError::Kind::unsupportedTradingSnapshotFormat) {
            status_ = Status::error;
            errorKind_ = SyncErrorKind::remoteFormatTooNew;
            errorDetail_ = e.what();
        } else {
            status_ = Status::error;
            errorKind_ = SyncErrorKind::other;
            errorDetail_ = e.what();
        }
    } catch (const SyncBackendError& e) {
        handleBackendError(e);
    } catch (const std::exception& e) {
        status_ = Status::error;
        errorKind_ = SyncErrorKind::other;
        errorDetail_ = e.what();
    }
    saveAndPublish();
}

void JournalSyncEngine::syncCycleBody(const Uuid& journalID) {
    requireJournal(journalID);
    const std::string frozenName = localSource_.syncJournalName();
    std::map<Uuid, LocalSnap> localEntries;
    for (const auto& [key, entry] : localSource_.syncEntrySnapshots()) {
        const std::string data = JournalSyncEncoding::canonicalData(entry);
        localEntries[key] = LocalSnap{entry, JournalSyncEncoding::contentHash(data)};
    }

    flushPendingJournalDeletions();
    flushPendingTradingSnapshotDeletions();
    if (deviceState_.isTombstoned(journalID)) return;

    auto [metas, newCursor] = backend_.listChanges(state_.cursor);
    if (!state_.cursor) state_.remoteFiles.clear();
    for (const auto& meta : metas) {
        if (meta.isDeleted) {
            state_.remoteFiles.erase(meta.path);
        } else if (meta.rev) {
            state_.remoteFiles[meta.path] = RemoteFileRecord{*meta.rev, meta.contentHash};
        }
    }
    state_.cursor = newCursor;
    requireJournal(journalID);

    detectPeerJournalTombstones();
    if (deviceState_.isTombstoned(journalID)) return;

    flushConflictArchiveCleanups();
    migrateLegacyRemoteIfNeeded(journalID, frozenName);
    requireJournal(journalID);
    ensureManifest(journalID, frozenName);
    refreshDiscoveredJournals(journalID);
    requireJournal(journalID);

    std::set<Uuid> entryIDs;
    for (const auto& [id, _] : localEntries) entryIDs.insert(id);
    for (const auto& [id, _] : state_.entries) entryIDs.insert(id);
    for (const auto& [path, _] : state_.remoteFiles) {
        if (auto key = JournalSyncLayout::entryIDFromEntryPath(path, journalID)) entryIDs.insert(*key);
        if (auto key = tombstoneEntryID(path, journalID)) entryIDs.insert(*key);
    }

    std::vector<Uuid> sorted(entryIDs.begin(), entryIDs.end());
    std::sort(sorted.begin(), sorted.end(), [](const Uuid& a, const Uuid& b) {
        return a.toString() < b.toString();
    });

    std::vector<PendingEntryMutation> pending;
    std::set<Uuid> supersededEntries;
    std::exception_ptr firstError;
    for (const auto& entryID : sorted) {
        try {
            reconcileEntry(entryID, journalID, localEntries, pending, supersededEntries);
        } catch (const JournalSyncError& e) {
            if (e.kind == JournalSyncError::Kind::journalSwitched) throw;
            if (!firstError) firstError = std::current_exception();
            std::fprintf(stderr, "Wick sync: day %s failed: %s\n", entryID.toString().c_str(), e.what());
        } catch (const std::exception& e) {
            if (!firstError) firstError = std::current_exception();
            std::fprintf(stderr, "Wick sync: day %s failed: %s\n", entryID.toString().c_str(), e.what());
        }
    }

    if (!pending.empty()) {
        requireJournal(journalID);
        std::vector<JournalSyncMutation> changes;
        changes.reserve(pending.size());
        for (const auto& item : pending) changes.push_back(item.mutation);
        auto applied = localSource_.applySyncedChanges(changes, journalID);
        for (const auto& item : pending) {
            if (applied.count(item.mutation.entryID) == 0) continue;
            if (item.baseline) state_.entries[item.mutation.entryID] = *item.baseline;
            else state_.entries.erase(item.mutation.entryID);
        }
    }

    for (const auto& entryID : sorted) {
        if (supersededEntries.count(entryID)) {
            auto it = state_.entries.find(entryID);
            if (it != state_.entries.end() && it->second.remoteContentHash) {
                uploadSettlementMarker(entryID, *it->second.remoteContentHash, journalID);
            }
        }
        bool hasConflict = false;
        for (const auto& c : state_.pendingConflicts) {
            if (c.entryID == entryID) { hasConflict = true; break; }
        }
        if (hasConflict) {
            auto it = state_.entries.find(entryID);
            if (it != state_.entries.end() && it->second.remoteContentHash
                && hasSettlingMarker(entryID, journalID, *it->second.remoteContentHash)) {
                removeConflicts(entryID);
            }
        }
    }

    try {
        reconcileImages(journalID);
    } catch (const std::exception& e) {
        if (!firstError) firstError = std::current_exception();
        std::fprintf(stderr, "Wick sync: images failed: %s\n", e.what());
    }
    try {
        reconcileTradingSnapshot(journalID);
    } catch (const JournalSyncError& e) {
        if (e.kind == JournalSyncError::Kind::journalSwitched) throw;
        if (!firstError) firstError = std::current_exception();
        std::fprintf(stderr, "Wick sync: trading snapshot failed: %s\n", e.what());
    } catch (const std::exception& e) {
        if (!firstError) firstError = std::current_exception();
        std::fprintf(stderr, "Wick sync: trading snapshot failed: %s\n", e.what());
    }

    collectGarbageTombstones(journalID);
    if (firstError) std::rethrow_exception(firstError);
}

void JournalSyncEngine::reconcileEntry(const Uuid& entryID,
                                      const Uuid& journalID,
                                      const std::map<Uuid, LocalSnap>& localEntries,
                                      std::vector<PendingEntryMutation>& mutations,
                                      std::set<Uuid>& supersededEntries) {
    const std::string entryPath = JournalSyncLayout::entryPath(journalID, entryID);
    const std::string tombPath = JournalSyncLayout::entryTombstonePath(journalID, entryID);
    std::optional<LocalSnap> local;
    auto lit = localEntries.find(entryID);
    if (lit != localEntries.end()) local = lit->second;
    std::optional<EntrySyncState> prev;
    auto pit = state_.entries.find(entryID);
    if (pit != state_.entries.end()) prev = pit->second;
    std::optional<RemoteFileRecord> remoteFile;
    auto rit = state_.remoteFiles.find(entryPath);
    if (rit != state_.remoteFiles.end()) remoteFile = rit->second;
    std::optional<RemoteFileRecord> remoteTomb;
    auto tit = state_.remoteFiles.find(tombPath);
    if (tit != state_.remoteFiles.end()) remoteTomb = tit->second;

    bool settlementSuperseded = false;
    if (prev && prev->settlement) {
        switch (executeSettlement(*prev->settlement, entryID, journalID, localEntries, remoteFile, mutations)) {
        case SettlementOutcome::executed:
            return;
        case SettlementOutcome::continueMatrix:
            break;
        case SettlementOutcome::superseded:
            settlementSuperseded = true;
            break;
        }
    }

    const bool localChanged = local && (!prev || !prev->localHash || local->hash != *prev->localHash);
    const bool localDeleted = !local && prev && prev->localHash;
    const bool remoteChanged = (remoteFile ? std::optional<std::string>(remoteFile->rev) : std::nullopt)
        != (prev ? prev->remoteRev : std::nullopt);
    const bool hasNewTombstone = remoteTomb && (!prev || !prev->tombstoneRev || remoteTomb->rev != *prev->tombstoneRev);

    if (remoteTomb) {
        TimePoint tombstoneDeletedAt{};
        if (hasNewTombstone || !prev || !prev->tombstoneDeletedAt) {
            tombstoneDeletedAt = downloadTombstone(tombPath).deletedAt;
        } else {
            tombstoneDeletedAt = *prev->tombstoneDeletedAt;
        }
        if (local && localChanged) {
            pushEntry(*local, journalID, remoteFile ? std::optional<std::string>(remoteFile->rev) : std::nullopt, mutations);
            backend_.deletePath(tombPath);
            state_.remoteFiles.erase(tombPath);
            recordConflict(entryID, "delete-vs-edit", "");
            return;
        }
        std::optional<LocalSnap> snap = local;
        if (local && localEntryMatchesSnapshot(entryID, snap)) {
            requireJournal(journalID);
            EntrySyncState tombstoneState;
            tombstoneState.tombstoneRev = remoteTomb->rev;
            tombstoneState.tombstoneDeletedAt = tombstoneDeletedAt;
            mutations.push_back(PendingEntryMutation{
                JournalSyncMutation::remove(entryID, local ? std::optional<std::string>(local->hash) : std::nullopt),
                tombstoneState});
        } else {
            EntrySyncState st;
            st.tombstoneRev = remoteTomb->rev;
            st.tombstoneDeletedAt = tombstoneDeletedAt;
            state_.entries[entryID] = st;
        }
        if (remoteFile) {
            backend_.deletePath(entryPath);
            state_.remoteFiles.erase(entryPath);
        }
        return;
    }

    if (localDeleted && remoteFile && !remoteChanged) {
        requireJournal(journalID);
        JournalTombstone tombstone;
        tombstone.entryID = entryID;
        tombstone.deletedAt = std::chrono::system_clock::now();
        tombstone.deviceID = deviceID_;
        const std::string data = encodeTombstone(tombstone);
        const std::string tombRev = backend_.upload(tombPath, data, std::nullopt);
        state_.remoteFiles[tombPath] = RemoteFileRecord{tombRev, JournalSyncEncoding::contentHash(data)};
        backend_.deletePath(entryPath);
        state_.remoteFiles.erase(entryPath);
        EntrySyncState st;
        st.tombstoneRev = tombRev;
        st.tombstoneDeletedAt = tombstone.deletedAt;
        state_.entries[entryID] = st;
        return;
    }

    if (localDeleted && remoteChanged && remoteFile) {
        pullEntry(*remoteFile, entryPath, entryID, journalID, local, mutations);
        recordConflict(entryID, "deletion overridden by remote edit", entryPath);
        return;
    }

    if (!remoteFile && prev && prev->remoteRev && local) {
        pushEntry(*local, journalID, std::nullopt, mutations);
        return;
    }

    if (local && localChanged && remoteChanged) {
        mergeEntry(*local, entryID, journalID, entryPath, mutations);
    } else if (remoteFile && remoteChanged && !localChanged) {
        pullEntry(*remoteFile, entryPath, entryID, journalID, local, mutations);
    } else if (local && localChanged) {
        pushEntry(*local, journalID, remoteFile ? std::optional<std::string>(remoteFile->rev) : std::nullopt, mutations);
    } else if (!local && !remoteFile && (!prev || !prev->tombstoneRev)) {
        state_.entries.erase(entryID);
    }

    if (settlementSuperseded) supersededEntries.insert(entryID);
}

JournalSyncEngine::SettlementOutcome
JournalSyncEngine::executeSettlement(const EntrySettlement& settlement,
                                     const Uuid& entryID,
                                     const Uuid& journalID,
                                     const std::map<Uuid, LocalSnap>& localEntries,
                                     const std::optional<RemoteFileRecord>& remoteFile,
                                     std::vector<PendingEntryMutation>& mutations) {
    if (auto it = state_.entries.find(entryID); it != state_.entries.end()) it->second.settlement.reset();

    switch (settlement.kind) {
    case EntrySettlementKind::pushSettled: {
        auto lit = localEntries.find(entryID);
        if (lit == localEntries.end() || lit->second.hash != settlement.hash) return SettlementOutcome::superseded;
        authoritativePush(lit->second, entryID, journalID, remoteFile);
        uploadSettlementMarker(entryID, settlement.hash, journalID);
        return SettlementOutcome::executed;
    }
    case EntrySettlementKind::adoptRemote: {
        if (!remoteFile) return SettlementOutcome::superseded;
        try {
            std::optional<LocalSnap> expected;
            auto lit = localEntries.find(entryID);
            if (lit != localEntries.end()) expected = lit->second;
            auto result = pullEntry(*remoteFile, JournalSyncLayout::entryPath(journalID, entryID),
                                    entryID, journalID, expected, mutations);
            if (!result.first) return SettlementOutcome::superseded;
            if (result.second) uploadSettlementMarker(entryID, *result.second, journalID);
            return SettlementOutcome::executed;
        } catch (...) {
            state_.entries[entryID].settlement = EntrySettlement::adoptRemote();
            return SettlementOutcome::executed;
        }
    }
    case EntrySettlementKind::markSettled:
        uploadSettlementMarker(entryID, settlement.hash, journalID);
        return SettlementOutcome::continueMatrix;
    default:
        return SettlementOutcome::continueMatrix;
    }
}

void JournalSyncEngine::authoritativePush(const LocalSnap& local,
                                          const Uuid& entryID,
                                          const Uuid& journalID,
                                          const std::optional<RemoteFileRecord>& remoteFile) {
    const std::string entryPath = JournalSyncLayout::entryPath(journalID, entryID);
    const std::string data = JournalSyncEncoding::canonicalData(local.entry);
    try {
        const std::string rev = backend_.upload(entryPath, data, remoteFile ? std::optional<std::string>(remoteFile->rev) : std::nullopt);
        recordPushedEntry(local, entryID, entryPath, rev);
        return;
    } catch (const SyncBackendError& e) {
        if (e.kind != SyncBackendError::Kind::writeConflict) {
            std::fprintf(stderr, "Wick sync: settlement push failed for %s: %s\n",
                         entryID.toString().c_str(), e.what());
            return;
        }
        try {
            auto [_, freshRev] = backend_.download(entryPath);
            const std::string rev = backend_.upload(entryPath, data, freshRev);
            recordPushedEntry(local, entryID, entryPath, rev);
        } catch (...) {
        }
    }
}

void JournalSyncEngine::recordPushedEntry(const LocalSnap& local,
                                          const Uuid& entryID,
                                          const std::string& entryPath,
                                          const std::string& rev) {
    state_.remoteFiles[entryPath] = RemoteFileRecord{rev, local.hash};
    EntrySyncState dayState = state_.entries.count(entryID) ? state_.entries[entryID] : EntrySyncState{};
    dayState.localHash = local.hash;
    dayState.remoteRev = rev;
    dayState.remoteContentHash = local.hash;
    appendUniqueHash(dayState.pushedHashes, local.hash, pushedHashHistoryLimit);
    state_.entries[entryID] = dayState;
}

void JournalSyncEngine::pushEntry(const LocalSnap& local,
                                 const Uuid& journalID,
                                 const std::optional<std::string>& currentRemoteRev,
                                 std::vector<PendingEntryMutation>& mutations) {
    requireJournal(journalID);
    const Uuid entryID = local.entry.id;
    const std::string entryPath = JournalSyncLayout::entryPath(journalID, entryID);
    const std::string data = JournalSyncEncoding::canonicalData(local.entry);
    try {
        const std::string rev = backend_.upload(entryPath, data, currentRemoteRev);
        recordPushedEntry(local, entryID, entryPath, rev);
    } catch (const SyncBackendError& e) {
        if (e.kind == SyncBackendError::Kind::writeConflict) {
            mergeEntry(local, entryID, journalID, entryPath, mutations);
        } else {
            throw;
        }
    }
}

std::pair<bool, std::optional<std::string>>
JournalSyncEngine::pullEntry(const RemoteFileRecord& remoteFile,
                             const std::string& entryPath,
                             const Uuid& entryID,
                             const Uuid& journalID,
                             const std::optional<LocalSnap>& snapshot,
                             std::vector<PendingEntryMutation>& mutations) {
    auto [data, downloadedRev] = backend_.download(entryPath);
    JournalEntry entry = JournalSyncEncoding::decodeEntry(data);
    if (!(entry.id == entryID)) {
        throw JournalSyncError::invalidRemoteEntryIdentity(entryPath);
    }
    localSource_.prepareForRemoteApply(entryID);
    if (!localEntryMatchesSnapshot(entryID, snapshot)) return {false, std::nullopt};
    requireJournal(journalID);
    const std::string canonical = JournalSyncEncoding::contentHash(data);
    const std::string rev = downloadedRev.empty() ? remoteFile.rev : downloadedRev;
    EntrySyncState dayState = state_.entries.count(entryID) ? state_.entries[entryID] : EntrySyncState{};
    dayState.localHash = canonical;
    dayState.remoteRev = rev;
    dayState.remoteContentHash = canonical;
    mutations.push_back(PendingEntryMutation{
        JournalSyncMutation::upsert(entry, snapshot ? std::optional<std::string>(snapshot->hash) : std::nullopt),
        dayState});
    return {true, canonical};
}

void JournalSyncEngine::mergeEntry(const LocalSnap& local,
                                  const Uuid& entryID,
                                  const Uuid& journalID,
                                  const std::string& entryPath,
                                  std::vector<PendingEntryMutation>& mutations) {
    auto [remoteData, remoteRev] = backend_.download(entryPath);
    JournalEntry remoteEntry = JournalSyncEncoding::decodeEntry(remoteData);
    const std::string remoteHash = JournalSyncEncoding::contentHash(remoteData);

    auto sit = state_.entries.find(entryID);
    if (remoteHash != local.hash && sit != state_.entries.end()) {
        const auto& pushed = sit->second.pushedHashes;
        if (std::find(pushed.begin(), pushed.end(), remoteHash) != pushed.end()) {
            const std::string data = JournalSyncEncoding::canonicalData(local.entry);
            try {
                const std::string rev = backend_.upload(entryPath, data, remoteRev);
                recordPushedEntry(local, entryID, entryPath, rev);
            } catch (const SyncBackendError&) {
            }
            return;
        }
    }

    if (!(remoteEntry.id == entryID)) {
        throw JournalSyncError::invalidRemoteEntryIdentity(entryPath);
    }
    auto result = JournalEntryMerge::merge(local.entry, remoteEntry);
    const std::string mergedData = JournalSyncEncoding::canonicalData(result.merged);
    const std::string mergedHash = JournalSyncEncoding::contentHash(mergedData);

    if (mergedHash == local.hash && mergedHash == remoteHash) {
        state_.remoteFiles[entryPath] = RemoteFileRecord{remoteRev, remoteHash};
        EntrySyncState dayState = state_.entries.count(entryID) ? state_.entries[entryID] : EntrySyncState{};
        dayState.localHash = local.hash;
        dayState.remoteRev = remoteRev;
        dayState.remoteContentHash = remoteHash;
        state_.entries[entryID] = dayState;
        return;
    }

    localSource_.prepareForRemoteApply(entryID);
    if (!localEntryMatchesSnapshot(entryID, local)) return;

    if (!result.losingItems.empty() || result.losingTitle) {
        const std::string archivePath = archiveConflict(result, entryID, journalID);
        recordConflict(entryID, "item-content-conflict", archivePath, local.entry, remoteEntry, result.merged);
    }

    if (mergedHash != remoteHash) {
        const std::string newRev = backend_.upload(entryPath, mergedData, remoteRev);
        state_.remoteFiles[entryPath] = RemoteFileRecord{newRev, mergedHash};
        EntrySyncState dayState = state_.entries.count(entryID) ? state_.entries[entryID] : EntrySyncState{};
        dayState.localHash = mergedHash;
        dayState.remoteRev = newRev;
        dayState.remoteContentHash = mergedHash;
        appendUniqueHash(dayState.pushedHashes, mergedHash, pushedHashHistoryLimit);
        if (mergedHash != local.hash) {
            requireJournal(journalID);
            mutations.push_back(PendingEntryMutation{
                JournalSyncMutation::upsert(result.merged, local.hash), dayState});
        } else {
            state_.entries[entryID] = dayState;
        }
    } else {
        state_.remoteFiles[entryPath] = RemoteFileRecord{remoteRev, mergedHash};
        EntrySyncState dayState = state_.entries.count(entryID) ? state_.entries[entryID] : EntrySyncState{};
        dayState.localHash = mergedHash;
        dayState.remoteRev = remoteRev;
        dayState.remoteContentHash = mergedHash;
        if (mergedHash != local.hash) {
            requireJournal(journalID);
            mutations.push_back(PendingEntryMutation{
                JournalSyncMutation::upsert(result.merged, local.hash), dayState});
        } else {
            state_.entries[entryID] = dayState;
        }
    }
}

bool JournalSyncEngine::localEntryMatchesSnapshot(const Uuid& entryID, const std::optional<LocalSnap>& snapshot) {
    auto fresh = localSource_.syncEntrySnapshot(entryID);
    if (!fresh) return !snapshot;
    try {
        return JournalSyncEncoding::contentHash(*fresh) == (snapshot ? snapshot->hash : std::string{});
    } catch (...) {
        return false;
    }
}

std::string JournalSyncEngine::archiveConflict(const JournalEntryMergeResult& result,
                                               const Uuid& entryID,
                                               const Uuid& journalID) {
    const auto now = std::chrono::system_clock::now();
    JournalConflictPayload payload;
    payload.entryID = entryID;
    payload.detectedAt = now;
    payload.deviceID = deviceID_;
    payload.reason = "item-content-conflict";
    payload.losingItems = result.losingItems;
    payload.losingTitle = result.losingTitle;
    std::string data;
    try {
        data = encodeConflictPayload(payload);
    } catch (...) {
        return "";
    }
    const std::string path = JournalSyncLayout::conflictPath(journalID, entryID, now, Uuid::generate());
    try {
        backend_.upload(path, data, std::nullopt);
    } catch (const std::exception& e) {
        std::fprintf(stderr, "Wick sync: conflict archive failed for %s: %s\n",
                     entryID.toString().c_str(), e.what());
        return "";
    }
    return path;
}

void JournalSyncEngine::recordConflict(const Uuid& entryID,
                                      const std::string& summary,
                                      const std::string& remotePath,
                                      const std::optional<JournalEntry>& local,
                                      const std::optional<JournalEntry>& remote,
                                      const std::optional<JournalEntry>& merged) {
    for (const auto& c : state_.pendingConflicts) {
        if (c.entryID == entryID && c.summary == summary) return;
    }
    std::string displayDay;
    const JournalEntry* src = merged ? &*merged : (local ? &*local : (remote ? &*remote : nullptr));
    if (src) displayDay = JournalDayKey::make(src->date, 0);
    SyncConflictRecord rec;
    rec.entryID = entryID;
    rec.displayDay = displayDay;
    rec.remotePath = remotePath;
    rec.summary = summary;
    rec.detectedAt = std::chrono::system_clock::now();
    rec.localEntry = local;
    rec.remoteEntry = remote;
    rec.mergedEntry = merged;
    state_.pendingConflicts.push_back(std::move(rec));
}

void JournalSyncEngine::removeConflicts(const Uuid& entryID) {
    state_.pendingConflicts.erase(
        std::remove_if(state_.pendingConflicts.begin(), state_.pendingConflicts.end(),
                       [&](const SyncConflictRecord& c) { return c.entryID == entryID; }),
        state_.pendingConflicts.end());
}

void JournalSyncEngine::uploadSettlementMarker(const Uuid& entryID, const std::string& settledHash, const Uuid& journalID) {
    JournalSettlementMarker marker;
    marker.entryID = entryID;
    marker.settledHash = settledHash;
    marker.deviceID = deviceID_;
    marker.stamp = std::chrono::system_clock::now();
    std::string data;
    try {
        data = encodeSettlementMarker(marker);
    } catch (...) {
        return;
    }
    const std::string path = JournalSyncLayout::settlementPath(journalID, entryID, std::chrono::system_clock::now(), Uuid::generate());
    try {
        const std::string rev = backend_.upload(path, data, std::nullopt);
        state_.remoteFiles[path] = RemoteFileRecord{rev, JournalSyncEncoding::contentHash(data)};
    } catch (const std::exception& e) {
        std::fprintf(stderr, "Wick sync: settlement marker failed for %s: %s\n",
                     entryID.toString().c_str(), e.what());
    }
}

bool JournalSyncEngine::hasSettlingMarker(const Uuid& entryID, const Uuid& journalID, const std::string& hash) {
    for (const auto& [path, _] : state_.remoteFiles) {
        if (!JournalSyncLayout::isSettlementPath(path, journalID)) continue;
        auto sid = JournalSyncLayout::settlementEntryID(path, journalID);
        if (!sid || !(*sid == entryID)) continue;
        try {
            auto [data, ign] = backend_.download(path);
            auto marker = decodeSettlementMarker(data);
            if (marker.settledHash == hash) return true;
        } catch (...) {
        }
    }
    return false;
}

void JournalSyncEngine::reconcileImages(const Uuid& journalID) {
    auto referencedSet = localSource_.syncedImageFilenames();
    std::vector<std::string> referenced;
    for (const auto& f : referencedSet) {
        if (JournalImageFilename::isValid(f)) referenced.push_back(f);
    }
    std::sort(referenced.begin(), referenced.end());
    for (const auto& filename : referenced) {
        const std::string path = JournalSyncLayout::imagePath(journalID, filename);
        if (state_.remoteFiles.count(asciiLower(path))) continue;
        auto data = localSource_.syncedImageData(filename);
        if (!data) continue;
        try {
            const std::string rev = backend_.upload(path, *data, std::nullopt);
            state_.remoteFiles[asciiLower(path)] = RemoteFileRecord{rev, JournalSyncEncoding::contentHash(*data)};
        } catch (const SyncBackendError& e) {
            if (e.kind != SyncBackendError::Kind::writeConflict) throw;
        }
    }
    for (const auto& filename : referenced) {
        if (localSource_.hasSyncedImage(filename)) continue;
        const std::string path = JournalSyncLayout::imagePath(journalID, filename);
        if (!state_.remoteFiles.count(asciiLower(path))) continue;
        try {
            auto [data, ign] = backend_.download(path);
            requireJournal(journalID);
            localSource_.storeSyncedImage(filename, data, journalID);
        } catch (...) {
        }
    }
}

void JournalSyncEngine::migrateLegacyRemoteIfNeeded(const Uuid& journalID, const std::string& localName) {
    const std::string manifestPath = JournalSyncLayout::manifestPath(journalID);
    auto mit = state_.remoteFiles.find(manifestPath);
    if (mit == state_.remoteFiles.end()) return;
    if (state_.manifestFormatVersion && *state_.manifestFormatVersion == JournalSyncLayout::formatVersion) return;
    auto [data, downloadedRev] = backend_.download(manifestPath);
    auto manifest = decodeManifest(data);
    if (manifest.formatVersion >= JournalSyncLayout::formatVersion) {
        state_.manifestFormatVersion = manifest.formatVersion;
        return;
    }
    auto upgraded = manifest;
    upgraded.formatVersion = JournalSyncLayout::formatVersion;
    upgraded.journalName = localName;
    upgraded.deviceID = deviceID_;
    const std::string upgradedData = encodeManifest(upgraded);
    const std::string ifRev = downloadedRev.empty() ? mit->second.rev : downloadedRev;
    const std::string rev = backend_.upload(manifestPath, upgradedData, ifRev);
    state_.remoteFiles[manifestPath] = RemoteFileRecord{rev, JournalSyncEncoding::contentHash(upgradedData)};
    state_.manifestRev = rev;
    state_.manifestFormatVersion = JournalSyncLayout::formatVersion;
    state_.manifestName = localName;

    const std::string root = JournalSyncLayout::journalRoot(journalID);
    for (const char* folder : {"days", "tombstones", "conflicts", "settlements"}) {
        const std::string path = root + "/" + folder;
        backend_.deletePath(path);
        std::vector<std::string> gone;
        for (const auto& [p, _] : state_.remoteFiles) {
            if (p.find(path + "/") == 0) gone.push_back(p);
        }
        for (const auto& p : gone) state_.remoteFiles.erase(p);
    }
    state_.entries.clear();
    state_.pendingConflicts.clear();
    state_.pendingConflictCleanups.clear();
}

void JournalSyncEngine::ensureManifest(const Uuid& journalID, const std::string& localName) {
    requireJournal(journalID);
    const std::string path = JournalSyncLayout::manifestPath(journalID);
    auto mit = state_.remoteFiles.find(path);
    if (mit == state_.remoteFiles.end()) {
        JournalSyncManifest manifest;
        manifest.formatVersion = JournalSyncLayout::formatVersion;
        manifest.journalID = journalID;
        manifest.journalName = localName;
        manifest.createdAt = std::chrono::system_clock::now();
        manifest.deviceID = deviceID_;
        const std::string data = encodeManifest(manifest);
        try {
            const std::string rev = backend_.upload(path, data, std::nullopt);
            state_.remoteFiles[path] = RemoteFileRecord{rev, JournalSyncEncoding::contentHash(data)};
            state_.manifestRev = rev;
            state_.manifestFormatVersion = JournalSyncLayout::formatVersion;
            state_.manifestName = localName;
        } catch (const SyncBackendError&) {
        }
        return;
    }

    const bool revChanged = !state_.manifestRev || mit->second.rev != *state_.manifestRev;
    bool seededFromLegacyState = false;
    if (!state_.manifestName && state_.manifestRev) {
        auto seeded = downloadManifest(path);
        state_.manifestName = seeded.journalName;
        seededFromLegacyState = true;
    }
    const bool localRenamed = state_.manifestName && localName != *state_.manifestName;
    if (!revChanged && !localRenamed) return;

    if (revChanged && (!localRenamed || seededFromLegacyState)) {
        auto manifest = downloadManifest(path);
        state_.manifestRev = mit->second.rev;
        state_.manifestFormatVersion = manifest.formatVersion;
        adoptJournalName(manifest.journalName, journalID);
        return;
    }

    auto current = downloadManifest(path);
    auto updated = current;
    updated.journalName = localName;
    updated.deviceID = deviceID_;
    const std::string data = encodeManifest(updated);
    try {
        const std::string rev = backend_.upload(path, data, mit->second.rev);
        state_.remoteFiles[path] = RemoteFileRecord{rev, JournalSyncEncoding::contentHash(data)};
        state_.manifestRev = rev;
        state_.manifestFormatVersion = updated.formatVersion;
        state_.manifestName = localName;
    } catch (const SyncBackendError& e) {
        if (e.kind != SyncBackendError::Kind::writeConflict) throw;
        auto [winnerData, winnerRev] = backend_.download(path);
        auto winner = decodeManifest(winnerData);
        if (winner.formatVersion > JournalSyncLayout::formatVersion) {
            throw JournalSyncError::unsupportedRemoteFormat(winner.formatVersion);
        }
        state_.remoteFiles[path] = RemoteFileRecord{winnerRev, JournalSyncEncoding::contentHash(winnerData)};
        state_.manifestRev = winnerRev;
        state_.manifestFormatVersion = winner.formatVersion;
        adoptJournalName(winner.journalName, journalID);
    }
}

JournalSyncManifest JournalSyncEngine::downloadManifest(const std::string& path) {
    auto [data, ign] = backend_.download(path);
    auto manifest = decodeManifest(data);
    if (manifest.formatVersion > JournalSyncLayout::formatVersion) {
        throw JournalSyncError::unsupportedRemoteFormat(manifest.formatVersion);
    }
    return manifest;
}

void JournalSyncEngine::adoptJournalName(const std::string& name, const Uuid& journalID) {
    if (name == localSource_.syncJournalName()) {
        state_.manifestName = name;
        return;
    }
    requireJournal(journalID);
    state_.manifestName = localSource_.applySyncedJournalName(name, journalID);
}

JournalTombstone JournalSyncEngine::downloadTombstone(const std::string& path) {
    auto [data, ign] = backend_.download(path);
    return decodeTombstone(data);
}

void JournalSyncEngine::refreshDiscoveredJournals(const Uuid& currentJournalID) {
    std::vector<std::string> paths;
    for (const auto& [p, _] : state_.remoteFiles) paths.push_back(p);
    std::sort(paths.begin(), paths.end());
    for (const auto& path : paths) {
        auto manifestJournalID = JournalSyncEngine::manifestJournalID(path);
        if (!manifestJournalID) continue;
        if (*manifestJournalID == currentJournalID) continue;
        if (deviceState_.isTombstoned(*manifestJournalID)) continue;
        auto mit = state_.remoteFiles.find(path);
        if (mit == state_.remoteFiles.end()) continue;
        const std::string key = manifestJournalID->toLowerString();
        auto dit = state_.discoveredJournals.find(key);
        if (dit != state_.discoveredJournals.end() && dit->second.manifestRev == mit->second.rev) continue;
        try {
            auto [data, ign] = backend_.download(path);
            auto manifest = decodeManifest(data);
            if (!(manifest.journalID == *manifestJournalID)) continue;
            if (manifest.formatVersion != JournalSyncLayout::formatVersion) continue;
            state_.discoveredJournals[key] = DiscoveredJournalRecord{manifest, mit->second.rev};
        } catch (...) {
        }
    }
    std::vector<std::string> prune;
    for (const auto& [key, rec] : state_.discoveredJournals) {
        auto uuid = Uuid::parse(key);
        if (!uuid) continue;
        if (state_.remoteFiles.count(JournalSyncLayout::manifestPath(*uuid)) == 0) prune.push_back(key);
    }
    for (const auto& k : prune) state_.discoveredJournals.erase(k);
}

std::optional<Uuid> JournalSyncEngine::manifestJournalID(const std::string& path) {
    static const std::string prefix = "/journals/";
    static const std::string suffix = "/manifest.json";
    if (path.size() < prefix.size() + suffix.size()) return std::nullopt;
    if (path.compare(0, prefix.size(), prefix) != 0) return std::nullopt;
    if (path.compare(path.size() - suffix.size(), suffix.size(), suffix) != 0) return std::nullopt;
    const std::string middle = path.substr(prefix.size(), path.size() - prefix.size() - suffix.size());
    if (middle.find('/') != std::string::npos) return std::nullopt;
    return Uuid::parse(middle);
}

std::optional<Uuid> JournalSyncEngine::tombstoneEntryID(const std::string& path, const Uuid& journalID) {
    const std::string prefix = JournalSyncLayout::journalRoot(journalID) + "/entry-tombstones/";
    static const std::string suffix = ".json";
    if (path.size() < prefix.size() + suffix.size()) return std::nullopt;
    if (path.compare(0, prefix.size(), prefix) != 0) return std::nullopt;
    if (path.compare(path.size() - suffix.size(), suffix.size(), suffix) != 0) return std::nullopt;
    return Uuid::parse(path.substr(prefix.size(), path.size() - prefix.size() - suffix.size()));
}

void JournalSyncEngine::collectGarbageTombstones(const Uuid& journalID) {
    const auto now = std::chrono::system_clock::now();
    std::vector<Uuid> ids;
    for (const auto& [id, _] : state_.entries) ids.push_back(id);
    for (const auto& entryID : ids) {
        auto it = state_.entries.find(entryID);
        if (it == state_.entries.end() || !it->second.tombstoneDeletedAt) continue;
        const double age = std::chrono::duration<double>(now - *it->second.tombstoneDeletedAt).count();
        if (age <= JournalSyncLayout::tombstoneRetention) continue;
        const std::string tombPath = JournalSyncLayout::entryTombstonePath(journalID, entryID);
        if (state_.remoteFiles.count(tombPath)) {
            try { backend_.deletePath(tombPath); } catch (...) {}
            state_.remoteFiles.erase(tombPath);
        }
        if (!it->second.localHash && !it->second.remoteRev) {
            state_.entries.erase(entryID);
        } else {
            it->second.tombstoneRev.reset();
            it->second.tombstoneDeletedAt.reset();
        }
    }
    std::vector<std::string> settlePaths;
    for (const auto& [path, _] : state_.remoteFiles) {
        if (JournalSyncLayout::isSettlementPath(path, journalID)) settlePaths.push_back(path);
    }
    for (const auto& path : settlePaths) {
        try {
            auto [data, ign] = backend_.download(path);
            auto marker = decodeSettlementMarker(data);
            const double age = std::chrono::duration<double>(now - marker.stamp).count();
            if (age <= JournalSyncLayout::tombstoneRetention) continue;
            backend_.deletePath(path);
            state_.remoteFiles.erase(path);
        } catch (...) {
        }
    }
    std::vector<std::string> jtombs;
    for (const auto& [path, _] : state_.remoteFiles) {
        if (JournalSyncLayout::journalTombstoneID(path)) jtombs.push_back(path);
    }
    for (const auto& path : jtombs) {
        try {
            auto [data, ign] = backend_.download(path);
            auto marker = decodeJournalDeletionTombstone(data);
            const double age = std::chrono::duration<double>(now - marker.deletedAt).count();
            if (age <= JournalSyncLayout::tombstoneRetention) continue;
            backend_.deletePath(path);
            state_.remoteFiles.erase(path);
        } catch (...) {
        }
    }
}

void JournalSyncEngine::requireJournal(const Uuid& journalID) {
    auto live = localSource_.syncJournalID();
    if (!live || !(*live == journalID)) throw JournalSyncError::journalSwitched();
}

void JournalSyncEngine::handleBackendError(const SyncBackendError& error) {
    switch (error.kind) {
    case SyncBackendError::Kind::needsAuth:
        status_ = Status::needsAuth;
        break;
    case SyncBackendError::Kind::cursorExpired:
        state_.cursor.reset();
        state_.remoteFiles.clear();
        status_ = Status::idle;
        pendingSync_ = true;
        break;
    case SyncBackendError::Kind::transport:
    case SyncBackendError::Kind::rateLimited:
        status_ = Status::offline;
        break;
    case SyncBackendError::Kind::server:
        status_ = Status::error;
        errorKind_ = SyncErrorKind::server;
        errorDetail_ = std::string("Dropbox ") + std::to_string(error.status) + ": " + error.what();
        break;
    default:
        status_ = Status::error;
        errorKind_ = SyncErrorKind::other;
        errorDetail_ = error.what();
        break;
    }
}

void JournalSyncEngine::publishFromState() {
    lastSyncAt_ = state_.lastSyncAt;
    pendingConflicts_ = state_.pendingConflicts;
    remoteJournalDeletions_ = deviceState_.unackedRemoteDeletions;
    discoveredJournals_.clear();
    for (const auto& [_, rec] : state_.discoveredJournals) {
        if (stateJournalID_ && rec.manifest.journalID == *stateJournalID_) continue;
        discoveredJournals_.push_back(rec.manifest);
    }
    std::sort(discoveredJournals_.begin(), discoveredJournals_.end(),
              [](const JournalSyncManifest& a, const JournalSyncManifest& b) {
                  std::string an = asciiLower(a.journalName), bn = asciiLower(b.journalName);
                  return an < bn;
              });
}

void JournalSyncEngine::saveAndPublish() {
    if (!stateJournalID_) return;
    stateStore_.save(state_, *stateJournalID_);
    publishFromState();
}

void JournalSyncEngine::queueJournalDeletion(const Uuid& journalID) {
    if (deviceState_.isTombstoned(journalID)) return;
    const bool knownRemotely = stateStore_.stateExists(journalID)
        || state_.remoteFiles.count(JournalSyncLayout::manifestPath(journalID)) > 0;
    if (!knownRemotely) return;
    JournalDeletionTombstone marker;
    marker.journalID = journalID;
    marker.deletedAt = std::chrono::system_clock::now();
    marker.deviceID = deviceID_;
    deviceState_.pendingJournalDeletions.push_back(marker);
    saveDeviceStateAndPublish();
}

void JournalSyncEngine::acknowledgeRemoteJournalDeletion(const Uuid& journalID) {
    deviceState_.unackedRemoteDeletions.erase(
        std::remove(deviceState_.unackedRemoteDeletions.begin(), deviceState_.unackedRemoteDeletions.end(), journalID),
        deviceState_.unackedRemoteDeletions.end());
    bool found = false;
    for (const auto& id : deviceState_.processedJournalTombstones) {
        if (id == journalID) { found = true; break; }
    }
    if (!found) deviceState_.processedJournalTombstones.push_back(journalID);
    saveDeviceStateAndPublish();
}

void JournalSyncEngine::clearJournalTombstone(const Uuid& journalID) {
    deviceState_.unackedRemoteDeletions.erase(
        std::remove(deviceState_.unackedRemoteDeletions.begin(), deviceState_.unackedRemoteDeletions.end(), journalID),
        deviceState_.unackedRemoteDeletions.end());
    deviceState_.processedJournalTombstones.erase(
        std::remove(deviceState_.processedJournalTombstones.begin(), deviceState_.processedJournalTombstones.end(), journalID),
        deviceState_.processedJournalTombstones.end());
    deviceState_.pendingJournalDeletions.erase(
        std::remove_if(deviceState_.pendingJournalDeletions.begin(), deviceState_.pendingJournalDeletions.end(),
                       [&](const JournalDeletionTombstone& t) { return t.journalID == journalID; }),
        deviceState_.pendingJournalDeletions.end());
    saveDeviceStateAndPublish();
}

bool JournalSyncEngine::isJournalTombstoned(const Uuid& journalID) const {
    return deviceState_.isTombstoned(journalID);
}

void JournalSyncEngine::flushPendingJournalDeletions() {
    std::vector<JournalDeletionTombstone> failed;
    for (const auto& marker : deviceState_.pendingJournalDeletions) {
        try {
            const std::string tombPath = JournalSyncLayout::journalTombstonePath(marker.journalID);
            if (state_.remoteFiles.count(tombPath) == 0) {
                const std::string data = encodeJournalDeletionTombstone(marker);
                try {
                    const std::string rev = backend_.upload(tombPath, data, std::nullopt);
                    state_.remoteFiles[tombPath] = RemoteFileRecord{rev, std::nullopt};
                } catch (const SyncBackendError& e) {
                    if (e.kind != SyncBackendError::Kind::writeConflict) throw;
                }
            }
            backend_.deletePath(JournalSyncLayout::journalRoot(marker.journalID));
            pruneRemoteFiles(JournalSyncLayout::journalRoot(marker.journalID));
            state_.discoveredJournals.erase(marker.journalID.toLowerString());
            stateStore_.clear(marker.journalID);
            deviceState_.unackedRemoteDeletions.erase(
                std::remove(deviceState_.unackedRemoteDeletions.begin(),
                            deviceState_.unackedRemoteDeletions.end(), marker.journalID),
                deviceState_.unackedRemoteDeletions.end());
            bool found = false;
            for (const auto& id : deviceState_.processedJournalTombstones) {
                if (id == marker.journalID) { found = true; break; }
            }
            if (!found) deviceState_.processedJournalTombstones.push_back(marker.journalID);
        } catch (...) {
            failed.push_back(marker);
        }
    }
    deviceState_.pendingJournalDeletions = std::move(failed);
    saveDeviceStateAndPublish();
}

void JournalSyncEngine::detectPeerJournalTombstones() {
    for (const auto& [path, _] : state_.remoteFiles) {
        auto id = JournalSyncLayout::journalTombstoneID(path);
        if (!id || deviceState_.isTombstoned(*id)) continue;
        deviceState_.unackedRemoteDeletions.push_back(*id);
        state_.discoveredJournals.erase(id->toLowerString());
    }
    std::vector<Uuid> ids = deviceState_.processedJournalTombstones;
    ids.insert(ids.end(), deviceState_.unackedRemoteDeletions.begin(), deviceState_.unackedRemoteDeletions.end());
    for (const auto& id : ids) {
        const std::string root = JournalSyncLayout::journalRoot(id);
        bool lingering = false;
        for (const auto& [path, _] : state_.remoteFiles) {
            if (path.find(root + "/") == 0) { lingering = true; break; }
        }
        if (!lingering) continue;
        try { backend_.deletePath(root); } catch (...) {}
        pruneRemoteFiles(root);
    }
    saveDeviceStateAndPublish();
}

void JournalSyncEngine::pruneRemoteFiles(const std::string& root) {
    std::vector<std::string> gone;
    for (const auto& [path, _] : state_.remoteFiles) {
        if (path.find(root + "/") == 0) gone.push_back(path);
    }
    for (const auto& p : gone) state_.remoteFiles.erase(p);
}

void JournalSyncEngine::saveDeviceStateAndPublish() {
    stateStore_.saveDeviceState(deviceState_);
    publishFromState();
}

void JournalSyncEngine::resetSyncState(const Uuid& journalID) {
    if (stateJournalID_ && *stateJournalID_ == journalID) state_ = JournalSyncState{};
    stateStore_.clear(journalID);
}

void JournalSyncEngine::queueConflictArchiveCleanup(const SyncConflictRecord& record) {
    if (record.remotePath.empty()) return;
    if (std::find(state_.pendingConflictCleanups.begin(), state_.pendingConflictCleanups.end(),
                  record.remotePath) != state_.pendingConflictCleanups.end())
        return;
    state_.pendingConflictCleanups.push_back(record.remotePath);
}

void JournalSyncEngine::flushConflictArchiveCleanups() {
    if (state_.pendingConflictCleanups.empty()) return;
    std::vector<std::string> remaining;
    for (const auto& path : state_.pendingConflictCleanups) {
        try {
            backend_.deletePath(path);
            state_.remoteFiles.erase(path);
        } catch (...) {
            remaining.push_back(path);
        }
    }
    state_.pendingConflictCleanups = std::move(remaining);
}

void JournalSyncEngine::dismissConflict(const Uuid& id) {
    auto it = std::find_if(state_.pendingConflicts.begin(), state_.pendingConflicts.end(),
                           [&](const SyncConflictRecord& c) { return c.id == id; });
    if (it == state_.pendingConflicts.end()) return;
    if (it->mergedEntry) {
        try {
            const std::string hash = JournalSyncEncoding::contentHash(*it->mergedEntry);
            state_.entries[it->entryID].settlement = EntrySettlement::markSettled(hash);
        } catch (...) {
        }
    }
    queueConflictArchiveCleanup(*it);
    state_.pendingConflicts.erase(it);
    saveAndPublish();
}

void JournalSyncEngine::resolveConflict(const Uuid& id, SyncConflictResolution resolution) {
    auto it = std::find_if(state_.pendingConflicts.begin(), state_.pendingConflicts.end(),
                           [&](const SyncConflictRecord& c) { return c.id == id; });
    if (it == state_.pendingConflicts.end()) return;
    const bool writable = stateJournalID_
        && localSource_.syncJournalID() && *localSource_.syncJournalID() == *stateJournalID_
        && localSource_.syncIsWritable();
    EntrySyncState dayState = state_.entries.count(it->entryID) ? state_.entries[it->entryID] : EntrySyncState{};
    switch (resolution) {
    case SyncConflictResolution::local:
        if (!it->localEntry || !writable || !stateJournalID_) return;
        localSource_.prepareForRemoteApply(it->entryID);
        localSource_.applySyncedEntry(*it->localEntry, *stateJournalID_);
        try {
            dayState.settlement = EntrySettlement::pushSettled(JournalSyncEncoding::contentHash(*it->localEntry));
        } catch (...) {
        }
        break;
    case SyncConflictResolution::remote:
        dayState.settlement = EntrySettlement::adoptRemote();
        break;
    case SyncConflictResolution::merged:
        if (it->mergedEntry) {
            try {
                dayState.settlement = EntrySettlement::markSettled(JournalSyncEncoding::contentHash(*it->mergedEntry));
            } catch (...) {
            }
        }
        break;
    }
    state_.entries[it->entryID] = dayState;
    queueConflictArchiveCleanup(*it);
    state_.pendingConflicts.erase(it);
    saveAndPublish();
}

void JournalSyncEngine::validateTradingSnapshot(const JournalTradingSnapshotDocument& doc, const Uuid& journalID) {
    if (doc.formatVersion > JournalTradingSnapshotDocument::currentFormatVersion)
        throw JournalSyncError(JournalSyncError::Kind::unsupportedTradingSnapshotFormat, "Unsupported trading snapshot format");
    if (doc.journalID != journalID)
        throw JournalSyncError(JournalSyncError::Kind::corruptData, "Trading snapshot journal ID mismatch");
}

void JournalSyncEngine::recordTradingSnapshotUpload(const std::string& data,
                                                    const std::string& rev,
                                                    const JournalTradingSnapshotDocument& doc,
                                                    const std::string& path) {
    state_.remoteFiles[path] = RemoteFileRecord{
        rev,
        JournalSyncEncoding::contentHash(data)
    };
    state_.tradingSnapshotRev = rev;
    state_.tradingSnapshotFetchedAtMilliseconds = doc.fetchedAtMilliseconds;
}

void JournalSyncEngine::flushPendingTradingSnapshotDeletions() {
    if (deviceState_.pendingTradingSnapshotDeletions.empty())
        return;
    std::vector<JournalTradingSnapshotTombstone> failed;
    for (const auto& marker : deviceState_.pendingTradingSnapshotDeletions) {
        const auto journalID = marker.journalID;
        const std::string path = JournalSyncLayout::tradingSnapshotPath(journalID);
        const std::string entryTombstonePath = JournalSyncLayout::tradingSnapshotTombstonePath(journalID);
        try {
            nlohmann::json j;
            j["journalID"] = marker.journalID.toString();
            j["deletedAtMilliseconds"] = marker.deletedAtMilliseconds;
            j["deviceID"] = marker.deviceID;
            const std::string data = j.dump();
            std::optional<std::string> knownRev;
            auto it = state_.remoteFiles.find(entryTombstonePath);
            if (it != state_.remoteFiles.end())
                knownRev = it->second.rev;
            const std::string tombstoneRev = backend_.upload(entryTombstonePath, data, knownRev);
            try { backend_.deletePath(path); } catch (...) {}
            state_.remoteFiles.erase(path);
            state_.remoteFiles[entryTombstonePath] = RemoteFileRecord{
                tombstoneRev,
                JournalSyncEncoding::contentHash(data)
            };
            if (stateJournalID_ && *stateJournalID_ == journalID) {
                state_.tradingSnapshotRev = std::nullopt;
                state_.tradingSnapshotFetchedAtMilliseconds = std::nullopt;
                state_.tradingSnapshotTombstoneRev = tombstoneRev;
                state_.tradingSnapshotDeletedAtMilliseconds = marker.deletedAtMilliseconds;
            }
        } catch (...) {
            failed.push_back(marker);
        }
    }
    deviceState_.pendingTradingSnapshotDeletions = failed;
    saveDeviceStateAndPublish();
}

void JournalSyncEngine::reconcileTradingSnapshot(const Uuid& journalID) {
    if (!localSource_.syncTradingSnapshotEnabled())
        return;
    for (const auto& marker : deviceState_.pendingTradingSnapshotDeletions) {
        if (marker.journalID == journalID)
            return;
    }
    requireJournal(journalID);

    const std::string path = JournalSyncLayout::tradingSnapshotPath(journalID);
    const auto local = localSource_.syncedTradingSnapshot(journalID);
    const std::string entryTombstonePath = JournalSyncLayout::tradingSnapshotTombstonePath(journalID);

    auto tit = state_.remoteFiles.find(entryTombstonePath);
    if (tit != state_.remoteFiles.end()) {
        std::optional<std::int64_t> deletedAt = state_.tradingSnapshotDeletedAtMilliseconds;
        if (tit->second.rev != state_.tradingSnapshotTombstoneRev.value_or("") || !deletedAt.has_value()) {
            auto [data, rev] = backend_.download(entryTombstonePath);
            const auto j = nlohmann::json::parse(data);
            const auto markerJid = Uuid::parse(j.value("journalID", ""));
            if (!markerJid || *markerJid != journalID)
                throw JournalSyncError(JournalSyncError::Kind::corruptData, "Trading snapshot tombstone journalID mismatch");
            state_.tradingSnapshotTombstoneRev = rev;
            state_.tradingSnapshotDeletedAtMilliseconds = j.value("deletedAtMilliseconds", static_cast<std::int64_t>(0));
            deletedAt = state_.tradingSnapshotDeletedAtMilliseconds;
        }

        if (local && deletedAt && local->fetchedAtMilliseconds > *deletedAt) {
            backend_.deletePath(entryTombstonePath);
            state_.remoteFiles.erase(entryTombstonePath);
            state_.tradingSnapshotTombstoneRev = std::nullopt;
            state_.tradingSnapshotDeletedAtMilliseconds = std::nullopt;
        } else {
            localSource_.removeSyncedTradingSnapshot(journalID);
            if (state_.remoteFiles.count(path)) {
                try { backend_.deletePath(path); } catch (...) {}
                state_.remoteFiles.erase(path);
            }
            state_.tradingSnapshotRev = std::nullopt;
            state_.tradingSnapshotFetchedAtMilliseconds = std::nullopt;
            return;
        }
    }

    auto rit = state_.remoteFiles.find(path);
    if (rit == state_.remoteFiles.end()) {
        state_.tradingSnapshotRev = std::nullopt;
        state_.tradingSnapshotFetchedAtMilliseconds = std::nullopt;
        if (!local)
            return;
        validateTradingSnapshot(*local, journalID);
        const std::string data = encodeTradingSnapshotDocument(*local);
        const std::string rev = backend_.upload(path, data, std::nullopt);
        requireJournal(journalID);
        recordTradingSnapshotUpload(data, rev, *local, path);
        return;
    }

    const auto& remoteRecord = rit->second;
    if (state_.tradingSnapshotRev.value_or("") != remoteRecord.rev) {
        auto [data, downloadedRev] = backend_.download(path);
        auto remote = decodeTradingSnapshotDocument(data);
        if (!remote)
            throw JournalSyncError(JournalSyncError::Kind::corruptData, "Failed to decode trading snapshot document");
        validateTradingSnapshot(*remote, journalID);
        requireJournal(journalID);

        if (local && local->fetchedAtMilliseconds > remote->fetchedAtMilliseconds) {
            validateTradingSnapshot(*local, journalID);
            const std::string localData = encodeTradingSnapshotDocument(*local);
            const std::string rev = backend_.upload(path, localData, downloadedRev);
            requireJournal(journalID);
            recordTradingSnapshotUpload(localData, rev, *local, path);
        } else {
            localSource_.applySyncedTradingSnapshot(*remote, journalID);
            state_.tradingSnapshotRev = downloadedRev;
            state_.tradingSnapshotFetchedAtMilliseconds = remote->fetchedAtMilliseconds;
        }
        return;
    }

    const auto baseline = state_.tradingSnapshotFetchedAtMilliseconds;
    const bool localIsMissingOrOlder = local
        ? (baseline ? (local->fetchedAtMilliseconds < *baseline) : false)
        : true;
    if (local && (baseline ? (local->fetchedAtMilliseconds > *baseline) : true)) {
        validateTradingSnapshot(*local, journalID);
        const std::string data = encodeTradingSnapshotDocument(*local);
        const std::string rev = backend_.upload(path, data, remoteRecord.rev);
        requireJournal(journalID);
        recordTradingSnapshotUpload(data, rev, *local, path);
    } else if (localIsMissingOrOlder) {
        auto [data, downloadedRev] = backend_.download(path);
        auto remote = decodeTradingSnapshotDocument(data);
        if (!remote)
            throw JournalSyncError(JournalSyncError::Kind::corruptData, "Failed to decode trading snapshot document");
        validateTradingSnapshot(*remote, journalID);
        requireJournal(journalID);
        localSource_.applySyncedTradingSnapshot(*remote, journalID);
        state_.tradingSnapshotRev = downloadedRev;
        state_.tradingSnapshotFetchedAtMilliseconds = remote->fetchedAtMilliseconds;
    }
}

} // namespace wick
