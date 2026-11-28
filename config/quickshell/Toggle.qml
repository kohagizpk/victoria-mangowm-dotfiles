import QtQuick

// Pill switch in the wallust accent.
Rectangle {
    id: toggle
    property bool checked: false
    property color accent: "#b18aa6"
    property color ink: "#ddd"
    signal toggled(bool checked)
    implicitWidth: 40
    implicitHeight: 22
    radius: height / 2
    opacity: enabled ? 1 : 0.4
    color: checked ? accent : Qt.alpha(ink, mouse.containsMouse ? 0.2 : 0.13)
    Behavior on color { ColorAnimation { duration: 140 } }
    Rectangle {
        width: 16; height: 16; radius: 8
        anchors.verticalCenter: parent.verticalCenter
        x: toggle.checked ? parent.width - width - 3 : 3
        color: toggle.checked ? "#101014" : toggle.ink
        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: toggle.toggled(!toggle.checked)
    }
}
