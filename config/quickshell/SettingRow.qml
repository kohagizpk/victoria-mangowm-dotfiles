import QtQuick
import QtQuick.Layouts

// Label (+ optional hint) on the left, any control on the right.
RowLayout {
    id: row
    required property var app
    property string label: ""
    property string hint: ""
    default property alias control: slot.data
    Layout.fillWidth: true
    spacing: 16
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 1
        Text { text: row.label; color: row.app.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        Text { visible: row.hint.length > 0; text: row.hint; color: row.app.fg; opacity: 0.45; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    }
    Item {
        id: slot
        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }
}
