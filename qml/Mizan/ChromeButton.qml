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

    /* The state fills, overridable as a set. The defaults are the dark chrome
       this button was built for; a caller seating it on a DIFFERENT fixed
       surface — the till's indigo edit bar — supplies its own trio, because
       navy hover squares on a light hue are chrome furniture in the wrong room.
       Ink and fill travel separately: the ink says what the button is on, the
       fill says what sits under it. */
    property color fillRest: "transparent"
    property color fillHover: Tokens.chromeHover
    property color fillDown: Tokens.chromeActive

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
