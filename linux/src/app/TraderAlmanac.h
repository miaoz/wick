#pragma once

#include <QDate>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

namespace wick {

struct AlmanacEntry {
    QString yi;
    QString ji;
    QString yiEn;
    QString jiEn;
    QString seal;
    QString sealEn;
    QString lucky;
    QString luckyEn;
    QString sha;
    QString shaEn;
};

/// Same date seed as WickCalendarKit/TraderAlmanac.swift: year*10000+month*100+day.
AlmanacEntry traderAlmanac(const QDate &date, bool highVolDay);

} // namespace wick
