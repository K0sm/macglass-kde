// SPDX-License-Identifier: GPL-3.0-or-later
#include "foldermodel.h"

#include <KCoreDirLister>
#include <KFormat>
#include <KIO/Global>
#include <QCollator>
#include <QFileInfo>

namespace {
bool isPartialName(const QString &name)
{
    static const QStringList suffixes = {
        QStringLiteral(".part"), QStringLiteral(".crdownload"), QStringLiteral(".download"),
        QStringLiteral(".opdownload"), QStringLiteral(".partial"), QStringLiteral(".!qB"),
    };
    for (const auto &s : suffixes) {
        if (name.endsWith(s, Qt::CaseInsensitive))
            return true;
    }
    return false;
}
}

FolderModel::FolderModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_lister(new KCoreDirLister(this))
{
    m_lister->setShowHiddenFiles(false);
    m_lister->setDelayedMimeTypes(false);
    m_lister->setAutoErrorHandlingEnabled(false);
    connect(m_lister, &KCoreDirLister::itemsAdded, this, &FolderModel::onItemsAdded);
    connect(m_lister, &KCoreDirLister::itemsDeleted, this, &FolderModel::onItemsDeleted);
    connect(m_lister, &KCoreDirLister::refreshItems, this, &FolderModel::onRefreshItems);
    connect(m_lister, qOverload<>(&KCoreDirLister::clear), this, &FolderModel::onClear);
}

void FolderModel::setFolder(const QUrl &url)
{
    if (url == m_url)
        return;
    m_url = url;
    onClear();
    m_lister->openUrl(url, KCoreDirLister::Reload);
    Q_EMIT folderChanged();
}

QString FolderModel::folderName() const
{
    const QString n = m_url.fileName();
    return n.isEmpty() ? m_url.toDisplayString() : n;
}

void FolderModel::setSortMode(const QString &mode)
{
    if (mode == m_sortMode || (mode != QLatin1String("date") && mode != QLatin1String("name") && mode != QLatin1String("kind")))
        return;
    m_sortMode = mode;
    resort();
    Q_EMIT sortModeChanged();
}

qint64 FolderModel::addedTime(const KFileItem &item)
{
    // macOS sorts the Downloads stack by "Date Added"; birth time is the
    // closest equivalent. Fall back to mtime on filesystems without btime.
    QDateTime t = item.time(KFileItem::CreationTime);
    if (!t.isValid())
        t = item.time(KFileItem::ModificationTime);
    return t.isValid() ? t.toMSecsSinceEpoch() : 0;
}

bool FolderModel::lessThan(const KFileItem &a, const KFileItem &b) const
{
    static QCollator collator = [] {
        QCollator c;
        c.setNumericMode(true);
        c.setCaseSensitivity(Qt::CaseInsensitive);
        return c;
    }();
    if (m_sortMode == QLatin1String("name"))
        return collator.compare(a.name(), b.name()) < 0;
    if (m_sortMode == QLatin1String("kind")) {
        if (a.isDir() != b.isDir())
            return a.isDir();
        const int c = collator.compare(a.mimeComment(), b.mimeComment());
        return c != 0 ? c < 0 : collator.compare(a.name(), b.name()) < 0;
    }
    const qint64 ta = addedTime(a), tb = addedTime(b);
    return ta != tb ? ta > tb : collator.compare(a.name(), b.name()) < 0; // newest first
}

int FolderModel::insertPosition(const KFileItem &item) const
{
    auto it = std::lower_bound(m_items.cbegin(), m_items.cend(), item,
                               [this](const KFileItem &a, const KFileItem &b) { return lessThan(a, b); });
    return int(it - m_items.cbegin());
}

int FolderModel::indexOf(const QUrl &url) const
{
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items.at(i).url() == url)
            return i;
    }
    return -1;
}

void FolderModel::insertSorted(const KFileItem &item)
{
    const int row = insertPosition(item);
    beginInsertRows({}, row, row);
    m_items.insert(row, item);
    endInsertRows();
}

void FolderModel::removeAt(int row)
{
    beginRemoveRows({}, row, row);
    m_items.removeAt(row);
    endRemoveRows();
}

void FolderModel::resort()
{
    beginResetModel();
    std::stable_sort(m_items.begin(), m_items.end(),
                     [this](const KFileItem &a, const KFileItem &b) { return lessThan(a, b); });
    endResetModel();
}

void FolderModel::onItemsAdded(const QUrl &, const KFileItemList &items)
{
    for (const KFileItem &item : items) {
        if (item.isHidden() || indexOf(item.url()) >= 0)
            continue;
        insertSorted(item);
    }
    Q_EMIT countChanged();
}

void FolderModel::onItemsDeleted(const KFileItemList &items)
{
    for (const KFileItem &item : items) {
        const int row = indexOf(item.url());
        if (row >= 0)
            removeAt(row);
    }
    Q_EMIT countChanged();
}

void FolderModel::onRefreshItems(const QList<QPair<KFileItem, KFileItem>> &items)
{
    // Renames and modifications: re-insert so ordering stays correct.
    for (const auto &pair : items) {
        const int row = indexOf(pair.first.url());
        if (row >= 0)
            removeAt(row);
        if (!pair.second.isHidden())
            insertSorted(pair.second);
    }
    Q_EMIT countChanged();
}

void FolderModel::onClear()
{
    beginResetModel();
    m_items.clear();
    endResetModel();
    Q_EMIT countChanged();
}

int FolderModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

QVariant FolderModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_items.size())
        return {};
    const KFileItem &item = m_items.at(index.row());
    switch (role) {
    case Qt::DisplayRole:
    case NameRole:
        return item.text();
    case UrlRole:
        return item.url();
    case IconRole:
        return item.iconName();
    case MimeRole:
        return item.mimetype();
    case KindRole:
        return item.mimeComment();
    case IsDirRole:
        return item.isDir();
    case SizeRole:
        return item.isDir() ? QString() : KIO::convertSize(item.size());
    case DateRole: {
        const qint64 t = addedTime(item);
        return t ? KFormat().formatRelativeDateTime(QDateTime::fromMSecsSinceEpoch(t), QLocale::ShortFormat) : QString();
    }
    case TimeRole:
        return item.time(KFileItem::ModificationTime).toMSecsSinceEpoch();
    case PartialRole:
        return isPartialName(item.name());
    }
    return {};
}

QHash<int, QByteArray> FolderModel::roleNames() const
{
    return {
        {NameRole, "name"},   {UrlRole, "url"},   {IconRole, "iconName"}, {MimeRole, "mimeType"},
        {KindRole, "kind"},   {IsDirRole, "isDir"}, {SizeRole, "sizeText"}, {DateRole, "dateText"},
        {TimeRole, "mtime"},  {PartialRole, "partial"},
    };
}
