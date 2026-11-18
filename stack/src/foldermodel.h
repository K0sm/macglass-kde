// SPDX-License-Identifier: GPL-3.0-or-later
// Live, sorted model of a directory (KCoreDirLister => KDirWatch/inotify).
#pragma once

#include <QAbstractListModel>
#include <QSortFilterProxyModel>
#include <QUrl>
#include <KFileItem>

// First N rows of a model (the fan only shows the newest items).
class LimitModel : public QSortFilterProxyModel
{
    Q_OBJECT
public:
    explicit LimitModel(QAbstractItemModel *source, int limit, QObject *parent = nullptr)
        : QSortFilterProxyModel(parent), m_limit(limit)
    {
        setSourceModel(source);
        // Row positions change on insert/remove, so re-evaluate the window.
        auto refilter = [this] { invalidateRowsFilter(); };
        connect(source, &QAbstractItemModel::rowsInserted, this, refilter);
        connect(source, &QAbstractItemModel::rowsRemoved, this, refilter);
        connect(source, &QAbstractItemModel::modelReset, this, refilter);
    }
protected:
    bool filterAcceptsRow(int row, const QModelIndex &) const override { return row < m_limit; }
private:
    int m_limit;
};

class KCoreDirLister;

class FolderModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(QUrl folderUrl READ folderUrl NOTIFY folderChanged)
    Q_PROPERTY(QString folderName READ folderName NOTIFY folderChanged)
    Q_PROPERTY(QString sortMode READ sortMode WRITE setSortMode NOTIFY sortModeChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        UrlRole,
        IconRole,
        MimeRole,
        KindRole,
        IsDirRole,
        SizeRole,
        DateRole,
        TimeRole,
        PartialRole,
    };
    Q_ENUM(Roles)

    explicit FolderModel(QObject *parent = nullptr);

    void setFolder(const QUrl &url);
    QUrl folderUrl() const { return m_url; }
    QString folderName() const;
    int count() const { return int(m_items.size()); }

    QString sortMode() const { return m_sortMode; }
    void setSortMode(const QString &mode);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

Q_SIGNALS:
    void countChanged();
    void folderChanged();
    void sortModeChanged();

private:
    void onItemsAdded(const QUrl &dir, const KFileItemList &items);
    void onItemsDeleted(const KFileItemList &items);
    void onRefreshItems(const QList<QPair<KFileItem, KFileItem>> &items);
    void onClear();

    bool lessThan(const KFileItem &a, const KFileItem &b) const;
    int insertPosition(const KFileItem &item) const;
    int indexOf(const QUrl &url) const;
    void insertSorted(const KFileItem &item);
    void removeAt(int row);
    void resort();
    static qint64 addedTime(const KFileItem &item);

    KCoreDirLister *m_lister;
    QList<KFileItem> m_items;
    QUrl m_url;
    QString m_sortMode = QStringLiteral("date");
};
