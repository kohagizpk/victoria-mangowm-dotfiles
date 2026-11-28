import QtQuick
import QtQuick.Controls

// Thin wallust-tinted slider. Callers bind `value` with a Binding element
// (when: !pressed) so a live source never fights the user's drag.
Slider {
    id: control
    property color accent: "#b18aa6"
    property color ink: "#ddd"
    readonly property bool active: hovered || pressed
    implicitHeight: 20
    padding: 0
    wheelEnabled: true

    background: Rectangle {
        x: control.leftPadding
        y: control.topPadding + control.availableHeight / 2 - height / 2
        width: control.availableWidth
        height: control.active ? 6 : 4
        radius: height / 2
        color: Qt.alpha(control.ink, 0.12)
        Behavior on height { NumberAnimation { duration: 90 } }
        Rectangle {
            width: Math.max(parent.height, control.visualPosition * parent.width)
            height: parent.height
            radius: parent.radius
            color: control.accent
        }
    }

    handle: Rectangle {
        x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
        y: control.topPadding + control.availableHeight / 2 - height / 2
        width: control.active ? 14 : 10
        height: width
        radius: width / 2
        color: control.accent
        border.width: control.active ? 3 : 0
        border.color: Qt.alpha(control.ink, 0.9)
        visible: control.enabled
        Behavior on width { NumberAnimation { duration: 90 } }
    }
}
