#include "LunarCalendar.h"

namespace wick {
namespace {

// Bit-packed lunar year data, 1900–2100 (standard almanac encoding).
// Bits 0-3: leap month (0 = none). Bit 16: leap month is 30 days.
// Bits 4-15: month lengths, bit 4 = month 1 … bit 15 = month 12 (1 = 30 days).
static const unsigned int kLunarInfo[] = {
    0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2,
    0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977,
    0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970,
    0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950,
    0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557,
    0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0,
    0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0,
    0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6,
    0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570,
    0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x055c0, 0x0ab60, 0x096d5, 0x092e0,
    0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5,
    0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930,
    0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530,
    0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45,
    0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0,
    0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06b20, 0x1a6c4, 0x0aae0,
    0x0a2e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0, 0x0a6d0, 0x055d4,
    0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50, 0x055a0, 0x0aba4, 0x0a5b0, 0x052b0,
    0x0b273, 0x06930, 0x07337, 0x06aa0, 0x0ad50, 0x14b55, 0x04b60, 0x0a570, 0x054e4, 0x0d160,
    0x0e968, 0x0d520, 0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a2d0, 0x0d150, 0x0f252,
    0x0d520
};

int leapMonthOf(int year)
{
    return static_cast<int>(kLunarInfo[year - 1900] & 0xf);
}

int leapDaysOf(int year)
{
    if (leapMonthOf(year) == 0)
        return 0;
    return (kLunarInfo[year - 1900] & 0x10000) ? 30 : 29;
}

int monthDaysOf(int year, int month)
{
    return (kLunarInfo[year - 1900] & (0x10000 >> month)) ? 30 : 29;
}

int yearDaysOf(int year)
{
    int sum = 348;
    for (unsigned int i = 0x8000; i > 0x8; i >>= 1) {
        if (kLunarInfo[year - 1900] & i)
            ++sum;
    }
    return sum + leapDaysOf(year);
}

QString monthName(int month, bool leap)
{
    static const char *kMonths[] = {
        "", "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月"};
    const QString name = QString::fromUtf8(kMonths[month]);
    return leap ? (QStringLiteral("闰") + name) : name;
}

QString dayName(int day)
{
    static const char *kDays[] = {
        "",   "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"};
    if (day < 1 || day > 30)
        return {};
    return QString::fromUtf8(kDays[day]);
}

} // namespace

QString lunarLine(const QDate &solar)
{
    if (!solar.isValid())
        return {};
    const QDate base(1900, 1, 31);
    if (solar < base || solar > QDate(2100, 12, 31))
        return {};

    int offset = static_cast<int>(base.daysTo(solar));
    int year = 1900;
    while (year <= 2100) {
        const int yd = yearDaysOf(year);
        if (offset < yd)
            break;
        offset -= yd;
        ++year;
    }
    if (year > 2100)
        return {};

    const int leap = leapMonthOf(year);
    for (int month = 1; month <= 12; ++month) {
        const int md = monthDaysOf(year, month);
        if (offset < md) {
            return QStringLiteral("农历") + monthName(month, false) + dayName(offset + 1);
        }
        offset -= md;
        if (month == leap) {
            const int ld = leapDaysOf(year);
            if (offset < ld) {
                return QStringLiteral("农历") + monthName(month, true) + dayName(offset + 1);
            }
            offset -= ld;
        }
    }
    return {};
}

} // namespace wick
