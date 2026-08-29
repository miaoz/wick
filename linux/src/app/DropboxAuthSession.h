#pragma once

#include <QString>
#include <QStringList>
#include <QUrl>

/// Linux stand-in for ASWebAuthenticationSession.
///
/// The running instance listens on a Unix socket under XDG_RUNTIME_DIR.
/// `wick --dropbox-callback db-hm5yscsy9a11g0q://2/token?code=...&state=...`
/// (started by the desktop file MIME handler) forwards the URL and exits.
class DropboxAuthSession {
public:
    static constexpr const char* kCallbackScheme = "db-hm5yscsy9a11g0q";

    /// Open the authorize URL in the default browser and block (nested event
    /// loop) until the second process delivers the callback, or until timeout.
    static QUrl run(const QUrl& authorizeUrl, const QString& callbackScheme);

    /// Second process: forward `url` to the listening instance. Returns a
    /// process exit code (0 on success).
    static int forwardCallback(const QString& url);

    /// If `args` is a Dropbox callback invocation, forward and return the
    /// process exit code. Otherwise return -1 (caller should start the app).
    static int maybeForwardAndExit(const QStringList& args);

    static QString socketPath();
    static void ensureMimeDefault();
};
