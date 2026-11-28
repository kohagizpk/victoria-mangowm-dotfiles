import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray

ShellRoot {
    id: root
    property string home: Quickshell.env("HOME")
    property var data: ({battery:[]})
    property var prefs: ({})
    property bool performance: false
    property bool dnd: false
    property date now: clock.date
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
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
    // Settings panel ("" = closed) and quick-settings state.
    property string settingsPage: ""
    property var settingsScreen: Quickshell.screens[0]
    property bool caffeine: false
    property bool nightLight: false
    property int nightTemp: 4000
    property string nightMode: "always"   // "always" or "schedule"
    property string nightStart: "20:00"
    property string nightEnd: "07:00"
    property var notifications: null
    // Automatic wallpaper rotation (scripts/wallpaper-random.sh) and opt-in weather.
    property bool wallRotate: false
    property int wallInterval: 30
    property bool weatherOn: false
    property string weatherCity: ""
    property var weather: null
    Timer { interval: Math.max(5, root.wallInterval) * 60000; repeat: true; running: root.wallRotate && !root.locked
        onTriggered: root.command(["bash", root.home + "/.config/mango/scripts/wallpaper-random.sh"]) }
    // wttr.in, every 30 min, only when enabled in Settings → Bar & clock.
    function refreshWeather() { if (weatherOn) { weatherProc.running = false; weatherProc.running = true } else weather = null }
    onWeatherOnChanged: refreshWeather()
    onWeatherCityChanged: refreshWeather()
    Timer { interval: 1800000; repeat: true; running: root.weatherOn; onTriggered: root.refreshWeather() }
    Process { id: weatherProc
        command: ["curl", "-fsS", "--max-time", "10", "https://wttr.in/" + encodeURIComponent(root.weatherCity.trim()) + "?format=j1"]
        stdout: StdioCollector { onStreamFinished: {
            try {
                const d = JSON.parse(text), c = d.current_condition[0], code = Number(c.weatherCode)
                const icon = code === 113 ? "󰖙" : code === 116 ? "󰖕" : [119,122].includes(code) ? "󰖐"
                    : [143,248,260].includes(code) ? "󰖑" : [200,386,389,392,395].includes(code) ? "󰖓"
                    : (code >= 179 && code <= 230) || (code >= 320 && code <= 338) || (code >= 368 && code <= 377) ? "󰖘" : "󰖗"
                const area = d.nearest_area && d.nearest_area[0] ? d.nearest_area[0].areaName[0].value : root.weatherCity
                root.weather = { icon: icon, temp: c.temp_C, feels: c.FeelsLikeC, desc: c.weatherDesc[0].value, area: area, humidity: c.humidity,
                                 max: d.weather[0].maxtempC, min: d.weather[0].mintempC }
            } catch (e) { root.weather = null }
        } } }
    // Screen recording state, pushed by scripts/record.sh through IPC.
    property bool recording: false
    property real recordingSince: 0
    function openSettings(page) { settingsScreen=popupScreen||Quickshell.screens[0]; settingsPage=page||"appearance"; refreshProfile() }
    readonly property var quickKeys: ["nightLight", "nightTemp", "dnd", "nightMode", "nightStart", "nightEnd", "wallRotate", "wallInterval", "weatherOn", "weatherCity"]
    function setQuick(key,value) { root[key]=value; const q={}; for (const k of quickKeys) q[k]=root[k]; quickFile.setText(JSON.stringify(q)) }
    FileView { id:quickFile; printErrors:false; watchChanges:true; onFileChanged:reload(); path:root.home+"/.local/state/victoria/quick.json"; onLoaded:{ try { let q=JSON.parse(text()); for (const k of root.quickKeys) if (q[k] !== undefined) root[k]=q[k] } catch(e) {} } }
    // wlsunset with a 1-minute "day" keeps the low temperature on all the time.
    // Schedule: wlsunset fades to the warm temperature between sunset (nightStart) and sunrise (nightEnd).
    Process { running: root.nightLight; command: root.nightMode === "schedule"
        ? ["wlsunset","-t",String(root.nightTemp),"-T","6500","-s",root.nightStart,"-S",root.nightEnd,"-d","1800"]
        : ["wlsunset","-t",String(root.nightTemp),"-T",String(root.nightTemp+1),"-S","00:00","-s","00:01"] }
    // Profile shown in the Control Center and Settings (scripts/victoria_settings.py profile()).
    property var profile: ({ name: Quickshell.env("USER"), avatar: null })
    property int avatarVersion: 0
    function refreshProfile() { profileCli.call("profile", undefined, r => { if (r.ok) { root.profile = r.data; root.avatarVersion++ } }) }
    Cli { id: profileCli; Component.onCompleted: { root.refreshProfile(); root.refreshKeyboard() } }
    // Keyboard layout indicator: Mango streams the active layout description.
    property var kbLayouts: []
    property string kbCurrent: ""
    readonly property string kbLabel: { const m = kbLayouts.find(l => l.description === kbCurrent); return m ? m.code : kbCurrent.substring(0, 2).toUpperCase() }
    function refreshKeyboard() { profileCli.call("keyboard", undefined, r => { if (r.ok) root.kbLayouts = r.data }) }
    Process { id: kbWatch; running: true; command: ["mmsg", "watch", "keyboardlayout"]
        stdout: SplitParser { onRead: line => { try { root.kbCurrent = JSON.parse(line).layout || "" } catch (e) {} } }
        onExited: kbRetry.start() }
    Timer { id: kbRetry; interval: 3000; onTriggered: kbWatch.running = true }
    FileView { printErrors: false; path: root.home + "/.config/mango/local/input.conf"; watchChanges: true; onFileChanged: { reload(); root.refreshKeyboard() } }
    // Focused monitor, streamed by Mango; new panels (OSD, launcher, lock) open there.
    property string activeMonitor: ""
    readonly property var activeScreen: Quickshell.screens.find(s => s.name === activeMonitor) || Quickshell.screens[0]
    Process { id: monWatch; running: true; command: ["mmsg", "watch", "all-monitors"]
        stdout: SplitParser { onRead: line => { try { const m = (JSON.parse(line).monitors || []).find(x => x.active); if (m) root.activeMonitor = m.name } catch (e) {} } }
        onExited: monRetry.start() }
    Timer { id: monRetry; interval: 3000; onTriggered: monWatch.running = true }

    // ---------- OSD ----------
    property var osdInfo: ({})
    property var osdScreen: Quickshell.screens[0]
    property bool osdVisible: false
    property bool osdReady: false   // ignore the burst of changes while PipeWire settles at startup
    Timer { interval: 3000; running: true; onTriggered: root.osdReady = true }
    Timer { id: osdHide; interval: 1600; onTriggered: root.osdVisible = false }
    function showOsd(info) {
        // The mixer/control center already show the change; don't cover them.
        if (!osdReady || popup === "audio" || popup === "mic" || popup === "control") return
        osdInfo = info; osdScreen = activeScreen; osdVisible = true; osdHide.restart()
    }
    function volumeOsd() { const n = audioNode(false); if (n) showOsd({ icon: n.audio.muted ? "󰝟" : n.audio.volume > 0.5 ? "󰕾" : "󰖀", title: n.description || "Volume", level: n.audio.volume, muted: n.audio.muted }) }
    Connections { target: root.sink ? root.sink.audio : null; function onVolumeChanged() { root.volumeOsd() } function onMutedChanged() { root.volumeOsd() } }
    Connections { target: root.source ? root.source.audio : null
        function onMutedChanged() { const n = root.audioNode(true); if (n) root.showOsd({ icon: n.audio.muted ? "󰍭" : "󰍬", title: n.description || "Microphone", level: n.audio.volume, muted: n.audio.muted }) } }
    onKbCurrentChanged: if (kbLayouts.length > 1) showOsd({ icon: "󰌌", title: kbLabel, detail: kbCurrent })
    LazyLoader { active: root.osdVisible; Osd { app: root } }

    // Launcher (Super + D) and clipboard history (Super + V).
    property bool launcherOpen: false
    property bool clipboardOpen: false
    LazyLoader { active: root.launcherOpen; Launcher { app: root } }
    LazyLoader { active: root.clipboardOpen; Clipboard { app: root } }

    // ---------- Lock screen (Lock.qml) ----------
    // Always instantiated: destroying a WlSessionLock while locked would leave Mango locked.
    property bool locked: false
    property bool lockSecure: false
    property string wallpaper: ""
    FileView { printErrors: false; path: root.home + "/.local/state/victoria/last-wallpaper"; watchChanges: true
        onFileChanged: reload(); onLoaded: root.wallpaper = text().trim() }
    onLockedChanged: if (locked) { popup = ""; settingsPage = ""; launcherOpen = false; clipboardOpen = false; refreshProfile() }
    Lock { app: root }

    property bool visualizer: prefs.show_visualizer !== false && !focused && Mpris.players.values.some(p => p.isPlaying)
    function command(args) { Quickshell.execDetached(args) }
    function script(name, args) { command(["python3",home+"/.config/mango/scripts/"+name].concat(args||[])) }
    function toggle(name, screen, x) { if(name==="control"&&popup!=="control")refreshProfile(); trayMenu.close(); popupScreen=screen; popupX=x===undefined ? screen.width-210 : x; popup=popup===name ? "" : name }
    // Audio is read and written through PipeWire directly: live, no polling, no processes.
    function audioNode(mic) { let n=mic ? source : sink; return n && n.audio ? n : null }
    function audioLabel(mic) { let n=audioNode(mic); return n ? Math.round(n.audio.volume*100)+"%" : "—" }
    function audioMuted(mic) { let n=audioNode(mic); return n ? n.audio.muted : false }
    function volume(mic,delta) { let n=audioNode(mic); if(!n)return; let v=n.audio.volume; n.audio.volume=delta>0 ? Math.min(Math.max(1,v),v+0.02) : Math.max(0,v-0.02) }
    function mute(mic) { let n=audioNode(mic); if(n)n.audio.muted=!n.audio.muted }
    function workspace(monitor,tag,toggle) {
        if(toggle)command(["sh","-c",'mmsg dispatch "focusmon,$1" && mmsg dispatch "toggleview,$2"',"sh",monitor,String(tag)])
        else command(["mmsg","dispatch","viewcrossmon,"+tag+","+monitor])
    }
    PwObjectTracker { objects: [root.sink, root.source].filter(n => n) }
    FileView { path: root.home+"/.config/mango/local/settings.json"; watchChanges: true; onFileChanged: reload(); onLoaded: { try { root.prefs=JSON.parse(text()) } catch(e) {} } }
    FileView { printErrors:false; path: root.home+"/.config/mango/local/performance.conf"; watchChanges: true; onFileChanged: reload(); onLoaded: root.performance=/^animations=0$/m.test(text()) }
    // Notifications are served by Quickshell (Notifications.qml); swaync is only the Waybar fallback.
    readonly property bool dndAvailable: true
    function setDnd(on) { setQuick("dnd", on) }
    Notifications { id: notificationCenter; app: root; Component.onCompleted: root.notifications = notificationCenter }
    FileView { path: root.home+"/.config/mango/waybar/colors.css"; watchChanges: true; onFileChanged: reload(); onLoaded: { let c={}; let pattern=/@define-color\s+(\w+)\s+(#[0-9a-fA-F]{6})/g; let m; while((m=pattern.exec(text()))!==null)c[m[1]]=m[2]; if(c.background)root.palette=c } }
    Process { running: true; command: ["python3",Qt.resolvedUrl("backend.py").toString().replace("file://","")]; stdout: SplitParser { onRead: line => { try {root.data=JSON.parse(line)}catch(e){console.warn(e)} } } }
    Process { id: tagWatch; running: true; command:["mmsg","watch","all-tags"]; stdout: SplitParser { onRead: line => {try{root.tags=JSON.parse(line).all_tags||[]}catch(e){}} } onExited: tagRetry.start() }
    Timer { id:tagRetry; interval:2000; onTriggered:tagWatch.running=true }
    Process { running: root.visualizer; command:["cava","-p",Qt.resolvedUrl("cava.conf").toString().replace("file://","")]; stdout:SplitParser {onRead:line=>root.cava=line.split(";").filter(n=>n!=="").map(n=>"▁▂▃▄▅▆▇█"[+n]||"").join("")} }
    SystemClock { id: clock; precision: root.prefs.clock_seconds === false ? SystemClock.Minutes : SystemClock.Seconds }
    IpcHandler { target:"bar"; function status():string {return JSON.stringify({palette:root.palette,focus:root.focused,popup:root.popup,screen:root.popupScreen?root.popupScreen.name:"none",players:Mpris.players.values.map(p=>({name:p.identity,title:p.trackTitle,meta:p.metadata}))})} function close():void {root.popup=""} function toggle(name:string):void {root.toggle(name,root.popupScreen)} function settings(page:string):void {root.popup="";root.openSettings(page)} function controlCenter():void {root.toggle("control",root.popupScreen)}
        // Scriptable quick settings (also handy for keybinds): quickshell ipc -p ~/.config/mango/quickshell call bar <fn> …
        function volume(mic:bool,delta:int):void {root.volume(mic,delta)}
        function mute(mic:bool):void {root.mute(mic)}
        function nightLight(on:bool):void {root.setQuick("nightLight",on)}
        function caffeine(on:bool):void {root.caffeine=on}
        function osd(kind:string,level:real):void {root.showOsd({icon:kind==="brightness"?(level>0.5?"󰃠":"󰃞"):"󰕾",title:kind==="brightness"?"Brightness":kind,level:level,muted:false})}
        function launcher():void {root.clipboardOpen=false;root.popup="";root.launcherOpen=!root.launcherOpen}
        function clipboard():void {root.launcherOpen=false;root.popup="";root.clipboardOpen=!root.clipboardOpen}
        function dnd(on:bool):void {root.setDnd(on)}
        function dndStatus():string {return root.dnd?"true":"false"}
        function clearNotifications():void {root.notifications.clearAll()}
        function notificationCount():string {return String(root.notifications.history.length)+" history, "+root.notifications.popups.length+" popups"}
        // lock/unlock mirror hyprlock's signals; session-controls.py waits for lockStatus "locked".
        function lock():void {root.locked=true}
        function unlock():void {root.locked=false}
        function lockStatus():string {return !root.locked?"unlocked":root.lockSecure?"locked":"pending"}
        // e.g. call bar set weatherCity "\"Lisbon\"" — value is JSON.
        function set(key:string,value:string):void {if(root.quickKeys.indexOf(key)>=0)root.setQuick(key,JSON.parse(value))}
        function get(key:string):string {return JSON.stringify(root[key])}
        function recording(on:bool):void {root.recording=on; root.recordingSince=Date.now()}
        function quick():string {return JSON.stringify({sink:root.sink?root.sink.name:null,volume:root.audioLabel(false),muted:root.audioMuted(false),source:root.source?root.source.name:null,micVolume:root.audioLabel(true),micMuted:root.audioMuted(true),nightLight:root.nightLight,nightTemp:root.nightTemp,caffeine:root.caffeine,dnd:root.dnd,dndAvailable:root.dndAvailable,performance:root.performance,focus:root.focused,profile:root.profile.name,settingsPage:root.settingsPage,kb:root.kbLabel,kbLayouts:root.kbLayouts.length,recording:root.recording,wallRotate:root.wallRotate,weather:root.weather})} }
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
            // "Keep awake": one inhibitor on the first screen is enough.
            IdleInhibitor { window: bar; enabled: root.caffeine && bar.screen === Quickshell.screens[0] }
            property int gap: Math.max(4,root.prefs.bar_margin||0)
            property bool altClock:false
            IpcHandler {
                target:"bar-"+bar.screen.name
                function mixer():void {audioButton.openPopup("audio")}
                function trayMenu(index:int):void {let item=trayItems.itemAt(index);if(item)item.showMenu()}
            }
            component Group: Rectangle { radius:Math.min(18,root.prefs.radius||12); color:Qt.alpha(root.bg,root.prefs.opacity||0.95); border.color:Qt.alpha(root.fg,0.13); height:24 }
            component BarChip: Chip { surface:root.bg; ink:root.fg; accent:root.accent; implicitHeight:22; radius:7; function openPopup(name) {root.toggle(name,bar.screen,mapToItem(bar.contentItem,0,0).x+width/2)} }
            Group {
                x:bar.gap; anchors.verticalCenter:parent.verticalCenter; width:leftRow.implicitWidth+8
                Row { id:leftRow; anchors.centerIn:parent; spacing:1
                    Repeater {
                        model: (root.tags.find(m=>m.monitor===bar.screen.name)||{}).tags || []
                        BarChip { required property var modelData; text:String(modelData.index); selected:modelData.is_active; ink:modelData.is_urgent?"#ff8080":modelData.client_count>0?root.fg:Qt.alpha(root.fg,0.4)
                            onClicked: button=>root.workspace(bar.screen.name,modelData.index,button===Qt.RightButton) }
                    }
                    BarChip { text:root.audioMuted(true)?"󰍭 Off":"󰍬 "+root.audioLabel(true); tip:root.source?root.source.description:""; onClicked:button=>button===Qt.RightButton?openPopup("mic"):root.mute(true); onScrolled:delta=>root.volume(true,delta) }
                    BarChip { id:audioButton; text:(root.audioMuted(false)?"󰝟 ":"󰕾 ")+root.audioLabel(false); tip:root.sink?root.sink.description:""; onClicked:button=>button===Qt.RightButton?openPopup("audio"):root.mute(false); onScrolled:delta=>root.volume(false,delta) }
                    BarChip { visible:root.stats; text:"󰍛 "+(root.data.cpu||0)+"%" }
                    BarChip { visible:root.stats; text:"󰾅 "+(root.data.memory||0)+"GB" }
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
                    BarChip { visible:root.focused; text:"FOCUS"; onClicked:root.script("victoria-controls.py",["--focus"]) }
                    Repeater { model:root.data.battery||[]; BarChip {required property var modelData; text:"󰁹 "+modelData.percent+"%";tip:modelData.status} }
                    BarChip { visible:root.kbLayouts.length>1; text:"󰌌 "+root.kbLabel; tip:root.kbCurrent+" · click to switch"; onClicked:root.command(["mmsg","dispatch","switch_keyboard_layout"]) }
                    BarChip { text:"󰤨 "+(root.data.network||"Offline").substring(0,16); tip:root.data.networkTip||"" }
                    BarChip { visible:root.stats; ink:root.data.temperature>=80?"#ff8080":root.fg; text:" "+(root.data.temperature===null?"—":root.data.temperature||"—")+"°C" }
                    BarChip { visible:root.media && root.player!==null; text:(root.player&&root.player.isPlaying?"󰐊 ":"󰏤 ")+(root.player?(root.player.trackArtist+" · "+root.player.trackTitle).substring(0,bar.width<1700?23:36):""); tip:root.player?root.player.trackTitle:""; onClicked:button=>{if(button===Qt.RightButton)openPopup("media");else if(root.player){if(button===Qt.MiddleButton && root.player.canGoPrevious)root.player.previous();else if(root.player.canTogglePlaying)root.player.togglePlaying()}} }
                    BarChip { visible:root.visualizer; text:root.cava; ink:root.accent }
                    BarChip { text:Qt.formatDateTime(clock.date,bar.altClock?"dd/MM/yyyy":(root.prefs.clock_24h===false?"hh:mm":"HH:mm")+(root.prefs.clock_seconds===false?"":":ss")+(root.prefs.clock_24h===false?" AP":"")); selected:true; onClicked:button=>button===Qt.RightButton?openPopup("calendar"):bar.altClock=!bar.altClock }
                    BarChip { visible:root.recording; ink:"#ff6b6b"; text:"● "+(function(){ const s=Math.floor((root.now-root.recordingSince)/1000); return Math.floor(s/60)+":"+String(s%60).padStart(2,"0") })(); tip:"Recording · click to stop"; onClicked:root.command(["bash",root.home+"/.config/mango/scripts/record.sh","stop"]) }
                    BarChip { visible:root.weatherOn && root.weather!==null; text:root.weather?root.weather.icon+" "+root.weather.temp+"°":""; tip:root.weather?root.weather.area+" · "+root.weather.desc+" · feels "+root.weather.feels+"°":""; onClicked:openPopup("calendar") }
                    BarChip { visible:root.dnd || (root.notifications !== null && root.notifications.history.length>0); text:(root.dnd?"󰂛":"󰂚")+(root.notifications !== null && root.notifications.history.length?" "+root.notifications.history.length:""); tip:(root.dnd?"Do not disturb is on":"Notifications")+" · right-click toggles DND"; onClicked:button=>button===Qt.RightButton?root.setDnd(!root.dnd):openPopup("control") }
                    BarChip { text:"";tip:"Control center";onClicked:openPopup("control") }
                    BarChip { text:"⏻";ink:root.accent;onClicked:button=>root.command(button===Qt.RightButton?["loginctl","poweroff"]:button===Qt.MiddleButton?["loginctl","reboot"]:["wlogout"]) }
                }
            }
        }
    }
    TrayMenu { id:trayMenu; app:root }
    LazyLoader { active:root.popup!==""; Popups { app:root } }
    LazyLoader { active:root.settingsPage!==""; Settings { app:root } }
}
