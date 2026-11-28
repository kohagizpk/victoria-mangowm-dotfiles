import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

// One PipeWire node (device or app stream): icon/mute tile, name, live volume.
// Volume is written straight to PipeWire, so dragging never spawns processes.
RowLayout {
    id: row
    required property var app
    property PwNode node: null
    property string title: node ? (node.description || node.nickname || node.name) : ""
    property string subtitle: ""
    property string icon: ""
    property string glyph: "󰕾"
    property bool big: false
    readonly property bool ready: node !== null && node.audio !== null
    readonly property real level: ready ? node.audio.volume : 0
    readonly property bool muted: ready && node.audio.muted
    spacing: 12
    Layout.fillWidth: true

    function setVolume(v) {
        if (!ready) return
        node.audio.volume = Math.max(0, v)
        if (node.audio.muted && v > 0) node.audio.muted = false
    }

    Rectangle {
        id: tile
        Layout.preferredWidth: row.big ? 38 : 32
        Layout.preferredHeight: Layout.preferredWidth
        Layout.alignment: Qt.AlignVCenter
        radius: 10
        color: tileMouse.containsMouse ? Qt.alpha(row.app.accent, 0.28)
             : row.muted ? Qt.alpha(row.app.fg, 0.06) : Qt.alpha(row.app.accent, 0.14)
        border.color: Qt.alpha(row.muted ? row.app.fg : row.app.accent, 0.3)
        Behavior on color { ColorAnimation { duration: 120 } }
        Image {
            id: appIcon
            anchors.centerIn: parent
            width: parent.width - 12; height: width
            sourceSize: Qt.size(width * 2, height * 2)
            source: row.icon ? Quickshell.iconPath(row.icon, true) : ""
            visible: status === Image.Ready
            opacity: row.muted ? 0.35 : 1
            asynchronous: true
        }
        Text {
            anchors.centerIn: parent
            visible: !appIcon.visible || row.muted
            text: row.muted ? "󰝟" : row.glyph
            color: row.muted ? Qt.alpha(row.app.fg, 0.55) : row.app.accent
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: row.big ? 17 : 15
        }
        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (row.ready) row.node.audio.muted = !row.node.audio.muted
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                text: row.title
                Layout.fillWidth: true
                elide: Text.ElideRight
                color: row.app.fg
                opacity: row.muted ? 0.55 : 1
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: row.big ? 13 : 12
                font.bold: row.big
            }
            Text {
                text: row.muted ? "MUTED" : Math.round((slider.pressed ? slider.value : row.level) * 100) + "%"
                color: row.muted ? Qt.alpha(row.app.fg, 0.45) : row.app.accent
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                font.letterSpacing: row.muted ? 1 : 0
            }
        }
        Text {
            visible: row.subtitle.length > 0
            text: row.subtitle
            Layout.fillWidth: true
            elide: Text.ElideRight
            color: row.app.fg
            opacity: 0.45
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
        }
        ThemedSlider {
            id: slider
            Layout.fillWidth: true
            accent: row.muted ? Qt.alpha(row.app.fg, 0.35) : row.app.accent
            ink: row.app.fg
            from: 0; to: 1; stepSize: 0.01
            enabled: row.ready
            Binding on value { value: row.level; when: !slider.pressed; restoreMode: Binding.RestoreNone }
            onMoved: row.setVolume(value)
        }
    }
}
