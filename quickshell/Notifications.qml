import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications

// Notification daemon: popups in the corner chosen in Settings, history for the
// Control Center, Do-not-disturb (critical alerts still show).
Item {
    id: daemon
    required property var app
    readonly property var history: server.trackedNotifications.values
    property var popups: []          // notifications currently shown as popups (newest first)

    readonly property string position: app.prefs.notification_position || "top-right"
    readonly property int timeoutMs: (app.prefs.notification_timeout || 8) * 1000
    readonly property int cardWidth: app.prefs.notification_width || 380
    readonly property bool showImages: app.prefs.notification_images !== false

    function dismissPopup(n) { popups = popups.filter(p => p !== n) }
    function clearAll() { for (const n of history.slice()) n.dismiss(); popups = [] }
    function iconFor(n) {
        const icon = n.appIcon || ""
        if (icon.startsWith("/") ) return "file://" + icon
        if (icon.startsWith("file://") || icon.startsWith("image://")) return icon
        return icon ? Quickshell.iconPath(icon, true) : ""
    }
    function invokeDefault(n) {
        const action = n.actions.find(a => a.identifier === "default")
        if (action) action.invoke()
        else if (n.desktopEntry) { const e = DesktopEntries.byId(n.desktopEntry); if (e) e.execute() }
        n.dismiss()
    }

    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        actionsSupported: true
        imageSupported: true
        onNotification: n => {
            n.tracked = true
            const critical = n.urgency === NotificationUrgency.Critical
            if (daemon.app.dnd && !critical) return
            // The Control Center already lists it.
            if (daemon.app.popup === "control" && !critical) return
            daemon.popups = [n].concat(daemon.popups.filter(p => p !== n)).slice(0, 4)
        }
    }

    // Popup stack in the configured corner of the focused monitor.
    PanelWindow {
        visible: daemon.popups.length > 0
        screen: daemon.app.activeScreen
        anchors {
            top: daemon.position.startsWith("top"); bottom: daemon.position.startsWith("bottom")
            right: daemon.position.endsWith("right"); left: daemon.position.endsWith("left")
        }
        margins { top: daemon.app.barHeight + 8; bottom: daemon.app.barHeight + 8; left: 10; right: 10 }
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: daemon.cardWidth
        implicitHeight: Math.max(1, stack.implicitHeight)
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "victoria-notifications"
        Column {
            id: stack
            width: parent.width
            spacing: 8
            Repeater {
                model: daemon.popups
                NotificationCard { required property var modelData; center: daemon; notification: modelData; popup: true }
            }
        }
    }
}
