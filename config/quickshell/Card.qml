import QtQuick
import QtQuick.Layouts

// Settings group: title, optional hint, then rows (default property).
Rectangle {
    id: card
    required property var app
    property string title: ""
    property string hint: ""
    property string icon: ""
    default property alias rows: body.data
    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + 28
    radius: 16
    color: Qt.alpha(app.fg, 0.035)
    border.color: Qt.alpha(app.fg, 0.08)
    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; leftMargin: 18; rightMargin: 18 }
        spacing: 10
        RowLayout {
            spacing: 10
            visible: card.title.length > 0
            Text { visible: card.icon.length > 0; text: card.icon; color: card.app.accent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15 }
            ColumnLayout {
                spacing: 1
                Text { text: card.title; color: card.app.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13; font.bold: true }
                Text { visible: card.hint.length > 0; text: card.hint; color: card.app.fg; opacity: 0.5; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            }
        }
        ColumnLayout { id: body; Layout.fillWidth: true; spacing: 10 }
    }
}
