import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The party selector: who this transaction is for. Ported from
 * pos/app/widgets/party.py::PartySelectionCard, which pos shares between the
 * till's customer and the purchase screen's supplier — so this is deliberately
 * not called CustomerCard.
 *
 *     ┌──────────────────────────────────────────────┐
 *     │ 👤  Walk-in            Select customer (F3) ⌄│
 *     └──────────────────────────────────────────────┘
 *
 *     ┌──────────────────────────────────────────────┐
 *     │ 👤  Amine Bekkar        0661 20 41 88   ✕   ⌄│
 *     └──────────────────────────────────────────────┘
 *
 * IT LOOKS LIKE A DROPDOWN BECAUSE THAT IS WHAT IT IS
 *
 * This was a 64px two-line card with the glyph in a filled chip and, when a customer
 * was attached, a brand-tinted face. It behaved as a combo box — tap it and a
 * searchable list drops under it — and looked like nothing else in the app, while the
 * real combo boxes two screens away (the category filter, the price level, the tax
 * rate) are 48px single-line fields with a chevron. An operator learns "this shape
 * opens a list" once; a control that opens a list without that shape has to be
 * learned separately.
 *
 * So the chrome is a field's: one line, `size.control` tall, `radius.sm`, the fill and
 * the hairline border a combo box has, and the chevron in the trailing indicator slot.
 * Nothing was dropped to get there — the name is the display text, the phone or the
 * invitation is the detail on the trailing side, and the leading glyph is the field's
 * icon rather than an avatar.
 *
 * WHAT IS ATTACHED IS STILL VISIBLE ACROSS A COUNTER
 *
 * The tinted face went, because a coloured field is not a field. The border in brand
 * stayed, which is the accent a Fluent field already uses to say "this one is live",
 * and it answers the same question the tint did — is this sale on account? — without
 * pretending to be a card.
 *
 * WHAT THIS IS AND IS NOT
 *
 * It is the SURFACE only: who is attached, and the two affordances for changing that.
 * It owns no list and no search — PartySelect wraps it with the dropdown that does,
 * and the card stays usable on its own for a caller that opens a full dialog instead.
 * Attached or not, it keeps the same size and position: a control that appears once a
 * customer exists would move the cart down in the middle of a sale.
 *
 * WHY REMOVING IS A SEPARATE BUTTON
 *
 * Because it is a different intent from "change the customer", and on a touchscreen
 * the difference has to be spatial: pos learned this and gave the card a dedicated ✕.
 * It only exists while somebody is attached, which is the one time it means anything.
 *
 * WHY THE CHEVRON IS OPTIONAL
 *
 * It is a promise about what the next tap does. A field that drops a list under itself
 * must say so before it is tapped; one that opens a dialog must not, because the
 * chevron would be a lie about where the answer appears.
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

    /* Draw the chevron, and turn it over while the list is down. `expanded` is
       the caller's state, not the card's: the card does not own the popup and
       must not guess whether it is open. */
    property bool dropdown: false
    property bool expanded: false

    signal removeRequested()

    // =====================================================================
    // GEOMETRY
    // =====================================================================
    /* A field's height, the same one every ComboBox and TextField in the app uses. */
    implicitHeight: Tokens.size.control
    hoverEnabled: true

    Accessible.role: Accessible.Button
    Accessible.name: title
    Accessible.description: subtitle

    /* Room for whatever is on the trailing edge, on whichever side that is.
       Padding is the one geometry LayoutMirroring does not flip, so it asks
       `mirrored` — the same property the style itself uses, which accounts for
       the control's locale as well as an ancestor's LayoutMirroring. Reserved
       only for the parts that are actually there, so an unattached card without
       a chevron uses the full width for its invitation. */
    readonly property int trailingRoom: (active ? Tokens.size.control : 0)
                                        + (dropdown ? Tokens.icon.sm
                                                      + 2 * Tokens.spacing.sm : 0)
    leftPadding: Tokens.spacing.sm + (mirrored ? trailingRoom : 0)
    rightPadding: Tokens.spacing.sm + (mirrored ? 0 : trailingRoom)

    // =====================================================================
    // SURFACE
    // =====================================================================
    background: Rectangle {
        /* `radius.sm`, not `md`: a field's corner, not a card's. */
        radius: Tokens.radius.sm

        color: !card.enabled ? Fluent.subtleSecondary
             : card.down ? Fluent.subtleTertiary
             : card.hovered ? Fluent.subtleSecondary
                            : Fluent.cardBackground
        Behavior on color { ColorAnimation { duration: Fluent.anim.appearance } }

        /* The brand border is what says "somebody is attached" now that the face is
           no longer tinted — the same accent a Fluent field uses for its live state,
           and the one thing on this control readable from across the counter. */
        border.width: 1
        border.color: !card.enabled ? Fluent.dividerBorder
                    : card.active ? Tokens.brand : Fluent.dividerBorder

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
    /* One line: the glyph, the display text, and the detail pushed to the trailing
       end. A RowLayout so the pair swaps sides under mirroring without either of
       them being told to, and so the name takes the slack while the detail keeps
       only what it needs. */
    contentItem: RowLayout {
        spacing: Tokens.spacing.sm

        Icon {
            Layout.alignment: Qt.AlignVCenter
            icon: card.glyph
            size: Tokens.icon.md
            color: !card.enabled ? Fluent.textDisabled
                 : card.active ? Tokens.brand : Fluent.textSecondary
        }

        /* AlignLeft pinned rather than left to default: a Text with no explicit
           alignment follows its OWN content's direction, so a French-named customer
           would sit on the wrong edge of an Arabic screen. It mirrors to AlignRight
           with the layout. */
        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            horizontalAlignment: Text.AlignLeft
            text: card.title
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.body
            font.weight: Font.DemiBold
            color: card.enabled ? Fluent.textPrimary : Fluent.textDisabled
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        /* The phone when there is one, the invitation when there is not — a combo
           box's secondary detail, and the reason nothing was lost by going to one
           line. Capped at 45% so a long name elides before this does: which customer
           is attached matters more than their phone number.

           The LTR mark is for the phone: without it "0661 20 41 88" is reordered by
           the bidi algorithm inside an Arabic line. */
        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: Math.round(card.availableWidth * 0.45)
            visible: card.subtitle !== ""
            horizontalAlignment: Text.AlignRight
            text: "\u200e" + card.subtitle
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.caption
            color: card.enabled ? Fluent.textTertiary : Fluent.textDisabled
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    /* Outside contentItem, so the ✕ takes its own clicks rather than the card's.
       Anchored, so Arabic moves the pair to the other edge — which is exactly what
       trailingRoom above has already made space for. A Row, so the chevron keeps
       the outer edge and the ✕ sits inboard of it: the chevron describes the whole
       field and the ✕ is one action inside it, and swapping that order would put a
       48px hit target between the finger and the edge it is aiming at. */
    Row {
        anchors.right: parent.right
        anchors.rightMargin: Tokens.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        IconButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: card.active
            glyph: "ic_fluent_dismiss_20_regular"
            glyphSize: Tokens.icon.sm
            glyphColor: Fluent.textSecondary
            tooltip: card.removeTip
            onClicked: card.removeRequested()
        }

        /* Not a button: the whole field already opens the list, and a second hit
           target that does the same thing is a second thing to aim at. */
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: card.dropdown
            icon: "ic_fluent_chevron_down_20_regular"
            size: Tokens.icon.sm
            color: !card.enabled ? Fluent.textDisabled
                 : card.active ? Tokens.brand : Fluent.textSecondary
            rotation: card.expanded ? 180 : 0
            Behavior on rotation {
                NumberAnimation { duration: Fluent.anim.appearance }
            }
        }
    }
}
