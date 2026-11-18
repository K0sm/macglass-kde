// SPDX-License-Identifier: GPL-3.0-or-later
// Space-bar Quick Look: a large KIO preview of the selected item.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: ql
    visible: opacity > 0
    opacity: 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    property url fileUrl
    property string name
    property string iconName
    property var mtime
    property string kind
    property string sizeText

    function show(url, n, icon, mt, k, sz) {
        fileUrl = url; name = n; iconName = icon; mtime = mt; kind = k; sizeText = sz;
        opacity = 1;
        card.forceActiveFocus();
    }
    function close() { opacity = 0; }

    MouseArea { anchors.fill: parent; enabled: ql.visible; onClicked: ql.close() }

    Kirigami.ShadowedRectangle {
        id: card
        width: Math.min(ql.width * 0.6, 760)
        height: Math.min(ql.height * 0.75, 640)
        anchors.centerIn: parent
        radius: 16
        color: Qt.rgba(0.11, 0.11, 0.12, 0.92)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)
        shadow.size: 40
        shadow.yOffset: 12
        shadow.color: Qt.rgba(0, 0, 0, 0.55)
        scale: 0.94 + 0.06 * ql.opacity

        Keys.onSpacePressed: ql.close()
        Keys.onEscapePressed: ql.close()
        Keys.onReturnPressed: stack.open(ql.fileUrl)

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                QQC2.Label { text: ql.name; font.weight: Font.Bold; elide: Text.ElideMiddle; Layout.fillWidth: true }
                QQC2.Button { text: qsTr("Open"); onClicked: stack.open(ql.fileUrl) }
                QQC2.ToolButton { icon.name: "window-close-symbolic"; onClicked: ql.close() }
            }
            Thumb {
                Layout.fillWidth: true
                Layout.fillHeight: true
                size: Math.min(width, height)
                fileUrl: ql.visible ? ql.fileUrl : ""
                iconName: ql.iconName
                mtime: ql.mtime
            }
            QQC2.Label {
                text: [ql.kind, ql.sizeText].filter(s => s && s.length).join(" · ")
                opacity: 0.6
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
