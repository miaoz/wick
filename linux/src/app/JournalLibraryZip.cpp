#include "JournalLibrary.h"

#include <QBuffer>
#include <QByteArray>
#include <QClipboard>
#include <QGuiApplication>
#include <QImage>
#include <QStringList>
#include <QUrl>

#include <filesystem>

using wick::Uuid;

namespace {

QString qs(const std::string &s)
{
    return QString::fromStdString(s);
}

std::string ss(const QString &s)
{
    return s.toStdString();
}

} // namespace

void JournalLibrary::touchActiveJournalMetadata()
{
    if (m_catalogReadOnly)
        return;
    for (auto &j : m_catalog.journals) {
        if (j.id == m_catalog.activeJournalID) {
            j.updatedAt = nowTp();
            writeCatalog();
            emit journalsChanged();
            return;
        }
    }
}

QString JournalLibrary::recoverCatalogFromScratch()
{
    std::error_code ec;
    const auto catalog = m_paths.catalogURL();
    if (std::filesystem::exists(catalog, ec)) {
        const auto quarantine =
            m_paths.librariesRoot
            / ("catalog.corrupt-" + Uuid::generate().toString() + ".json");
        std::filesystem::rename(catalog, quarantine, ec);
        if (ec)
            return QStringLiteral("无法隔离损坏的目录");
    }
    m_catalogReadOnly = false;
    m_errorBanner.clear();
    seedDefaultJournal();
    if (m_catalogReadOnly || !m_store)
        return QStringLiteral("无法重建日记目录");
    emit readOnlyChanged();
    emit bannersChanged();
    rebuildAfterStructuralChange();
    return {};
}

QUrl JournalLibrary::imageFileUrl(const QString &filename) const
{
    if (!m_store)
        return {};
    const auto path = m_store->imageURL(ss(filename));
    if (!path)
        return {};
    return QUrl::fromLocalFile(QString::fromStdString(path->string()));
}

QStringList JournalLibrary::itemImageFilenames(const QString &itemId) const
{
    QStringList images;
    const auto *item = findItem(itemId);
    if (!item)
        return images;
    for (const auto &name : item->imageFilenames)
        images.push_back(qs(name));
    return images;
}

QString JournalLibrary::addImageFromUrl(const QString &itemId, const QUrl &fileUrl)
{
    if (isReadOnly() || !m_store)
        return {};
    auto [entry, item] = findItemAndEntry(itemId);
    if (!entry || !item)
        return {};
    const QString local = fileUrl.isLocalFile() ? fileUrl.toLocalFile() : fileUrl.toString();
    if (local.isEmpty())
        return {};
    const auto name = m_store->addImageFromFile(entry->id, item->id, ss(local));
    if (!name)
        return {};
    m_dirty = false;
    m_savedState = QStringLiteral("已自动保存");
    touchActiveJournalMetadata();
    emit itemsChanged();
    emit daysChanged();
    emit savedStateChanged();
    return qs(*name);
}

bool JournalLibrary::pasteClipboardImage(const QString &itemId)
{
    if (isReadOnly() || !m_store)
        return false;
    auto [entry, item] = findItemAndEntry(itemId);
    if (!entry || !item)
        return false;
    const QClipboard *clipboard = QGuiApplication::clipboard();
    if (!clipboard)
        return false;
    const QImage img = clipboard->image();
    if (img.isNull())
        return false;
    QByteArray bytes;
    QBuffer buffer(&bytes);
    buffer.open(QIODevice::WriteOnly);
    if (!img.save(&buffer, "PNG"))
        return false;
    const auto name = m_store->addImage(entry->id, item->id,
                                        std::string_view(bytes.constData(), bytes.size()),
                                        "png");
    if (!name)
        return false;
    m_dirty = false;
    m_savedState = QStringLiteral("已自动保存");
    touchActiveJournalMetadata();
    emit itemsChanged();
    emit daysChanged();
    emit savedStateChanged();
    return true;
}

void JournalLibrary::removeImage(const QString &itemId, const QString &filename)
{
    if (isReadOnly() || !m_store)
        return;
    auto [entry, item] = findItemAndEntry(itemId);
    if (!entry || !item)
        return;
    m_store->removeImage(ss(filename), entry->id, item->id);
    m_dirty = false;
    m_savedState = QStringLiteral("已自动保存");
    touchActiveJournalMetadata();
    emit itemsChanged();
    emit daysChanged();
    emit savedStateChanged();
}

QString JournalLibrary::exportArchiveTo(const QUrl &destination)
{
    if (m_catalogReadOnly || (m_store && m_store->isReadOnlyDueToLoadFailure)) {
        return QStringLiteral("日记只读保护中，无法导出。");
    }
    if (!m_store)
        return QStringLiteral("没有活动日记");
    flushNow();
    const QString local = destination.isLocalFile() ? destination.toLocalFile()
                                                    : destination.toString();
    if (local.isEmpty())
        return QStringLiteral("无效的导出路径");
    const auto err = m_store->exportArchive(ss(local));
    if (err)
        return qs(*err);
    return {};
}

QString JournalLibrary::importArchiveFrom(const QUrl &source)
{
    if (m_catalogReadOnly) {
        const QString recovered = recoverCatalogFromScratch();
        if (!recovered.isEmpty())
            return recovered;
    }
    if (!m_store)
        return QStringLiteral("没有活动日记");
    flushNow();
    const QString local = source.isLocalFile() ? source.toLocalFile() : source.toString();
    if (local.isEmpty())
        return QStringLiteral("无效的导入路径");
    const auto err = m_store->importArchive(ss(local));
    if (err)
        return qs(*err);
    m_errorBanner.clear();
    m_restoreBanner.clear();
    m_dirty = false;
    m_savedState = QStringLiteral("已自动保存");
    ensureSelection();
    touchActiveJournalMetadata();
    rebuildAfterStructuralChange();
    emit readOnlyChanged();
    emit bannersChanged();
    return {};
}
