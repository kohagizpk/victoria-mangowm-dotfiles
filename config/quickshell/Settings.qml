import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Wayland

// Victoria Settings: centered panel, wallust-themed, edits a draft until Apply.
PanelWindow {
    id: win
    required property var app
    readonly property string page: app.settingsPage
    screen: app.settingsScreen
    implicitWidth: Math.min(980, (screen ? screen.width : 1920) - 80)
    implicitHeight: Math.min(700, (screen ? screen.height : 1080) - 100)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "victoria-settings"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    readonly property var pages: [
        { id: "profile", icon: "󰀄", label: "Profile" },
        { id: "appearance", icon: "󰏘", label: "Appearance" },
        { id: "bar", icon: "󰍜", label: "Bar & clock" },
        { id: "notifications", icon: "󰂚", label: "Notifications" },
        { id: "input", icon: "󰌌", label: "Keyboard & mouse" },
        { id: "idle", icon: "󰒲", label: "Lock & idle" },
        { id: "setup", icon: "󰍹", label: "Setup" },
        { id: "shortcuts", icon: "", label: "Shortcuts" },
        { id: "health", icon: "󰓙", label: "Health" }
    ]
    readonly property var settingsPages: ["appearance", "bar", "notifications", "input", "idle"]
    readonly property var profileNotes: ({ Minimal: "Flat, still and quiet", Comfort: "Bigger text, softer spacing", Effects: "Rounder, layered, animated" })

    property var info: null
    property var saved: ({})
    property var draft: ({})
    readonly property bool dirty: JSON.stringify(draft) !== JSON.stringify(saved)
    property string status: ""
    property bool statusError: false

    function v(key) { return draft[key] }
    function set(key, value) { const d = Object.assign({}, draft); d[key] = value; draft = d }
    function merge(values) { draft = Object.assign({}, draft, values) }
    function say(text, error) { status = text; statusError = error === true }
    function close() { app.settingsPage = "" }
    function load() {
        cli.call("state", undefined, r => {
            if (!r.ok) { say(r.error, true); return }
            info = r.data
            saved = r.data.settings
            draft = Object.assign({}, r.data.settings)
            setup.reset()
        })
    }
    function apply() {
        say("Applying…")
        cli.call("save", draft, r => {
            if (!r.ok) { say(r.error, true); return }
            saved = r.data
            draft = Object.assign({}, r.data)
            say("Applied. Mango, the bar and notifications reloaded.")
        })
    }

    Component.onCompleted: load()
    Cli { id: cli }

    // Wizard state for the Setup page (keyboard, displays, apps).
    QtObject {
        id: setup
        property string primary: "English (US)"
        property string secondary: "None"
        property string switchKey: "Alt + Shift"
        property string layout: "Keep current"
        property real scale: 1
        property string terminal: "Keep current"
        property string browser: "Keep current"
        property int countdown: 0
        function reset() {
            if (!win.info) return
            primary = win.info.keyboard.primary
            secondary = win.info.keyboard.secondary
            switchKey = win.info.keyboard.switch
        }
        function apply() {
            win.say("Applying setup…")
            cli.call("setup", { keyboard: primary, secondary: secondary, switch: switchKey, layout: layout,
                                scale: scale, terminal: terminal, browser: browser }, r => {
                if (!r.ok) { win.say(r.error, true); return }
                if (r.data.confirmDisplays) { countdown = 20; win.say("Keep the new display layout?") }
                else win.say("Setup applied. The keyboard layout is active now.")
            })
        }
        function confirm(keep) {
            countdown = 0
            cli.call("displays", keep ? "keep" : "revert", r => win.say(!r.ok ? r.error : keep ? "Display layout kept." : "Display layout reverted.", !r.ok))
        }
    }
    Timer {
        interval: 1000; repeat: true
        running: setup.countdown > 0
        onTriggered: { setup.countdown -= 1; if (setup.countdown === 0) setup.confirm(false) }
    }

    // ---------- shared pieces ----------
    component Label: Text { color: win.app.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; wrapMode: Text.WordWrap }
    component Button: Chip { surface: win.app.bg; ink: win.app.fg; accent: win.app.accent; implicitHeight: 32; radius: 10 }
    component Switch: Toggle { accent: win.app.accent; ink: win.app.fg }
    component Choice: Segmented { accent: win.app.accent; ink: win.app.fg }
    component Combo: ThemedCombo { accent: win.app.accent; ink: win.app.fg; surface: win.app.bg; implicitWidth: 260 }
    component Field: TextField {
        color: win.app.fg
        placeholderTextColor: Qt.alpha(win.app.fg, 0.35)
        selectionColor: Qt.alpha(win.app.accent, 0.4)
        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12
        leftPadding: 12; rightPadding: 12
        implicitHeight: 34
        background: Rectangle {
            radius: 10
            color: Qt.alpha(win.app.fg, 0.05)
            border.color: parent.activeFocus ? win.app.accent : Qt.alpha(win.app.fg, 0.12)
        }
    }
    component ToggleRow: SettingRow {
        id: toggleRow
        property string key: ""
        app: win.app
        Switch { checked: win.v(toggleRow.key) === true; onToggled: c => win.set(toggleRow.key, c) }
    }
    component Range: RangeSetting {
        id: range
        property string key: ""
        app: win.app
        value: win.v(key) || 0
        onChanged: value => win.set(range.key, value)
    }
    component PageHeader: ColumnLayout {
        property string title: ""
        property string subtitle: ""
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        spacing: 2
        Text { text: parent.title; color: win.app.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 20; font.bold: true }
        Text { text: parent.subtitle; color: win.app.fg; opacity: 0.5; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
    }
    component Page: ScrollView {
        default property alias content: pageColumn.data
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            id: pageColumn
            width: parent.width - 14
            spacing: 14
        }
    }

    // ---------- window ----------
    Rectangle {
        anchors.fill: parent
        radius: 24
        color: win.app.bg
        border.color: Qt.alpha(win.app.accent, 0.5)
        focus: true
        Keys.onEscapePressed: win.close()

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // Sidebar
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 220
                radius: 24
                color: Qt.alpha(win.app.fg, 0.03)
                ColumnLayout {
                    anchors { fill: parent; margins: 16 }
                    spacing: 4
                    RowLayout {
                        Layout.bottomMargin: 18
                        Layout.topMargin: 6
                        spacing: 10
                        Rectangle {
                            implicitWidth: 34; implicitHeight: 34; radius: 11
                            color: win.app.accent
                            Text { anchors.centerIn: parent; text: "V"; color: win.app.bg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 17; font.bold: true }
                        }
                        ColumnLayout {
                            spacing: 0
                            Text { text: "Victoria"; color: win.app.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14; font.bold: true }
                            Text { text: "Settings"; color: win.app.fg; opacity: 0.45; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.letterSpacing: 2 }
                        }
                    }
                    Repeater {
                        model: win.pages
                        Rectangle {
                            required property var modelData
                            readonly property bool current: win.page === modelData.id
                            Layout.fillWidth: true
                            implicitHeight: 36
                            radius: 11
                            color: current ? Qt.alpha(win.app.accent, 0.18) : navMouse.containsMouse ? Qt.alpha(win.app.fg, 0.05) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Rectangle {
                                visible: parent.current
                                width: 3; height: 16; radius: 2
                                anchors { left: parent.left; leftMargin: 2; verticalCenter: parent.verticalCenter }
                                color: win.app.accent
                            }
                            RowLayout {
                                anchors { fill: parent; leftMargin: 14; rightMargin: 10 }
                                spacing: 12
                                Text { text: modelData.icon; color: parent.parent.current ? win.app.accent : win.app.fg; opacity: parent.parent.current ? 1 : 0.7; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15; Layout.preferredWidth: 18 }
                                Text { text: modelData.label; color: win.app.fg; opacity: parent.parent.current ? 1 : 0.75; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; font.bold: parent.parent.current; Layout.fillWidth: true }
                                Rectangle {
                                    visible: win.dirty && win.settingsPages.indexOf(modelData.id) >= 0 && win.settingsPages.some(p => p === modelData.id)
                                             && modelData.id === win.page
                                    implicitWidth: 6; implicitHeight: 6; radius: 3; color: win.app.accent
                                }
                            }
                            MouseArea { id: navMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.app.settingsPage = modelData.id }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    Button {
                        Layout.fillWidth: true
                        text: win.app.focused ? "󰽥  Leave focus mode" : "󰽥  Focus mode"
                        selected: win.app.focused
                        tip: "Silence notifications and hide secondary bar modules"
                        onClicked: cli.call("focus", undefined, r => win.say(!r.ok ? r.error : r.data ? "Focus mode on." : "Focus mode off.", !r.ok))
                    }
                }
            }

            // Content
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 22
                Layout.rightMargin: 14
                spacing: 12

                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    active: win.info !== null
                    sourceComponent: ({ profile: profilePage, appearance: appearancePage, bar: barPage, notifications: notificationsPage, input: inputPage,
                                        idle: idlePage, setup: setupPage, shortcuts: shortcutsPage, health: healthPage })[win.page] || appearancePage
                }
                Label {
                    visible: win.info === null
                    Layout.fillWidth: true; Layout.fillHeight: true
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    text: win.status || "Loading your settings…"
                    opacity: 0.6
                }

                // Footer: status + apply bar for draft-based pages.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.rightMargin: 8
                    spacing: 10
                    Text {
                        Layout.fillWidth: true
                        text: win.status || (win.settingsPages.indexOf(win.page) < 0 ? "" : win.dirty ? "You have unsaved changes." : "Changes apply when you press Apply.")
                        color: win.statusError ? "#ff8080" : win.app.fg
                        opacity: win.statusError ? 1 : 0.55
                        elide: Text.ElideRight
                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11
                    }
                    Button { visible: win.dirty; text: "Discard"; onClicked: { win.draft = Object.assign({}, win.saved); win.say("") } }
                    Button {
                        text: cli.busy ? "Working…" : "Apply"
                        selected: win.dirty
                        enabled: win.dirty && !cli.busy
                        opacity: enabled ? 1 : 0.45
                        visible: win.settingsPages.indexOf(win.page) >= 0
                        onClicked: win.apply()
                    }
                    Button { text: "×"; implicitWidth: 32; onClicked: win.close() }
                }
            }
        }
    }

    // ---------- pages ----------
    Component {
        id: profilePage
        Page {
            id: profileView
            readonly property string home: win.app.home
            function pick(path) {
                win.say("Updating your picture…")
                cli.call("avatar", path, r => { win.say(r.ok ? (path ? "Profile picture updated." : "Profile picture removed.") : r.error, !r.ok); if (r.ok) win.app.refreshProfile() })
            }
            PageHeader { title: "Profile"; subtitle: "Your picture appears in the Control Center and on the lock screen. It is saved as ~/.face." }

            Card {
                app: win.app
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 22
                    Avatar {
                        app: win.app
                        implicitWidth: 112; implicitHeight: 112
                        ring: true
                        source: win.app.profile.round || ""
                        name: win.app.profile.name || ""
                        version: win.app.avatarVersion
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Label { text: "Display name"; opacity: 0.55; font.pixelSize: 10 }
                        Field {
                            Layout.fillWidth: true
                            text: win.app.profile.name || ""
                            maximumLength: 40
                            placeholderText: win.app.profile.user || ""
                            onEditingFinished: if (text !== win.app.profile.name)
                                cli.call("profile-name", text, r => { if (r.ok) { win.app.profile = r.data; win.say("Name saved.") } else win.say(r.error, true) })
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            Button { text: "󰉏  Choose image…"; selected: true; enabled: !cli.busy
                                onClicked: { win.say("Pick an image in the file chooser…"); cli.call("avatar-choose", undefined, r => { win.say(!r.ok ? r.error : r.data ? "Profile picture updated." : "No image chosen.", !r.ok); if (r.ok && r.data) win.app.refreshProfile() }) } }
                            Button { text: "󰉋  Avatars folder"; tip: "~/Pictures/Avatars — drop pictures here"; onClicked: win.app.command(["xdg-open", profileView.home + "/Pictures/Avatars"]) }
                            Button { text: "󰆴  Remove"; visible: !!win.app.profile.avatar; onClicked: profileView.pick(null) }
                        }
                    }
                }
            }

            Repeater {
                model: [
                    { title: "Avatars", icon: "󰀄", folder: profileView.home + "/Pictures/Avatars", hint: "Pictures you drop in ~/Pictures/Avatars" },
                    { title: "Pictures", icon: "󰋩", folder: profileView.home + "/Pictures", hint: "Images directly inside ~/Pictures" },
                    { title: "Wallpapers", icon: "󰸉", folder: profileView.home + "/Pictures/Wallpapers", hint: "Your wallpaper collection" }
                ]
                Card {
                    id: gallery
                    required property var modelData
                    app: win.app
                    title: modelData.title
                    icon: modelData.icon
                    hint: modelData.hint
                    visible: files.count > 0 || modelData.title === "Avatars"
                    FolderListModel {
                        id: files
                        folder: "file://" + gallery.modelData.folder
                        showDirs: false
                        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.PNG", "*.JPG", "*.JPEG"]
                        sortField: FolderListModel.Time
                    }
                    Label { visible: files.count === 0; opacity: 0.5; font.pixelSize: 11; text: "Empty for now — put a few pictures in " + gallery.modelData.folder.replace(profileView.home, "~") + "." }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 10
                        Repeater {
                            model: files
                            Item {
                                required property string filePath
                                required property string fileName
                                width: 68; height: 68
                                Image {
                                    anchors.fill: parent
                                    source: "file://" + parent.filePath
                                    sourceSize: Qt.size(136, 136)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                // Frame drawn over the photo; hover shows the accent.
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 12
                                    color: "transparent"
                                    border.width: thumbMouse.containsMouse ? 3 : 1
                                    border.color: thumbMouse.containsMouse ? win.app.accent : Qt.alpha(win.app.fg, 0.2)
                                }
                                MouseArea {
                                    id: thumbMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: profileView.pick(parent.filePath)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: appearancePage
        Page {
            PageHeader { title: "Make it yours"; subtitle: "Colors follow your wallpaper through wallust. Everything previews here before you apply it." }

            // Live preview of the desktop with the draft values.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 190
                radius: 18
                clip: true
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.darker(win.app.palette.color1 || win.app.accent, 1.6) }
                    GradientStop { position: 1; color: Qt.darker(win.app.palette.color4 || win.app.accent, 2.2) }
                }
                readonly property color previewAccent: win.v("color_mode") === "fixed" ? win.v("accent") : win.app.accent
                readonly property real gap: (win.v("gaps") || 0) * 0.6
                Rectangle {
                    id: mockBar
                    anchors { left: parent.left; right: parent.right; top: win.v("bar_position") === "bottom" ? undefined : parent.top; bottom: win.v("bar_position") === "bottom" ? parent.bottom : undefined; margins: 8 }
                    height: 18; radius: 7
                    color: Qt.alpha(win.app.bg, 0.9)
                    Row {
                        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        Repeater { model: 4; Rectangle { required property int index; width: 10; height: 10; radius: 3; color: index === 0 ? parent.parent.parent.previewAccent : Qt.alpha(win.app.fg, 0.3) } }
                    }
                    Text { anchors.centerIn: parent; text: "12:00"; color: win.app.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: Math.max(8, (win.v("font_size") || 12) - 3) }
                }
                Row {
                    anchors {
                        left: parent.left; right: parent.right; margins: 8 + parent.gap
                        top: win.v("bar_position") === "bottom" ? parent.top : mockBar.bottom
                        bottom: win.v("bar_position") === "bottom" ? mockBar.top : parent.bottom
                        topMargin: 8 + parent.gap; bottomMargin: 8 + parent.gap
                    }
                    spacing: parent.gap
                    Repeater {
                        model: [{ focused: true, title: "kitty" }, { focused: false, title: "helium" }]
                        Rectangle {
                            required property var modelData
                            width: (parent.width - parent.spacing) / 2
                            height: parent.height
                            radius: (win.v("radius") || 0) * 0.7
                            color: win.app.bg
                            opacity: modelData.focused ? 1 : win.v("opacity") || 1
                            border.width: win.v("border") || 0
                            border.color: modelData.focused ? parent.parent.previewAccent : Qt.alpha(win.app.fg, 0.2)
                            Column {
                                anchors { fill: parent; margins: 12 }
                                spacing: 6
                                Text { text: modelData.title; color: modelData.focused ? parent.parent.parent.parent.previewAccent : win.app.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: win.v("font_size") || 12; font.bold: true }
                                Repeater { model: 3; Rectangle { required property int index; width: parent.width * (0.9 - index * 0.2); height: 5; radius: 3; color: Qt.alpha(win.app.fg, 0.15) } }
                            }
                        }
                    }
                }
            }

            Card {
                app: win.app; title: "Start from a profile"; icon: "󰉼"
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Repeater {
                        model: Object.keys(win.info.profiles)
                        Rectangle {
                            required property string modelData
                            readonly property var profile: win.info.profiles[modelData]
                            readonly property bool active: Object.keys(profile).every(k => win.draft[k] === profile[k])
                            Layout.fillWidth: true
                            implicitHeight: 64
                            radius: 14
                            color: active ? Qt.alpha(win.app.accent, 0.18) : profileMouse.containsMouse ? Qt.alpha(win.app.fg, 0.06) : Qt.alpha(win.app.fg, 0.03)
                            border.color: active ? win.app.accent : Qt.alpha(win.app.fg, 0.1)
                            ColumnLayout {
                                anchors { fill: parent; margins: 12 }
                                spacing: 2
                                Text { text: modelData; color: win.app.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13; font.bold: true }
                                Text { text: win.profileNotes[modelData] || ""; color: win.app.fg; opacity: 0.5; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10 }
                            }
                            MouseArea { id: profileMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.merge(parent.profile) }
                        }
                    }
                }
            }

            Card {
                app: win.app; title: "Color"; icon: "󰏘"; hint: "Wallpaper keeps the palette in sync with every new wallpaper."
                SettingRow {
                    app: win.app; label: "Palette source"
                    Choice { options: [{ label: "Wallpaper", value: "wallpaper" }, { label: "Fixed accent", value: "fixed" }]; value: win.v("color_mode"); onPicked: x => win.set("color_mode", x) }
                }
                ColumnLayout {
                    visible: win.v("color_mode") === "fixed"
                    Layout.fillWidth: true
                    spacing: 8
                    Label { text: "Accent — pick from your current palette or type a color"; opacity: 0.6; font.pixelSize: 11 }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        Repeater {
                            model: ["color1", "color2", "color3", "color4", "color5", "color6", "color9", "color10", "color11", "color12", "color13", "color14"]
                                .map(k => win.app.palette[k]).filter((c, i, all) => c && all.indexOf(c) === i)
                            Rectangle {
                                required property string modelData
                                readonly property bool chosen: String(win.v("accent")).toLowerCase() === modelData.toLowerCase()
                                width: 30; height: 30; radius: 10
                                color: modelData
                                border.width: chosen ? 3 : 1
                                border.color: chosen ? win.app.fg : Qt.alpha(win.app.fg, 0.2)
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.set("accent", parent.modelData.toUpperCase()) }
                            }
                        }
                        Field {
                            width: 120
                            text: win.v("accent") || ""
                            maximumLength: 7
                            validator: RegularExpressionValidator { regularExpression: /#[0-9a-fA-F]{0,6}/ }
                            onTextEdited: if (/^#[0-9a-fA-F]{6}$/.test(text)) win.set("accent", text.toUpperCase())
                        }
                    }
                }
            }

            Card {
                app: win.app; title: "Shape & spacing"; icon: "󰹑"
                Range { key: "gaps"; label: "Space between windows"; unit: " px"; from: 0; to: 30 }
                Range { key: "border"; label: "Border thickness"; unit: " px"; from: 0; to: 8 }
                Range { key: "radius"; label: "Rounded corners"; unit: " px"; from: 0; to: 30 }
                Range { key: "opacity"; label: "Inactive window opacity"; from: 0.7; to: 1; step: 0.01; decimals: 2 }
                Range { key: "font_size"; label: "Interface text size"; unit: " px"; from: 10; to: 20 }
            }

            Card {
                app: win.app; title: "Motion & depth"; icon: "󰄄"
                ToggleRow { key: "animations"; label: "Window animations" }
                SettingRow {
                    app: win.app; label: "Animation speed"; opacity: win.v("animations") ? 1 : 0.4
                    Choice { options: [{ label: "Fast", value: "fast" }, { label: "Normal", value: "normal" }, { label: "Relaxed", value: "relaxed" }]; value: win.v("animation_speed"); onPicked: x => win.set("animation_speed", x) }
                }
                ToggleRow { key: "shadows"; label: "Window shadows" }
                SettingRow {
                    app: win.app; label: "Background blur"; hint: "Off while SceneFX issue #198 breaks screen sharing with blur."
                    Switch { checked: false; enabled: false }
                }
            }

            Card {
                app: win.app; title: "Wallpaper"; icon: "󰸉"; hint: "Your wallpapers live in ~/Pictures/Wallpapers. Picking one regenerates every color automatically."
                RowLayout {
                    spacing: 8
                    Button { text: "󰸉  Choose wallpaper"; selected: true; onClicked: { win.close(); win.app.command(["bash", win.app.home + "/.config/mango/scripts/wallpaper-picker.sh"]) } }
                    Button { text: "󰉋  Open folder"; tip: "~/Pictures/Wallpapers — drop images here"; onClicked: win.app.command(["xdg-open", win.app.home + "/Pictures/Wallpapers"]) }
                    Button { text: "󰑓  Refresh colors"; onClicked: cli.call("repair", "Refresh colors", r => win.say(r.ok ? "Colors regenerated from the current wallpaper." : r.error, !r.ok)) }
                }
                SettingRow {
                    app: win.app; label: "Change automatically"; hint: "A random wallpaper from the folder, on every monitor. Applies right away."
                    Switch { checked: win.app.wallRotate; onToggled: c => win.app.setQuick("wallRotate", c) }
                }
                RangeSetting {
                    visible: win.app.wallRotate
                    app: win.app; label: "Every"; unit: " min"; from: 5; to: 240; step: 5
                    value: win.app.wallInterval
                    onChanged: value => win.app.setQuick("wallInterval", value)
                }
            }

            Card {
                app: win.app; title: "Night light"; icon: "󰖔"; hint: "Warmer colors in the evening. Applies right away."
                SettingRow {
                    app: win.app; label: "Night light"
                    Switch { checked: win.app.nightLight; onToggled: c => win.app.setQuick("nightLight", c) }
                }
                SettingRow {
                    app: win.app; label: "When"; opacity: win.app.nightLight ? 1 : 0.4
                    Choice { options: [{ label: "Always", value: "always" }, { label: "Scheduled", value: "schedule" }]; value: win.app.nightMode; onPicked: x => win.app.setQuick("nightMode", x) }
                }
                RowLayout {
                    visible: win.app.nightMode === "schedule"
                    Layout.fillWidth: true
                    spacing: 10
                    Label { text: "From"; opacity: 0.7 }
                    Field { implicitWidth: 90; text: win.app.nightStart; inputMask: "99:99"; onEditingFinished: if (/^([01]\d|2[0-3]):[0-5]\d$/.test(text)) win.app.setQuick("nightStart", text) }
                    Label { text: "to"; opacity: 0.7 }
                    Field { implicitWidth: 90; text: win.app.nightEnd; inputMask: "99:99"; onEditingFinished: if (/^([01]\d|2[0-3]):[0-5]\d$/.test(text)) win.app.setQuick("nightEnd", text) }
                    Label { text: "· fades over 30 min"; opacity: 0.45; font.pixelSize: 10; Layout.fillWidth: true }
                }
                RangeSetting {
                    app: win.app; label: "Warmth"; unit: " K"; from: 2500; to: 6000; step: 100
                    value: win.app.nightTemp
                    onChanged: value => win.app.setQuick("nightTemp", value)
                }
            }
        }
    }

    Component {
        id: barPage
        Page {
            PageHeader { title: "Bar & clock"; subtitle: "Only the information you want to see, where you want it." }
            Card {
                app: win.app; title: "Placement"; icon: "󰍜"
                SettingRow {
                    app: win.app; label: "Position"
                    Choice { options: [{ label: "Top", value: "top" }, { label: "Bottom", value: "bottom" }]; value: win.v("bar_position"); onPicked: x => win.set("bar_position", x) }
                }
                Range { key: "bar_margin"; label: "Space from screen edges"; unit: " px"; from: 0; to: 16 }
            }
            Card {
                app: win.app; title: "Modules"; icon: "󰕮"
                ToggleRow { key: "show_stats"; label: "CPU, memory and temperature" }
                ToggleRow { key: "show_media"; label: "Now playing" }
                ToggleRow { key: "show_visualizer"; label: "Audio visualizer"; hint: "Runs cava only while something is playing." }
                ToggleRow { key: "show_tray"; label: "App tray" }
            }
            Card {
                app: win.app; title: "Clock"; icon: "󰥔"
                ToggleRow { key: "clock_24h"; label: "24-hour clock" }
                ToggleRow { key: "clock_seconds"; label: "Show seconds" }
                Label {
                    opacity: 0.55; font.pixelSize: 11
                    text: "Preview: " + Qt.formatDateTime(win.app.now, (win.v("clock_24h") ? "HH:mm" : "hh:mm") + (win.v("clock_seconds") ? ":ss" : "") + (win.v("clock_24h") ? "" : " AP"))
                }
            Card {
                app: win.app; title: "Weather"; icon: "󰖐"; hint: "Shown in the bar and the calendar. Uses wttr.in every 30 minutes; that service sees your IP address and the city."
                SettingRow {
                    app: win.app; label: "Show the weather"
                    Switch { checked: win.app.weatherOn; onToggled: c => win.app.setQuick("weatherOn", c) }
                }
                RowLayout {
                    visible: win.app.weatherOn
                    Layout.fillWidth: true
                    spacing: 8
                    Field {
                        Layout.fillWidth: true
                        text: win.app.weatherCity
                        placeholderText: "City, e.g. São Paulo (empty = guess from your IP)"
                        onEditingFinished: if (text !== win.app.weatherCity) win.app.setQuick("weatherCity", text.trim())
                    }
                    Button { text: "󰑓"; tip: "Refresh now"; onClicked: win.app.refreshWeather() }
                }
                Label {
                    visible: win.app.weatherOn
                    opacity: 0.6; font.pixelSize: 11
                    text: win.app.weather ? win.app.weather.icon + "  " + win.app.weather.temp + "° · " + win.app.weather.desc + " · " + win.app.weather.area : "Loading…"
                }
            }
            }
        }
    }

    Component {
        id: notificationsPage
        Page {
            PageHeader { title: "Notifications"; subtitle: "Less interruption, the way you prefer. Critical alerts always stay visible." }
            Card {
                app: win.app; title: "Where they appear"; icon: "󰂚"
                RowLayout {
                    spacing: 18
                    // Click the corner of the miniature screen.
                    Rectangle {
                        implicitWidth: 180; implicitHeight: 112; radius: 12
                        color: Qt.alpha(win.app.fg, 0.05)
                        border.color: Qt.alpha(win.app.fg, 0.15)
                        Repeater {
                            model: ["top-left", "top-right", "bottom-left", "bottom-right"]
                            Rectangle {
                                required property string modelData
                                readonly property bool chosen: win.v("notification_position") === modelData
                                width: 64; height: 22; radius: 7
                                x: modelData.endsWith("left") ? 8 : parent.width - width - 8
                                y: modelData.startsWith("top") ? 8 : parent.height - height - 8
                                color: chosen ? win.app.accent : cornerMouse.containsMouse ? Qt.alpha(win.app.accent, 0.25) : Qt.alpha(win.app.fg, 0.1)
                                MouseArea { id: cornerMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.set("notification_position", parent.modelData) }
                            }
                        }
                    }
                    Label { Layout.fillWidth: true; opacity: 0.6; font.pixelSize: 11; text: "Click a corner. The notification panel opens on the same side." }
                }
            }
            Card {
                app: win.app; title: "Behavior"; icon: "󰔟"
                Range { key: "notification_timeout"; label: "Time on screen"; unit: " s"; from: 3; to: 20 }
                Range { key: "notification_width"; label: "Width"; unit: " px"; from: 300; to: 600; step: 20 }
                ToggleRow { key: "notification_images"; label: "Show images and app icons" }
            }
        }
    }

    Component {
        id: inputPage
        Page {
            PageHeader { title: "Keyboard & mouse"; subtitle: "Make moving around feel natural. Layouts live in Setup." }
            Card {
                app: win.app; title: "Pointer"; icon: "󰇀"
                Range { key: "cursor_size"; label: "Pointer size"; unit: " px"; from: 16; to: 64; step: 4 }
                ToggleRow { key: "focus_follows_mouse"; label: "Focus windows when the pointer enters" }
            }
            Card {
                app: win.app; title: "Touchpad"; icon: "󰟸"
                ToggleRow { key: "tap_to_click"; label: "Tap to click" }
                ToggleRow { key: "natural_scroll"; label: "Natural scrolling"; hint: "Content follows your fingers." }
            }
            Card {
                app: win.app; title: "Key repeat"; icon: "󰌌"; hint: "How long to hold a key before it repeats, and how fast."
                Range { key: "repeat_delay"; label: "Delay before repeating"; unit: " ms"; from: 150; to: 1000; step: 25 }
                Range { key: "repeat_rate"; label: "Repeat rate"; unit: " /s"; from: 10; to: 80 }
                Field { Layout.fillWidth: true; placeholderText: "Hold a key here to test… (after Apply)" }
            }
        }
    }

    Component {
        id: idlePage
        Page {
            PageHeader { title: "Lock & idle"; subtitle: "Automatic locking, screens and sleep. Media apps can still keep the screen awake." }
            Card {
                app: win.app; title: "Automatic actions"; icon: "󰒲"
                ToggleRow { key: "idle_enabled"; label: "Lock and power down when idle" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    opacity: win.v("idle_enabled") ? 1 : 0.4
                    enabled: win.v("idle_enabled") === true
                    Range { key: "idle_lock_minutes"; label: "Lock after"; unit: " min"; from: 1; to: 120 }
                    Range { key: "idle_screen_minutes"; label: "Turn screens off after"; unit: " min"; from: 1; to: 180 }
                    Range { key: "idle_suspend_minutes"; label: "Suspend after (0 = never)"; unit: " min"; from: 0; to: 240 }
                    Label {
                        readonly property bool valid: win.v("idle_screen_minutes") >= win.v("idle_lock_minutes")
                            && (!win.v("idle_suspend_minutes") || win.v("idle_suspend_minutes") >= win.v("idle_screen_minutes"))
                        Layout.fillWidth: true
                        font.pixelSize: 11
                        color: valid ? win.app.fg : "#ff8080"
                        opacity: valid ? 0.55 : 1
                        text: valid ? "Order: lock → screens off → suspend. Locking always happens first."
                                    : "Screens must turn off after locking, and suspend after that."
                    }
                }
            }
            Card {
                app: win.app; title: "Right now"; icon: "󰌾"
                RowLayout {
                    spacing: 8
                    Button { text: "󰌾  Lock"; onClicked: { win.close(); win.app.script("session-controls.py", ["lock"]) } }
                    Button { text: "󰶐  Screens off"; onClicked: { win.close(); win.app.script("session-controls.py", ["screen-off"]) } }
                    Button { text: "󰅶  Keep awake"; selected: win.app.caffeine; tip: "Block idle actions until you turn this off"; onClicked: win.app.caffeine = !win.app.caffeine }
                }
            }
        }
    }

    Component {
        id: setupPage
        Page {
            PageHeader { title: "Setup"; subtitle: "Keyboard layouts, displays and your favorite apps. Nothing is installed here." }
            Rectangle {
                visible: setup.countdown > 0
                Layout.fillWidth: true
                implicitHeight: 56; radius: 14
                color: Qt.alpha(win.app.accent, 0.2)
                border.color: win.app.accent
                RowLayout {
                    anchors { fill: parent; margins: 12 }
                    Label { Layout.fillWidth: true; font.bold: true; text: "Keep this display layout? Reverting in " + setup.countdown + " s" }
                    Button { text: "Revert"; onClicked: setup.confirm(false) }
                    Button { text: "Keep"; selected: true; onClicked: setup.confirm(true) }
                }
            }
            Card {
                app: win.app; title: "Keyboard"; icon: "󰌌"; hint: "Add a second layout to switch between them with a shortcut."
                SettingRow { app: win.app; label: "Layout"
                    Combo { model: win.info.keyboards; currentIndex: model.indexOf(setup.primary); onActivated: i => setup.primary = model[i] }
                }
                SettingRow { app: win.app; label: "Second layout"
                    Combo { model: ["None"].concat(win.info.keyboards); currentIndex: model.indexOf(setup.secondary); onActivated: i => setup.secondary = model[i] }
                }
                SettingRow { app: win.app; label: "Switch layouts with"; visible: setup.secondary !== "None"
                    Choice { options: win.info.switches; value: setup.switchKey; onPicked: x => setup.switchKey = x }
                }
                Field { Layout.fillWidth: true; placeholderText: "Type here to try the layout (after Apply setup)…" }
            }
            Card {
                app: win.app; title: "Displays"; icon: "󰍹"
                Row {
                    spacing: 10
                    visible: win.info.displays.length > 0
                    Repeater {
                        model: win.info.displays
                        Rectangle {
                            required property var modelData
                            width: modelData.width / 14; height: modelData.height / 14; radius: 8
                            color: Qt.alpha(win.app.accent, 0.12)
                            border.color: Qt.alpha(win.app.accent, 0.6)
                            Column {
                                anchors.centerIn: parent
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.modelData.name; color: win.app.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.bold: true }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.modelData.width + "×" + parent.parent.modelData.height + (parent.parent.modelData.refresh ? " · " + parent.parent.modelData.refresh + " Hz" : ""); color: win.app.fg; opacity: 0.6; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                            }
                        }
                    }
                }
                Label { visible: win.info.displays.length === 0; opacity: 0.6; text: "No readable displays. Keep the current layout." }
                SettingRow { app: win.app; label: "Arrangement"; hint: "Automatic places the detected displays side by side. You get 20 s to confirm."
                    Choice { options: [{ label: "Keep current", value: "Keep current" }, { label: "Automatic", value: "Automatic side by side" }]; value: setup.layout; onPicked: x => setup.layout = x }
                }
                SettingRow { app: win.app; label: "Scale"; visible: setup.layout !== "Keep current"
                    Choice { options: [{ label: "100%", value: 1 }, { label: "125%", value: 1.25 }, { label: "150%", value: 1.5 }, { label: "200%", value: 2 }]; value: setup.scale; onPicked: x => setup.scale = x }
                }
            }
            Card {
                app: win.app; title: "Apps"; icon: "󰀻"; hint: "Super + Enter opens the terminal, Super + W the browser. Only installed apps are listed."
                SettingRow { app: win.app; label: "Terminal"
                    Choice { options: ["Keep current"].concat(win.info.terminals); value: setup.terminal; onPicked: x => setup.terminal = x }
                }
                SettingRow { app: win.app; label: "Browser"
                    Choice { options: ["Keep current"].concat(win.info.browsers); value: setup.browser; onPicked: x => setup.browser = x }
                }
            }
            Card {
                app: win.app; title: "Welcome screen"; icon: "󰋜"
                SettingRow { app: win.app; label: "Open Settings automatically at login"
                    Switch {
                        checked: win.info.openAtLogin
                        onToggled: c => cli.call("open-at-login", c, r => { if (r.ok) win.info = Object.assign({}, win.info, { openAtLogin: r.data }) })
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Reset"; onClicked: setup.reset() }
                Button { text: "󰄬  Apply setup"; selected: true; enabled: !cli.busy && setup.countdown === 0; onClicked: setup.apply() }
            }
        }
    }

    Component {
        id: shortcutsPage
        ColumnLayout {
            id: shortcutsView
            spacing: 12
            property var rows: []
            property string query: ""
            readonly property var shown: rows.filter(r => (r.keys + " " + r.action).toLowerCase().indexOf(query.toLowerCase()) >= 0)
            Component.onCompleted: cli.call("shortcuts", undefined, r => { if (r.ok) rows = r.data; else win.say(r.error, true) })
            PageHeader { title: "Shortcuts"; subtitle: "The bindings Mango actually loaded, including your personal overrides." }
            Field { Layout.fillWidth: true; placeholderText: "  Search a key, app or action…"; onTextChanged: shortcutsView.query = text; Component.onCompleted: forceActiveFocus() }
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: shortcutsView.shown
                ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width - 12
                    implicitHeight: 38
                    radius: 10
                    color: rowMouse.containsMouse ? Qt.alpha(win.app.accent, 0.1) : Qt.alpha(win.app.fg, 0.03)
                    MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 12 }
                        spacing: 6
                        Row {
                            Layout.preferredWidth: 250
                            spacing: 4
                            Repeater {
                                model: modelData.keys.split(" + ")
                                Rectangle {
                                    required property string modelData
                                    width: keyText.implicitWidth + 14; height: 22; radius: 6
                                    color: Qt.alpha(win.app.accent, 0.14)
                                    border.color: Qt.alpha(win.app.accent, 0.4)
                                    Text { id: keyText; anchors.centerIn: parent; text: modelData; color: win.app.accent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.bold: true }
                                }
                            }
                        }
                        Text { Layout.fillWidth: true; text: modelData.action; elide: Text.ElideRight; color: win.app.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12 }
                    }
                }
            }
            Label { visible: shortcutsView.rows.length > 0 && shortcutsView.shown.length === 0; opacity: 0.5; text: "No shortcut matches “" + shortcutsView.query + "”." }
        }
    }

    Component {
        id: healthPage
        Page {
            id: healthView
            property var rows: []
            property bool checked: false
            function check() { cli.call("diagnostics", undefined, r => { if (r.ok) { rows = r.data; checked = true } else win.say(r.error, true) }) }
            Component.onCompleted: check()
            PageHeader { title: "Desktop health"; subtitle: "Checks explain what is missing. Repairs run only when you press them." }
            Card {
                app: win.app
                title: !healthView.checked ? "Checking…" : healthView.rows.every(r => r.ok) ? "Everything looks good" : healthView.rows.filter(r => !r.ok).length + " thing(s) need attention"
                icon: healthView.rows.every(r => r.ok) ? "󰄬" : "󰀦"
                Repeater {
                    model: healthView.rows
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 10
                        Text { text: modelData.ok ? "󰄬" : "󰀦"; color: modelData.ok ? win.app.accent : "#ffb070"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13; Layout.alignment: Qt.AlignTop }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Label { text: modelData.name; Layout.fillWidth: true }
                            Label { visible: !modelData.ok; text: modelData.hint; opacity: 0.55; font.pixelSize: 10; Layout.fillWidth: true }
                        }
                    }
                }
            }
            Card {
                app: win.app; title: "Repairs"; icon: "󰖷"
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Button { text: "󰑐  Run checks again"; selected: true; onClicked: healthView.check() }
                    Repeater {
                        model: [{ label: "󰏘  Refresh colors", action: "Refresh colors" }, { label: "󰸉  Restore wallpaper", action: "Restore wallpaper" }, { label: "󰂚  Reload notifications", action: "Reload notifications" }]
                        Button {
                            required property var modelData
                            text: modelData.label
                            onClicked: cli.call("repair", modelData.action, r => win.say(r.ok ? r.data : r.error, !r.ok))
                        }
                    }
                }
            }
        }
    }
}
