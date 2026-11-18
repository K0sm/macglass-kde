// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls as QQC2

QQC2.Menu {
    id: menu
    QQC2.MenuItem { enabled: false; text: qsTr("View Content As") }
    Repeater {
        model: [ { v: "auto", t: qsTr("Automatic") }, { v: "fan", t: qsTr("Fan") }, { v: "grid", t: qsTr("Grid") }, { v: "list", t: qsTr("List") } ]
        delegate: QQC2.MenuItem {
            required property var modelData
            text: modelData.t
            checkable: true
            checked: stack.view === modelData.v
            onTriggered: stack.setView(modelData.v)
        }
    }
    QQC2.MenuSeparator {}
    QQC2.MenuItem { enabled: false; text: qsTr("Sort By") }
    Repeater {
        model: [ { v: "date", t: qsTr("Date Added") }, { v: "name", t: qsTr("Name") }, { v: "kind", t: qsTr("Kind") } ]
        delegate: QQC2.MenuItem {
            required property var modelData
            text: modelData.t
            checkable: true
            checked: stack.model.sortMode === modelData.v
            onTriggered: stack.setSort(modelData.v)
        }
    }
    QQC2.MenuSeparator {}
    QQC2.MenuItem { text: qsTr("Open in %1").arg(stack.fileManagerName); icon.name: "document-open-folder"; onTriggered: stack.openFolder() }
}
