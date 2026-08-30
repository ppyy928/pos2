import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The KPI card that opens every list page. Ported from
 * pos/app/widgets/cards.py::KpiCard.
 *
 *   ┌──────────────────────────────┐
 *   │ ┌────┐  TOTAL STOCK VALUE    │   <- label, 13px caps, in the tone's ink
 *   │ │ 📦 │  1,204,500            │   <- value, 34px, neutral ink
 *   │ └────┘  ▲ 4.2% vs last week  │   <- optional subtext, own tone
 *   └──────────────────────────────┘
 *
 * pos's structure exactly — a tinted glyph chip beside a caption/value column —
 * with the two merchant requirements applied:
 *
 *   BIGGER    the value is 34px (font.amount), read across a counter rather
 *             than from a desk. The chip is 60px, the card 128px tall.
 *   COLOURED  the chip carries the tone as a tint/ink PAIR, and the label is
 *             set in the same ink. Tokens designs those two colours together
 *             and guarantees 4.5:1 for ink on tint and on light surfaces, so
 *             colouring the label costs nothing in legibility.
 *
 * WHY THE VALUE STAYS NEUTRAL
 *
 * pos's set_tone deliberately clears the tone off the value ("value tone" is
 * reset to "" there) and this keeps that. The number is the thing being read;
 * it gets maximum contrast, and the colour identifies *which* number it is.
 * A tone on the value is reserved for the case where the value's own sign
 * carries meaning — a page passes that through `valueTone` explicitly.
 *
 * TONE
 *
 * `tone` is a name, not a colour, because that is what crosses the boundary
 * from a page ("success" | "info" | "warning" | "danger" | "primary"). For the
 * dashboard, which colours a card by *module* rather than by sentiment, assign
 * `ink` and `fill` directly:
 *
 *     KpiCard { ink: Tokens.hue.rose; fill: Tokens.tint.rose; ... }
 *
 * One mechanism, two ways in — the tone name is just the default lookup.
 */
Rectangle {
    id: card

    // =====================================================================
    // API
    // =====================================================================
    property string label: ""
    property string value: "—"

    /* Glyph name from FluentSystemIcons-Index.js. Every name in that font is
       spelled _20_ regardless of the size it is drawn at, and an unknown name
       renders as nothing at all — so it is left empty by default and the chip
       hides itself rather than showing an empty tinted square. */
    property string glyph: ""

    property string tone: "primary"
    property color ink: Tokens.toneInk(tone)
    property color fill: Tokens.toneFill(tone)

    /* Second line under the value: a delta, a count, a qualifier. Its own tone,
       because "▼ 12%" is bad news on a sales card and good news on a returns
       card, and only the page knows which. */
    property string subtext: ""
    property string subtextTone: ""

    /* pos pairs a compact value with a full-precision tooltip (set_money uses
       fmt_compact + fmt_money) so a large figure abbreviates instead of
       clipping, and the exact number is one hover away. */
    property string valueTooltip: ""

    /* Tone the value itself. Off by default — see the note above. */
    property string valueTone: ""

    // =====================================================================
    // SURFACE
    // =====================================================================
    /* Writable, because the same card is now used in two places with different
       room. A page has a whole row of the window to spend on four cards; a detail
       dialog has whatever is left above a table, and the 128px card that opens a
       page would push the table off the bottom there. Only the box shrinks — the
       value stays at font.amount in both, which is the point of the card. */
    property int chipSize: 60
    property int minHeight: 128

    /* Same reasoning: the floor CardRow wraps at travels with the card, so a
       dialog can pack four narrower cards into one row instead of two. */
    property int floorWidth: 320

    /* Declared here rather than at every call site: a card's whole reason for
       existing is to sit in a CardRow and share the row's width equally with its
       siblings, and repeating this on four cards per page is four chances to
       forget one and have it collapse to 320 while the rest stretch.
       Harmless when the card is not in a Layout — an attached property nobody
       reads. */
    Layout.fillWidth: true

    implicitHeight: Math.max(minHeight,
                             2 * Tokens.size.cardPadding
                             + Math.max(card.chipSize, textColumn.implicitHeight))

    /* A constant, not a measurement of the content. A Column's implicit width
       is the widest child's *assigned* width, and every child here is assigned
       `parent.width` — which resolves back through the Row to this card. Reading
       it here would close a binding loop (card width -> column width -> card
       implicit width -> card width).
       Cards are always laid out by CardRow, which imposes an equal width on
       each; this is only the floor that decides when CardRow wraps, so it is
       the same number as CardRow.minCardWidth. */
    implicitWidth: floorWidth

    color: Fluent.cardBackground
    radius: Tokens.radius.lg
    border.width: 1
    border.color: Fluent.dividerBorder

    Row {
        anchors.fill: parent
        anchors.margins: Tokens.size.cardPadding
        spacing: Tokens.spacing.md

        /* Leading edge in both directions: a Row positions by x and mirrors,
           so the chip is on the right in Arabic without being asked. */
        Rectangle {
            id: chip
            anchors.verticalCenter: parent.verticalCenter
            width: card.chipSize
            height: card.chipSize
            visible: card.glyph !== ""
            radius: Tokens.radius.md
            color: card.fill

            Icon {
                anchors.centerIn: parent
                icon: card.glyph
                size: Tokens.icon.lg
                color: card.ink
            }
        }

        Column {
            id: textColumn
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - (chip.visible ? card.chipSize + parent.spacing : 0)
            spacing: Tokens.spacing.xs

            /* All three lines pin their alignment to AlignLeft, which mirrors to
               AlignRight in Arabic, so the column is flush against the chip in
               both directions.
               Leaving it unset would NOT do that. Text with no explicit
               alignment follows its own content's direction, and these three
               lines do not agree on one: an Arabic label is an RTL paragraph and
               would sit right, while a digits-only value is an LTR paragraph and
               would sit left — the label and the number under it drifting to
               opposite edges of the same card. */

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignLeft
                text: card.label
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.overline
                font.weight: Font.DemiBold
                /* Caps and tracking, not a larger size: this is the quietest
                   line on the card and it still has to be identifiable at a
                   glance, which letterspaced caps do without taking room from
                   the value. */
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.8
                color: card.ink
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                id: valueText
                width: parent.width
                horizontalAlignment: Text.AlignLeft
                    text: card.value
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.amount
                    /* Tabular figures. At 34px the difference is not subtle: a card
                       whose value ticks from 999 to 1,000 physically moves when the
                       digits are proportional, and two cards side by side cannot be
                       compared at a glance. */
                    font.features: Tokens.figures
                    font.weight: Font.DemiBold
                color: card.valueTone !== "" ? Tokens.toneInk(card.valueTone)
                                             : Fluent.textPrimary
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignLeft
                visible: card.subtext !== ""
                text: card.subtext
                font.family: Tokens.font.family
                font.pixelSize: Tokens.font.caption
                color: card.subtextTone !== "" ? Tokens.toneInk(card.subtextTone)
                                               : Fluent.textSecondary
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    /* The full-precision figure behind an abbreviated value. A plain Item has
       no hovered state of its own, hence the handler. */
    HoverHandler { id: hover }

    QC.ToolTip {
        text: card.valueTooltip
        visible: hover.hovered && card.valueTooltip !== ""
        delay: 500
    }
}
