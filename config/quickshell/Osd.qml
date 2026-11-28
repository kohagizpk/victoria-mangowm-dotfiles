import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// On-screen indicator for volume, microphone, brightness and keyboard layout.
// Shown by shell.qml's showOsd(); hides itself after a short delay.
PanelWindow {
    id: osd
    required property var app
    screen: app.osdScreen
    anchors.bottom: true
    margins.bottom: 90
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 300
    implicitHeight: 64
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "victoria-osd"
    // Never steal input: the indicator is purely visual.
    mask: Region {}

    readonly property var info: app.osdInfo
    readonly property bool hasLevel: info.level !== undefined && info.level !== null

    Rectangle {
        anchors.fill: parent
        radius: 20
        color: Qt.alpha(osd.app.bg, 0.96)
        border.color: Qt.alpha(osd.app.accent, 0.5)

        RowLayout {
            anchors { fill: parent; leftMargin: 18; rightMargin: 20 }
            spacing: 14
            Rectangle {
                implicitWidth: 36; implicitHeight: 36; radius: 12
                color: osd.info.muted ? Qt.alpha(osd.app.fg, 0.1) : osd.app.accent
                Text {
                    anchors.centerIn: parent
                    text: osd.info.icon || ""
                    color: osd.info.muted ? osd.app.fg : osd.app.bg
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 17
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: osd.info.title || ""
                        elide: Text.ElideRight
                        color: osd.app.fg
                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; font.bold: true
                    }
                    Text {
                        visible: osd.hasLevel
                        text: osd.info.muted ? "MUTED" : Math.round(osd.info.level * 100) + "%"
                        color: osd.info.muted ? Qt.alpha(osd.app.fg, 0.5) : osd.app.accent
                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.bold: true
                    }
                }
                Rectangle {
                    visible: osd.hasLevel
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: 3
                    color: Qt.alpha(osd.app.fg, 0.12)
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, osd.info.level || 0))
                        height: parent.height
                        radius: 3
                        color: osd.info.muted ? Qt.alpha(osd.app.fg, 0.35) : osd.app.accent
                        Behavior on width { NumberAnimation { duration: 90 } }
                    }
                }
                Text {
                    visible: !osd.hasLevel && (osd.info.detail || "").length > 0
                    text: osd.info.detail || ""
                    color: osd.app.fg; opacity: 0.55
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10
                }
            }
        }
    }
}
