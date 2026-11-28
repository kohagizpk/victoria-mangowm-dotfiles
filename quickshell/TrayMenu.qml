import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: menuWindow
    required property var app
    property var handles: []
    property string heading: ""
    property real anchorX: 0
    property var targetScreen: Quickshell.screens[0]
    visible: handles.length > 0
    screen: targetScreen
    anchors { top:app.prefs.bar_position!=="bottom";bottom:app.prefs.bar_position==="bottom";left:true }
    margins {top:app.barHeight+4;bottom:app.barHeight+4;left:Math.max(6,Math.min(anchorX,screen.width-implicitWidth-6))}
    exclusionMode:ExclusionMode.Ignore
    implicitWidth:280
    implicitHeight:Math.min(screen.height-60,content.implicitHeight+16)
    color:"transparent"
    WlrLayershell.namespace:"victoria-tray-menu"
    WlrLayershell.keyboardFocus:WlrKeyboardFocus.OnDemand
    function open(item, display, x) {
        if (!item.hasMenu) return;
        app.popup="";
        targetScreen=display;anchorX=x;heading=item.title||item.id;handles=[item.menu];
    }
    function close() {handles=[]}
    QsMenuOpener {id:opener;menu:menuWindow.handles.length?menuWindow.handles[menuWindow.handles.length-1]:null}
    Rectangle {
        anchors.fill:parent;radius:12;color:app.bg;border.color:Qt.alpha(app.accent,0.5)
        focus:true
        Keys.onEscapePressed:menuWindow.close()
        ScrollView {
            anchors.fill:parent;anchors.margins:8;contentWidth:availableWidth;clip:true
            ColumnLayout {
                id:content;width:parent.width;spacing:2
                RowLayout {
                    Layout.fillWidth:true
                    Chip {visible:menuWindow.handles.length>1;text:"‹";ink:app.fg;accent:app.accent;surface:app.bg;onClicked:menuWindow.handles=menuWindow.handles.slice(0,-1)}
                    Text {text:menuWindow.heading;Layout.fillWidth:true;elide:Text.ElideRight;color:Qt.alpha(app.fg,0.65);font.pixelSize:11}
                    Chip {text:"×";ink:app.fg;accent:app.accent;surface:app.bg;onClicked:menuWindow.close()}
                }
                Repeater {
                    model:opener.children
                    delegate:Rectangle {
                        id:entry
                        required property var modelData
                        Layout.fillWidth:true
                        implicitHeight:modelData.isSeparator?9:32
                        radius:6
                        color:hover.containsMouse&&!modelData.isSeparator?Qt.alpha(app.accent,0.22):"transparent"
                        Rectangle {visible:entry.modelData.isSeparator;anchors.centerIn:parent;width:parent.width-12;height:1;color:Qt.alpha(app.fg,0.15)}
                        RowLayout {
                            visible:!entry.modelData.isSeparator;anchors.fill:parent;anchors.leftMargin:8;anchors.rightMargin:8;spacing:8
                            Text {text:entry.modelData.checkState===Qt.Checked?"✓":"";color:app.accent;Layout.preferredWidth:12}
                            Image {visible:source.toString().length>0;source:entry.modelData.icon;sourceSize.width:16;sourceSize.height:16;Layout.preferredWidth:16;Layout.preferredHeight:16}
                            Text {text:entry.modelData.text.replace(/&/g,"");color:entry.modelData.enabled?app.fg:Qt.alpha(app.fg,0.4);font.pixelSize:12;Layout.fillWidth:true;elide:Text.ElideRight}
                            Text {text:entry.modelData.hasChildren?"›":"";color:app.fg}
                        }
                        MouseArea {
                            id:hover;anchors.fill:parent;hoverEnabled:true;enabled:!entry.modelData.isSeparator&&entry.modelData.enabled
                            onClicked:{if(entry.modelData.hasChildren)menuWindow.handles=menuWindow.handles.concat([entry.modelData]);else{entry.modelData.triggered();menuWindow.close()}}
                        }
                    }
                }
            }
        }
    }
}
