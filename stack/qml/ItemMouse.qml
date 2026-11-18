// SPDX-License-Identifier: GPL-3.0-or-later
// Shared interaction for a stack item: click = open, right-click = menu,
// press-and-move = drag the real file out (QDrag with text/uri-list).
import QtQuick

MouseArea {
    id: area
    property url fileUrl
    property string iconName
    property string name
    property var mtime: 0
    property string kind
    property string sizeText
    property bool isDir: false

    signal activated()

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor

    property point pressPos
    property bool dragStarted: false

    onPressed: (mouse) => {
        pressPos = Qt.point(mouse.x, mouse.y);
        dragStarted = false;
    }
    onPositionChanged: (mouse) => {
        if (!(pressedButtons & Qt.LeftButton) || dragStarted)
            return;
        if (Math.hypot(mouse.x - pressPos.x, mouse.y - pressPos.y) > 8) {
            dragStarted = true;
            stack.startDrag(fileUrl, iconName);
        }
    }
    onClicked: (mouse) => {
        if (dragStarted)
            return;
        if (mouse.button === Qt.RightButton) {
            itemMenu.openFor(area, fileUrl, name, iconName, mtime, kind, sizeText, isDir);
        } else {
            area.activated();
            stack.open(fileUrl);
        }
    }
}
