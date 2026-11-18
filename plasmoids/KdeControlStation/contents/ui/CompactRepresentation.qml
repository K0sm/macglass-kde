import QtQml 2.15
import QtQuick 2.15
import QtQuick.Layouts 1.15

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
// MacGlass patch: tray-sized icon (not panel-height) + macOS open/hover highlight.
MouseArea {
    id: compactRep

    readonly property bool useCustomButtonImage: (Plasmoid.configuration.useCustomButtonImage && Plasmoid.configuration.customButtonImage.length != 0)

    Layout.minimumWidth: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing * 2
    Layout.preferredWidth: Layout.minimumWidth
    Layout.maximumWidth: Layout.minimumWidth
    Layout.fillHeight: true
    hoverEnabled: true
    onClicked: root.expanded = !root.expanded

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 4; anchors.bottomMargin: 4
        radius: 6
        color: Kirigami.Theme.textColor
        opacity: root.expanded ? 0.16 : (compactRep.containsMouse ? 0.08 : 0)
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    Kirigami.Icon {
        anchors.centerIn: parent
        width: Kirigami.Units.iconSizes.smallMedium
        height: width
        source: compactRep.useCustomButtonImage ? Plasmoid.configuration.customButtonImage : Plasmoid.configuration.icon
        smooth: true
    }
}
