#pragma once

#include "TradingModels.h"

#include <vector>

namespace wick {

struct PositionAggregator {
    static std::vector<TradingPosition> aggregate(const std::vector<TradingFill> &fills);
};

} // namespace wick
