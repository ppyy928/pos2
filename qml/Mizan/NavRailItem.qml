import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import QtQuick.Templates as T
import FluentControls

/*
 * One row in the navigation rail.
 *
 * Built on T.AbstractButton, not Controls.Button: AbstractButton carries the
 * button semantics we want (hovered/pressed/checked, Space/Enter activation,
 * focus, the Accessible role) and brings no visuals at all. A styled Button
 * would paint Fluent's light control fills onto this permanently-dark rail and
 * we would spend more code suppressing them than drawing our own.
 *
 * Sizing is Tokens.size.control (48) rather than the POS command height: the
 * rail holds 12 destinations plus section captions, and at 64 each the list
 * would not fit a 768px screen. 48 is MIZAN's documented touch floor and the
 * rail scrolls, so nothing is unreachable.
 */
T.AbstractButton {
    id: control

    /* One entry from Mizan.Destinations.all. */
    required property var destination
    property bool collapsed: false
    /* Optional count badge — low stock, payments due, open shifts. 0 hides it. */
    property int badgeCount: 0

    readonly property color hue: Tokens.chromeHueFor(destination.key)

    text: destination.title
    checkable: true
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Layout.fillWidth: true
    implicitHeight: Tokens.size.control
    implicitWidth: Tokens.size.navExpanded

    Accessible.role: Accessible.PageTab
    Accessible.name: text
    Accessible.checked: checked

    background: Rectangle {
        // Inset so the fill reads as a pill inside the rail rather than a
        // full-bleed band, which is what makes the rail feel like a list.
        x: Tokens.spacing.xs
        width: parent.width - Tokens.spacing.xs * 2
        height: parent.height - 2
        y: 1
        radius: Tokens.radius.sm
        color: control.checked ? Tokens.chromeActive
             : control.down    ? Tokens.chromeActive
             : control.hovered ? Tokens.chromeHover
             : "transparent"

        Behavior on color {
            ColorAnimation { duration: Fluent.anim.appearance }
        }

        // Focus ring, drawn in the module hue so keyboard focus is visible on
        // navy without borrowing Fluent's light focus border.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 2
            border.color: control.hue
            visible: control.visualFocus
        }
    }

    contentItem: Item {
        clip: true

        // Leading edge indicator. Anchors flip under LayoutMirroring, so this
        // is the leading edge in RTL too.
        Rectangle {
            id: edge
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 4
            height: control.checked ? Tokens.icon.md : 0
            radius: 2
            color: control.hue

            Behavior on height {
                NumberAnimation {
                    duration: Fluent.anim.speed
                    easing.type: Easing.OutQuint
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.spacing.md
            anchors.rightMargin: Tokens.spacing.sm
            spacing: Tokens.spacing.md

            Icon {
                icon: control.destination.icon
                size: Tokens.icon.md
                Layout.alignment: Qt.AlignVCenter
                color: control.checked ? control.hue
                     : control.hovered ? Tokens.onChrome
                     : Tokens.onChromeMuted
            }

            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: control.text
                elide: Text.ElideRight
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                font.weight: control.checked ? Font.DemiBold : Font.Normal
                color: control.checked ? Tokens.onChrome
                     : control.hovered ? Tokens.onChrome
                     : Tokens.onChromeMuted
                // Fades out as the rail narrows; the clip above hides the rest.
                opacity: control.collapsed ? 0 : 1

                Behavior on opacity {
                    NumberAnimation { duration: Fluent.anim.appearance }
                }
            }

            InfoBadge {
                // InfoBadge derives its own label from `count` and applies the
                // maxCount "99+" clamp, so there is no text to pass.
                visible: control.badgeCount > 0 && !control.collapsed
                count: control.badgeCount
                badgeColor: control.hue
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // Collapsed rail shows icons only, so the name has to come from a tip.
        // Controls.ToolTip, not Templates: the Templates one has no visuals.
        QC.ToolTip {
            visible: control.collapsed && control.hovered
            delay: 400
            text: control.text
        }
    }
}
