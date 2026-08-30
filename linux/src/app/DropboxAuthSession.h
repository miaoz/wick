#pragma once

#include <QString>
#include <QStringList>
#include <QUrl>

/// Linux stand-in for ASWebAuthenticationSession.
///
/// The running instance's WickIpc socket receives
/// `db-hm5yscsy9a11g0q://2/token?code=...&state=...` from a second process
/// started by the desktop MIME handler.
class DropboxAuthSession {
public:
    static constexpr const char* kCallbackScheme = "db-hm5yscsy9a11g0q";

    /// Open the authorize URL in the default browser and block (nested event
    /// loop) until WickIpc delivers the callback, or until timeout.
    static QUrl run(const QUrl& authorizeUrl, const QString& callbackScheme);

    static void ensureMimeDefault();
};
