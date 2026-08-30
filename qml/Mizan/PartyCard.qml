import QtQuick
import QtQuick.Controls as QC
import FluentControls
import Mizan

/*
 * The party selector: who this transaction is for. Ported from
 * pos/app/widgets/party.py::PartySelectionCard, which pos shares between the
 * till's customer and the purchase screen's supplier — so this is deliberately
 * not called CustomerCard.
 *
 *     ┌──────────────────────────────────────────────┐
 *     │ 👤   Walk-in customer                        │
 *     │      Tap to attach a customer                │
 *     └──────────────────────────────────────────────┘
 *
 *     ┌──────────────────────────────────────────────┐
 *     │ 👤   Amine Bekkar                        ✕   │
 *     │      0661 20 41 88                           │
 *     └──────────────────────────────────────────────┘
 *
 * WHY IT IS A BUTTON AND NOT A FIELD
 *
 * There is nothing to type. A customer is chosen from a list that only Python can
 * search, so the card's whole job is to say who is attached and to open that
 * list. Attached or not, it keeps the same size and position — a control that
 * appears once a customer exists would move the cart down by 64px in the middle
 * of a sale.
 *
 * WHY REMOVING IS A SEPARATE BUTTON
 *
 * Because it is a different intent from "change the customer", and on a
 * touchscreen the difference has to be spatial: pos learned this and gave the
 * card a dedicated ✕. It only exists while somebody is attached, which is the one
 * time it means anything.
 */
QC.AbstractButton {
    id: card

    // =====================================================================
    // API
    // =====================================================================
    property string glyph: "ic_fluent_person_20_regular"

    /* The name when somebody is attached, the invitation when nobody is. The page
       supplies both cases as text — the card does not know what "walk-in" is
       called in Arabic and should not have to. */
    property string title: ""
    property string subtitle: ""

    /* Drives the accent treatment and the ✕. Named for the state, not for what is
       in `title`: a customer with no phone number still has a name, and an empty
       subtitle must not make the card look unattached. */
    property bool active: false

    property string removeTip: ""

    signal removeRequested()

    // =====================================================================
    // GEOMETRY
    // =====================================================================
    implicitHeight: Tokens.size.posCommand
    hoverEnabled: true

    Accessible.role: Accessible.Button
    Accessible.name: title

    /* Room for the ✕, on whichever side the trailing edge is. Padding is the one
       geometry LayoutMirroring does not flip, so it asks `mirrored` — the same
       property the style itself uses, which accounts for the control's locale as
       well as an ancestor's LayoutMirroring. Reserved only while the button is
       there, so an unattached card uses the full width for its invitation. */
    readonly property int removeRoom: active ? Tokens.size.control : 0
    leftPadding: Tokens.spacing.sm + (mirrored ? removeRoom : 0)
    rightPadding: Tokens.spacing.sm + (mirrored ? 0 : removeRoom)

    // =====================================================================
    // SURFACE
    // =====================================================================
    background: Rectangle {
        radius: Tokens.radius.md

        /* Attached is a brand tint, unattached is an ordinary card. The colour is
           the fastest way to answer "is this sale on account?" from across the
           counter, which is the question the whole card exists to answer. */
        color: card.active ? Tokens.brandTint
             : card.down ? Fluent.subtleTertiary
             : card.hovered ? Fluent.subtleSecondary
                            : Fluent.cardBackground
        Behavior on color { ColorAnimation { duration: Fluent.anim.appearance } }

        border.width: 1
        border.color: card.active ? Tokens.brand : Fluent.dividerBorder

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 2
            border.color: Fluent.accent
            visible: card.visualFocus
        }
    }

    // =====================================================================
    // CONTENT
    // =====================================================================
    contentItem: Row {
        spacing: Tokens.spacing.sm

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Tokens.icon.lg + Tokens.spacing.xs
            height: width
            radius: Tokens.radius.sm
            color: card.active ? Tokens.brand : Fluent.subtleSecondary

            Icon {
                anchors.centerIn: parent
                icon: card.glyph
                size: Tokens.icon.md
                color: card.active ? Tokens.onBrand : Fluent.textSecondary
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - parent.spacing
                   - (Tokens.icon.lg + Tokens.spacing.xs)
            spacing: 1

            /* Both lines pin AlignLeft, which mirrors to AlignRight in Arabic.
               Left to itself, a Text follows its own content's direction — and
               these two lines routinely disagree: an Arabic name over a phone
               number would sit on opposite edges of the same card. */
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignLeft
                text: card.title
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.body
                font.weight: Font.DemiBold
                color: Fluent.textPrimary
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignLeft
                visible: card.subtitle !== ""
                /* A phone number is an LTR island: without the mark, "0661 20 41
                   88" is reordered by the bidi algorithm inside an Arabic card. */
                text: "\u200e" + card.subtitle
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                color: Fluent.textSecondary
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    /* Outside contentItem, so it takes its own clicks rather than the card's.
       Anchored, so Arabic moves it to the other edge — which is exactly what
       removeRoom above has already made space for. */
    IconButton {
        anchors.right: parent.right
        anchors.rightMargin: Tokens.spacing.xs
        anchors.verticalCenter: parent.verticalCenter
        visible: card.active
        glyph: "ic_fluent_dismiss_20_regular"
        glyphSize: Tokens.icon.sm
        glyphColor: Fluent.textSecondary
        tooltip: card.removeTip
        onClicked: card.removeRequested()
    }
}
