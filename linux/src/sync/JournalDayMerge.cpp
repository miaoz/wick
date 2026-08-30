#include "JournalDayMerge.h"

#include <algorithm>
#include <map>
#include <stdexcept>

namespace wick {

JournalEntryMergeResult JournalEntryMerge::merge(const JournalEntry& local, const JournalEntry& remote) {
    if (!(local.id == remote.id)) {
        throw std::logic_error("Only versions of the same entry may merge");
    }
    const bool localIsBase = local.createdAt <= remote.createdAt;
    const JournalEntry& base = localIsBase ? local : remote;
    const JournalEntry& other = localIsBase ? remote : local;
    const bool localWinsConflicts = local.updatedAt >= remote.updatedAt;

    std::map<Uuid, JournalItem> itemsByID;
    std::vector<Uuid> order;
    for (const auto& item : base.items) {
        itemsByID[item.id] = item;
        order.push_back(item.id);
    }

    std::vector<JournalItem> losingItems;
    for (const auto& item : other.items) {
        auto it = itemsByID.find(item.id);
        if (it == itemsByID.end()) {
            itemsByID[item.id] = item;
            order.push_back(item.id);
            continue;
        }
        if (it->second == item) continue;

        const JournalItem existing = it->second;
        const JournalItem localCopy = localIsBase ? existing : item;
        const JournalItem remoteCopy = localIsBase ? item : existing;
        const JournalItem winner = localWinsConflicts ? localCopy : remoteCopy;
        const JournalItem loser = localWinsConflicts ? remoteCopy : localCopy;
        itemsByID[item.id] = winner;
        if (!loser.isEmpty()) losingItems.push_back(loser);
    }

    std::vector<JournalItem> items;
    for (const auto& id : order) {
        auto it = itemsByID.find(id);
        if (it != itemsByID.end()) items.push_back(it->second);
    }
    std::vector<JournalItem> nonEmpty;
    for (const auto& item : items) {
        if (!item.isEmpty()) nonEmpty.push_back(item);
    }
    if (!nonEmpty.empty()) items = std::move(nonEmpty);
    if (items.empty()) items.push_back(JournalItem{Uuid::generate(), "", "", {}, std::nullopt});

    const std::string localTitle = trimCopy(local.title);
    const std::string remoteTitle = trimCopy(remote.title);
    std::string title = base.title;
    std::optional<std::string> losingTitle;
    if (localTitle != remoteTitle) {
        if (localTitle.empty()) {
            title = remote.title;
        } else if (remoteTitle.empty()) {
            title = local.title;
        } else {
            title = localWinsConflicts ? local.title : remote.title;
            losingTitle = localWinsConflicts ? remote.title : local.title;
        }
    }

    JournalEntry merged = base;
    merged.id = local.id;
    merged.date = localWinsConflicts ? local.date : remote.date;
    merged.title = title;
    merged.items = std::move(items);
    merged.createdAt = std::min(local.createdAt, remote.createdAt);
    merged.updatedAt = std::max(local.updatedAt, remote.updatedAt);

    return JournalEntryMergeResult{std::move(merged), std::move(losingItems), std::move(losingTitle)};
}

} // namespace wick
