#pragma once

#include "JournalModels.h"

#include <optional>
#include <vector>

namespace wick {

struct JournalEntryMergeResult {
    JournalEntry merged;
    std::vector<JournalItem> losingItems;
    std::optional<std::string> losingTitle;
};

struct JournalEntryMerge {
    static JournalEntryMergeResult merge(const JournalEntry& local, const JournalEntry& remote);
};

} // namespace wick
