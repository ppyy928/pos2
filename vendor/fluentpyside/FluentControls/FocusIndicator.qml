import QtQuick

Rectangle {
    id: root
    property var control: null
    property int margins: 3
    visible: control && control.activeFocus
    color: "transparent"
    border.color: Fluent.accent
    border.width: 2
    radius: Fluent.appearance.buttonRadius + 2

    anchors.fill: parent
    anchors.margins: margins
}
