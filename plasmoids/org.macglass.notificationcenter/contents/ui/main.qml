/*
 * MacGlass — Clock & Notification Center
 *
 * Menu bar: "Wed 18 Nov  12:44" (tabular digits, so the bar never shifts),
 * plus a moon when Do Not Disturb is on — like macOS.
 * Click: Notification Center — notification history (newest first, click to
 * open, hover to dismiss, Clear All) above a calendar widget.
 *
 * Popups are still produced by Plasma's own Notifications applet (kept
 * hidden in the tray); this widget reads the same history through the
 * public org.kde.notificationmanager module and marks it read when opened.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils
import org.kde.notificationmanager as NotificationManager
import org.kde.plasma.workspace.calendar as PlasmaCalendar

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: compactRepresentation
    switchWidth: Kirigami.Units.gridUnit * 1000
    switchHeight: Kirigami.Units.gridUnit * 1000

    // ── time ─────────────────────────────────────────────
    property date now: new Date()
    property date today: new Date(now.getFullYear(), now.getMonth(), now.getDate())

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            const d = new Date();
            const step = Plasmoid.configuration.showSeconds ? 1000 : 60000;
            if (Math.floor(d.getTime() / step) !== Math.floor(root.now.getTime() / step))
                root.now = d;
            if (d.getDate() !== root.today.getDate() || d.getMonth() !== root.today.getMonth())
                root.today = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        }
    }

    readonly property string timeText: Qt.formatTime(now,
        (Plasmoid.configuration.use24h ? "HH:mm" : "h:mm AP") + (Plasmoid.configuration.showSeconds ? ":ss" : ""))
    readonly property string dateText: Qt.formatDate(now, Plasmoid.configuration.dateFormat)

    toolTipMainText: Qt.formatDate(now, Qt.locale().dateFormat(Locale.LongFormat))
    toolTipSubText: unreadCount > 0 ? i18np("%1 unread notification", "%1 unread notifications", unreadCount) : ""

    // ── notifications ────────────────────────────────────
    NotificationManager.Settings { id: notificationSettings }

    readonly property bool dndActive: {
        root.now; // re-check every minute
        const until = notificationSettings.notificationsInhibitedUntil;
        return (!isNaN(until) && until > new Date()) || notificationSettings.notificationsInhibitedByApplication;
    }

    NotificationManager.Notifications {
        id: historyModel
        showExpired: true
        showDismissed: true
        showAddedDuringInhibition: true
        showJobs: false
        showNotifications: true
        // honours System Settings → Notifications → "Show in history" per app (incl. @other)
        blacklistedDesktopEntries: notificationSettings.historyBlacklistedApplications
        blacklistedNotifyRcNames: notificationSettings.historyBlacklistedServices
        urgencies: NotificationManager.Notifications.LowUrgency
                 | NotificationManager.Notifications.NormalUrgency
                 | NotificationManager.Notifications.CriticalUrgency
        sortMode: NotificationManager.Notifications.SortByDate
        sortOrder: Qt.DescendingOrder
        groupMode: NotificationManager.Notifications.GroupDisabled
        lastRead: Plasmoid.configuration.lastRead ? new Date(Plasmoid.configuration.lastRead) : new Date(0)
    }
    readonly property int unreadCount: historyModel.unreadNotificationsCount

    function markRead() {
        Plasmoid.configuration.lastRead = new Date().toISOString();
    }
    onExpandedChanged: () => { if (root.expanded) root.markRead(); }

    function clearAll() {
        historyModel.clear(NotificationManager.Notifications.ClearExpired);
        for (let i = historyModel.count - 1; i >= 0; --i) {
            const idx = historyModel.index(i, 0);
            if (historyModel.data(idx, NotificationManager.Notifications.ClosableRole))
                historyModel.close(idx);
        }
    }

    function ago(d) {
        if (!d || isNaN(d)) return "";
        const mins = Math.floor((root.now.getTime() - d.getTime()) / 60000);
        if (mins < 1) return i18n("now");
        if (mins < 60) return i18n("%1m ago", mins);
        const hours = Math.floor(mins / 60);
        if (hours < 24) return i18n("%1h ago", hours);
        return Qt.formatDate(d, "d MMM");
    }

    // ── menu bar ─────────────────────────────────────────
    compactRepresentation: MouseArea {
        id: bar
        Layout.minimumWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        Rectangle {   // macOS-style pressed/open highlight
            anchors.fill: parent
            anchors.topMargin: 4; anchors.bottomMargin: 4
            radius: 6
            color: Kirigami.Theme.textColor
            opacity: root.expanded ? 0.16 : (bar.containsMouse ? 0.08 : 0)
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Math.round(Kirigami.Units.smallSpacing * 1.5)   // macOS: one wide space between date and time

            Kirigami.Icon {
                visible: root.dndActive
                source: "weather-clear-night-symbolic"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
            }
            PC3.Label {
                text: root.dateText
                font.features: { "tnum": 1 }
                textFormat: Text.PlainText
            }
            PC3.Label {
                text: root.timeText
                font.features: { "tnum": 1 }
                textFormat: Text.PlainText
            }
        }
    }

    // ── Notification Center ──────────────────────────────
    fullRepresentation: PlasmaExtras.Representation {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        Layout.minimumWidth: Layout.preferredWidth
        Layout.maximumWidth: Layout.preferredWidth
        // grows with the notification list, like macOS; scrolls past ~6 cards
        Layout.preferredHeight: Math.min(Kirigami.Units.gridUnit * 40,
            Math.max(Kirigami.Units.gridUnit * 8, list.contentHeight) + Kirigami.Units.gridUnit * 21)
        Layout.minimumHeight: Layout.preferredHeight
        Layout.maximumHeight: Layout.preferredHeight
        collapseMarginsHint: false

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 4
                    font.weight: Font.DemiBold
                    text: i18n("Notifications")
                }
                PC3.ToolButton {
                    visible: historyModel.count > 0
                    text: i18n("Clear All")
                    onClicked: root.clearAll()
                }
            }

            PC3.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff

                ListView {
                    id: list
                    model: historyModel
                    spacing: Kirigami.Units.smallSpacing * 2
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160 } }
                    remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 120 } }
                    displaced: Transition { NumberAnimation { property: "y"; duration: 160; easing.type: Easing.OutCubic } }

                    PlasmaExtras.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.gridUnit * 2
                        visible: list.count === 0
                        iconName: root.dndActive ? "weather-clear-night-symbolic" : "notifications-symbolic"
                        text: i18n("No Notifications")
                        explanation: root.dndActive ? i18n("Do Not Disturb is on") : ""
                    }

                    delegate: Rectangle {
                        id: card
                        required property int index
                        required property var model

                        width: ListView.view.width
                        implicitHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2
                        radius: 14
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b,
                                       hover.hovered ? 0.11 : 0.065)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.07)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        HoverHandler { id: hover }
                        TapHandler {
                            enabled: card.model.hasDefaultAction === true
                            onTapped: {
                                historyModel.invokeDefaultAction(historyModel.index(card.index, 0),
                                                                 NotificationManager.Notifications.Close);
                                root.expanded = false;
                            }
                        }

                        RowLayout {
                            id: content
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.largeSpacing

                            Kirigami.Icon {
                                Layout.alignment: Qt.AlignTop
                                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                                source: card.model.applicationIconName || card.model.iconName || "preferences-desktop-notification-bell"
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                RowLayout {
                                    Layout.fillWidth: true
                                    PC3.Label {
                                        Layout.fillWidth: true
                                        text: card.model.applicationName || ""
                                        font: Kirigami.Theme.smallFont
                                        opacity: 0.7
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                    }
                                    PC3.Label {
                                        visible: !hover.hovered || !card.model.closable
                                        text: root.ago(card.model.updated || card.model.created)
                                        font: Kirigami.Theme.smallFont
                                        opacity: 0.6
                                        textFormat: Text.PlainText
                                    }
                                    PC3.ToolButton {
                                        visible: hover.hovered && card.model.closable === true
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                                        Layout.preferredHeight: Layout.preferredWidth
                                        icon.name: "window-close-symbolic"
                                        display: PC3.AbstractButton.IconOnly
                                        text: i18n("Dismiss")
                                        onClicked: historyModel.close(historyModel.index(card.index, 0))
                                    }
                                }
                                PC3.Label {
                                    Layout.fillWidth: true
                                    text: card.model.summary || ""
                                    font.weight: Font.DemiBold
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                }
                                PC3.Label {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: card.model.body || ""
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                    textFormat: Text.StyledText
                                    opacity: 0.88
                                    onLinkActivated: link => Qt.openUrlExternally(link)
                                }
                            }
                        }
                    }
                }
            }

            // Calendar widget card
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 15
                radius: 16
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.065)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.07)

                PlasmaCalendar.MonthView {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing * 2
                    today: root.today
                    showWeekNumbers: false
                    borderOpacity: 0
                }
            }

            PC3.ToolButton {
                Layout.alignment: Qt.AlignRight
                icon.name: "configure"
                text: i18n("Notification Settings…")
                onClicked: KCMUtils.KCMLauncher.openSystemSettings("kcm_notifications")
            }
        }
    }
}
