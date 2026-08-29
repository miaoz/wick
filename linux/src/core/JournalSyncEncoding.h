#pragma once

#include "JournalModels.h"

#include <string>
#include <string_view>
#include <variant>

namespace wick {

// Canonical JSON matching Swift JournalSyncEncoding:
// JSONEncoder outputFormatting = prettyPrinted + sortedKeys, iso8601 dates.
// Pretty print: 2-space indent, space BEFORE and after colon (`"key" : value`).
// Slashes escaped (JSONEncoder does not set withoutEscapingSlashes).
// Nil optionals omitted. Legacy `dayKey` is never emitted.
namespace JournalSyncEncoding {

std::string encode(const JournalEntry& entry);
std::string encode(const JournalItem& item);
std::string encode(const JournalSnapshot& snapshot);
std::string encode(const JournalCatalogSnapshot& catalog);
std::string encode(const JournalInfo& info);

JournalEntry decodeEntry(std::string_view json);
JournalItem decodeItem(std::string_view json);
JournalSnapshot decodeSnapshot(std::string_view json);
JournalCatalogSnapshot decodeCatalogObject(std::string_view json);

std::string canonicalData(const JournalEntry& entry);
std::string contentHash(std::string_view data);
std::string contentHash(const JournalEntry& entry);

} // namespace JournalSyncEncoding

} // namespace wick
