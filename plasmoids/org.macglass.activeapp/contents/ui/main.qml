/*
 * MacGlass — Active Application Name
 * Shows the active application's name in bold, like the macOS menu bar.
 * Uses Plasma's own task model (org.kde.taskmanager), so it tracks focus
 * exactly like the Global Menu applet does, on Wayland and XWayland.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    property string appName: ""

    function refresh() {
        const idx = tasks.activeTask;
        if (idx && idx.valid) {
            const name = tasks.data(idx, TaskManager.AbstractTasksModel.AppName)
                      || tasks.data(idx, Qt.DisplayRole) || "";
            appName = name;
        } else {
            appName = "";
        }
    }

    TaskManager.VirtualDesktopInfo { id: vdInfo }
    TaskManager.ActivityInfo { id: actInfo }

    TaskManager.TasksModel {
        id: tasks
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortDisabled
        filterByScreen: Plasmoid.configuration.onlyThisScreen
        screenGeometry: Plasmoid.containment.screenGeometry
        virtualDesktop: vdInfo.currentDesktop
        activity: actInfo.currentActivity
        onActiveTaskChanged: root.refresh()
        onDataChanged: root.refresh()
        onCountChanged: root.refresh()
    }

    Component.onCompleted: refresh()

    fullRepresentation: MouseArea {
        id: area
        Layout.minimumWidth: label.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
        Layout.fillHeight: true
        hoverEnabled: true
        acceptedButtons: Qt.NoButton

        PC3.Label {
            id: label
            anchors.centerIn: parent
            width: Math.min(implicitWidth, area.Layout.maximumWidth)
            text: root.appName.length ? root.appName : Plasmoid.configuration.fallbackText
            font.weight: Font.Bold
            elide: Text.ElideRight
            textFormat: Text.PlainText

            Behavior on text {
                SequentialAnimation {
                    NumberAnimation { target: label; property: "opacity"; to: 0.35; duration: 70; easing.type: Easing.OutCubic }
                    PropertyAction {}
                    NumberAnimation { target: label; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
