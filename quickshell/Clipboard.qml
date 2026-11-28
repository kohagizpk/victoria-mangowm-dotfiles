import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Clipboard history (Super + V) over cliphist, with image thumbnails.
PanelWindow {
    id: win
    required property var app
    screen: app.activeScreen
    implicitWidth: 560
    implicitHeight: 560
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "victoria-clipboard"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    property var rows: []          // [{ id, line, text, image }]
    property var thumbs: ({})      // id -> thumbnail path
    property string query: ""
    property int current: 0
    property bool confirmClear: false
    readonly property var shown: rows.filter(r => !query || r.text.toLowerCase().indexOf(query.toLowerCase()) >= 0)

    function close() { app.clipboardOpen = false }
    function pick(row) {
        if (!row) return
        // cliphist decode reads the original "ID<TAB>preview" line.
        app.command(["sh", "-c", 'printf "%s\\n" "$1" | cliphist decode | wl-copy', "sh", row.line])
        close()
    }
    function remove(row) {
        app.command(["sh", "-c", 'printf "%s\\n" "$1" | cliphist delete', "sh", row.line])
        rows = rows.filter(r => r.id !== row.id)
    }
    function clearAll() { app.command(["cliphist", "wipe"]); rows = []; confirmClear = false }
    onQueryChanged: current = 0

    Process {
        running: true
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n").slice(0, 300)) {
                    const tab = line.indexOf("\t")
                    if (tab < 0) continue
                    const body = line.slice(tab + 1)
                    out.push({ id: line.slice(0, tab), line: line, text: body, image: /^\[\[ binary data .*(png|jpe?g|webp|bmp)/.test(body) })
                }
                win.rows = out
                thumbProc.input = out.filter(r => r.image).slice(0, 40).map(r => r.line).join("\n") + "\n"
                thumbProc.running = true
            }
        }
    }
    Process {
        id: thumbProc
        property string input: ""
        command: ["bash", win.app.home + "/.config/mango/scripts/clipboard-thumbs.sh"]
        stdinEnabled: true
        onRunningChanged: if (running) { write(input); stdinEnabled = false }
        stdout: SplitParser {
            onRead: line => {
                const [id, path] = line.split("\t")
                const t = Object.assign({}, win.thumbs); t[id] = path; win.thumbs = t
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 22
        color: win.app.bg
        border.color: Qt.alpha(win.app.accent, 0.5)

        ColumnLayout {
            anchors { fill: parent; margins: 16 }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    id: search
                    Layout.fillWidth: true
                    implicitHeight: 42
                    focus: true
                    placeholderText: "󰅌  Search the clipboard…"
                    color: win.app.fg
                    placeholderTextColor: Qt.alpha(win.app.fg, 0.4)
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13
                    leftPadding: 14
                    background: Rectangle { radius: 13; color: Qt.alpha(win.app.fg, 0.05); border.color: win.app.accent }
                    onTextChanged: win.query = text
                    Component.onCompleted: forceActiveFocus()
                    Keys.onEscapePressed: win.close()
                    Keys.onReturnPressed: win.pick(win.shown[win.current])
                    Keys.onEnterPressed: win.pick(win.shown[win.current])
                    Keys.onDeletePressed: event => { if (search.text.length === 0 && win.shown[win.current]) win.remove(win.shown[win.current]); else event.accepted = false }
                    Keys.onDownPressed: { win.current = Math.min(list.count - 1, win.current + 1); list.positionViewAtIndex(win.current, ListView.Contain) }
                    Keys.onUpPressed: { win.current = Math.max(0, win.current - 1); list.positionViewAtIndex(win.current, ListView.Contain) }
                }
                Chip {
                    text: win.confirmClear ? "Clear all?" : "󰆴"
                    tip: "Erase the whole history"
                    selected: win.confirmClear
                    surface: win.app.bg; ink: win.app.fg; accent: win.app.accent
                    implicitHeight: 42
                    onClicked: win.confirmClear ? win.clearAll() : (win.confirmClear = true)
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 3
                model: win.shown
                ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === win.current
                    readonly property string thumb: win.thumbs[modelData.id] || ""
                    width: ListView.view.width - 10
                    implicitHeight: thumb ? 76 : 46
                    radius: 12
                    color: selected ? Qt.alpha(win.app.accent, 0.2) : rowMouse.containsMouse ? Qt.alpha(win.app.fg, 0.05) : Qt.alpha(win.app.fg, 0.02)
                    border.color: selected ? Qt.alpha(win.app.accent, 0.5) : "transparent"
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onEntered: win.current = parent.index
                        onClicked: mouse => mouse.button === Qt.MiddleButton ? win.remove(parent.modelData) : win.pick(parent.modelData)
                    }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 12
                        Image {
                            visible: parent.parent.thumb.length > 0
                            Layout.preferredWidth: 96; Layout.preferredHeight: 60
                            source: parent.parent.thumb ? "file://" + parent.parent.thumb : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        Text {
                            visible: !parent.parent.thumb
                            text: parent.parent.modelData.image ? "󰋩" : "󰅍"
                            color: win.app.accent
                            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15
                        }
                        Text {
                            Layout.fillWidth: true
                            text: parent.parent.modelData.image ? parent.parent.modelData.text.replace(/^\[\[ binary data /, "Image · ").replace(/ \]\]$/, "")
                                                                : parent.parent.modelData.text.replace(/\s+/g, " ").trim()
                            maximumLineCount: 2
                            wrapMode: Text.WrapAnywhere
                            elide: Text.ElideRight
                            color: win.app.fg
                            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12
                        }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: win.rows.length === 0 ? "The clipboard history is empty." : list.count ? "Enter copy · Del remove · middle-click remove · Esc close" : "Nothing matches “" + win.query + "”"
                color: win.app.fg; opacity: 0.4
                horizontalAlignment: Text.AlignHCenter
                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10
            }
        }
    }
}
