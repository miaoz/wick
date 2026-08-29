#pragma once

#include <QDate>
#include <QString>

namespace wick {

/// Simple Gregorian → Chinese lunar line for the inspector / page stamp.
/// Covers 1900-01-31 … 2100-12-31. Empty outside that range.
QString lunarLine(const QDate &solar);

} // namespace wick
