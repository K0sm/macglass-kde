// SPDX-License-Identifier: GPL-3.0-or-later
#include "thumbprovider.h"

#include <KConfigGroup>
#include <KFileItem>
#include <KIO/PreviewJob>
#include <KSharedConfig>
#include <QCoreApplication>
#include <QPixmap>
#include <QPointer>
#include <QQuickTextureFactory>

namespace {
QStringList enabledPlugins()
{
    // Respect the plugins the user enabled for Dolphin previews.
    const KConfigGroup g(KSharedConfig::openConfig(QStringLiteral("dolphinrc")), QStringLiteral("PreviewSettings"));
    return g.readEntry("Plugins", KIO::PreviewJob::defaultPlugins());
}

class ThumbResponse : public QQuickImageResponse
{
public:
    ThumbResponse(const QUrl &url, int size)
    {
        // KIO jobs must live in the GUI thread.
        QMetaObject::invokeMethod(qApp, [self = QPointer<ThumbResponse>(this), url, size] {
            if (!self)
                return;
            static const QStringList plugins = enabledPlugins();
            KFileItem item(url);
            auto *job = new KIO::PreviewJob(KFileItemList{item}, QSize(size, size), &plugins);
            job->setScaleType(KIO::PreviewJob::ScaledAndCached);
            job->setIgnoreMaximumSize(false);
            QObject::connect(job, &KIO::PreviewJob::gotPreview, [self](const KFileItem &, const QPixmap &pix) {
                if (self)
                    self->m_image = pix.toImage();
            });
            QObject::connect(job, &KIO::PreviewJob::failed, [self](const KFileItem &) {
                if (self)
                    self->m_error = QStringLiteral("no preview");
            });
            QObject::connect(job, &KJob::result, [self](KJob *) {
                if (!self)
                    return;
                if (self->m_image.isNull() && self->m_error.isEmpty())
                    self->m_error = QStringLiteral("no preview");
                Q_EMIT self->finished();
            });
            job->start();
        }, Qt::QueuedConnection);
    }

    QQuickTextureFactory *textureFactory() const override
    {
        return QQuickTextureFactory::textureFactoryForImage(m_image);
    }
    QString errorString() const override { return m_error; }

    QImage m_image;
    QString m_error;
};
}

QQuickImageResponse *ThumbProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    QString raw = id;
    const int q = raw.lastIndexOf(QLatin1String("?v="));
    if (q >= 0)
        raw.truncate(q); // version suffix only busts the QML image cache
    const QUrl url = QUrl(QUrl::fromPercentEncoding(raw.toUtf8()));
    const int wanted = std::max(requestedSize.width(), requestedSize.height());
    return new ThumbResponse(url, wanted > 0 ? std::clamp(wanted, 32, 1024) : 256);
}
