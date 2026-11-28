import QtQuick
import QtQuick.Layouts

// Month calendar (weather on top when enabled). DND and performance live in the Control Center.
Item {
    id: view
    required property var app
    implicitWidth: 380
    implicitHeight: column.implicitHeight

    property date month: new Date(app.now.getFullYear(), app.now.getMonth(), 1)
    readonly property int offset: (new Date(month.getFullYear(), month.getMonth(), 1).getDay() + 6) % 7
    readonly property int days: new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
    readonly property bool currentMonth: month.getMonth() === app.now.getMonth() && month.getFullYear() === app.now.getFullYear()
    function step(delta) { month = new Date(month.getFullYear(), month.getMonth() + delta, 1) }

    component Label: Text { color: view.app.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12 }
    component Button: Chip { surface: view.app.bg; ink: view.app.fg; accent: view.app.accent }

    ColumnLayout {
        id: column
        width: parent.width
        spacing: 12

        Rectangle {
            visible: view.app.weatherOn && view.app.weather !== null
            Layout.fillWidth: true
            implicitHeight: 58
            radius: 14
            color: Qt.alpha(view.app.accent, 0.1)
            border.color: Qt.alpha(view.app.accent, 0.3)
            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                spacing: 12
                Text { text: view.app.weather ? view.app.weather.icon : ""; color: view.app.accent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 26 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { text: view.app.weather ? view.app.weather.temp + "°  " + view.app.weather.desc : ""; font.bold: true; font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true }
                    Label { text: view.app.weather ? view.app.weather.area + " · feels " + view.app.weather.feels + "° · " + view.app.weather.min + "°/" + view.app.weather.max + "° · " + view.app.weather.humidity + "% humidity" : ""; opacity: 0.55; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Button { text: "‹"; onClicked: view.step(-1) }
            Label {
                text: view.month.toLocaleDateString(Qt.locale("en_US"), "MMMM yyyy")
                font.pixelSize: 16; font.bold: true
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }
            Button { text: "›"; onClicked: view.step(1) }
        }

        GridLayout {
            columns: 7; rowSpacing: 3; columnSpacing: 3
            Layout.fillWidth: true
            Repeater {
                model: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
                Label { required property string modelData; text: modelData; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; opacity: 0.4; font.pixelSize: 10; font.letterSpacing: 1 }
            }
            Repeater {
                model: 42
                Rectangle {
                    required property int index
                    readonly property int day: index - view.offset + 1
                    readonly property bool valid: day > 0 && day <= view.days
                    readonly property bool today: valid && view.currentMonth && day === view.app.now.getDate()
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: 8
                    color: today ? view.app.accent : "transparent"
                    border.color: valid && !today && index % 7 >= 5 ? Qt.alpha(view.app.accent, 0.15) : "transparent"
                    Label {
                        anchors.centerIn: parent
                        text: parent.valid ? parent.day : ""
                        color: parent.today ? view.app.bg : view.app.fg
                        opacity: parent.today ? 1 : 0.85
                        font.bold: parent.today
                    }
                }
            }
        }

        Button { text: "Today"; Layout.alignment: Qt.AlignHCenter; visible: !view.currentMonth; onClicked: view.month = new Date(view.app.now.getFullYear(), view.app.now.getMonth(), 1) }
    }
}
