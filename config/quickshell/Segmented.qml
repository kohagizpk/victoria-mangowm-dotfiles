import QtQuick
import QtQuick.Layouts

// Row of mutually exclusive options. `options` is a list of strings or {label, value}.
Rectangle {
    id: seg
    property var options: []
    property var value
    property color accent: "#b18aa6"
    property color ink: "#ddd"
    signal picked(var value)
    implicitHeight: 30
    implicitWidth: row.implicitWidth + 6
    radius: 10
    color: Qt.alpha(ink, 0.06)
    border.color: Qt.alpha(ink, 0.08)
    RowLayout {
        id: row
        anchors { fill: parent; margins: 3 }
        spacing: 2
        Repeater {
            model: seg.options
            Rectangle {
                required property var modelData
                readonly property var optionValue: typeof modelData === "object" ? modelData.value : modelData
                readonly property bool active: optionValue === seg.value
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitWidth: label.implicitWidth + 20
                radius: 8
                color: active ? seg.accent : optionMouse.containsMouse ? Qt.alpha(seg.accent, 0.15) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: typeof parent.modelData === "object" ? parent.modelData.label : parent.modelData
                    color: parent.active ? "#101014" : seg.ink
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.bold: parent.active
                }
                MouseArea {
                    id: optionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.picked(parent.optionValue)
                }
            }
        }
    }
}
