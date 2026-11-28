import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

// MPRIS now-playing card. Rounded art is drawn with Canvas so it also works
// on the software scene graph (no shader effects).
Item {
    id: view
    required property var app
    implicitWidth: 460
    implicitHeight: 172

    property var chosen: null
    readonly property var players: Mpris.players.values
    readonly property var player: chosen && players.indexOf(chosen) >= 0 ? chosen : app.player
    readonly property bool hasPlayer: player !== null
    readonly property real length: hasPlayer && player.lengthSupported ? player.length : 0

    function time(value) {
        const n = Math.max(0, Math.floor(value))
        const h = Math.floor(n / 3600), m = Math.floor(n % 3600 / 60), s = String(n % 60).padStart(2, "0")
        return h > 0 ? h + ":" + String(m).padStart(2, "0") + ":" + s : m + ":" + s
    }
    function cycle() {
        if (players.length < 2) return
        chosen = players[(players.indexOf(player) + 1) % players.length]
    }

    // MPRIS does not stream position; poll it only while visible and playing.
    Timer {
        interval: 1000; repeat: true
        running: view.hasPlayer && view.player.isPlaying && view.player.positionSupported
        onTriggered: view.player.positionChanged()
    }

    component Control: Rectangle {
        id: control
        property string glyph: ""
        property bool primary: false
        property bool lit: false
        signal pressed()
        implicitWidth: primary ? 44 : 32
        implicitHeight: implicitWidth
        radius: implicitWidth / 2
        opacity: enabled ? 1 : 0.3
        color: primary ? (mouse.containsMouse ? Qt.lighter(view.app.accent, 1.15) : view.app.accent)
             : mouse.containsMouse ? Qt.alpha(view.app.accent, 0.18) : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            anchors.centerIn: parent
            text: control.glyph
            color: control.primary ? view.app.bg : control.lit ? view.app.accent : view.app.fg
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: control.primary ? 18 : 15
        }
        Rectangle {
            visible: control.lit && !control.primary
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 2 }
            width: 4; height: 4; radius: 2; color: view.app.accent
        }
        MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: control.pressed() }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 18

        Item {
            id: cover
            Layout.preferredWidth: 150
            Layout.preferredHeight: 150
            Layout.alignment: Qt.AlignVCenter
            readonly property string url: view.hasPlayer ? view.player.trackArtUrl : ""

            Image {
                id: art
                visible: false
                source: cover.url
                asynchronous: true
                cache: true
                onStatusChanged: canvas.requestPaint()
            }
            Canvas {
                id: canvas
                anchors.fill: parent
                renderStrategy: Canvas.Immediate
                property color accent: view.app.accent
                property color base: view.app.bg
                onAccentChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d"), r = 16, w = width, h = height
                    ctx.reset()
                    ctx.beginPath()
                    ctx.moveTo(r, 0); ctx.arcTo(w, 0, w, h, r); ctx.arcTo(w, h, 0, h, r)
                    ctx.arcTo(0, h, 0, 0, r); ctx.arcTo(0, 0, w, 0, r); ctx.closePath()
                    ctx.clip()
                    if (art.status === Image.Ready && art.implicitWidth > 0) {
                        // Center-crop to a square so video thumbnails don't stretch.
                        const iw = art.implicitWidth, ih = art.implicitHeight, s = Math.min(iw, ih)
                        ctx.drawImage(art, (iw - s) / 2, (ih - s) / 2, s, s, 0, 0, w, h)
                    } else {
                        const g = ctx.createLinearGradient(0, 0, w, h)
                        g.addColorStop(0, Qt.alpha(accent, 0.45))
                        g.addColorStop(1, Qt.alpha(accent, 0.08))
                        ctx.fillStyle = base; ctx.fillRect(0, 0, w, h)
                        ctx.fillStyle = g; ctx.fillRect(0, 0, w, h)
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: art.status !== Image.Ready
                text: "󰝚"
                color: view.app.fg
                opacity: 0.8
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 44
            }
            Rectangle {
                anchors.fill: parent
                radius: 16
                color: "transparent"
                border.color: Qt.alpha(view.app.accent, 0.4)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Rectangle {
                    implicitHeight: 20
                    implicitWidth: source.implicitWidth + 16
                    radius: 10
                    color: sourceMouse.containsMouse && view.players.length > 1 ? Qt.alpha(view.app.accent, 0.28) : Qt.alpha(view.app.accent, 0.14)
                    Text {
                        id: source
                        anchors.centerIn: parent
                        text: (view.hasPlayer ? view.player.identity : "No player").toUpperCase() + (view.players.length > 1 ? "  ⇄" : "")
                        color: view.app.accent
                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9; font.letterSpacing: 1.5; font.bold: true
                    }
                    MouseArea {
                        id: sourceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: view.players.length > 1
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.cycle()
                    }
                }
                Item { Layout.fillWidth: true }
                Control {
                    glyph: "󰏌"
                    visible: view.hasPlayer && view.player.canRaise
                    implicitWidth: 24
                    onPressed: { view.player.raise(); view.app.popup = "" }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 6
                text: view.hasPlayer && view.player.trackTitle ? view.player.trackTitle : "Nothing playing"
                elide: Text.ElideRight
                color: view.app.fg
                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16; font.bold: true
            }
            Text {
                Layout.fillWidth: true
                text: view.hasPlayer ? (view.player.trackArtist || "Unknown artist") : "Open a music player"
                elide: Text.ElideRight
                color: view.app.fg; opacity: 0.7
                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12
            }
            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: view.hasPlayer ? view.player.trackAlbum : ""
                elide: Text.ElideRight
                color: view.app.fg; opacity: 0.4
                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10
            }

            Item { Layout.fillHeight: true }

            ThemedSlider {
                id: progress
                Layout.fillWidth: true
                accent: view.app.accent
                ink: view.app.fg
                from: 0; to: Math.max(1, view.length)
                enabled: view.hasPlayer && view.player.canSeek && view.length > 0
                wheelEnabled: false
                Binding on value { value: view.hasPlayer ? view.player.position : 0; when: !progress.pressed; restoreMode: Binding.RestoreNone }
                // Seek once on release instead of flooding the player on every pixel.
                onPressedChanged: if (!pressed && enabled) view.player.position = value
            }
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: view.time(progress.pressed ? progress.value : (view.hasPlayer ? view.player.position : 0))
                    color: view.app.fg; opacity: 0.5
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: view.length > 0 ? view.time(view.length) : "--:--"
                    color: view.app.fg; opacity: 0.5
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 2
                spacing: 8
                Control {
                    glyph: "󰒝"
                    visible: view.hasPlayer && view.player.shuffleSupported
                    lit: view.hasPlayer && view.player.shuffle
                    onPressed: view.player.shuffle = !view.player.shuffle
                }
                Control {
                    glyph: "󰒮"
                    enabled: view.hasPlayer && view.player.canGoPrevious
                    onPressed: view.player.previous()
                }
                Control {
                    primary: true
                    glyph: view.hasPlayer && view.player.isPlaying ? "󰏤" : "󰐊"
                    enabled: view.hasPlayer && view.player.canTogglePlaying
                    onPressed: view.player.togglePlaying()
                }
                Control {
                    glyph: "󰒭"
                    enabled: view.hasPlayer && view.player.canGoNext
                    onPressed: view.player.next()
                }
                Control {
                    visible: view.hasPlayer && view.player.loopSupported
                    lit: view.hasPlayer && view.player.loopState !== MprisLoopState.None
                    glyph: view.hasPlayer && view.player.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
                    onPressed: view.player.loopState = view.player.loopState === MprisLoopState.None ? MprisLoopState.Playlist
                        : view.player.loopState === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None
                }
            }
        }
    }
}
