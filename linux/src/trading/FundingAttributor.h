#pragma once

#include "TradingModels.h"

#include <vector>

namespace wick {

struct FundingAttributor {
    static std::vector<TradingPosition> attach(
        const std::vector<TradingPosition> &positions,
        const std::vector<FundingEvent> &funding);
};

} // namespace wick
