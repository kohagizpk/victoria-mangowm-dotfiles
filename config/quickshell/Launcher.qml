import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// App launcher (Super + D): fuzzy search over .desktop entries, most-used first,
// plus a tiny calculator ("2*21" -> Enter copies 42).
PanelWindow {
    id: win
    required property var app
    screen: app.activeScreen
    implicitWidth: 600
    implicitHeight: 540
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "victoria-launcher"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    property string query: ""
    property int current: 0
    property var usage: ({})

    function close() { app.launcherOpen = false }
    function score(entry, q) {
        if (!q) return 0
        const name = (entry.name || "").toLowerCase()
        if (name.startsWith(q)) return 100
        if (name.indexOf(q) >= 0) return 70
        const extra = [entry.genericName, entry.comment, (entry.keywords || []).join(" "), (entry.categories || []).join(" ")].join(" ").toLowerCase()
        if (extra.indexOf(q) >= 0) return 40
        // Subsequence match: "ffx" finds "Firefox".
        let i = 0
        for (const ch of name) if (ch === q[i]) i++
        return i === q.length ? 15 : -1
    }
    readonly property var results: {
        const q = query.trim().toLowerCase()
        return DesktopEntries.applications.values
            .filter(e => !e.noDisplay)
            .map(e => ({ entry: e, s: score(e, q) + Math.min(30, (usage[e.id] || 0) * 3) }))
            .filter(r => !q || r.s >= 15)
            .sort((a, b) => b.s - a.s || a.entry.name.localeCompare(b.entry.name))
            .slice(0, 60)
            .map(r => r.entry)
    }
    // Only digits, operators and parentheses, so evaluating it is safe.
    readonly property string calc: {
        const q = query.trim().replace(/^=/, "").replace(/,/g, ".").replace(/\^/g, "**")
        if (!/^[\d\s+\-*/().%]+$/.test(q) || !/[+\-*/%]/.test(q)) return ""
        try { const v = Function('"use strict"; return (' + q + ')')(); return Number.isFinite(v) ? String(Math.round(v * 1e10) / 1e10) : "" } catch (e) { return "" }
    }
    function launch(entry) {
        if (!entry) return
        const u = Object.assign({}, usage); u[entry.id] = (u[entry.id] || 0) + 1
        usageFile.setText(JSON.stringify(u))
        entry.execute()
        close()
    }
    function activate() {
        if (calc && current === 0) { app.command(["wl-copy", calc]); close(); return }
        launch(results[current - (calc ? 1 : 0)])
    }
    onQueryChanged: current = 0

    FileView {
        id: usageFile
        path: win.app.home + "/.local/state/victoria/launcher.json"
        printErrors: false
        onLoaded: { try { win.usage = JSON.parse(text()) } catch (e) {} }
    }

    Rectangle {
        anchors.fill: parent
        radius: 22
        color: win.app.bg
        border.color: Qt.alpha(win.app.accent, 0.5)

        ColumnLayout {
            anchors { fill: parent; margins: 16 }
            spacing: 12

            TextField {
                id: search
                Layout.fillWidth: true
                implicitHeight: 44
                focus: true
                placeholderText: "  Search apps, or type 12*4"
                color: win.app.fg
                placeholderTextColor: Qt.alpha(win.app.fg, 0.4)
                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14
                leftPadding: 16
                background: Rectangle { radius: 14; color: Qt.alpha(win.app.fg, 0.05); border.color: win.app.accent }
                onTextChanged: win.query = text
                Component.onCompleted: forceActiveFocus()
                Keys.onEscapePressed: win.close()
                Keys.onReturnPressed: win.activate()
                Keys.onEnterPressed: win.activate()
                Keys.onDownPressed: { win.current = Math.min(list.count - 1, win.current + 1); list.positionViewAtIndex(win.current, ListView.Contain) }
                Keys.onUpPressed: { win.current = Math.max(0, win.current - 1); list.positionViewAtIndex(win.current, ListView.Contain) }
                Keys.onTabPressed: { win.current = (win.current + 1) % Math.max(1, list.count); list.positionViewAtIndex(win.current, ListView.Contain) }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: (win.calc ? [{ calc: win.calc }] : []).concat(win.results)
                ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool isCalc: modelData.calc !== undefined
                    readonly property bool selected: index === win.current
                    width: ListView.view.width - 10
                    implicitHeight: 50
                    radius: 12
                    color: selected ? Qt.alpha(win.app.accent, 0.2) : rowMouse.containsMouse ? Qt.alpha(win.app.fg, 0.05) : "transparent"
                    border.color: selected ? Qt.alpha(win.app.accent, 0.5) : "transparent"
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: win.current = parent.index
                        onClicked: win.activate()
                    }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 12
                        Item {
                            implicitWidth: 32; implicitHeight: 32
                            Image {
                                id: icon
                                anchors.fill: parent
                                visible: !parent.parent.parent.isCalc && status === Image.Ready
                                source: parent.parent.parent.isCalc ? "" : Quickshell.iconPath(parent.parent.parent.modelData.icon || "", true)
                                sourceSize: Qt.size(64, 64)
                                asynchronous: true
                            }
                            Rectangle {
                                anchors.fill: parent
                                visible: !icon.visible
                                radius: 10
                                color: Qt.alpha(win.app.accent, 0.18)
                                Text { anchors.centerIn: parent; text: parent.parent.parent.parent.isCalc ? "󰃬" : "󰀻"; color: win.app.accent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16 }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: parent.parent.parent.isCalc ? "= " + parent.parent.parent.modelData.calc : parent.parent.parent.modelData.name
                                elide: Text.ElideRight
                                color: win.app.fg
                                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13; font.bold: parent.parent.parent.selected
                            }
                            Text {
                                Layout.fillWidth: true
                                text: parent.parent.parent.isCalc ? "Enter copies the result" : (parent.parent.parent.modelData.comment || parent.parent.parent.modelData.genericName || "")
                                visible: text.length > 0
                                elide: Text.ElideRight
                                color: win.app.fg; opacity: 0.5
                                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10
                            }
                        }
                        Text { visible: parent.parent.selected; text: "↵"; color: win.app.accent; font.pixelSize: 14 }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: list.count ? "↑↓ move · Enter open · Esc close" : "No app matches “" + win.query + "”"
                color: win.app.fg; opacity: 0.4
                horizontalAlignment: Text.AlignHCenter
                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10
            }
        }
    }
}
