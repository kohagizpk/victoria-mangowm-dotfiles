import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Labelled slider with a live value readout; emits `changed` with the rounded value.
ColumnLayout {
    id: setting
    required property var app
    property string label: ""
    property string unit: ""
    property real from: 0
    property real to: 100
    property real step: 1
    property real value: 0
    property int decimals: 0
    signal changed(real value)
    Layout.fillWidth: true
    spacing: 4
    RowLayout {
        Layout.fillWidth: true
        Text { text: setting.label; color: setting.app.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; Layout.fillWidth: true }
        Text {
            text: (slider.pressed ? slider.value : setting.value).toFixed(setting.decimals) + setting.unit
            color: setting.app.accent
            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.bold: true
        }
    }
    ThemedSlider {
        id: slider
        Layout.fillWidth: true
        accent: setting.app.accent
        ink: setting.app.fg
        from: setting.from; to: setting.to; stepSize: setting.step
        snapMode: Slider.SnapAlways
        Binding on value { value: setting.value; when: !slider.pressed; restoreMode: Binding.RestoreNone }
        onMoved: setting.changed(Number(value.toFixed(setting.decimals)))
    }
}
