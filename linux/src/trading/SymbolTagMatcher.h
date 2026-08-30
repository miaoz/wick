#pragma once

#include "TradingModels.h"

#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace wick {

struct SymbolTagMatcher {
    static bool matches(std::string_view tag, std::string_view symbol);
    static std::string baseAsset(std::string_view symbol);
    static std::optional<std::string> quoteAsset(std::string_view symbol);
    static std::optional<std::string> preferredTag(std::string_view symbol,
                                                   const std::map<std::string, int> &tagCounts);
    static std::optional<std::string> normalize(std::string_view raw);
    static std::string perpBase(const std::string &normalized);
};

} // namespace wick
