import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The till's entry readout. Ported from
 * pos/app/widgets/keypad_display.py::KeypadDisplay.
 *
 *     ┌────────────────────────────────────────────────┐
 *     │ 6133273401234                      # QTY       │
 *     └────────────────────────────────────────────────┘
 *
 * A readout, not a field: it takes no focus and holds no state. The page owns
 * the buffer — every digit, whether it came from the on-screen numpad, a
 * keyboard or a scanner burst, is appended there and mirrored here. That is what
 * makes one buffer the single source of truth for what is about to be applied,
 * which is pos's design and worth keeping: two places to look for "what have I
 * typed" is how a cashier applies a quantity to the wrong line.
 *
 * WHY THE VALUE IS TEXT AND NOT A NUMBER
 *
 * It is shown exactly as typed, leading zeros and all, because half of what is
 * typed here is a barcode. Formatting "0612" as 612 would make a scan
 * unrecognisable to the person holding the product.
 *
 * WHY THE BADGE IS THE PAGE'S WORDS
 *
 * The mode vocabulary — its label, its glyph and its tone — belongs to Numpad,
 * which owns the buttons that switch it. This shows what it is given rather than
 * looking anything up, so the keypad and the readout cannot end up disagreeing
 * about what "+ AMT" is called or what colour it is.
 */
Rectangle {
    id: display

    // =====================================================================
    // API
    // =====================================================================
    /* The buffer, verbatim. */
    property string text: ""

    /* Shown when the buffer is empty. A plain "0" rather than a muted hint, so
       the readout always looks like a live numeric entry — pos made the same
       choice explicitly, having tried the placeholder. */
    property string placeholder: "0"

    /* What the next Apply will do, in the page's own words. */
    property string modeText: ""
    property string modeGlyph: ""
    property string tone: ""

    /*
     * APPLY LIVES HERE NOW, NOT ON THE PAD.
     *
     * It was the fourth key of the numpad's side column — under "# Qty", "+ Amount",
     * "− Discount" — which put the confirm action inside the grid of things being
     * confirmed, and cost a whole 72px key to say what a tick says. It is a filled
     * icon at the trailing end of this strip instead: beside the number it applies,
     * where the eye already is after typing, and where the mode pill has been saying
     * what it will do all along.
     */
    property bool actionEnabled: true
    signal applied()

    // =====================================================================
    // SURFACE
    // =====================================================================
    implicitHeight: Tokens.size.command
    radius: Tokens.radius.md
    color: Fluent.subtleSecondary
    border.width: 1
    border.color: display.tone !== "" ? Tokens.toneInk(display.tone)
                                      : Fluent.dividerBorder

    /* The border is the only thing that carries the tone across the whole strip,
       so it is worth animating: the mode changes under the operator's thumb and
       a hard switch reads as a flicker. */
    Behavior on border.color { ColorAnimation { duration: Fluent.anim.appearance } }

    // =====================================================================
    // CONTENT
    // =====================================================================
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.spacing.md
        anchors.rightMargin: Tokens.spacing.xs
        spacing: Tokens.spacing.sm

        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter

            /* U+200E LEFT-TO-RIGHT MARK, for the same reason DataTable prefixes
               it to a barcode column: a run of digits inside an Arabic paragraph
               is resolved against the paragraph direction and comes out
               reversed. A scan that reads backwards is worse than useless — the
               cashier cannot tell whether the scanner or the code is wrong. */
            text: "\u200e" + (display.text !== "" ? display.text : display.placeholder)

            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.amount
            /* Tabular figures: this readout changes under the thumb, and digits of
               different widths make the whole number slide as it is typed. */
            font.features: Tokens.figures
            font.weight: Font.DemiBold
            color: display.text !== "" ? Fluent.textPrimary : Fluent.textTertiary
            elide: Text.ElideLeft
            /* Eliding from the left, uniquely in this app: what matters in a long
               entry is the end of it — the digits that just landed. */
            maximumLineCount: 1
            horizontalAlignment: Text.AlignLeft
        }

        /* The active mode, as a tone pill. Same shape as the stock pill on a
           tile, so "a small coloured pill" means the same thing on both halves
           of this screen. */
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: display.modeText !== ""
            implicitWidth: badge.implicitWidth + 2 * Tokens.spacing.sm
            implicitHeight: badge.implicitHeight + Tokens.spacing.xs
            radius: Tokens.radius.pill
            color: Tokens.toneFill(display.tone)

            Row {
                id: badge
                anchors.centerIn: parent
                spacing: Tokens.spacing.xs

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: display.modeGlyph !== ""
                    icon: display.modeGlyph
                    size: Tokens.icon.sm
                    color: Tokens.toneInk(display.tone)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: display.modeText
                    font.family: Tokens.font.family
                    font.pixelSize: Tokens.font.caption
                    font.weight: Font.DemiBold
                    color: Tokens.toneInk(display.tone)
                }
            }
        }

        /*
         * Apply, as a filled icon.
         *
         * Coloured by the MODE, not fixed: the pill beside it already carries that
         * tone, so the button that acts on it carries the same one — pressing a green
         * tick while the strip says "Received" in green is one statement, and pressing
         * a blue one would be two.
         *
         * Built from a Rectangle and a MouseArea rather than a styled Button, the way
         * the library builds its own controls: a styled Button would bring its own
         * implicit size and padding into a 56px strip that has exactly 48 to give.
         */
        Rectangle {
            id: applyButton

            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Tokens.size.control
            implicitHeight: Tokens.size.control
            radius: Tokens.radius.sm

            readonly property color hue: display.tone !== ""
                                         ? Tokens.toneInk(display.tone) : Tokens.brand

            color: !display.actionEnabled ? Fluent.subtleTertiary
                 : applyArea.pressed ? Qt.darker(hue, 1.18)
                 : applyArea.containsMouse ? Qt.lighter(hue, 1.08)
                                           : hue

            Behavior on color { ColorAnimation { duration: Fluent.anim.fast } }

            Icon {
                anchors.centerIn: parent
                icon: "ic_fluent_checkmark_20_filled"
                size: Tokens.icon.md
                /* onBrand rather than the theme's own foreground: this sits on a
                   saturated fill in both themes, and Tokens keeps the pair. */
                color: display.actionEnabled ? Tokens.onBrand : Fluent.textTertiary
            }

            MouseArea {
                id: applyArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: display.actionEnabled
                cursorShape: Qt.PointingHandCursor
                onClicked: display.applied()
            }

            QC.ToolTip.text: Strings.t("pos.numpad.apply", "Apply")
            QC.ToolTip.visible: applyArea.containsMouse
            QC.ToolTip.delay: 500
        }
    }
}
