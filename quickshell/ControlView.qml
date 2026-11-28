import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

// Quick settings: Wi-Fi, Bluetooth, sound, toggles, media and session actions.
Item {
    id: view
    required property var app
    implicitWidth: 400
    implicitHeight: Math.min(760, column.implicitHeight)

    property string expanded: ""   // "", "wifi" or "bluetooth"
    property var askPassword: null // WifiNetwork waiting for a passphrase

    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property var networks: wifi ? wifi.networks.values.slice().sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength)) : []
    readonly property var activeNetwork: networks.find(n => n.connected) || null
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var btDevices: adapter ? adapter.devices.values.slice().sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired)) : []
    readonly property var btConnected: btDevices.filter(d => d.connected)
    readonly property var player: app.player
    readonly property var history: app.notifications ? app.notifications.history : []

    function strength(n) { const s = n.signalStrength > 1 ? n.signalStrength / 100 : n.signalStrength; return s > 0.75 ? "󰤨" : s > 0.5 ? "󰤥" : s > 0.25 ? "󰤢" : "󰤟" }
    function profileName(p) { return p === PowerProfile.PowerSaver ? "Power saver" : p === PowerProfile.Performance ? "Performance" : "Balanced" }
    function cycleProfile() {
        const order = [PowerProfile.PowerSaver, PowerProfile.Balanced].concat(PowerProfiles.hasPerformanceProfile ? [PowerProfile.Performance] : [])
        PowerProfiles.profile = order[(order.indexOf(PowerProfiles.profile) + 1) % order.length]
    }
    function run(name, args) { app.popup = ""; app.script(name, args) }
    // Close first so the panel isn't in the shot; slurp needs the screen free.
    function capture(args) { app.popup = ""; app.command(["sh", "-c", 'sleep 0.35; exec bash "$0" "$@"', app.home + "/.config/mango/scripts/" + args[0]].concat(args.slice(1))) }

    // Scan only while the network list is open.
    Binding { target: view.wifi; property: "scannerEnabled"; value: view.expanded === "wifi"; when: view.wifi !== null }
    Binding { target: view.adapter; property: "discovering"; value: view.expanded === "bluetooth"; when: view.adapter !== null && view.adapter.enabled }

    component Label: Text { color: view.app.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; elide: Text.ElideRight }
    component Section: Text { color: view.app.fg; opacity: 0.45; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9; font.letterSpacing: 2; Layout.topMargin: 2 }

    // Big tile: icon, title, state; main click toggles, the arrow expands.
    component Tile: Rectangle {
        id: tile
        property string icon: ""
        property string title: ""
        property string detail: ""
        property bool lit: false
        property bool expandable: false
        signal toggled()
        signal expand()
        Layout.fillWidth: true
        implicitHeight: 54
        radius: 16
        color: lit ? Qt.alpha(view.app.accent, tileMouse.containsMouse ? 0.32 : 0.22) : Qt.alpha(view.app.fg, tileMouse.containsMouse ? 0.08 : 0.045)
        border.color: lit ? Qt.alpha(view.app.accent, 0.55) : Qt.alpha(view.app.fg, 0.08)
        Behavior on color { ColorAnimation { duration: 120 } }
        MouseArea { id: tileMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tile.toggled() }
        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 6 }
            spacing: 10
            Rectangle {
                implicitWidth: 30; implicitHeight: 30; radius: 10
                color: tile.lit ? view.app.accent : Qt.alpha(view.app.fg, 0.08)
                Text { anchors.centerIn: parent; text: tile.icon; color: tile.lit ? view.app.bg : view.app.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15 }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label { text: tile.title; font.bold: true; Layout.fillWidth: true }
                Label { text: tile.detail; opacity: 0.55; font.pixelSize: 10; Layout.fillWidth: true; visible: text.length > 0 }
            }
            Rectangle {
                visible: tile.expandable
                implicitWidth: 26; implicitHeight: 38; radius: 9
                color: arrowMouse.containsMouse ? Qt.alpha(view.app.fg, 0.1) : "transparent"
                Text { anchors.centerIn: parent; text: "›"; color: view.app.fg; font.pixelSize: 16; rotation: view.expanded !== "" && tile.expandable && view.expanded === tile.objectName ? 90 : 0; Behavior on rotation { NumberAnimation { duration: 120 } } }
                MouseArea { id: arrowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tile.expand() }
            }
        }
    }

    // Round action button with label below.
    component Action: ColumnLayout {
        id: action
        property string icon: ""
        property string label: ""
        property bool danger: false
        property bool confirm: false
        property bool armed: false
        signal activated()
        function press() { if (!confirm || armed) { armed = false; activated() } else { armed = true; disarm.restart() } }
        Timer { id: disarm; interval: 3000; onTriggered: action.armed = false }
        Layout.fillWidth: true
        spacing: 4
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 42; implicitHeight: 42; radius: 14
            color: action.armed ? "#c05050" : actionMouse.containsMouse ? (action.danger ? Qt.alpha("#c05050", 0.6) : Qt.alpha(view.app.accent, 0.28)) : Qt.alpha(view.app.fg, 0.06)
            Behavior on color { ColorAnimation { duration: 120 } }
            Text { anchors.centerIn: parent; text: action.icon; color: view.app.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16 }
            MouseArea { id: actionMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: action.press() }
        }
        Label { Layout.alignment: Qt.AlignHCenter; text: action.armed ? "Again to confirm" : action.label; opacity: action.armed ? 1 : 0.6; font.pixelSize: 9 }
    }

    // One row in the Wi-Fi / Bluetooth lists.
    component ListRow: Rectangle {
        id: listRow
        property string icon: ""
        property string title: ""
        property string detail: ""
        property bool active: false
        property bool busy: false
        signal activated()
        Layout.fillWidth: true
        implicitHeight: 38
        radius: 10
        color: active ? Qt.alpha(view.app.accent, 0.15) : rowMouse.containsMouse ? Qt.alpha(view.app.fg, 0.06) : "transparent"
        MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: listRow.activated() }
        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            spacing: 10
            Text { text: listRow.icon; color: listRow.active ? view.app.accent : view.app.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14 }
            Label { text: listRow.title; Layout.fillWidth: true; font.bold: listRow.active }
            Label { text: listRow.busy ? "…" : listRow.detail; opacity: 0.5; font.pixelSize: 10 }
        }
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            id: column
            width: parent.width
            spacing: 10

            // Header: who, uptime-free greeting, settings and power.
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Avatar {
                    app: view.app
                    implicitWidth: 40; implicitHeight: 40
                    source: view.app.profile.round || ""
                    name: view.app.profile.name || ""
                    version: view.app.avatarVersion
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { view.app.popup = ""; view.app.openSettings("profile") } }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { text: view.app.profile.name || Quickshell.env("USER"); font.bold: true; font.pixelSize: 13 }
                    Label { text: Qt.formatDateTime(view.app.now, "dddd, d MMMM"); opacity: 0.55; font.pixelSize: 10 }
                }
                Chip { text: ""; tip: "Settings"; surface: view.app.bg; ink: view.app.fg; accent: view.app.accent; onClicked: { view.app.popup = ""; view.app.openSettings("appearance") } }
                Chip { text: "󰌾"; tip: "Lock"; surface: view.app.bg; ink: view.app.fg; accent: view.app.accent; onClicked: view.run("session-controls.py", ["lock"]) }
            }

            // Connectivity
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Tile {
                    objectName: "wifi"
                    icon: !Networking.wifiEnabled ? "󰤮" : view.activeNetwork ? view.strength(view.activeNetwork) : "󰤯"
                    title: "Wi-Fi"
                    detail: !view.wifi ? "No adapter" : !Networking.wifiEnabled ? "Off" : view.activeNetwork ? view.activeNetwork.name : "Not connected"
                    lit: Networking.wifiEnabled && view.wifi !== null
                    expandable: view.wifi !== null && Networking.wifiEnabled
                    onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                    onExpand: view.expanded = view.expanded === "wifi" ? "" : "wifi"
                }
                Tile {
                    objectName: "bluetooth"
                    icon: !view.adapter || !view.adapter.enabled ? "󰂲" : view.btConnected.length ? "󰂱" : "󰂯"
                    title: "Bluetooth"
                    detail: !view.adapter ? "No adapter" : !view.adapter.enabled ? "Off" : view.btConnected.length ? view.btConnected.map(d => d.name).join(", ") : "On"
                    lit: view.adapter !== null && view.adapter.enabled
                    expandable: view.adapter !== null && view.adapter.enabled
                    onToggled: if (view.adapter) view.adapter.enabled = !view.adapter.enabled
                    onExpand: view.expanded = view.expanded === "bluetooth" ? "" : "bluetooth"
                }
            }

            // Wi-Fi list
            ColumnLayout {
                visible: view.expanded === "wifi"
                Layout.fillWidth: true
                spacing: 2
                Section { text: "NETWORKS" + (view.wifi && view.wifi.scannerEnabled ? " · SCANNING" : "") }
                Repeater {
                    model: view.expanded === "wifi" ? view.networks.slice(0, 10) : []
                    ListRow {
                        required property var modelData
                        icon: view.strength(modelData)
                        title: modelData.name || "Hidden network"
                        detail: modelData.connected ? "Connected" : modelData.known ? "Saved" : (modelData.security === WifiSecurityType.Open || modelData.security === WifiSecurityType.Owe) ? "Open" : "󰌾"
                        active: modelData.connected
                        busy: modelData.stateChanging
                        onActivated: {
                            if (modelData.connected) modelData.disconnect()
                            else if (modelData.known || (modelData.security === WifiSecurityType.Open || modelData.security === WifiSecurityType.Owe)) modelData.connect()
                            else { view.askPassword = modelData; password.text = ""; password.forceActiveFocus() }
                        }
                    }
                }
                RowLayout {
                    visible: view.askPassword !== null
                    Layout.fillWidth: true
                    spacing: 6
                    TextField {
                        id: password
                        Layout.fillWidth: true
                        echoMode: TextInput.Password
                        placeholderText: view.askPassword ? "Password for " + view.askPassword.name : ""
                        color: view.app.fg
                        placeholderTextColor: Qt.alpha(view.app.fg, 0.35)
                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11
                        background: Rectangle { radius: 9; color: Qt.alpha(view.app.fg, 0.05); border.color: password.activeFocus ? view.app.accent : Qt.alpha(view.app.fg, 0.12) }
                        onAccepted: { view.askPassword.connectWithPsk(text); text = ""; view.askPassword = null }
                        Keys.onEscapePressed: view.askPassword = null
                    }
                    Chip { text: "Join"; selected: true; surface: view.app.bg; ink: view.app.fg; accent: view.app.accent; onClicked: password.accepted() }
                }
                Label { visible: view.networks.length === 0; text: "Searching for networks…"; opacity: 0.5; font.pixelSize: 11 }
            }

            // Bluetooth list
            ColumnLayout {
                visible: view.expanded === "bluetooth"
                Layout.fillWidth: true
                spacing: 2
                Section { text: "DEVICES" + (view.adapter && view.adapter.discovering ? " · SEARCHING" : "") }
                Repeater {
                    model: view.expanded === "bluetooth" ? view.btDevices.filter(d => d.paired || d.name).slice(0, 10) : []
                    ListRow {
                        required property var modelData
                        icon: modelData.icon && modelData.icon.indexOf("audio") >= 0 ? "󰋋" : modelData.icon && modelData.icon.indexOf("input") >= 0 ? "󰌌" : "󰂯"
                        title: modelData.name || modelData.address
                        detail: modelData.connected ? (modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "% · " : "") + "Connected" : modelData.paired ? "Paired" : "Pair"
                        active: modelData.connected
                        busy: modelData.pairing || modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting
                        onActivated: {
                            if (modelData.connected) modelData.disconnect()
                            else if (modelData.paired) modelData.connect()
                            else { modelData.trusted = true; modelData.pair() }
                        }
                    }
                }
                Chip { text: "Advanced…"; surface: view.app.bg; ink: view.app.fg; accent: view.app.accent; onClicked: { view.app.popup = ""; view.app.command(["blueman-manager"]) } }
            }

            // Quick toggles
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: 8
                columnSpacing: 8
                Tile {
                    icon: "󰂛"; title: "Do not disturb"
                    detail: view.app.dndAvailable ? (view.app.dnd ? "Notifications muted" : "Off") : "Unavailable"
                    lit: view.app.dnd
                    onToggled: view.app.setDnd(!view.app.dnd)
                }
                Tile {
                    icon: "󰖔"; title: "Night light"
                    detail: view.app.nightLight ? view.app.nightTemp + " K" : "Off"
                    lit: view.app.nightLight
                    onToggled: view.app.setQuick("nightLight", !view.app.nightLight)
                }
                Tile {
                    icon: "󰅶"; title: "Keep awake"
                    detail: view.app.caffeine ? "Idle actions paused" : "Off"
                    lit: view.app.caffeine
                    onToggled: view.app.caffeine = !view.app.caffeine
                }
                Tile {
                    icon: "󱐋"; title: "Performance"
                    detail: view.app.performance ? "Effects disabled" : "Off"
                    lit: view.app.performance
                    onToggled: view.app.script("session-controls.py", ["performance"])
                }
                Tile {
                    icon: PowerProfiles.profile === PowerProfile.PowerSaver ? "󰌪" : PowerProfiles.profile === PowerProfile.Performance ? "󰓅" : "󰗑"
                    title: "Power profile"
                    detail: view.profileName(PowerProfiles.profile)
                    lit: PowerProfiles.profile !== PowerProfile.Balanced
                    onToggled: view.cycleProfile()
                }
                Tile {
                    icon: "󰽥"; title: "Focus mode"
                    detail: view.app.focused ? "On" : "Off"
                    lit: view.app.focused
                    onToggled: view.app.script("victoria-controls.py", ["--focus"])
                }
            }

            RangeSetting {
                visible: view.app.nightLight
                app: view.app
                label: "Night light warmth"
                unit: " K"
                from: 2500; to: 6000; step: 100
                value: view.app.nightTemp
                onChanged: value => view.app.setQuick("nightTemp", value)
            }

            // Notification history
            RowLayout {
                Layout.fillWidth: true
                visible: view.app.notifications !== null
                Section { text: "NOTIFICATIONS" + (view.history.length ? " · " + view.history.length : ""); Layout.fillWidth: true }
                Chip { visible: view.history.length > 0; text: "Clear all"; surface: view.app.bg; ink: view.app.fg; accent: view.app.accent; implicitHeight: 24; onClicked: view.app.notifications.clearAll() }
            }
            Text {
                visible: view.app.notifications !== null && view.history.length === 0
                text: view.app.dnd ? "Do not disturb is on — new notifications wait here." : "You're all caught up."
                color: view.app.fg; opacity: 0.45
                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11
            }
            Repeater {
                model: view.history.slice().reverse().slice(0, 6)
                NotificationCard {
                    required property var modelData
                    center: view.app.notifications
                    notification: modelData
                    Layout.fillWidth: true
                    width: column.width
                }
            }

            // Sound
            Section { text: "SOUND" }
            VolumeRow { app: view.app; node: Pipewire.defaultAudioSink; glyph: "󰕾"; subtitle: "Output" }
            VolumeRow { app: view.app; node: Pipewire.defaultAudioSource; glyph: "󰍬"; subtitle: "Microphone" }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Chip { text: "󰕾  Mixer"; surface: view.app.bg; ink: view.app.fg; accent: view.app.accent; onClicked: view.app.popup = "audio" }
                Chip { text: "󰍬  Inputs"; surface: view.app.bg; ink: view.app.fg; accent: view.app.accent; onClicked: view.app.popup = "mic" }
            }

            // Now playing (compact)
            Rectangle {
                visible: view.player !== null
                Layout.fillWidth: true
                implicitHeight: 54
                radius: 14
                color: Qt.alpha(view.app.accent, 0.1)
                border.color: Qt.alpha(view.app.accent, 0.3)
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: view.app.popup = "media" }
                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 6 }
                    spacing: 8
                    Text { text: "󰝚"; color: view.app.accent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 18 }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Marquee { text: view.player ? view.player.trackTitle || view.player.identity : ""; color: view.app.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; font.bold: true; Layout.fillWidth: true }
                        Marquee { text: view.player ? view.player.trackArtist : ""; color: view.app.fg; opacity: 0.55; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; Layout.fillWidth: true }
                    }
                    Chip { text: "󰒮"; surface: view.app.bg; ink: view.app.fg; accent: view.app.accent; onClicked: view.player.previous() }
                    Chip { text: view.player && view.player.isPlaying ? "󰏤" : "󰐊"; selected: true; surface: view.app.bg; ink: view.app.fg; accent: view.app.accent; onClicked: view.player.togglePlaying() }
                    Chip { text: "󰒭"; surface: view.app.bg; ink: view.app.fg; accent: view.app.accent; onClicked: view.player.next() }
                }
            }

            // Capture
            Section { text: "CAPTURE" + (view.app.recording ? " · RECORDING" : "") }
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Action { icon: "󰨒"; label: "Region"; onActivated: view.capture(["screenshot.sh", "region"]) }
                Action { icon: "󰖯"; label: "Window"; onActivated: view.capture(["screenshot.sh", "window"]) }
                Action { icon: "󰍹"; label: "Screen"; onActivated: view.capture(["screenshot.sh", "screen"]) }
                Action { icon: "󰏫"; label: "Annotate"; onActivated: view.capture(["screenshot.sh", "region", "--edit"]) }
                Action {
                    icon: view.app.recording ? "󰓛" : "󰑊"
                    label: view.app.recording ? "Stop" : "Record"
                    danger: view.app.recording
                    onActivated: view.capture(view.app.recording ? ["record.sh", "stop"] : ["record.sh", "start", "screen", "audio"])
                }
            }

            // Tools and session
            Section { text: "QUICK ACTIONS" }
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Action { icon: "󰸉"; label: "Wallpaper"; onActivated: { view.app.popup = ""; view.app.command(["bash", view.app.home + "/.config/mango/scripts/wallpaper-picker.sh"]) } }
                Action { icon: "󰑖"; label: "Shuffle"; onActivated: view.app.command(["bash", view.app.home + "/.config/mango/scripts/wallpaper-random.sh"]) }
                Action { icon: "󰅌"; label: "Clipboard"; onActivated: { view.app.popup = ""; view.app.clipboardOpen = true } }
                Action { icon: "󰀻"; label: "Apps"; onActivated: { view.app.popup = ""; view.app.launcherOpen = true } }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Action { icon: "󰶐"; label: "Screens off"; onActivated: view.run("session-controls.py", ["screen-off"]) }
                Action { icon: "󰒲"; label: "Suspend"; onActivated: view.run("session-controls.py", ["suspend"]) }
                Action { icon: "󰜉"; label: "Restart"; danger: true; confirm: true; onActivated: view.app.command(["loginctl", "reboot"]) }
                Action { icon: "⏻"; label: "Shut down"; danger: true; confirm: true; onActivated: view.app.command(["loginctl", "poweroff"]) }
            }
        }
    }
}
