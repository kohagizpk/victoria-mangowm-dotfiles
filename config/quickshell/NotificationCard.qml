import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

// One notification: popup (with timeout bar) or history entry in the Control Center.
Rectangle {
    id: card
    required property var center
    required property var notification
    property bool popup: false
    readonly property bool critical: notification.urgency === NotificationUrgency.Critical
    readonly property int timeout: critical ? 0 : notification.expireTimeout > 0
        // Apps send milliseconds; tolerate small values that look like seconds.
        ? (notification.expireTimeout < 100 ? notification.expireTimeout * 1000 : notification.expireTimeout) : card.center.timeoutMs
    width: card.center.cardWidth
    implicitHeight: body.implicitHeight + 24
    radius: 16
    color: card.center.app.bg
    border.color: critical ? "#e78284" : Qt.alpha(card.center.app.accent, popup ? 0.55 : 0.25)
    clip: true

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => mouse.button === Qt.LeftButton ? card.center.invokeDefault(card.notification)
                            : card.popup && mouse.button === Qt.RightButton ? card.center.dismissPopup(card.notification)
                            : card.notification.dismiss()
    }
    // Timeout bar; hovering pauses it.
    Rectangle {
        visible: card.popup && card.timeout > 0
        anchors.bottom: parent.bottom
        height: 2
        color: card.center.app.accent
        width: parent.width
        NumberAnimation on width {
            running: card.popup && card.timeout > 0
            paused: hover.containsMouse
            from: card.width; to: 0
            duration: card.timeout
        }
    }
    RowLayout {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 12
        Item {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 40; implicitHeight: 40
            Image {
                id: picture
                anchors.fill: parent
                source: card.center.showImages && card.notification.image ? card.notification.image : card.center.iconFor(card.notification)
                sourceSize: Qt.size(80, 80)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }
            Rectangle {
                anchors.fill: parent
                visible: !picture.visible
                radius: 12
                color: Qt.alpha(card.center.app.accent, 0.18)
                Text { anchors.centerIn: parent; text: card.critical ? "󰀦" : "󰂚"; color: card.critical ? "#e78284" : card.center.app.accent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 18 }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: card.notification.appName || "Notification"
                    elide: Text.ElideRight
                    color: card.center.app.accent
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9; font.letterSpacing: 1.5; font.bold: true
                    font.capitalization: Font.AllUppercase
                }
                Text {
                    text: "×"
                    color: card.center.app.fg; opacity: closeMouse.containsMouse ? 1 : 0.45
                    font.pixelSize: 16
                    MouseArea { id: closeMouse; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.notification.dismiss() }
                }
            }
            Text {
                Layout.fillWidth: true
                text: card.notification.summary
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: card.center.app.fg
                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; font.bold: true
            }
            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: card.notification.body
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: card.popup ? 4 : 3
                elide: Text.ElideRight
                color: card.center.app.fg; opacity: 0.75
                linkColor: card.center.app.accent
                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 6
                visible: card.notification.actions.some(a => a.identifier !== "default")
                Repeater {
                    model: card.notification.actions.filter(a => a.identifier !== "default")
                    Chip {
                        required property var modelData
                        text: modelData.text
                        surface: card.center.app.bg; ink: card.center.app.fg; accent: card.center.app.accent
                        implicitHeight: 26
                        onClicked: { modelData.invoke(); card.notification.dismiss() }
                    }
                }
            }
        }
    }
    // Dismissal is timer-driven (the bar above is only the visual); hovering holds it.
    Timer {
        interval: card.timeout
        running: card.popup && card.timeout > 0 && !hover.containsMouse
        onTriggered: card.center.dismissPopup(card.notification)
    }
    // A notification closed elsewhere (app, history, timeout) leaves the popup stack.
    Connections { target: card.notification; function onClosed() { card.center.dismissPopup(card.notification) } }
}
