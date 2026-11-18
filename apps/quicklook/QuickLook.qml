/*
 * MacGlass — Quick Look
 * macOS-style instant preview for Dolphin (Space). Run by ~/.local/bin/macglass-quicklook.
 * Images (incl. animated), video, audio, PDF, text/code; anything else shows icon + info.
 * Space / Esc: close · Enter / "Open with": open in the default app.
 */
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtMultimedia
import QtQuick.Pdf
import org.kde.kirigami as Kirigami

QQC2.ApplicationWindow {
    id: win

    // ── passed in by the launcher (context properties via -- args) ─────────
    readonly property var args: Qt.application.arguments
    function arg(name, fallback) {
        const i = args.indexOf("--" + name);
        return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
    }
    readonly property string filePath: arg("file", "")
    readonly property string mime: arg("mime", "application/octet-stream")
    readonly property string appName: arg("app", "")
    readonly property string sizeText: arg("size", "")
    readonly property string modifiedText: arg("modified", "")
    readonly property string outputName: arg("output", "")
    readonly property url fileUrl: "file://" + filePath.split("/").map(encodeURIComponent).join("/")
    readonly property string fileName: filePath.substring(filePath.lastIndexOf("/") + 1)

    readonly property string kind: {
        if (mime === "application/pdf") return "pdf";
        if (mime.startsWith("image/")) return "image";
        if (mime.startsWith("video/")) return "video";
        if (mime.startsWith("audio/")) return "audio";
        if (mime.startsWith("text/") || /(json|xml|javascript|x-shellscript|x-yaml|toml|x-desktop|sql|x-python|x-perl|x-ruby|x-php)/.test(mime)) return "text";
        return "info";
    }

    title: fileName
    flags: Qt.Window
    color: Kirigami.Theme.backgroundColor
    visible: false   // shown once the content size is known (KWin ignores client resizes after mapping)
    screen: {
        const ss = Qt.application.screens;
        for (let i = 0; i < ss.length; ++i) if (ss[i].name === outputName) return ss[i];
        return Qt.application.screens[0];
    }

    // macOS sizes the panel to the content, capped to the screen
    readonly property int maxW: Math.round(screen.width * 0.62)
    readonly property int maxH: Math.round(screen.height * 0.78)
    function fit(w, h) {
        const k = Math.min(1, maxW / w, maxH / h);
        width = Math.max(420, Math.round(w * k));
        height = Math.max(260, Math.round(h * k));
        x = screen.virtualX + (screen.width - width) / 2;
        y = screen.virtualY + (screen.height - height) / 2;
    }
    function reveal() { if (!visible) { show(); raise(); requestActivate(); } }
    Timer { id: revealFallback; interval: 700; running: true; onTriggered: win.reveal() }
    Component.onCompleted: {
        if (kind === "pdf" || kind === "text") fit(Math.min(maxW, 900), maxH);
        else if (kind === "audio" || kind === "info") fit(520, 300);
        else fit(960, 600);
        if (kind !== "image" && kind !== "video") reveal();
    }

    function openExternally() { Qt.openUrlExternally(fileUrl); Qt.quit(); }

    Shortcut { sequences: ["Space", "Escape", StandardKey.Close]; onActivated: Qt.quit() }
    Shortcut { sequences: ["Return", "Enter"]; onActivated: win.openExternally() }

    // ── content ────────────────────────────────────────────────────────
    Loader {
        anchors.fill: parent
        sourceComponent: ({ image: imageView, video: videoView, audio: audioView, pdf: pdfView, text: textView, info: infoView })[win.kind]
    }

    // floating "Open with …" pill, top-right (macOS Quick Look style)
    // ToolButton + own pill: Darkly crashes drawing a QQC2 push button outside QWidgets
    QQC2.ToolButton {
        id: openBtn
        display: QQC2.AbstractButton.TextBesideIcon
        background: Rectangle {
            radius: height / 2
            color: openBtn.down ? Qt.rgba(0.2, 0.2, 0.22, 0.95) : Qt.rgba(0.12, 0.12, 0.13, openBtn.hovered ? 0.92 : 0.8)
            border.color: Qt.rgba(1, 1, 1, 0.12)
        }
        leftPadding: Kirigami.Units.largeSpacing; rightPadding: Kirigami.Units.largeSpacing
        z: 10
        anchors.top: parent.top; anchors.right: parent.right
        anchors.margins: Kirigami.Units.largeSpacing
        icon.name: "document-open"
        text: win.appName ? qsTr("Open with %1").arg(win.appName) : qsTr("Open")
        opacity: hover.hovered || win.kind === "info" || win.kind === "audio" ? 1 : 0.0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        onClicked: win.openExternally()
    }
    HoverHandler { id: hover }

    Component {
        id: imageView
        Rectangle {
            color: "#141416"
            Loader {
                anchors.fill: parent
                sourceComponent: /(gif|webp|apng)$/.test(win.mime) ? animated : still
            }
            Component { id: still; Image {
                anchors.fill: parent
                source: win.fileUrl
                fillMode: Image.PreserveAspectFit
                asynchronous: true; autoTransform: true; smooth: true; mipmap: true
                onStatusChanged: {
                    if (status === Image.Ready) { win.fit(implicitWidth, implicitHeight); win.reveal(); }
                    else if (status === Image.Error) { loaderFallback.visible = true; win.reveal(); }
                }
            } }
            Component { id: animated; AnimatedImage {
                id: img
                anchors.fill: parent
                source: win.fileUrl
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                autoTransform: true
                smooth: true; mipmap: true
                onStatusChanged: {
                    if (status === Image.Ready) { win.fit(implicitWidth, implicitHeight); win.reveal(); }
                    else if (status === Image.Error) { loaderFallback.visible = true; win.reveal(); }
                }
            } }
            QQC2.Label { id: loaderFallback; visible: false; anchors.centerIn: parent; text: qsTr("Can't preview this image") }
        }
    }

    Component {
        id: videoView
        Rectangle {
            color: "black"
            MediaPlayer {
                id: player
                source: win.fileUrl
                videoOutput: vout
                audioOutput: AudioOutput {}
                Component.onCompleted: play()
                onMetaDataChanged: {
                    const r = metaData.value(MediaMetaData.Resolution);
                    if (r && r.width > 0) { win.fit(r.width, r.height + 44); win.reveal(); }
                }
            }
            VideoOutput { id: vout; anchors.fill: parent; anchors.bottomMargin: 44 }
            MediaBar { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; player: player }
            TapHandler { onTapped: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
        }
    }

    Component {
        id: audioView
        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing
            MediaPlayer {
                id: aplayer
                source: win.fileUrl
                audioOutput: AudioOutput {}
                Component.onCompleted: play()
            }
            Item { Layout.fillHeight: true }
            Kirigami.Icon { Layout.alignment: Qt.AlignHCenter; source: win.mime.replace("/", "-"); fallback: "audio-x-generic"; implicitWidth: 96; implicitHeight: 96 }
            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter; Layout.maximumWidth: win.width - 40
                text: aplayer.metaData.stringValue(MediaMetaData.Title) || win.fileName
                font.weight: Font.DemiBold; elide: Text.ElideRight
            }
            QQC2.Label { Layout.alignment: Qt.AlignHCenter; opacity: 0.7; text: aplayer.metaData.stringValue(MediaMetaData.ContributingArtist) || aplayer.metaData.stringValue(MediaMetaData.AlbumArtist) || "" }
            Item { Layout.fillHeight: true }
            MediaBar { Layout.fillWidth: true; player: aplayer }
        }
    }

    component MediaBar: Rectangle {
        required property MediaPlayer player
        height: 44
        color: Qt.rgba(0, 0, 0, 0.55)
        function fmt(ms) { const s = Math.floor(ms / 1000); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 12
            QQC2.ToolButton {
                icon.name: player.playbackState === MediaPlayer.PlayingState ? "media-playback-pause" : "media-playback-start"
                onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
            }
            QQC2.Label { text: fmt(player.position); font.features: ({ "tnum": 1 }); color: "white" }
            QQC2.Slider {
                Layout.fillWidth: true
                from: 0; to: Math.max(1, player.duration); value: player.position
                onMoved: player.position = value
            }
            QQC2.Label { text: fmt(player.duration); font.features: ({ "tnum": 1 }); color: "white" }
        }
    }

    Component {
        id: pdfView
        PdfMultiPageView {
            document: PdfDocument { source: win.fileUrl }
        }
    }

    Component {
        id: textView
        QQC2.ScrollView {
            QQC2.TextArea {
                id: ta
                readOnly: true
                wrapMode: TextEdit.NoWrap
                textFormat: TextEdit.PlainText
                font.family: "JetBrains Mono"
                font.pointSize: 10
                leftPadding: Kirigami.Units.largeSpacing * 2; topPadding: Kirigami.Units.largeSpacing
                background: Rectangle { color: Kirigami.Theme.backgroundColor }
                Component.onCompleted: {
                    const xhr = new XMLHttpRequest();
                    xhr.onreadystatechange = () => {
                        if (xhr.readyState === XMLHttpRequest.DONE)
                            text = xhr.responseText.length > 400000 ? xhr.responseText.substring(0, 400000) + "\n…" : xhr.responseText;
                    };
                    xhr.open("GET", win.fileUrl); xhr.send();
                }
            }
        }
    }

    Component {
        id: infoView
        RowLayout {
            spacing: Kirigami.Units.gridUnit
            Item { Layout.preferredWidth: Kirigami.Units.gridUnit }
            Kirigami.Icon { source: win.mime.replace("/", "-"); fallback: "unknown"; implicitWidth: 128; implicitHeight: 128 }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                QQC2.Label { Layout.fillWidth: true; text: win.fileName; font.weight: Font.DemiBold; font.pointSize: 13; wrapMode: Text.WrapAnywhere; maximumLineCount: 3; elide: Text.ElideRight }
                QQC2.Label { text: win.mime; opacity: 0.7 }
                QQC2.Label { text: win.sizeText; opacity: 0.7; visible: text.length > 0 }
                QQC2.Label { text: win.modifiedText ? qsTr("Modified %1").arg(win.modifiedText) : ""; opacity: 0.7; visible: text.length > 0 }
            }
        }
    }
}
