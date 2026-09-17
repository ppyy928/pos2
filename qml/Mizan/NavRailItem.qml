import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import QtQuick.Templates as T
import FluentControls
import Mizan

/*
 * One row in the navigation rail.
 *
 * Built on T.AbstractButton, not Controls.Button: AbstractButton carries the
 * button semantics we want (hovered/pressed/checked, Space/Enter activation,
 * focus, the Accessible role) and brings no visuals at all — a styled Button
 * would paint Fluent's light control fills and we draw the row ourselves.
 *
 * ACTIVE IS THREE THINGS, NOT ONE
 *
 * The checked row carries a lighter navy fill, a leading emerald marker, and
 * DemiBold weight, so the active destination is legible without colour and
 * without reading any label. The module hue is the icon's colour when checked
 * — pinned to its light-on-dark variant (Tokens.chromeHueFor) because the
 * rail is navy in both themes and a theme-following hue would disappear on
 * it. The label stays in the rail's own light ink.
 *
 * Sizing is Tokens.size.control (48) rather than the POS command height: the
 * rail holds 12 destinations plus section captions, and at 64 each the list
 * would not fit a 768px screen. 48 is the touch floor and the rail scrolls,
 * so nothing is unreachable.
 */
T.AbstractButton {
    id: control

    /* One entry from Mizan.Destinations.all. */
    required property var destination
    property bool collapsed: false
    /* Optional count badge — low stock, payments due, open shifts. 0 hides it. */
    property int badgeCount: 0

    /* The module's hue, pinned light: this row sits on navy in both themes,
       and the theme-following variant of "products teal" is dark enough to
       vanish on it. */
    readonly property color hue: Tokens.chromeHueFor(destination.key)

    /* Translated, not the literal `title`: Destinations carries both the key and
       an English word, and this is a binding on Strings.t — which reads
       `strings.map` while it runs — so the label follows a language change the
       moment the operator makes one. `title` stays as the fallback, exactly like
       every other Strings.t call in the app. */
    text: Strings.t(destination.titleKey, destination.title)
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
        /* The navy family's own steps, one per state, so the row changes
           surface and not just ink when it is pointed at or chosen. */
        color: control.checked ? Tokens.navy.active
             : control.down    ? Tokens.navy.active
             : control.hovered ? Tokens.navy.hover
             : "transparent"

        Behavior on color {
            ColorAnimation { duration: Fluent.anim.appearance }
        }

        // Focus ring, in the rail's emerald — visible against every state.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 2
            border.color: Tokens.navy.mark
            visible: control.visualFocus
        }
    }

    contentItem: Item {
        clip: true

        // Leading edge indicator. Anchors flip under LayoutMirroring, so this
        // is the leading edge in RTL too. One of the three active signals —
        // see the header — and the emerald one, so "where am I" has a colour
        // the whole rail shares.
        Rectangle {
            id: edge
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: control.checked ? Tokens.icon.md : 0
            radius: 2
            color: Tokens.navy.mark

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
            /* The scrollbar's seat plus the ordinary padding: the rail's
               Fluent bar is an overlay on this same edge, and the badge at
               the row's end is the one thing on a rail it would cover. */
            anchors.rightMargin: Tokens.spacing.sm + Tokens.size.scrollSeat
            spacing: Tokens.spacing.md

            Icon {
                icon: control.destination.icon
                size: Tokens.icon.md
                Layout.alignment: Qt.AlignVCenter
                color: control.checked ? control.hue
                     : control.hovered ? Tokens.navy.text
                                       : Tokens.navy.muted
            }

            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: control.text
                elide: Text.ElideRight
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                font.weight: control.checked ? Font.DemiBold : Font.Normal
                color: control.checked ? Tokens.navy.text
                     : control.hovered ? Tokens.navy.text
                                       : Tokens.navy.muted
                // Fades out as the rail narrows; the clip above hides the rest.
                opacity: control.collapsed ? 0 : 1

                Behavior on opacity {
                    NumberAnimation { duration: Fluent.anim.appearance }
                }
            }

            InfoBadge {
                // InfoBadge derives its own label from `count` and applies the
                // maxCount "99+" clamp, so there is no text to pass. Outlined
                // rather than solid: a solid badge would put white text on the
                // light chrome hues, while the outlined pill draws hue-on-navy
                // for both border and figure.
                visible: control.badgeCount > 0 && !control.collapsed
                count: control.badgeCount
                solid: false
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
