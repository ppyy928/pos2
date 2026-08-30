import QtQuick
import QtQuick.Controls

ItemDelegate {
    id: root
    property var itemData
    property var currentPage
    highlighted: String(navigationBar.currentPage) === String(itemData.page)
    height: 60
    width: parent ? parent.width : 200

    FocusIndicator { control: parent; anchors.margins: 2 }

    Indicator {
        id: indicator
        x: 34
        y: root.height / 2 - indicator.height / 2
        currentItemHeight: root.height
        visible: highlighted
        width: 4
        z: 1
    }

    background: Rectangle {
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        clip: true
        radius: Fluent.appearance.buttonRadius / 2
        color: pressed ? Fluent.subtleTertiary
            : (root.highlighted || root.hovered) ? Fluent.subtleSecondary
            : Fluent.subtle

        Row {
            id: left
            spacing: 24
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 11 + 34

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                size: itemData.icon || itemData.source ? 19 : 0
                icon: itemData.icon || ""
                source: itemData.source || ""
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: Fluent.typography.body
                font.family: Fluent.typography.fontFamily
                color: Fluent.textPrimary
                text: itemData.title
                clip: true
                opacity: navigationBar.collapsed ? 0 : 1
                elide: Text.ElideRight
                width: parent.parent.width - parent.anchors.leftMargin - x - 10
                Behavior on opacity { NumberAnimation { duration: Fluent.anim.appearance } }
            }
        }

        Behavior on color { ColorAnimation { duration: Fluent.anim.appearance; easing.type: Easing.InOutQuart } }
    }

    onClicked: {
        if (itemData.page && String(navigationBar.currentPage) !== String(itemData.page)) {
            navigationView.safePush(itemData.page, false)
        }
    }
}
