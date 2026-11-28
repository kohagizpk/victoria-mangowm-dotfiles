import QtQuick
import Quickshell
import Quickshell.Wayland

// One popup surface; only the open view is instantiated.
PanelWindow {
    id: win
    required property var app
    readonly property var titles: ({ media: "NOW PLAYING", calendar: "CALENDAR", audio: "AUDIO", mic: "MICROPHONE", control: "CONTROL CENTER" })
    readonly property int pad: 18

    visible: app.popup !== ""
    screen: app.popupScreen
    anchors { top: app.prefs.bar_position !== "bottom"; bottom: app.prefs.bar_position === "bottom"; left: true }
    margins {
        top: app.barHeight + 4
        bottom: app.barHeight + 4
        left: Math.max(6, Math.min(app.popupX - implicitWidth / 2, (screen ? screen.width : 1920) - implicitWidth - 6))
    }
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: (content.item ? content.item.implicitWidth : 400) + pad * 2
    implicitHeight: (content.item ? content.item.implicitHeight : 200) + header.height + pad * 2 + 6
    color: "transparent"
    WlrLayershell.namespace: "victoria-popup"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Rectangle {
        anchors.fill: parent
        radius: 20
        color: win.app.bg
        border.color: Qt.alpha(win.app.accent, 0.5)
        focus: true
        Keys.onEscapePressed: win.app.popup = ""

        Item {
            id: header
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: win.pad }
            height: 24
            Rectangle {
                id: dot
                anchors.verticalCenter: parent.verticalCenter
                width: 6; height: 6; radius: 3
                color: win.app.accent
            }
            Text {
                anchors { left: dot.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
                text: win.titles[win.app.popup] || ""
                color: win.app.fg; opacity: 0.6
                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.letterSpacing: 2
            }
            Chip {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                implicitHeight: 24
                text: "×"
                surface: win.app.bg; ink: win.app.fg; accent: win.app.accent
                onClicked: win.app.popup = ""
            }
        }

        Loader {
            id: content
            anchors { top: header.bottom; topMargin: 6; left: parent.left; right: parent.right; bottom: parent.bottom; margins: win.pad }
            sourceComponent: ({ media: media, calendar: calendar, control: control })[win.app.popup] || audio
        }
    }

    Component { id: media; MediaView { app: win.app } }
    Component { id: calendar; CalendarView { app: win.app } }
    Component { id: control; ControlView { app: win.app } }
    Component { id: audio; AudioView { app: win.app; mic: win.app.popup === "mic" } }
}
