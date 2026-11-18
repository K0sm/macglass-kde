// SPDX-License-Identifier: GPL-3.0-or-later
// File icon or real thumbnail (KIO thumbnailers: images, PDFs, video, fonts, …).
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root
    property url fileUrl
    property string iconName: "unknown"
    property var mtime: 0
    property bool isDir: false
    property int size: 64
    property bool dimmed: false

    implicitWidth: size
    implicitHeight: size
    opacity: dimmed ? 0.5 : 1

    readonly property string thumbSource: !isDir && fileUrl.toString().length
        ? "image://thumb/" + encodeURIComponent(fileUrl.toString()) + "?v=" + mtime : ""

    // Loads (and caches) the thumbnail; the visible item reuses the cached texture.
    Image {
        id: probe
        visible: false
        asynchronous: true
        cache: true
        source: root.thumbSource
        sourceSize: Qt.size(Math.max(128, root.size * 2), Math.max(128, root.size * 2))
    }
    readonly property bool hasThumb: probe.status === Image.Ready && probe.implicitWidth > 1

    Kirigami.Icon {
        anchors.fill: parent
        source: root.iconName.length ? root.iconName : "unknown"
        visible: !root.hasThumb
        smooth: true
    }

    Kirigami.ShadowedImage {
        visible: root.hasThumb
        anchors.centerIn: parent
        readonly property real k: root.hasThumb ? Math.min(root.width / probe.implicitWidth, root.height / probe.implicitHeight) : 1
        width: Math.round(probe.implicitWidth * k * 0.94)
        height: Math.round(probe.implicitHeight * k * 0.94)
        source: root.hasThumb ? root.thumbSource : ""
        sourceSize: probe.sourceSize
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        color: "transparent"
        radius: Math.max(3, root.size / 16)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)
        shadow.size: Math.max(4, root.size / 8)
        shadow.yOffset: Math.max(1, root.size / 32)
        shadow.color: Qt.rgba(0, 0, 0, 0.45)
    }
}
