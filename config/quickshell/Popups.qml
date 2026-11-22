import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris

PanelWindow {
    id: win
    required property var app
    visible:app.popup!==""
    screen:app.popupScreen
    anchors { top:app.prefs.bar_position!=="bottom"; bottom:app.prefs.bar_position==="bottom"; left:true }
    margins { top:app.barHeight+4;bottom:app.barHeight+4;left:Math.max(6,Math.min(app.popupX-win.implicitWidth/2,(screen?screen.width:1920)-win.implicitWidth-6)) }
    exclusionMode:ExclusionMode.Ignore
    implicitWidth:app.popup==="media"?460:400
    implicitHeight:app.popup==="media"?250:app.popup==="calendar"?420:Math.min(600,Math.max(270,audioColumn.implicitHeight+80))
    color:"transparent"
    WlrLayershell.namespace:"victoria-popup"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    property var chosenPlayer:null
    property var player:chosenPlayer && Mpris.players.values.indexOf(chosenPlayer)>=0?chosenPlayer:app.player
    property date month: new Date()
    function stepMonth(delta) {month=new Date(month.getFullYear(),month.getMonth()+delta,1)}
    function minutes(value) { let n=Math.max(0,Math.floor(value));return Math.floor(n/60)+":"+String(n%60).padStart(2,"0") }
    component Label: Text { color:app.fg;font.family:"JetBrainsMono Nerd Font";font.pixelSize:12;elide:Text.ElideRight }
    component Button: Chip { surface:app.bg; ink:app.fg;accent:app.accent }
    Rectangle {
        anchors.fill:parent;radius:20;color:app.bg;border.color:Qt.alpha(app.accent,0.5)
        focus:true
        Keys.onEscapePressed:app.popup=""
        RowLayout { anchors {top:parent.top;left:parent.left;right:parent.right;margins:16}
            Label {text:app.popup==="media"?"NOW PLAYING":app.popup==="calendar"?"CALENDAR":app.popup==="mic"?"MICROPHONE":"AUDIO";font.letterSpacing:2;opacity:0.65;Layout.fillWidth:true}
            Button {text:"×";onClicked:app.popup=""}
        }
        RowLayout {
            visible:app.popup==="media";anchors {left:parent.left;right:parent.right;top:parent.top;bottom:parent.bottom;leftMargin:20;rightMargin:20;topMargin:58;bottomMargin:20} spacing:20
            Rectangle {
                id:disc;Layout.preferredWidth:130;Layout.preferredHeight:130;radius:65;color:"#111116";border.color:app.accent;border.width:2
                Repeater {model:5;Rectangle {required property int index;anchors.centerIn:parent;width:118-index*10;height:width;radius:width/2;color:"transparent";border.color:"#303039"}}
                Image {id:art;anchors.centerIn:parent;width:78;height:78;source:app.popup==="media"&&win.player?win.player.trackArtUrl:"";cache:false;sourceSize.width:180;sourceSize.height:180;fillMode:Image.PreserveAspectCrop;asynchronous:true;visible:false}
                Rectangle {id:mask;anchors.centerIn:parent;width:78;height:78;radius:39;visible:false;layer.enabled:app.popup==="media";color:"white"}
                MultiEffect {anchors.centerIn:parent;width:78;height:78;source:art;maskEnabled:true;maskSource:mask;visible:art.status===Image.Ready}
                Rectangle {anchors.centerIn:parent;width:78;height:78;radius:39;color:app.accent;visible:art.status!==Image.Ready;Text{anchors.centerIn:parent;text:"♫";font.pixelSize:32;color:app.fg}}
                Rectangle {anchors.centerIn:parent;width:10;height:10;radius:5;color:"#111116";border.color:Qt.alpha(app.fg,0.5)}
                RotationAnimator on rotation {from:0;to:360;duration:20000;loops:Animation.Infinite;running:win.visible && app.popup==="media" && win.player!==null && win.player.isPlaying}
            }
            ColumnLayout {Layout.fillWidth:true;spacing:8
                ThemedCombo { accent:app.accent;ink:app.fg;surface:app.bg;Layout.fillWidth:true;model:Mpris.players.values.map(p=>p.identity);currentIndex:Mpris.players.values.indexOf(win.player);visible:Mpris.players.values.length>1;onActivated:index=>win.chosenPlayer=Mpris.players.values[index]}
                Label {text:win.player?win.player.trackTitle:"No music playing";font.pixelSize:18;font.bold:true;Layout.fillWidth:true}
                Label {text:win.player?win.player.trackArtist:"Open your music player";opacity:0.65;Layout.fillWidth:true}
                ThemedSlider { accent:app.accent;ink:app.fg;Layout.fillWidth:true;from:0;to:win.player?Math.max(1,win.player.length):1;value:win.player?win.player.position:0;enabled:win.player!==null && win.player.canSeek;onMoved:if(win.player)win.player.position=value}
                RowLayout {Layout.fillWidth:true
                    Label {text:win.player?win.minutes(win.player.position):"0:00";opacity:0.6}
                    Item{Layout.fillWidth:true}
                    Label {text:win.player?win.minutes(win.player.length):"0:00";opacity:0.6}
                }
                RowLayout {Layout.alignment:Qt.AlignHCenter;spacing:12
                    Button{text:"󰒮";enabled:win.player!==null&&win.player.canGoPrevious;onClicked:win.player.previous()}
                    Button{text:win.player&&win.player.isPlaying?"󰏤":"󰐊";selected:true;enabled:win.player!==null&&win.player.canTogglePlaying;onClicked:win.player.togglePlaying()}
                    Button{text:"󰒭";enabled:win.player!==null&&win.player.canGoNext;onClicked:win.player.next()}
                }
            }
        }
        Timer {interval:1000;repeat:true;running:win.visible&&app.popup==="media"&&win.player!==null&&win.player.isPlaying;onTriggered:win.player.positionChanged()}
        ColumnLayout {
            visible:app.popup==="calendar";anchors {top:parent.top;left:parent.left;right:parent.right;margins:20;topMargin:62} spacing:14
            RowLayout {Layout.fillWidth:true
                Button{text:"‹";onClicked:win.stepMonth(-1)}
                Label {text:win.month.toLocaleDateString(Qt.locale("en_US"),"MMMM yyyy");font.pixelSize:17;font.bold:true;Layout.fillWidth:true;horizontalAlignment:Text.AlignHCenter}
                Button{text:"›";onClicked:win.stepMonth(1)}
            }
            GridLayout {columns:7;rowSpacing:3;columnSpacing:3;Layout.fillWidth:true
                Repeater {model:["MON","TUE","WED","THU","FRI","SAT","SUN"];Label{required property string modelData;text:modelData;Layout.fillWidth:true;horizontalAlignment:Text.AlignHCenter;opacity:0.45;font.pixelSize:10}}
                Repeater {model:42
                    Rectangle {required property int index;property int day:index-((new Date(win.month.getFullYear(),win.month.getMonth(),1).getDay()+6)%7)+1;property bool valid:day>0&&day<=new Date(win.month.getFullYear(),win.month.getMonth()+1,0).getDate();property bool today:valid&&day===new Date().getDate()&&win.month.getMonth()===new Date().getMonth()&&win.month.getFullYear()===new Date().getFullYear();Layout.fillWidth:true;implicitHeight:29;radius:8;color:today?app.accent:"transparent";Label{anchors.centerIn:parent;text:parent.valid?parent.day:"";color:parent.today?app.bg:app.fg}}
                }
            }
            Button {text:"Today";Layout.alignment:Qt.AlignHCenter;onClicked:win.month=new Date()}
            Rectangle {Layout.fillWidth:true;implicitHeight:1;color:Qt.alpha(app.fg,0.12)}
            RowLayout {Layout.fillWidth:true;spacing:8
                Button {
                    text:"󰂛 Do not disturb";Layout.fillWidth:true
                    selected:app.data.dnd===true
                    enabled:app.data.dndAvailable===true
                    opacity:enabled?1:0.4
                    tip:enabled?(selected?"Enabled · click to disable":"Mute notifications"):"Notification service unavailable"
                    onClicked:app.command(["swaync-client","-d"])
                }
                Button {
                    text:"󱐋 Performance";Layout.fillWidth:true
                    selected:app.data.performance===true
                    tip:selected?"Enabled · restore visual effects":"Disable Mango visual effects"
                    onClicked:app.script("session-controls.py",["performance"])
                }
            }
        }
        ScrollView {
            visible:app.popup==="audio"||app.popup==="mic";anchors {fill:parent;margins:20;topMargin:62} clip:true;contentWidth:availableWidth
            ColumnLayout {id:audioColumn;width:parent.width;spacing:12
                property bool mic:app.popup==="mic"
                Label {text:audioColumn.mic?"Input device":"Output device";font.bold:true}
                ThemedCombo { accent:app.accent;ink:app.fg;surface:app.bg;Layout.fillWidth:true;textRole:"label";model:app.data[audioColumn.mic?"sources":"sinks"]||[];currentIndex:model.findIndex(d=>d.name===app.data[audioColumn.mic?"source":"sink"]);onActivated:index=>{let d=model[index];app.command(["pactl",audioColumn.mic?"set-default-source":"set-default-sink",d.name]);(app.data[audioColumn.mic?"source-outputs":"sink-inputs"]||[]).forEach(s=>app.command(["pactl",audioColumn.mic?"move-source-output":"move-sink-input",String(s.id),d.name]))}}
                Repeater {model: (app.data[audioColumn.mic?"sources":"sinks"]||[]).filter(d=>d.name===app.data[audioColumn.mic?"source":"sink"])
                    ColumnLayout {required property var modelData;Layout.fillWidth:true
                        RowLayout {Label{text:modelData.label+" · "+modelData.volume+"%";Layout.fillWidth:true}Button{text:modelData.mute?"󰝟":"󰕾";onClicked:app.mute(audioColumn.mic)}}
                        ThemedSlider { accent:app.accent;ink:app.fg;Layout.fillWidth:true;from:0;to:100;stepSize:1;value:parent.modelData.volume;onMoved:app.command(["pactl",audioColumn.mic?"set-source-volume":"set-sink-volume",String(parent.modelData.id),Math.round(value)+"%"])}
                    }
                }
                Label {visible:!audioColumn.mic;text:"Applications";font.bold:true}
                Repeater {model:audioColumn.mic?[]:app.data["sink-inputs"]||[]
                    ColumnLayout {required property var modelData;Layout.fillWidth:true
                        RowLayout {Label{text:modelData.label+" · "+modelData.volume+"%";Layout.fillWidth:true}Button{text:modelData.mute?"󰝟":"󰕾";onClicked:app.command(["pactl","set-sink-input-mute",String(modelData.id),"toggle"])}}
                        ThemedSlider { accent:app.accent;ink:app.fg;Layout.fillWidth:true;from:0;to:100;stepSize:1;value:parent.modelData.volume;onMoved:app.command(["pactl","set-sink-input-volume",String(parent.modelData.id),Math.round(value)+"%"])}
                    }
                }
                Label {visible:!audioColumn.mic&&!(app.data["sink-inputs"]||[]).length;text:"No applications are playing audio";opacity:0.6}
            }
        }
    }
}
