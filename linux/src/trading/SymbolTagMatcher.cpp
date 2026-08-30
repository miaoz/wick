#include "SymbolTagMatcher.h"

#include <algorithm>
#include <cctype>

namespace wick {
namespace {

const std::vector<std::string> kDerivativePrefixes = {"1000000", "10000", "1000"};
const std::vector<std::string> kStableQuotes = {
    "FDUSD", "USDT", "USDC", "BUSD", "TUSD", "USDP", "DAI", "USD"};
const std::vector<std::string> kQuoteAssets = {
    "FDUSD", "USDT", "USDC", "BUSD", "TUSD", "USDP", "DAI", "USD", "BNB", "BTC", "ETH"};

} // namespace

std::optional<std::string> SymbolTagMatcher::normalize(std::string_view raw)
{
    std::string out;
    for (unsigned char c : raw) {
        if (std::isalnum(c))
            out.push_back(static_cast<char>(std::toupper(c)));
    }
    if (out.empty())
        return std::nullopt;
    return out;
}

std::string SymbolTagMatcher::perpBase(const std::string &normalized)
{
    std::string base = normalized;
    for (const auto &prefix : kDerivativePrefixes) {
        if (base.rfind(prefix, 0) == 0) {
            base.erase(0, prefix.size());
            break;
        }
    }
    for (const auto &quote : kStableQuotes) {
        if (base.size() > quote.size() && base.compare(base.size() - quote.size(), quote.size(), quote) == 0) {
            base.erase(base.size() - quote.size());
            break;
        }
    }
    return base;
}

bool SymbolTagMatcher::matches(std::string_view tag, std::string_view symbol)
{
    const auto nTag = normalize(tag);
    const auto nSym = normalize(symbol);
    if (!nTag || !nSym)
        return false;
    if (*nSym == *nTag)
        return true;
    if (nSym->rfind(*nTag, 0) == 0) {
        const std::string rest = nSym->substr(nTag->size());
        if (rest.empty() || std::find(kStableQuotes.begin(), kStableQuotes.end(), rest) != kStableQuotes.end())
            return true;
    }
    for (const auto &prefix : kDerivativePrefixes) {
        if (nSym->rfind(prefix, 0) == 0 && nSym->substr(prefix.size()).rfind(*nTag, 0) == 0)
            return true;
    }
    const std::string tagBase = perpBase(*nTag);
    const std::string symbolBase = perpBase(*nSym);
    if (!tagBase.empty() && tagBase == symbolBase) {
        const bool tagBare = tagBase == *nTag;
        const bool symbolBare = symbolBase == *nSym;
        if (tagBare || symbolBare)
            return true;
    }
    return false;
}

std::string SymbolTagMatcher::baseAsset(std::string_view symbol)
{
    std::string base(symbol);
    for (char &c : base)
        c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    for (const auto &prefix : kDerivativePrefixes) {
        if (base.rfind(prefix, 0) == 0) {
            base.erase(0, prefix.size());
            break;
        }
    }
    for (const auto &quote : kQuoteAssets) {
        if (base.size() > quote.size() && base.compare(base.size() - quote.size(), quote.size(), quote) == 0) {
            base.erase(base.size() - quote.size());
            break;
        }
    }
    return base.empty() ? std::string(symbol) : base;
}

std::optional<std::string> SymbolTagMatcher::preferredTag(
    std::string_view symbol, const std::map<std::string, int> &tagCounts)
{
    std::optional<std::string> bestDisplay;
    std::string bestKey;
    int bestCount = -1;
    for (const auto &[tag, count] : tagCounts) {
        const auto key = normalize(tag);
        if (!key || !matches(tag, symbol))
            continue;
        const bool better = count > bestCount
            || (count == bestCount
                && (key->size() < bestKey.size()
                    || (key->size() == bestKey.size() && *key < bestKey)));
        if (better) {
            bestDisplay = tag;
            bestKey = *key;
            bestCount = count;
        }
    }
    return bestDisplay;
}

} // namespace wick
