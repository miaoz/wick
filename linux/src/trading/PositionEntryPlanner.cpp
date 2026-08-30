#include "PositionEntryPlanner.h"

#include "Crypto.h"
#include "SymbolTagMatcher.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstring>
#include <set>

namespace wick {

std::vector<PlannedPositionDay> PositionEntryPlanner::plan(
    const std::vector<TradingPosition> &positions,
    const std::map<std::string, std::vector<std::string>> &existingTagsByDay,
    const std::function<std::string(TimePoint)> &dayKey,
    const std::function<TimePoint(TimePoint)> &startOfDay)
{
    struct Group {
        TimePoint day{};
        std::set<std::string> symbols;
    };
    std::map<std::string, Group> byDay;
    for (const auto &position : positions) {
        const TimePoint open{std::chrono::milliseconds(position.openTime)};
        const std::string key = dayKey(open);
        const auto itTags = existingTagsByDay.find(key);
        const std::vector<std::string> existing =
            itTags == existingTagsByDay.end() ? std::vector<std::string>{} : itTags->second;
        bool covered = false;
        for (const auto &tag : existing) {
            if (SymbolTagMatcher::matches(tag, position.symbol)) {
                covered = true;
                break;
            }
        }
        if (covered)
            continue;
        auto &group = byDay[key];
        if (group.symbols.empty())
            group.day = startOfDay(open);
        group.symbols.insert(position.symbol);
    }

    std::vector<PlannedPositionDay> out;
    out.reserve(byDay.size());
    for (auto &[key, group] : byDay) {
        PlannedPositionDay row;
        row.day = group.day;
        row.dayKey = key;
        row.symbols.assign(group.symbols.begin(), group.symbols.end());
        std::sort(row.symbols.begin(), row.symbols.end());
        out.push_back(std::move(row));
    }
    std::sort(out.begin(), out.end(),
              [](const PlannedPositionDay &a, const PlannedPositionDay &b) { return a.day < b.day; });
    return out;
}

Uuid PositionEntryPlanner::stableItemID(const Uuid &journalID, std::string_view dayKey,
                                        std::string_view symbol)
{
    std::string upper(symbol);
    for (char &c : upper)
        c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    const std::string source = std::string("wick.exchange-item.v1|")
        + journalID.toLowerString() + "|" + std::string(dayKey) + "|" + trimCopy(upper);
    const auto digest = sha256Bytes(source);
    Uuid u;
    std::memcpy(u.bytes.data(), digest.data(), 16);
    u.bytes[6] = static_cast<uint8_t>((u.bytes[6] & 0x0f) | 0x50);
    u.bytes[8] = static_cast<uint8_t>((u.bytes[8] & 0x3f) | 0x80);
    return u;
}

} // namespace wick
