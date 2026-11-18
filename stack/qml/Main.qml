// SPDX-License-Identifier: GPL-3.0-or-later
// MacGlass Downloads stack — root window (a transparent layer-shell overlay).
import QtQuick
import QtQuick.Window
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Window {
    id: win
    visible: false
    color: "transparent"
    flags: Qt.FramelessWindowHint
    title: "Downloads Stack"

    // 0 = collapsed into the dock icon, 1 = fully open. Each view derives its
    // own (staggered / eased) motion from this single driver.
    property real progress: 0
    property bool closing: false
    readonly property string view: stack.effectiveView

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    Connections {
        target: stack
        function onOpenRequested() {
            win.closing = false;
            quickLook.close();
            closeAnim.stop();
            win.progress = 0;
            root.opacity = 1;
            openAnim.restart();
            root.forceActiveFocus();
        }
        function onDragStarted() {
            openAnim.stop();
            closeAnim.stop();
            root.opacity = 0;
        }
        function onCloseRequested() {
            win.closing = true;
            openAnim.stop();
            closeAnim.restart();
        }
    }

    NumberAnimation {
        id: openAnim
        target: win; property: "progress"; to: 1
        duration: win.view === "fan" ? 420 : 300
        easing.type: Easing.Linear
    }
    NumberAnimation {
        id: closeAnim
        target: win; property: "progress"; to: 0
        duration: win.view === "fan" ? 230 : 170
        easing.type: Easing.Linear
        onFinished: stack.finishClose()
    }

    // Easing helpers shared by the views.
    function outBack(t, amount) {
        const c1 = amount === undefined ? 1.15 : amount, c3 = c1 + 1;
        return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
    }
    function outCubic(t) { return 1 - Math.pow(1 - t, 3); }
    function outQuint(t) { return 1 - Math.pow(1 - t, 5); }

    Item {
        id: root
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: quickLook.visible ? quickLook.close() : stack.Hide()

        // Click anywhere outside the stack closes it, like macOS.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: quickLook.visible ? quickLook.close() : stack.Hide()
        }

        Loader {
            id: viewLoader
            anchors.fill: parent
            focus: true
            sourceComponent: win.view === "fan" && stack.model.count > 0 ? fanComponent : panelComponent
        }

        Component {
            id: fanComponent
            FanView { focus: true }
        }
        Component {
            id: panelComponent
            PanelView { focus: true; mode: win.view === "list" ? "list" : "grid" }
        }

        QuickLook { id: quickLook; anchors.fill: parent }
    }

    function quickLookAt(url, name, iconName, mtime, kind, sizeText) {
        quickLook.show(url, name, iconName, mtime, kind, sizeText);
    }

    ItemMenu { id: itemMenu }
    ViewMenu { id: viewMenu }
}
