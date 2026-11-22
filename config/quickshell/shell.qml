import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.SystemTray

ShellRoot {
    id: root
    property string home: Quickshell.env("HOME")
    property var data: ({settings:{},sinks:[],sources:[],"sink-inputs":[],battery:[]})
    property var prefs: data.settings || ({})
    property var tags: []
    property var palette: ({background:"#111014",foreground:"#dedade",color5:"#b18aa6"})
    property color bg: palette.background
    property color fg: palette.foreground
    property color accent: prefs.color_mode === "fixed" ? prefs.accent : Qt.lighter(palette.color5,1.6)
    property int barHeight: 28
    property real popupX: 0
    property string popup: ""
    property var popupScreen: Quickshell.screens[0]
    property var player: Mpris.players.values.find(p => p.isPlaying && p.trackTitle) || Mpris.players.values.find(p => p.trackTitle) || Mpris.players.values[0] || null
    property string cava: ""
    property bool focused: data.focus || false
    property bool stats: prefs.show_stats !== false && !focused
    property bool media: prefs.show_media !== false && !focused
    property bool visualizer: prefs.show_visualizer !== false && !focused && (data["sink-inputs"] || []).some(s => !s.corked && !s.mute)
    function command(args) { Quickshell.execDetached(args) }
    function script(name, args) { command(["python3",home+"/.config/mango/scripts/"+name].concat(args||[])) }
    function toggle(name, screen, x) { trayMenu.close(); popupScreen=screen; popupX=x===undefined ? screen.width-210 : x; popup=popup===name ? "" : name }
    function audioDefault(mic) { return (data[mic ? "sources":"sinks"]||[]).find(d => d.name===data[mic ? "source":"sink"]) || {volume:0,mute:false} }
    function volume(mic,delta) { command(["wpctl","set-volume","-l","1.0",mic?"@DEFAULT_AUDIO_SOURCE@":"@DEFAULT_AUDIO_SINK@",delta>0?"2%+":"2%-"]) }
    function mute(mic) { command(["wpctl","set-mute",mic?"@DEFAULT_AUDIO_SOURCE@":"@DEFAULT_AUDIO_SINK@","toggle"]) }
    FileView { path: root.home+"/.config/mango/waybar/colors.css"; watchChanges: true; onFileChanged: reload(); onLoaded: { let c={}; let pattern=/@define-color\s+(\w+)\s+(#[0-9a-fA-F]{6})/g; let m; while((m=pattern.exec(text()))!==null)c[m[1]]=m[2]; if(c.background)root.palette=c } }
    Process { running: true; command: ["python3",Qt.resolvedUrl("backend.py").toString().replace("file://","")]; stdout: SplitParser { onRead: line => { try {root.data=JSON.parse(line)}catch(e){console.warn(e)} } } }
    Process { id: tagWatch; running: true; command:["mmsg","watch","all-tags"]; stdout: SplitParser { onRead: line => {try{root.tags=JSON.parse(line).all_tags||[]}catch(e){}} } onExited: tagRetry.start() }
    Timer { id:tagRetry; interval:2000; onTriggered:tagWatch.running=true }
    Process { running: root.visualizer; command:["python3",Qt.resolvedUrl("visualizer.py").toString().replace("file://","")]; stdout:SplitParser {onRead:line=>root.cava=line} }
    SystemClock { id: clock; precision: root.prefs.clock_seconds === false ? SystemClock.Minutes : SystemClock.Seconds }
    IpcHandler { target:"bar"; function status():string {return JSON.stringify({palette:root.palette,focus:root.focused,popup:root.popup,screen:root.popupScreen?root.popupScreen.name:"none",players:Mpris.players.values.map(p=>({name:p.identity,title:p.trackTitle,meta:p.metadata}))})} function close():void {root.popup=""} function toggle(name:string):void {root.toggle(name,root.popupScreen)} }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData
            anchors { top: root.prefs.bar_position !== "bottom"; bottom: root.prefs.bar_position === "bottom"; left:true; right:true }
            implicitHeight: root.barHeight
            color:"transparent"
            WlrLayershell.namespace:"victoria-bar"
            property int gap: Math.max(4,root.prefs.bar_margin||0)
            property bool altClock:false
            IpcHandler {
                target:"bar-"+bar.screen.name
                function mixer():void {audioButton.openPopup("audio")}
                function trayMenu(index:int):void {let item=trayItems.itemAt(index);if(item)item.showMenu()}
            }
            component Group: Rectangle { radius:Math.min(18,root.prefs.radius||12); color:Qt.alpha(root.bg,root.prefs.opacity||0.95); border.color:Qt.alpha(root.fg,0.13); height:24 }
            component Item: Chip { surface:root.bg; ink:root.fg; accent:root.accent; implicitHeight:22; radius:7; function openPopup(name) {root.toggle(name,bar.screen,mapToItem(bar.contentItem,0,0).x+width/2)} }
            Group {
                x:bar.gap; anchors.verticalCenter:parent.verticalCenter; width:leftRow.implicitWidth+8
                Row { id:leftRow; anchors.centerIn:parent; spacing:1
                    Repeater {
                        model: (root.tags.find(m=>m.monitor===bar.screen.name)||{}).tags || []
                        Item { required property var modelData; text:String(modelData.index); selected:modelData.is_active; ink:modelData.is_urgent?"#ff8080":modelData.client_count>0?root.fg:Qt.alpha(root.fg,0.4)
                            onClicked: button=>root.command(["python3",Qt.resolvedUrl("backend.py").toString().replace("file://",""),"workspace",bar.screen.name,String(modelData.index),button===Qt.RightButton?"toggle":"view"]) }
                    }
                    Item { text:""; tip:"Victoria Settings"; onClicked:root.script("victoria-controls.py") }
                    Item { text:root.audioDefault(true).mute?"󰍭 Off":"󰍬 On"; onClicked:button=>button===Qt.RightButton?openPopup("mic"):root.mute(true); onScrolled:delta=>root.volume(true,delta) }
                    Item { id:audioButton; text:(root.audioDefault(false).mute?"󰝟 ":"󰕾 ")+root.audioDefault(false).volume+"%"; onClicked:button=>button===Qt.RightButton?openPopup("audio"):root.mute(false); onScrolled:delta=>root.volume(false,delta) }
                    Item { visible:root.stats; text:"󰍛 "+(root.data.cpu||0)+"%" }
                    Item { visible:root.stats; text:"󰾅 "+(root.data.memory||0)+"GB" }
                }
            }
            Group {
                anchors.centerIn:parent; width:trayRow.implicitWidth+16; visible:root.prefs.show_tray!==false && trayRow.implicitWidth>0
                Row { id:trayRow; anchors.centerIn:parent; spacing:10
                    Repeater { id:trayItems; model:SystemTray.items
                        Image { id:trayIcon; function showMenu() {if(modelData.hasMenu)trayMenu.open(modelData,bar.screen,mapToItem(bar.contentItem,0,0).x)} required property var modelData; width:18;height:18; sourceSize.width:18;sourceSize.height:18; source:modelData.icon; fillMode:Image.PreserveAspectFit
                            MouseArea { anchors.fill:parent; acceptedButtons:Qt.LeftButton|Qt.RightButton|Qt.MiddleButton; onClicked:mouse=>{if(mouse.button===Qt.RightButton || trayIcon.modelData.onlyMenu)trayIcon.showMenu();else if(mouse.button===Qt.MiddleButton)trayIcon.modelData.secondaryActivate();else trayIcon.modelData.activate()} onWheel:event=>trayIcon.modelData.scroll(event.angleDelta.y,false) }
                        }
                    }
                }
            }
            Group {
                anchors.right:parent.right; anchors.rightMargin:bar.gap; anchors.verticalCenter:parent.verticalCenter; width:rightRow.implicitWidth+8
                Row { id:rightRow; anchors.centerIn:parent; spacing:1
                    Item { visible:root.focused; text:"FOCUS"; onClicked:root.script("victoria-controls.py",["--focus"]) }
                    Repeater { model:root.data.battery||[]; Item {required property var modelData; text:"󰁹 "+modelData.percent+"%";tip:modelData.status} }
                    Item { text:"󰤨 "+(root.data.network||"Offline").substring(0,16); tip:root.data.networkTip||"" }
                    Item { visible:root.stats; ink:root.data.temperature>=80?"#ff8080":root.fg; text:" "+(root.data.temperature===null?"—":root.data.temperature||"—")+"°C" }
                    Item { visible:root.media && root.player!==null; text:(root.player&&root.player.isPlaying?"󰐊 ":"󰏤 ")+(root.player?(root.player.trackArtist+" · "+root.player.trackTitle).substring(0,bar.width<1700?23:36):""); tip:root.player?root.player.trackTitle:""; onClicked:button=>{if(button===Qt.RightButton)openPopup("media");else if(root.player){if(button===Qt.MiddleButton && root.player.canGoPrevious)root.player.previous();else if(root.player.canTogglePlaying)root.player.togglePlaying()}} }
                    Item { visible:root.visualizer; text:root.cava; ink:root.accent }
                    Item { text:Qt.formatDateTime(clock.date,bar.altClock?"dd/MM/yyyy":(root.prefs.clock_24h===false?"hh:mm":"HH:mm")+(root.prefs.clock_seconds===false?"":":ss")+(root.prefs.clock_24h===false?" AP":"")); selected:true; onClicked:button=>button===Qt.RightButton?openPopup("calendar"):bar.altClock=!bar.altClock }
                    Item { text:"";tip:"Control center";onClicked:root.script("control-center.py") }
                    Item { text:"⏻";ink:root.accent;onClicked:button=>root.command(button===Qt.RightButton?["systemctl","poweroff"]:button===Qt.MiddleButton?["systemctl","reboot"]:["wlogout"]) }
                }
            }
        }
    }
    TrayMenu { id:trayMenu; app:root }
    LazyLoader { active:root.popup!==""; Popups { app:root } }
}
