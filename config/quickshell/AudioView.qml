import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

// Output mixer (mic: false) or input mixer (mic: true), live from PipeWire.
Item {
    id: view
    required property var app
    property bool mic: false
    implicitWidth: 400
    implicitHeight: Math.min(560, column.implicitHeight)

    readonly property var nodes: Pipewire.nodes.values
    readonly property var devices: nodes.filter(n => n.audio && !n.isStream && n.isSink === !mic)
    readonly property var current: mic ? Pipewire.defaultAudioSource : Pipewire.defaultAudioSink
    // media.class is unambiguous: Stream/Output/Audio plays, Stream/Input/Audio records.
    // (PwNode.isSink is true for playback streams, so it can't tell them apart.)
    readonly property var streams: nodes.filter(n => {
        const cls = String(n.properties["media.class"] || "")
        return n.audio && cls.startsWith(mic ? "Stream/Input/Audio" : "Stream/Output/Audio")
            && !cls.includes("Internal") && n.name !== "cava"
    })

    function appName(n) {
        const name = n.properties["application.name"] || n.description || n.nickname
        if (name) return name
        const base = String(n.name).split(".")[0]  // e.g. spotifast.soloist.….output
        return base.charAt(0).toUpperCase() + base.slice(1)
    }
    function streamDetail(n) {
        const media = n.properties["media.name"] || ""
        return media === appName(n) ? "" : media
    }
    function appIcon(n) {
        return n.properties["application.icon-name"]
            || String(n.properties["application.process.binary"] || n.properties["application.name"] || String(n.name).split(".")[0]).toLowerCase()
    }
    function select(device) {
        if (mic) Pipewire.preferredDefaultAudioSource = device
        else Pipewire.preferredDefaultAudioSink = device
        // Move streams that are already playing/recording, like the old mixer did.
        app.command(["sh", "-c", mic
            ? 'pactl list short source-outputs | cut -f1 | xargs -r -I{} pactl move-source-output {} "$1"'
            : 'pactl list short sink-inputs | cut -f1 | xargs -r -I{} pactl move-sink-input {} "$1"', "sh", device.name])
    }

    // Binds every listed node so volume/mute are live and writable.
    // Track the raw node list (not the filtered views): binding a node fills in its
    // properties, which would re-run the filters and loop.
    PwObjectTracker { objects: Pipewire.nodes.values }

    component Section: Text {
        color: view.app.fg; opacity: 0.5
        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.letterSpacing: 2
        Layout.topMargin: 4
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            id: column
            width: parent.width
            spacing: 10

            VolumeRow {
                app: view.app
                node: view.current
                big: true
                glyph: view.mic ? "󰍬" : "󰕾"
                title: view.current ? (view.current.description || view.current.name) : (view.mic ? "No microphone" : "No output device")
                subtitle: view.mic ? "Default input" : "Default output"
            }

            Section { text: view.mic ? "INPUT DEVICES" : "OUTPUT DEVICES"; visible: view.devices.length > 1 }
            Repeater {
                model: view.devices.length > 1 ? view.devices : []
                Rectangle {
                    required property var modelData
                    readonly property bool chosen: modelData === view.current
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: 9
                    color: chosen ? Qt.alpha(view.app.accent, 0.16) : deviceMouse.containsMouse ? Qt.alpha(view.app.fg, 0.06) : "transparent"
                    border.color: chosen ? Qt.alpha(view.app.accent, 0.45) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 10
                        Rectangle {
                            implicitWidth: 10; implicitHeight: 10; radius: 5
                            color: parent.parent.chosen ? view.app.accent : "transparent"
                            border.color: Qt.alpha(parent.parent.chosen ? view.app.accent : view.app.fg, 0.6)
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.description || modelData.nickname || modelData.name
                            elide: Text.ElideRight
                            color: view.app.fg
                            opacity: parent.parent.chosen ? 1 : 0.75
                            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11
                        }
                    }
                    MouseArea {
                        id: deviceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (!parent.chosen) view.select(parent.modelData)
                    }
                }
            }

            Section { text: view.mic ? "RECORDING" : "APPLICATIONS" }
            Repeater {
                model: view.streams
                VolumeRow {
                    required property var modelData
                    app: view.app
                    node: modelData
                    title: view.appName(modelData)
                    subtitle: view.streamDetail(modelData)
                    icon: view.appIcon(modelData)
                    glyph: view.mic ? "󰍬" : "󰎆"
                }
            }
            Text {
                visible: view.streams.length === 0
                text: view.mic ? "No application is using the microphone" : "No application is playing audio"
                color: view.app.fg; opacity: 0.45
                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11
                Layout.bottomMargin: 4
            }
        }
    }
}
