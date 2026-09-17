import QtQuick
import QtQuick.Controls as QC
import QtQuick.Templates as T
import FluentControls

/*
 * A square icon button for the chrome: the nav rail's controls, the till's
 * edit bar.
 *
 * Fluent's own ToolButton would do for the light rail, but the edit bar needs
 * a button that draws its own states over a fixed light fill, so this one
 * control serves both. The DEFAULTS below are the light rail's; a caller
 * seating it on a different surface supplies its own set, which is what the
 * till's edit bar does. Same AbstractButton reasoning as NavRailItem:
 * semantics without visuals.
 */
T.AbstractButton {
    id: control

    property string iconName: ""
    property int iconSize: Tokens.icon.md
    property color iconColor: Tokens.workspace.textSub
    property color iconColorActive: Tokens.workspace.text

    /* The state fills, overridable as a set. The defaults are the light
       rail's; the till's indigo edit bar supplies its own trio, because navy
       hover squares on a light hue are chrome furniture in the wrong room.
       Ink and fill travel separately: the ink says what the button is on, the
       fill says what sits under it. */
    property color fillRest: "transparent"
    property color fillHover: Fluent.subtleSecondary
    property color fillDown: Fluent.subtleTertiary

    property string tip: ""

    implicitWidth: Tokens.size.control
    implicitHeight: Tokens.size.control

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.Button
    Accessible.name: tip !== "" ? tip : iconName

    background: Rectangle {
        radius: Tokens.radius.sm
        color: control.down    ? control.fillDown
             : control.hovered ? control.fillHover
             : control.fillRest

        Behavior on color { ColorAnimation { duration: Fluent.anim.appearance } }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 2
            border.color: Tokens.brand
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
