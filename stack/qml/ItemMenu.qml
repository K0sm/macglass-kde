// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls as QQC2

QQC2.Menu {
    id: menu
    property url fileUrl
    property string name
    property string iconName
    property var mtime
    property string kind
    property string sizeText
    property bool isDir

    function openFor(item, url, n, icon, mt, k, sz, dir) {
        fileUrl = url; name = n; iconName = icon; mtime = mt; kind = k; sizeText = sz; isDir = dir;
        popup();
    }

    QQC2.MenuItem { text: qsTr("Open"); icon.name: "document-open"; onTriggered: stack.open(menu.fileUrl) }
    QQC2.MenuItem { text: qsTr("Open With…"); icon.name: "document-open-symbolic"; enabled: !menu.isDir; onTriggered: stack.openWith(menu.fileUrl) }
    QQC2.MenuItem { text: qsTr("Quick Look"); icon.name: "quickview"; onTriggered: win.quickLookAt(menu.fileUrl, menu.name, menu.iconName, menu.mtime, menu.kind, menu.sizeText) }
    QQC2.MenuItem { text: qsTr("Show in %1").arg(stack.fileManagerName); icon.name: "document-open-folder"; onTriggered: stack.reveal(menu.fileUrl) }
    QQC2.MenuSeparator {}
    QQC2.MenuItem { text: qsTr("Copy"); icon.name: "edit-copy"; onTriggered: stack.copy(menu.fileUrl) }
    QQC2.MenuItem { text: qsTr("Copy Path"); icon.name: "edit-copy-path"; onTriggered: stack.copyPath(menu.fileUrl) }
    QQC2.MenuSeparator {}
    QQC2.MenuItem { text: qsTr("Move to Trash"); icon.name: "user-trash"; onTriggered: stack.trash(menu.fileUrl) }
}
