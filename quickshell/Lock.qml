import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam

// Victoria lock screen (ext-session-lock). Password checked through PAM ("login"
// service, the same stack hyprlock uses). If this process dies while locked the
// compositor keeps the session locked; see README "Lock screen" for recovery.
Scope {
    id: lockScope
    required property var app

    property string password: ""
    property string status: ""
    property bool failed: false
    property bool checking: pam.active

    function submit() {
        if (pam.active || password.length === 0) return
        failed = false
        status = "Checking…"
        pam.start()
    }

    PamContext {
        id: pam
        config: "login"
        onMessageChanged: if (!messageIsError && !responseRequired && message.length) lockScope.status = message
        onResponseRequiredChanged: if (responseRequired) { respond(lockScope.password) }
        onCompleted: result => {
            if (result === PamResult.Success) {
                lockScope.status = ""
                lockScope.password = ""
                lockScope.app.locked = false
            } else {
                lockScope.failed = true
                lockScope.password = ""
                lockScope.status = result === PamResult.MaxTries ? "Too many attempts — wait a moment" : "Wrong password — try again"
            }
        }
        onError: error => { lockScope.failed = true; lockScope.password = ""; lockScope.status = "Could not check the password (" + PamError.toString(error) + ")" }
    }

    WlSessionLock {
        id: sessionLock
        locked: lockScope.app.locked
        onSecureChanged: lockScope.app.lockSecure = secure

        WlSessionLockSurface {
            id: surface
            color: lockScope.app.bg

            // Wallpaper, dimmed (no blur: the shell renders in software).
            Image {
                anchors.fill: parent
                source: lockScope.app.wallpaper ? "file://" + lockScope.app.wallpaper : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(surface.width, surface.height)
                asynchronous: true
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.alpha(lockScope.app.bg, 0.55) }
                    GradientStop { position: 1; color: Qt.alpha(lockScope.app.bg, 0.92) }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: 380
                spacing: 14

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDateTime(lockScope.app.now, lockScope.app.prefs.clock_24h === false ? "hh:mm" : "HH:mm")
                    color: lockScope.app.fg
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 88; font.bold: true
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 26
                    text: Qt.formatDateTime(lockScope.app.now, "dddd, d MMMM")
                    color: lockScope.app.fg; opacity: 0.7
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15
                }
                Avatar {
                    Layout.alignment: Qt.AlignHCenter
                    app: lockScope.app
                    implicitWidth: 96; implicitHeight: 96
                    ring: true
                    source: lockScope.app.profile.round || ""
                    name: lockScope.app.profile.name || ""
                    version: lockScope.app.avatarVersion
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: lockScope.app.profile.name || Quickshell.env("USER")
                    color: lockScope.app.fg
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16; font.bold: true
                }
                TextField {
                    id: field
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    implicitHeight: 48
                    focus: true
                    enabled: !pam.active
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    horizontalAlignment: TextInput.AlignHCenter
                    placeholderText: pam.active ? "Checking…" : "Password"
                    text: lockScope.password
                    color: lockScope.app.fg
                    placeholderTextColor: Qt.alpha(lockScope.app.fg, 0.45)
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15
                    background: Rectangle {
                        radius: 16
                        color: Qt.alpha(lockScope.app.bg, 0.85)
                        border.width: 2
                        border.color: lockScope.failed ? "#e78284" : lockScope.app.accent
                    }
                    onTextChanged: { lockScope.password = text; if (text.length) lockScope.failed = false }
                    onAccepted: lockScope.submit()
                    Keys.onEscapePressed: text = ""
                    Component.onCompleted: forceActiveFocus()
                    // Keep typing focus on the field of the focused monitor.
                    Connections { target: surface; function onVisibleChanged() { if (surface.visible) field.forceActiveFocus() } }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: lockScope.status || ((lockScope.app.kbLayouts.length > 1 ? "󰌌 " + lockScope.app.kbLabel + "  ·  " : "") + "Type your password, then press Enter")
                    color: lockScope.failed ? "#e78284" : lockScope.app.fg
                    opacity: lockScope.failed ? 1 : 0.6
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12
                }
            }

            // Now playing, bottom center.
            Rectangle {
                visible: lockScope.app.player !== null
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 48 }
                width: 360; height: 54; radius: 16
                color: Qt.alpha(lockScope.app.bg, 0.85)
                border.color: Qt.alpha(lockScope.app.accent, 0.4)
                RowLayout {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 8 }
                    spacing: 8
                    Text { text: "󰝚"; color: lockScope.app.accent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 18 }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: lockScope.app.player ? lockScope.app.player.trackTitle : ""; color: lockScope.app.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; font.bold: true }
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: lockScope.app.player ? lockScope.app.player.trackArtist : ""; color: lockScope.app.fg; opacity: 0.6; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10 }
                    }
                    Chip { text: "󰒮"; surface: lockScope.app.bg; ink: lockScope.app.fg; accent: lockScope.app.accent; onClicked: lockScope.app.player.previous() }
                    Chip { text: lockScope.app.player && lockScope.app.player.isPlaying ? "󰏤" : "󰐊"; selected: true; surface: lockScope.app.bg; ink: lockScope.app.fg; accent: lockScope.app.accent; onClicked: lockScope.app.player.togglePlaying() }
                    Chip { text: "󰒭"; surface: lockScope.app.bg; ink: lockScope.app.fg; accent: lockScope.app.accent; onClicked: lockScope.app.player.next() }
                }
            }
        }
    }
}
