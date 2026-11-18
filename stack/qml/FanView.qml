// SPDX-License-Identifier: GPL-3.0-or-later
// macOS-style "Fan": newest item nearest the dock, arcing up and to the right,
// labels on the left. Items spring out of the dock icon one after another.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: fan

    readonly property int n: rep.count
    readonly property int slots: n + 1                 // + "Open in <file manager>"
    readonly property int iconSize: 64
    readonly property real step: 70
    readonly property real curve: 1.25                 // px * i²  → arc to the right
    readonly property real tilt: 1.15                  // degrees per step
    readonly property real stagger: 0.075
    readonly property real baseY: height - 10
    readonly property real originX: stack.anchorX
    property int current: 0

    function slotProgress(i) {
        const t = win.progress * (1 + stagger * slots) - stagger * i;
        return Math.max(0, Math.min(1, t));
    }

    Keys.onUpPressed: current = Math.min(slots - 1, current + 1)
    Keys.onDownPressed: current = Math.max(0, current - 1)
    Keys.onReturnPressed: current < n ? rep.itemAt(current).openIt() : stack.openFolder()
    Keys.onSpacePressed: if (current < n) rep.itemAt(current).look()

    Repeater {
        id: rep
        model: stack.fanModel

        delegate: Item {
            id: slot
            required property int index
            required property url url
            required property string name
            required property string iconName
            required property var mtime
            required property string kind
            required property string sizeText
            required property bool isDir
            required property bool partial

            function openIt() { stack.open(url) }
            function look() { win.quickLookAt(url, name, iconName, mtime, kind, sizeText) }

            readonly property real t: fan.slotProgress(index)
            readonly property real e: win.closing ? win.outCubic(t) : win.outBack(t, 1.25)
            readonly property real tx: fan.originX + fan.curve * index * index
            readonly property real ty: fan.baseY - fan.iconSize / 2 - index * fan.step - 4
            readonly property bool hot: mouse.containsMouse || fan.current === index

            // icon centre interpolates from the dock icon to its fan slot
            x: fan.originX + (tx - fan.originX) * e - width + fan.iconSize / 2
            y: (fan.baseY + fan.iconSize / 2) + (ty - fan.baseY - fan.iconSize / 2) * e - height / 2
            width: label.width + 12 + fan.iconSize
            height: fan.iconSize
            opacity: Math.min(1, t * 2.2)
            rotation: index * fan.tilt * e
            transformOrigin: Item.Right
            scale: 0.35 + 0.65 * Math.min(1.08, e)
            z: fan.n - index

            Rectangle {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: icon.left
                anchors.rightMargin: 12
                width: Math.min(text.implicitWidth + 20, 280)
                height: text.implicitHeight + 8
                radius: height / 2
                color: slot.hot ? Kirigami.Theme.highlightColor : Qt.rgba(0.11, 0.11, 0.12, 0.82)
                border.width: 1
                border.color: slot.hot ? "transparent" : Qt.rgba(1, 1, 1, 0.10)
                Behavior on color { ColorAnimation { duration: 90 } }

                QQC2.Label {
                    id: text
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, 260)
                    text: slot.name + (slot.partial ? " — downloading…" : "")
                    color: "white"
                    elide: Text.ElideMiddle
                    font.weight: Font.Medium
                }
            }

            Thumb {
                id: icon
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                size: fan.iconSize
                fileUrl: slot.url
                iconName: slot.iconName
                mtime: slot.mtime
                isDir: slot.isDir
                dimmed: slot.partial
                scale: slot.hot ? 1.07 : 1
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            }

            ItemMouse {
                id: mouse
                anchors.fill: parent
                fileUrl: slot.url; iconName: slot.iconName; name: slot.name
                mtime: slot.mtime; kind: slot.kind; sizeText: slot.sizeText; isDir: slot.isDir
                onEntered: fan.current = slot.index
            }
        }
    }

    // Top of the fan: open the real folder (macOS "Open in Finder").
    Item {
        id: openSlot
        readonly property int index: fan.n
        readonly property real t: fan.slotProgress(index)
        readonly property real e: win.closing ? win.outCubic(t) : win.outBack(t, 1.25)
        readonly property real tx: fan.originX + fan.curve * index * index
        readonly property real ty: fan.baseY - fan.iconSize / 2 - index * fan.step + 8
        readonly property bool hot: openMouse.containsMouse || fan.current === index

        x: fan.originX + (tx - fan.originX) * e - width + 22
        y: (fan.baseY + fan.iconSize / 2) + (ty - fan.baseY - fan.iconSize / 2) * e - height / 2
        width: openLabel.width + 12 + 44
        height: 44
        opacity: Math.min(1, t * 2.2)
        rotation: index * fan.tilt * e
        transformOrigin: Item.Right
        scale: 0.35 + 0.65 * Math.min(1.08, e)

        Rectangle {
            id: openLabel
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: openCircle.left
            anchors.rightMargin: 12
            width: openText.implicitWidth + 20
            height: openText.implicitHeight + 8
            radius: height / 2
            color: openSlot.hot ? Kirigami.Theme.highlightColor : Qt.rgba(0.11, 0.11, 0.12, 0.82)
            border.width: 1
            border.color: openSlot.hot ? "transparent" : Qt.rgba(1, 1, 1, 0.10)
            QQC2.Label {
                id: openText
                anchors.centerIn: parent
                color: "white"
                font.weight: Font.Medium
                text: {
                    const more = stack.model.count - fan.n;
                    return (more > 0 ? qsTr("%1 more · ").arg(more) : "") + qsTr("Open in %1").arg(stack.fileManagerName);
                }
            }
        }
        Rectangle {
            id: openCircle
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 44; height: 44; radius: 22
            color: openSlot.hot ? Kirigami.Theme.highlightColor : Qt.rgba(0.17, 0.17, 0.18, 0.9)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.14)
            Kirigami.Icon {
                anchors.centerIn: parent
                width: 22; height: 22
                source: "go-next-symbolic"
                color: "white"
                isMask: true
            }
        }
        MouseArea {
            id: openMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onEntered: fan.current = openSlot.index
            onClicked: (m) => m.button === Qt.RightButton ? viewMenu.popup() : stack.openFolder()
        }
    }
}
