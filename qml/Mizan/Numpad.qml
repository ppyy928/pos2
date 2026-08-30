import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * On-screen numeric keypad. A pure view: it holds no buffer and no business
 * logic, it reports presses and lets the page decide what they mean.
 *
 *     Numpad {
 *         activeMode: page.mode
 *         onKeyPressed: (key) => page.feed(key)
 *         onModeRequested: (mode) => page.mode = mode
 *     }
 *
 * Layout (LTR; the whole thing mirrors in Arabic because it is built from
 * Layouts, which mirror):
 *
 *     ┌────────┬─────┬─────┬─────┐
 *     │ # QTY  │  7  │  8  │  9  │
 *     ├────────┼─────┼─────┼─────┤
 *     │ + AMT  │  4  │  5  │  6  │
 *     ├────────┼─────┼─────┼─────┤
 *     │ − DISC │  1  │  2  │  3  │
 *     ├────────┼─────┼─────┼─────┤
 *     │        │  0  │  .  │  ⌫  │
 *     └────────┴─────┴─────┴─────┘
 *
 * TWO SIGNALS, NOT ONE
 *
 * pos routes every press through a single `pressed(str)` and encodes the mode
 * buttons into it as "qty_mode" / "plus_amt" / "minus_amt", which the page then
 * translates back through a _MODE_TO_KEY table. Splitting the mode column onto
 * its own signal deletes that table: the page receives the mode name it already
 * uses everywhere else.
 *
 * WHY THE MODE BUTTONS ARE NOT `checkable`
 *
 * An AbstractButton with `checkable: true` assigns its own `checked` on click,
 * which destroys any binding on it — the same trap as ComboBox.currentIndex.
 * So the mode column is stateless: `highlighted` is bound to activeMode, and a
 * click only *asks* for the change. The page owns the state, the keypad shows
 * it, and there is no second copy to fall out of step. That also makes an
 * exclusive ButtonGroup unnecessary — one bound comparison cannot elect two
 * winners.
 *
 * WHY NO KEY REPLACES ITS `background`
 *
 * Every key here is a plain styled Button. Colour is carried in the *ink* only.
 * Substituting a Rectangle background would have been the obvious way to tint
 * the three modes, and it would have cost the style's focus ring, its hover and
 * pressed fills, and — because padding, insets and implicitHeight all come from
 * the same `__config` table the vendoring scaler multiplied — quietly opted
 * these keys out of the app-wide scale. Tinting the glyph and label instead
 * reaches the same "coloured" goal and keeps all of that intact.
 */
Item {
    id: root

    // =====================================================================
    // API
    // =====================================================================
    /* Which entry-mode toggles the side column carries, in order. POS wants
       all three; a purchase screen that only edits quantities passes ["qty"],
       and the spacer below them takes the rows they do not use. */
    property var modes: ["qty", "plus", "minus"]

    /* The mode currently in force, owned by the page. */
    property string activeMode: "qty"

    /* Digits "0".."9", ".", "back", "clear". Same vocabulary as pos
       minus the three mode keys, which have their own signal, and minus
       "apply", which is now KeypadDisplay's trailing button. */
    signal keyPressed(string key)
    signal modeRequested(string mode)

    readonly property int keySize: Tokens.size.numpadKey
    readonly property int gap: Tokens.spacing.xs

    /* Four rows of keys: the digit block is always four rows tall regardless of
       how many modes the side column carries. Across, the side column is 1.4
       keys wide (see its Layout.preferredWidth) plus three digit columns, with
       one gap between the two blocks and two inside the grid. */
    implicitHeight: 4 * keySize + 3 * gap
    implicitWidth: Math.round(keySize * 4.4) + 3 * gap

    // =====================================================================
    // MODE VOCABULARY
    // =====================================================================
    /* Label, glyph and tone per mode. The glyph carries the meaning at a glance
       — an operator reaching for "discount" finds the minus sign before they
       read the word, which matters at speed and in a second language. The tone
       is the same one the rest of the app already uses for that meaning:
       quantity is neutral information, an added amount is a caution because it
       is money the customer owes, a discount is money leaving. */
    readonly property var modeSpecs: ({
        "qty":   { key: "pos.numpad.qty",   fallback: "QTY",
                   glyph: "ic_fluent_number_symbol_20_regular", tone: "info" },
        "plus":  { key: "pos.numpad.plus",  fallback: "+ AMT",
                   glyph: "ic_fluent_add_20_regular",           tone: "warning" },
        "minus": { key: "pos.numpad.minus", fallback: "− DISC",
                   glyph: "ic_fluent_subtract_20_regular",      tone: "danger" },
        /* A delivery screen edits what a thing COST, which a sale screen never
           does — its prices come off the shelf. Same pad, two more stops pulled
           out: `price` is what it will be sold for, which the line entry sheet
           asks for beside the cost so the margin between them is in view. */
        "cost":  { key: "pos.numpad.cost",  fallback: "COST",
                   glyph: "ic_fluent_tag_20_regular",           tone: "primary" },
        "price": { key: "pos.numpad.price", fallback: "SELL",
                   glyph: "ic_fluent_arrow_trending_20_regular", tone: "success" }
    })

    function specFor(mode) {
        var spec = modeSpecs[mode]
        return spec !== undefined ? spec
             : { key: "", fallback: mode, glyph: "", tone: "" }
    }

    // =====================================================================
    // LAYOUT
    // =====================================================================
    RowLayout {
        anchors.fill: parent
        spacing: root.gap

        // -----------------------------------------------------------------
        // side column: the entry modes
        // -----------------------------------------------------------------
        /*
         * Apply used to be the fourth key here. It moved to the trailing end of
         * KeypadDisplay, where the number it applies is — see that file's note. The
         * column is now three keys and nothing else, and it disappears entirely when
         * a page passes no modes, which is how the pad becomes a plain numeric entry
         * while a payment is being confirmed.
         */
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.modes.length > 0
            /* A little wider than one digit key. The side labels are words, not
               single characters, so a straight quarter of the width would elide
               "الكمية" at 15px. 1.4 fits it and still reads as one column. */
            Layout.preferredWidth: root.keySize * 1.4
            spacing: root.gap

            Repeater {
                model: root.modes

                delegate: QC.Button {
                    id: modeKey
                    required property string modelData

                    readonly property var spec: root.specFor(modelData)

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: root.keySize
                    /* Exactly one key tall, never more. Apply used to be the fourth
                       item in this column, so four items divided the height evenly by
                       accident; with three, the same fillHeight stretched each of
                       them to a third of the pad and the side column stopped lining
                       up with the digit rows beside it. The spacer takes the slack. */
                    Layout.maximumHeight: root.keySize

                    /* Not checkable — see the header. */
                    highlighted: root.activeMode === modelData
                    onClicked: root.modeRequested(modelData)

                    QC.ToolTip.text: Strings.t(spec.key, spec.fallback)
                    QC.ToolTip.visible: hovered
                    QC.ToolTip.delay: 700

                    /* Tone-coloured while inactive so the three modes are told
                       apart before any is chosen. Active or disabled, the style
                       owns the colour: on an accent fill `icon.color` is already
                       the correct on-accent ink, and greyed-out is greyed-out. */
                    readonly property color ink: (highlighted || !enabled)
                        ? icon.color : Tokens.toneInk(spec.tone)

                    /* An Item around a centred Column, not the Column itself.
                       Control assigns contentItem both the full available width
                       AND height, so a Column used directly would be stretched
                       to 72px and stack its children from the top edge. The
                       wrapper absorbs the stretch and forwards the Column's own
                       implicit size so the button still measures from content. */
                    contentItem: Item {
                        implicitWidth: modeStack.implicitWidth
                        implicitHeight: modeStack.implicitHeight

                        Column {
                            id: modeStack
                            anchors.centerIn: parent
                            spacing: 2

                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: modeKey.spec.glyph !== ""
                                icon: modeKey.spec.glyph
                                size: Tokens.icon.md
                                color: modeKey.ink
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Strings.t(modeKey.spec.key, modeKey.spec.fallback)
                                font.pixelSize: Tokens.font.caption
                                font.weight: Font.DemiBold
                                color: modeKey.ink
                            }
                        }
                    }
                }
            }

            /* Absorbs the rows the side column does not use: with three modes it is
               zero-height, with fewer it keeps them key-sized at the top instead of
               stretching each one down a third of the pad. */
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        // -----------------------------------------------------------------
        // digit block
        // -----------------------------------------------------------------
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 3
            columnSpacing: root.gap
            rowSpacing: root.gap

            /* Rows read 7-8-9 / 4-5-6 / 1-2-3 / 0-.-⌫ — telephone order, which
               is what every till and calculator uses. `flow` is left at its
               default because GridLayout mirrors on its own in Arabic, and a
               mirrored numpad is correct: the digit *order* is a reading order,
               not a fixed spatial arrangement.

               "." and "back" come from the same list as the digits rather than
               being appended as separate items, so all twelve cells are placed
               by one rule and none can drift out of position. */
            Repeater {
                model: ["7", "8", "9", "4", "5", "6", "1", "2", "3", "0", ".", "back"]

                delegate: QC.Button {
                    id: digitKey
                    required property string modelData

                    readonly property bool isBack: modelData === "back"

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: root.keySize

                    text: isBack ? "" : modelData
                    onClicked: root.keyPressed(modelData)

                    /* Hold backspace to clear. pos has no clear key at all — it
                       clears from Escape, which a till with no keyboard does not
                       have, so emptying a mis-scanned 13-digit barcode there is
                       thirteen taps. autoRepeat would have been the other way to
                       soften that, but Qt suppresses pressAndHold when it is on,
                       and one gesture that empties the buffer beats a fast
                       repeat that still has to run the whole way. */
                    onPressAndHold: if (isBack) root.keyPressed("clear")

                    Accessible.name: isBack
                        ? Strings.t("pos.numpad.back", "Backspace") : text

                    QC.ToolTip.text: Strings.t("pos.numpad.back.hint",
                                               "Backspace — hold to clear")
                    QC.ToolTip.visible: isBack && hovered
                    QC.ToolTip.delay: 700

                    /* 32px digits. This is the one place in the app where type
                       size is a usability requirement rather than a style
                       choice: the key is struck without looking, so the digit
                       has to be legible in peripheral vision. */
                    font.pixelSize: Tokens.font.title
                    font.weight: Font.Medium

                    contentItem: Item {
                        implicitWidth: digitKey.isBack
                            ? backGlyph.implicitWidth : digitLabel.implicitWidth
                        implicitHeight: digitKey.isBack
                            ? backGlyph.implicitHeight : digitLabel.implicitHeight

                        Icon {
                            id: backGlyph
                            anchors.centerIn: parent
                            visible: digitKey.isBack
                            icon: "ic_fluent_backspace_20_regular"
                            size: Tokens.icon.lg
                            color: digitKey.icon.color
                        }

                        Text {
                            id: digitLabel
                            anchors.centerIn: parent
                            visible: !digitKey.isBack
                            text: digitKey.text
                            font: digitKey.font
                            color: digitKey.icon.color
                        }
                    }
                }
            }
        }
    }
}
