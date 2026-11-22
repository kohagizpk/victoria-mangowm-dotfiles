import QtQuick
import QtQuick.Controls
Slider {
    id:control
    property color accent:"#b18aa6"
    property color ink:"#ddd"
    implicitHeight:22
    background:Rectangle {x:control.leftPadding;y:control.topPadding+control.availableHeight/2-height/2;width:control.availableWidth;height:4;radius:2;color:Qt.alpha(control.ink,0.15)
        Rectangle {width:control.visualPosition*parent.width;height:parent.height;radius:2;color:control.accent}
    }
    handle:Rectangle {x:control.leftPadding+control.visualPosition*(control.availableWidth-width);y:control.topPadding+control.availableHeight/2-height/2;width:12;height:12;radius:6;color:control.accent;visible:control.enabled}
}
