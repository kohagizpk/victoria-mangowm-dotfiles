import QtQuick

// Round profile picture. `source` is the pre-rounded PNG from victoria_settings
// (round_avatar), so no shader or Canvas masking is needed on the software renderer.
// Falls back to the first letter of `name` on an accent disc.
Item {
    id: avatar
    required property var app
    property string source: ""
    property string name: ""
    property int version: 0          // bump to re-read the same path after it changed
    property bool ring: false
    implicitWidth: 40
    implicitHeight: 40

    Image {
        id: picture
        anchors.fill: parent
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        fillMode: Image.PreserveAspectFit
        visible: status === Image.Ready
    }
    function reload() { picture.source = ""; if (source.length) picture.source = "file://" + source }
    onSourceChanged: reload()
    onVersionChanged: reload()
    Component.onCompleted: reload()

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        visible: !picture.visible
        color: avatar.app.accent
        Text {
            anchors.centerIn: parent
            text: (avatar.name || "?").charAt(0).toUpperCase()
            color: avatar.app.bg
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: parent.height * 0.45
            font.bold: true
        }
    }
    Rectangle {
        anchors { fill: parent; margins: -3 }
        radius: width / 2
        visible: avatar.ring
        color: "transparent"
        border.width: 2
        border.color: avatar.app.accent
    }
}
