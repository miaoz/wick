#pragma once

#include "JournalSyncBackend.h"

#include <functional>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace wick {

std::string dropboxStyleContentHash(std::string_view data);

class FakeSyncBackend : public JournalSyncBackend {
public:
    bool authorized = true;
    int uploadCount = 0;
    int downloadCount = 0;
    std::optional<SyncBackendError> failNextEntryUpload;
    std::optional<SyncBackendError> failNextIncremental;
    std::function<void()> onListChanges;

    bool isAuthorized() const override { return authorized; }
    std::optional<std::string> accountEmail() const override {
        return authorized ? std::optional<std::string>("fake@example.com") : std::nullopt;
    }

    std::string authorize() override;
    void signOut() override { authorized = false; }

    std::pair<std::vector<RemoteFileMeta>, std::string>
    listChanges(const std::optional<std::string>& cursor) override;

    std::pair<std::string, std::string> download(const std::string& path) override;
    std::string upload(const std::string& path,
                       std::string_view data,
                       const std::optional<std::string>& ifRev) override;
    void deletePath(const std::string& path) override;

    std::optional<std::string> fileData(const std::string& path) const;
    bool hasFile(const std::string& path) const;
    std::vector<std::string> allPaths() const;
    void seedFile(const std::string& path, std::string_view data);

private:
    struct StoredFile {
        std::string data;
        std::string rev;
    };
    struct Change {
        int version = 0;
        RemoteFileMeta meta;
    };

    void log(const RemoteFileMeta& meta);

    std::map<std::string, StoredFile> files_;
    std::vector<Change> changeLog_;
    int revCounter_ = 0;
    int version_ = 0;
};

} // namespace wick
