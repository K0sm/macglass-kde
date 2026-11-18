// SPDX-License-Identifier: GPL-3.0-or-later
// Grid / List stack: a frosted-glass panel that zooms out of the dock icon.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: pv
    property string mode: "grid"           // "grid" | "list"

    readonly property int count: stack.model.count
    readonly property bool empty: count === 0
    readonly property int pad: 14
    readonly property int radius: 16
    readonly property int cellW: 112
    readonly property int cellH: 118
    readonly property int rowH: 44
    readonly property int cols: Math.max(1, Math.min(stack.gridColumns, count))
    readonly property int headerH: 44
    readonly property int footerH: 44
    readonly property real maxBodyH: Math.max(200, height * 0.66 - headerH - footerH)
    readonly property real bodyH: empty ? 150
        : mode === "grid" ? Math.min(Math.ceil(count / cols) * cellH, maxBodyH)
                          : Math.min(count * rowH, maxBodyH)
    readonly property real panelW: empty ? 300 : mode === "grid" ? Math.max(340, cols * cellW + 2 * pad) : 380
    readonly property real panelH: headerH + bodyH + footerH
    readonly property real e: win.closing ? win.outCubic(win.progress) : win.outBack(win.progress, 0.9)

    Keys.forwardTo: [body.item]

    Kirigami.ShadowedRectangle {
        id: panel
        width: pv.panelW
        height: pv.panelH
        x: Math.max(12, Math.min(pv.width - width - 12, stack.anchorX - width / 2))
        y: pv.height - height - 16
        radius: pv.radius
        color: Qt.rgba(0.11, 0.11, 0.12, 0.72)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)
        shadow.size: 30
        shadow.yOffset: 10
        shadow.color: Qt.rgba(0, 0, 0, 0.50)

        opacity: Math.min(1, win.progress * 1.7)
        transform: Scale {
            origin.x: stack.anchorX - panel.x
            origin.y: panel.height + 16
            xScale: 0.12 + 0.88 * pv.e
            yScale: 0.12 + 0.88 * pv.e
        }

        // Blur behind only once fully open (the region can't follow the zoom).
        readonly property bool settled: win.progress >= 1 && !win.closing
        function syncBlur() {
            if (settled)
                stack.setBlurRect(x, y, width, height, pv.radius);
            else
                stack.clearBlur();
        }
        onSettledChanged: syncBlur()
        onWidthChanged: if (settled) syncBlur()
        onHeightChanged: if (settled) syncBlur()

        // Swallow clicks so they don't close the stack.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (m) => { if (m.button === Qt.RightButton) viewMenu.popup() }
        }

        // ---- header ---------------------------------------------------
        RowLayout {
            id: header
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: pv.pad + 4; rightMargin: pv.pad - 4 }
            height: pv.headerH
            QQC2.Label {
                text: stack.model.folderName
                font.weight: Font.Bold
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            QQC2.Label {
                visible: !pv.empty
                text: qsTr("%n item(s)", "", pv.count)
                opacity: 0.55
            }
            Repeater {
                model: [ { v: "fan", icon: "view-list-tree" }, { v: "grid", icon: "view-list-icons" }, { v: "list", icon: "view-list-details" } ]
                QQC2.ToolButton {
                    required property var modelData
                    icon.name: modelData.icon
                    checkable: true
                    checked: win.view === modelData.v
                    display: QQC2.AbstractButton.IconOnly
                    QQC2.ToolTip.text: modelData.v === "fan" ? qsTr("Fan") : modelData.v === "grid" ? qsTr("Grid") : qsTr("List")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: 500
                    onClicked: stack.setView(modelData.v)
                }
            }
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: header.bottom }
            height: 1; color: Qt.rgba(1, 1, 1, 0.07)
        }

        // ---- body ------------------------------------------------------
        Loader {
            id: body
            anchors { left: parent.left; right: parent.right; top: header.bottom; leftMargin: pv.pad; rightMargin: pv.pad }
            height: pv.bodyH
            focus: true
            sourceComponent: pv.empty ? emptyComp : pv.mode === "grid" ? gridComp : listComp
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: footer.top }
            height: 1; color: Qt.rgba(1, 1, 1, 0.07)
        }

        // ---- footer ----------------------------------------------------
        RowLayout {
            id: footer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: pv.pad; rightMargin: pv.pad }
            height: pv.footerH
            Item { Layout.fillWidth: true }
            QQC2.Button {
                flat: true
                text: qsTr("Open in %1").arg(stack.fileManagerName)
                icon.name: "go-next-symbolic"
                onClicked: stack.openFolder()
            }
        }
    }

    // little pointer towards the dock icon
    Rectangle {
        width: 16; height: 16
        rotation: 45
        x: stack.anchorX - width / 2
        y: panel.y + panel.height - height / 2 - 1
        color: Qt.rgba(0.11, 0.11, 0.12, 0.72)
        border.width: 0
        opacity: panel.opacity
        visible: win.progress > 0.6
        z: -1
    }

    // ---- views ---------------------------------------------------------
    Component {
        id: gridComp
        GridView {
            id: grid
            clip: true
            focus: true
            cellWidth: (width) / pv.cols
            cellHeight: pv.cellH
            model: stack.model
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: true
            currentIndex: 0
            highlightFollowsCurrentItem: true
            QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
            Keys.onReturnPressed: if (currentItem) stack.open(currentItem.fileUrl)
            Keys.onSpacePressed: if (currentItem) currentItem.look()

            delegate: Item {
                id: cell
                required property int index
                required property url url
                required property string name
                required property string iconName
                required property var mtime
                required property string kind
                required property string sizeText
                required property bool isDir
                required property bool partial
                readonly property url fileUrl: url
                function look() { win.quickLookAt(url, name, iconName, mtime, kind, sizeText) }

                width: grid.cellWidth
                height: grid.cellHeight
                readonly property bool hot: ma.containsMouse

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: 10
                    color: GridView.isCurrentItem && grid.activeFocus && !cell.hot ? Qt.rgba(0.04, 0.52, 1, 0.28)
                         : cell.hot ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                    Behavior on color { ColorAnimation { duration: 90 } }
                }
                Thumb {
                    id: th
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 10
                    size: 64
                    fileUrl: cell.url; iconName: cell.iconName; mtime: cell.mtime; isDir: cell.isDir
                    dimmed: cell.partial
                    scale: cell.hot ? 1.06 : 1
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }
                QQC2.Label {
                    anchors { top: th.bottom; topMargin: 6; left: parent.left; right: parent.right; leftMargin: 6; rightMargin: 6 }
                    text: cell.name
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
                ItemMouse {
                    id: ma
                    anchors.fill: parent
                    fileUrl: cell.url; iconName: cell.iconName; name: cell.name
                    mtime: cell.mtime; kind: cell.kind; sizeText: cell.sizeText; isDir: cell.isDir
                    onEntered: grid.currentIndex = cell.index
                }
            }
        }
    }

    Component {
        id: listComp
        ListView {
            id: list
            clip: true
            focus: true
            model: stack.model
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: true
            currentIndex: 0
            QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
            Keys.onReturnPressed: if (currentItem) stack.open(currentItem.fileUrl)
            Keys.onSpacePressed: if (currentItem) currentItem.look()

            delegate: Item {
                id: row
                required property int index
                required property url url
                required property string name
                required property string iconName
                required property var mtime
                required property string kind
                required property string sizeText
                required property string dateText
                required property bool isDir
                required property bool partial
                readonly property url fileUrl: url
                function look() { win.quickLookAt(url, name, iconName, mtime, kind, sizeText) }

                width: ListView.view.width
                height: pv.rowH
                readonly property bool hot: ma.containsMouse

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 2; anchors.bottomMargin: 2
                    radius: 8
                    color: ListView.isCurrentItem && list.activeFocus && !row.hot ? Qt.rgba(0.04, 0.52, 1, 0.28)
                         : row.hot ? Kirigami.Theme.highlightColor : "transparent"
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8; anchors.rightMargin: 10
                    spacing: 10
                    Thumb {
                        size: 30
                        Layout.preferredWidth: 30; Layout.preferredHeight: 30
                        fileUrl: row.url; iconName: row.iconName; mtime: row.mtime; isDir: row.isDir
                        dimmed: row.partial
                    }
                    QQC2.Label {
                        text: row.name
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        color: row.hot ? "white" : Kirigami.Theme.textColor
                    }
                    QQC2.Label {
                        text: row.partial ? qsTr("Downloading…") : row.dateText
                        opacity: row.hot ? 0.9 : 0.5
                        color: row.hot ? "white" : Kirigami.Theme.textColor
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                }
                ItemMouse {
                    id: ma
                    anchors.fill: parent
                    fileUrl: row.url; iconName: row.iconName; name: row.name
                    mtime: row.mtime; kind: row.kind; sizeText: row.sizeText; isDir: row.isDir
                    onEntered: list.currentIndex = row.index
                }
            }
        }
    }

    Component {
        id: emptyComp
        ColumnLayout {
            spacing: 8
            Item { Layout.fillHeight: true }
            Kirigami.Icon {
                source: "folder-download"
                Layout.preferredWidth: 56; Layout.preferredHeight: 56
                Layout.alignment: Qt.AlignHCenter
                opacity: 0.55
            }
            QQC2.Label {
                text: qsTr("No Items")
                font.weight: Font.DemiBold
                Layout.alignment: Qt.AlignHCenter
                opacity: 0.75
            }
            QQC2.Label {
                text: qsTr("Files you download will appear here.")
                Layout.alignment: Qt.AlignHCenter
                opacity: 0.5
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
            Item { Layout.fillHeight: true }
        }
    }
}
