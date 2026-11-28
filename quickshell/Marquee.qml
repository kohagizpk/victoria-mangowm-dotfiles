import QtQuick

// Single-line text that scrolls back and forth when it doesn't fit,
// pausing at each end; short text stays still. Only animates while visible.
Item {
    id: marquee
    property alias text: label.text
    property alias color: label.color
    property alias font: label.font
    property int speed: 35            // pixels per second
    property int pause: 1600          // ms to rest at each end
    readonly property real overflow: Math.max(0, label.implicitWidth - width)
    implicitHeight: label.implicitHeight
    clip: true

    Text {
        id: label
        x: 0
        anchors.verticalCenter: parent.verticalCenter
    }

    SequentialAnimation {
        id: scroll
        running: marquee.overflow > 0 && marquee.visible && marquee.width > 0
        loops: Animation.Infinite
        PauseAnimation { duration: marquee.pause }
        NumberAnimation { target: label; property: "x"; to: -marquee.overflow; duration: marquee.overflow / marquee.speed * 1000; easing.type: Easing.InOutSine }
        PauseAnimation { duration: marquee.pause }
        NumberAnimation { target: label; property: "x"; to: 0; duration: marquee.overflow / marquee.speed * 1000; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) label.x = 0
    }
    // New song or new size: start again from the beginning.
    function restart() { label.x = 0; if (scroll.running) scroll.restart() }
    onTextChanged: restart()
    onWidthChanged: restart()
}
