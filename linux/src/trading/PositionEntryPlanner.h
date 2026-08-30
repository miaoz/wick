#pragma once

#include "JournalModels.h"
#include "TradingModels.h"

#include <functional>
#include <map>
#include <string>
#include <vector>

namespace wick {

struct PlannedPositionDay {
    TimePoint day{};
    std::string dayKey;
    std::vector<std::string> symbols;
};

struct PositionEntryPlanner {
    static std::vector<PlannedPositionDay> plan(
        const std::vector<TradingPosition> &positions,
        const std::map<std::string, std::vector<std::string>> &existingTagsByDay,
        const std::function<std::string(TimePoint)> &dayKey,
        const std::function<TimePoint(TimePoint)> &startOfDay);

    static Uuid stableItemID(const Uuid &journalID, std::string_view dayKey, std::string_view symbol);
};

} // namespace wick
