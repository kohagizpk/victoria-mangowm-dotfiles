import QtQuick
import QtQuick.Controls
Rectangle {
    id: chip
    property string text: ""
    property color surface: "#111014"
    property color ink: "#ddd"
    property color accent: "#b18aa6"
    property bool selected: false
    property string tip: ""
    signal clicked(int button)
    signal scrolled(int delta)
    implicitWidth: label.implicitWidth + 18
    implicitHeight: 30
    radius: 9
    color: selected ? accent : mouse.containsMouse ? Qt.alpha(accent,0.18) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }
    Text { id: label; anchors.centerIn: parent; text: chip.text; color: chip.selected ? "#101014" : chip.ink; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; font.bold: chip.selected }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton; onClicked: event => chip.clicked(event.button); onWheel: event => chip.scrolled(event.angleDelta.y) }
    ToolTip {
        visible:mouse.containsMouse && chip.tip.length>0
        text:chip.tip;delay:600;padding:9
        contentItem:Text {text:chip.tip;color:chip.ink;font.pixelSize:12;wrapMode:Text.Wrap; width:Math.min(implicitWidth,420)}
        background:Rectangle {color:chip.surface;radius:8;border.color:Qt.alpha(chip.accent,0.5)}
    }
}
