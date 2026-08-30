import QtQuick
import QtQuick.Controls as QC
import QtQuick.Templates as T
import FluentControls

/*
 * A square icon button for the dark chrome (nav rail, POS totals dock).
 *
 * Fluent's own ToolButton inks from the theme-switched palette and would paint
 * light fills on navy, so this draws its own states from Tokens.chrome*. Same
 * AbstractButton reasoning as NavRailItem: semantics without visuals.
 */
T.AbstractButton {
    id: control

    property string iconName: ""
    property int iconSize: Tokens.icon.md
    property color iconColor: Tokens.onChromeMuted
    property color iconColorActive: Tokens.onChrome
    property string tip: ""

    implicitWidth: Tokens.size.control
    implicitHeight: Tokens.size.control

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.Button
    Accessible.name: tip !== "" ? tip : iconName

    background: Rectangle {
        radius: Tokens.radius.sm
        color: control.down    ? Tokens.chromeActive
             : control.hovered ? Tokens.chromeHover
             : "transparent"

        Behavior on color { ColorAnimation { duration: Fluent.anim.appearance } }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 2
            border.color: Tokens.onChrome
            visible: control.visualFocus
        }
    }

    contentItem: Icon {
        icon: control.iconName
        size: control.iconSize
        color: (control.hovered || control.down)
            ? control.iconColorActive : control.iconColor
    }

    QC.ToolTip {
        visible: control.tip !== "" && control.hovered
        delay: 400
        text: control.tip
    }
}
