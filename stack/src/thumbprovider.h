// SPDX-License-Identifier: GPL-3.0-or-later
// image://thumb/<percent-encoded url>?v=<mtime> — KIO thumbnails (same plugins as Dolphin).
#pragma once

#include <QQuickAsyncImageProvider>

class ThumbProvider : public QQuickAsyncImageProvider
{
public:
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;
};
