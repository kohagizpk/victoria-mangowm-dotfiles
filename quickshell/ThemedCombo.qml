import QtQuick
import QtQuick.Controls
ComboBox {
    id:control
    property color accent:"#b18aa6"
    property color ink:"#ddd"
    property color surface:"#17151b"
    implicitHeight:30
    leftPadding:10;rightPadding:24
    background:Rectangle {radius:8;color:Qt.alpha(control.ink,0.07);border.color:Qt.alpha(control.ink,0.1)}
    contentItem:Text {text:control.displayText;color:control.ink;font.pixelSize:11;verticalAlignment:Text.AlignVCenter;elide:Text.ElideRight}
    indicator:Text {x:control.width-20;y:6;text:"⌄";color:control.ink}
    delegate:ItemDelegate {required property int index;required property var modelData;width:control.width;text:control.textRole?modelData[control.textRole]:String(modelData);contentItem:Text{text:parent.text;color:control.ink;elide:Text.ElideRight;font.pixelSize:12}background:Rectangle{color:parent.highlighted?Qt.alpha(control.accent,0.25):control.surface}highlighted:control.highlightedIndex===index}
    popup:Popup {y:control.height+4;width:control.width;padding:4;implicitHeight:Math.min(contentItem.implicitHeight+8,240);background:Rectangle{color:control.surface;radius:10;border.color:control.accent}contentItem:ListView{clip:true;implicitHeight:contentHeight;model:control.popup.visible?control.delegateModel:null;currentIndex:control.highlightedIndex}}
}
