#include "JournalSyncEncoding.h"

#include <nlohmann/json.hpp>
#include <openssl/sha.h>

#include <cctype>
#include <cstdio>
#include <sstream>
#include <utility>

namespace wick {
namespace {

using json = nlohmann::json;

// ---------------------------------------------------------------------------
// Swift pretty JSON writer (JSONEncoder prettyPrinted + sortedKeys)
// ---------------------------------------------------------------------------

struct J {
    enum class Kind { boolean, number, string, array, object };
    Kind kind = Kind::object;
    bool b = false;
    std::int64_t n = 0;
    std::string s;
    std::vector<J> a;
    std::vector<std::pair<std::string, J>> o;

    static J boolean(bool v) {
        J j;
        j.kind = Kind::boolean;
        j.b = v;
        return j;
    }
    static J number(std::int64_t v) {
        J j;
        j.kind = Kind::number;
        j.n = v;
        return j;
    }
    static J str(std::string v) {
        J j;
        j.kind = Kind::string;
        j.s = std::move(v);
        return j;
    }
    static J arr(std::vector<J> v) {
        J j;
        j.kind = Kind::array;
        j.a = std::move(v);
        return j;
    }
    static J obj(std::vector<std::pair<std::string, J>> v) {
        J j;
        j.kind = Kind::object;
        j.o = std::move(v);
        return j;
    }
};

class SwiftWriter {
public:
    std::string out;
    int indent = 0; // indent *level* (2 spaces each)

    void writeIndent() {
        for (int i = 0; i < indent; ++i) out += "  ";
    }

    void writeString(std::string_view str) {
        out.push_back('"');
        for (unsigned char c : str) {
            switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '/': out += "\\/"; break; // default JSONEncoder escapes slashes
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out.push_back(static_cast<char>(c));
                }
                break;
            }
        }
        out.push_back('"');
    }

    void write(const J& v) {
        switch (v.kind) {
        case J::Kind::boolean:
            out += v.b ? "true" : "false";
            break;
        case J::Kind::number: {
            out += std::to_string(v.n);
            break;
        }
        case J::Kind::string:
            writeString(v.s);
            break;
        case J::Kind::array: {
            out.push_back('[');
            out.push_back('\n');
            ++indent;
            bool first = true;
            for (const auto& elem : v.a) {
                if (!first) {
                    out += ",\n";
                }
                first = false;
                writeIndent();
                write(elem);
            }
            out.push_back('\n');
            --indent;
            writeIndent();
            out.push_back(']');
            break;
        }
        case J::Kind::object: {
            out.push_back('{');
            out.push_back('\n');
            ++indent;
            if (!v.o.empty()) {
                writeIndent();
            }
            bool first = true;
            for (const auto& [key, val] : v.o) {
                if (!first) {
                    out += ",\n";
                    writeIndent();
                }
                first = false;
                writeString(key);
                out += " : ";
                write(val);
            }
            out.push_back('\n');
            --indent;
            writeIndent();
            out.push_back('}');
            break;
        }
        }
    }
};

J encodeReview(const JournalReview& r) {
    return J::obj({
        {"createdAt", J::str(formatIso8601(r.createdAt))},
        {"note", J::str(r.note)},
        {"updatedAt", J::str(formatIso8601(r.updatedAt))},
        {"verdict", J::str(std::string(toString(r.verdict)))},
    });
}

J encodeItem(const JournalItem& item) {
    std::vector<J> files;
    files.reserve(item.imageFilenames.size());
    for (const auto& f : item.imageFilenames) files.push_back(J::str(f));

    std::vector<std::pair<std::string, J>> fields;
    fields.push_back({"body", J::str(item.body)});
    fields.push_back({"id", J::str(item.id.toString())});
    fields.push_back({"imageFilenames", J::arr(std::move(files))});
    if (item.review) {
        fields.push_back({"review", encodeReview(*item.review)});
    }
    fields.push_back({"tag", J::str(item.tag)});
    return J::obj(std::move(fields));
}

J encodeEntry(const JournalEntry& e) {
    std::vector<J> items;
    items.reserve(e.items.size());
    for (const auto& it : e.items) items.push_back(encodeItem(it));
    return J::obj({
        {"createdAt", J::str(formatIso8601(e.createdAt))},
        {"date", J::str(formatIso8601(e.date))},
        {"id", J::str(e.id.toString())},
        {"items", J::arr(std::move(items))},
        {"title", J::str(e.title)},
        {"updatedAt", J::str(formatIso8601(e.updatedAt))},
    });
}

J encodeBinding(const JournalExchangeBinding& b) {
    return J::obj({
        {"accountLabel", J::str(b.accountLabel)},
        {"venue", J::str(std::string(toString(b.venue)))},
    });
}

J encodeInfo(const JournalInfo& info) {
    std::vector<std::pair<std::string, J>> fields;
    fields.push_back({"createdAt", J::str(formatIso8601(info.createdAt))});
    if (info.exchangeBinding) {
        fields.push_back({"exchangeBinding", encodeBinding(*info.exchangeBinding)});
    }
    fields.push_back({"id", J::str(info.id.toString())});
    fields.push_back({"name", J::str(info.name)});
    fields.push_back({"updatedAt", J::str(formatIso8601(info.updatedAt))});
    return J::obj(std::move(fields));
}

J encodeSnapshot(const JournalSnapshot& snap) {
    std::vector<J> entries;
    entries.reserve(snap.entries.size());
    for (const auto& e : snap.entries) entries.push_back(encodeEntry(e));
    return J::obj({
        {"entries", J::arr(std::move(entries))},
        {"version", J::number(snap.version)},
    });
}

J encodeCatalog(const JournalCatalogSnapshot& cat) {
    std::vector<J> journals;
    journals.reserve(cat.journals.size());
    for (const auto& info : cat.journals) journals.push_back(encodeInfo(info));
    return J::obj({
        {"activeJournalID", J::str(cat.activeJournalID.toString())},
        {"journals", J::arr(std::move(journals))},
        {"version", J::number(cat.version)},
    });
}

std::string dump(const J& v) {
    SwiftWriter w;
    w.write(v);
    return w.out;
}

// ---------------------------------------------------------------------------
// Decode via nlohmann (parse only; field mapping is strict)
// ---------------------------------------------------------------------------

const json& require(const json& j, const char* key) {
    if (!j.is_object() || !j.contains(key)) {
        throw DecodeError(std::string("missing key: ") + key);
    }
    return j.at(key);
}

std::string requireString(const json& j, const char* key) {
    const auto& v = require(j, key);
    if (!v.is_string()) throw DecodeError(std::string("expected string: ") + key);
    return v.get<std::string>();
}

std::int64_t requireInt(const json& j, const char* key) {
    const auto& v = require(j, key);
    if (v.is_number_integer()) return v.get<std::int64_t>();
    if (v.is_number_unsigned()) return static_cast<std::int64_t>(v.get<std::uint64_t>());
    if (v.is_number_float()) {
        const double d = v.get<double>();
        if (d != static_cast<double>(static_cast<std::int64_t>(d))) {
            throw DecodeError(std::string("expected integer: ") + key);
        }
        return static_cast<std::int64_t>(d);
    }
    throw DecodeError(std::string("expected integer: ") + key);
}

Uuid requireUuid(const json& j, const char* key) {
    auto parsed = Uuid::parse(requireString(j, key));
    if (!parsed) throw DecodeError(std::string("invalid UUID: ") + key);
    return *parsed;
}

TimePoint requireDate(const json& j, const char* key) {
    return parseIso8601(requireString(j, key));
}

JournalReview decodeReview(const json& j) {
    if (!j.is_object()) throw DecodeError("review must be an object");
    JournalReview r;
    auto verdict = parseReviewVerdict(requireString(j, "verdict"));
    if (!verdict) throw DecodeError("invalid review verdict");
    r.verdict = *verdict;
    r.note = requireString(j, "note");
    r.createdAt = requireDate(j, "createdAt");
    r.updatedAt = requireDate(j, "updatedAt");
    return r;
}

JournalItem decodeItemObj(const json& j) {
    if (!j.is_object()) throw DecodeError("item must be an object");
    JournalItem item;
    item.id = requireUuid(j, "id");
    item.tag = requireString(j, "tag");
    item.body = requireString(j, "body");
    const auto& files = require(j, "imageFilenames");
    if (!files.is_array()) throw DecodeError("imageFilenames must be an array");
    for (const auto& f : files) {
        if (!f.is_string()) throw DecodeError("imageFilenames entries must be strings");
        item.imageFilenames.push_back(f.get<std::string>());
    }
    JournalImageFilename::validateAll(item.imageFilenames);
    if (j.contains("review") && !j.at("review").is_null()) {
        item.review = decodeReview(j.at("review"));
    }
    return item;
}

JournalEntry decodeEntryObj(const json& j) {
    if (!j.is_object()) throw DecodeError("entry must be an object");
    JournalEntry e;
    e.id = requireUuid(j, "id");
    e.date = requireDate(j, "date");
    e.title = requireString(j, "title");
    const auto& items = require(j, "items");
    if (!items.is_array()) throw DecodeError("items must be an array");
    for (const auto& it : items) e.items.push_back(decodeItemObj(it));
    e.createdAt = requireDate(j, "createdAt");
    e.updatedAt = requireDate(j, "updatedAt");
    return e;
}

JournalExchangeBinding decodeBinding(const json& j) {
    if (!j.is_object()) throw DecodeError("exchangeBinding must be an object");
    JournalExchangeBinding b;
    auto venue = parseExchangeVenue(requireString(j, "venue"));
    if (!venue) throw DecodeError("invalid exchange venue");
    b.venue = *venue;
    b.accountLabel = requireString(j, "accountLabel");
    return b;
}

JournalInfo decodeInfo(const json& j) {
    if (!j.is_object()) throw DecodeError("journal info must be an object");
    JournalInfo info;
    info.id = requireUuid(j, "id");
    info.name = requireString(j, "name");
    info.createdAt = requireDate(j, "createdAt");
    info.updatedAt = requireDate(j, "updatedAt");
    if (j.contains("exchangeBinding") && !j.at("exchangeBinding").is_null()) {
        info.exchangeBinding = decodeBinding(j.at("exchangeBinding"));
    }
    return info;
}

json parseOrThrow(std::string_view text) {
    try {
        return json::parse(text.begin(), text.end());
    } catch (const json::parse_error& e) {
        throw DecodeError(std::string("corrupt JSON: ") + e.what());
    }
}

} // namespace

namespace JournalSyncEncoding {

std::string encode(const JournalEntry& entry) { return dump(encodeEntry(entry)); }
std::string encode(const JournalItem& item) { return dump(encodeItem(item)); }
std::string encode(const JournalSnapshot& snapshot) { return dump(encodeSnapshot(snapshot)); }
std::string encode(const JournalCatalogSnapshot& catalog) { return dump(encodeCatalog(catalog)); }
std::string encode(const JournalInfo& info) { return dump(encodeInfo(info)); }

JournalEntry decodeEntry(std::string_view jsonText) {
    return decodeEntryObj(parseOrThrow(jsonText));
}

JournalItem decodeItem(std::string_view jsonText) {
    return decodeItemObj(parseOrThrow(jsonText));
}

JournalSnapshot decodeSnapshot(std::string_view jsonText) {
    const json j = parseOrThrow(jsonText);
    if (!j.is_object()) throw DecodeError("snapshot must be an object");
    JournalSnapshot snap;
    snap.version = static_cast<int>(requireInt(j, "version"));
    const auto& entries = require(j, "entries");
    if (!entries.is_array()) throw DecodeError("entries must be an array");
    for (const auto& e : entries) snap.entries.push_back(decodeEntryObj(e));
    return snap;
}

JournalCatalogSnapshot decodeCatalogObject(std::string_view jsonText) {
    const json j = parseOrThrow(jsonText);
    if (!j.is_object()) throw DecodeError("catalog must be an object");
    JournalCatalogSnapshot cat;
    cat.version = static_cast<int>(requireInt(j, "version"));
    cat.activeJournalID = requireUuid(j, "activeJournalID");
    const auto& journals = require(j, "journals");
    if (!journals.is_array()) throw DecodeError("journals must be an array");
    for (const auto& info : journals) cat.journals.push_back(decodeInfo(info));
    return cat;
}

std::string canonicalData(const JournalEntry& entry) { return encode(entry); }

std::string contentHash(std::string_view data) {
    unsigned char digest[SHA256_DIGEST_LENGTH];
    SHA256(reinterpret_cast<const unsigned char*>(data.data()), data.size(), digest);
    static constexpr char kHex[] = "0123456789abcdef";
    std::string hex;
    hex.resize(SHA256_DIGEST_LENGTH * 2);
    for (int i = 0; i < SHA256_DIGEST_LENGTH; ++i) {
        hex[static_cast<size_t>(i) * 2] = kHex[digest[i] >> 4];
        hex[static_cast<size_t>(i) * 2 + 1] = kHex[digest[i] & 0x0f];
    }
    return hex;
}

std::string contentHash(const JournalEntry& entry) {
    return contentHash(canonicalData(entry));
}

} // namespace JournalSyncEncoding
} // namespace wick
