import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * The till's entry readout. Ported from
 * pos/app/widgets/keypad_display.py::KeypadDisplay.
 *
 *     ┌──────────────────────────────────────────────┐
 *     │  6133                                  [ ➜ ] │
 *     │  Coca-Cola 1.5L                               │
 *     └──────────────────────────────────────────────┘
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
 * It is shown exactly as typed, leading zeros and all. Formatting "0612" as 612
 * would make the number a different number; the readout's job is to show the
 * entry, not to interpret it.
 *
 * WHY THERE IS NO MODE PILL
 *
 * The entry's mode is the lit key on the pad itself — the highlighted mode
 * button with its tone ink is one glance down-right away, and a pill here
 * would only repeat that answer in a second place the two could disagree.
 * The readout shows the number; the pad says what the number is.
 *
 * WHY THE TARGET LINE IS GONE
 *
 * There used to be a second line under the figure naming the cart line the
 * number would change. It was the answer to a real question — "which thing
 * will this number change" — but the cart itself is the answer: the selected
 * row is already lit, and the readout repeating its name put a caption under
 * the biggest figure on the screen and made the number itself smaller to pay
 * for it. The strip is one line of figure and the commit key, and the space
 * the caption held belongs to the number.
 *
 * WHY SUBMIT IS AN ICON
 *
 * It was the fourth key of the numpad's side column once, and then a tick at
 * this strip's trailing end beside the word "Apply". A tick reads as "done",
 * and "Apply" reads as a settings verb; what this key does is commit the typed
 * quantity to the selected line. So: an enter-arrow alone — the shape a
 * keyboard's Enter key already means, needing no word beside it — always in
 * the one emerald, beside the number it commits, where the eye already is
 * after typing. The tooltip and the accessible name say the whole act,
 * "Submit quantity", so the key explains itself on hover and to a screen
 * reader without spending the strip's width on a label.
 *
 * `actionVisible: false` for a readout with nothing to commit. The payment
 * calculator is that case — it works out change and commits nothing, so a
 * submit key there was a control that did literally nothing when pressed.
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

    /*
     * The commit control's own words. The default comes from the catalogue so
     * the page does not have to pass it; the property exists so a future
     * readout could commit something else.
     */
    property string actionTooltip: Strings.t("pos.numpad.submit.qty",
                                             "Submit quantity")

    /* `actionVisible: false` for a readout with nothing to apply. */
    property bool actionVisible: true
    property bool actionEnabled: true
    signal applied()

    // =====================================================================
    // SURFACE
    // =====================================================================
    /* One line — the figure — plus the commit key: 64 holds the figure at the
       size a number read at speed wants, with the key centred against it.
       Fixed, so the keypad region below never shifts. */
    implicitHeight: 64
    radius: Tokens.radius.md
    color: Fluent.subtleSecondary
    border.width: 1
    border.color: Fluent.dividerBorder

    // =====================================================================
    // CONTENT
    // =====================================================================
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.spacing.sm
        anchors.rightMargin: Tokens.spacing.xs
        spacing: Tokens.spacing.sm

        /* The number, the most prominent thing in the bar, and the only
            thing in it besides the commit key. */
        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter

            /* U+200E LEFT-TO-RIGHT MARK, for the same reason DataTable prefixes
               it to a barcode column: a run of digits inside an Arabic paragraph
               is resolved against the paragraph direction and comes out
               reversed. A typed entry that reads backwards is worse than
               useless — the operator cannot tell whether they or the entry
               are wrong. */
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

        /*
         * Submit, the enter-arrow alone in the one emerald.
         *
         * Built from a Rectangle and a MouseArea rather than a styled Button, the way
         * the library builds its own controls: a styled Button would bring its own
         * implicit size and padding into a 56px strip that has exactly 48 to give.
         *
         * The arrow is the ENTER-arrow shape — an arrow committing into its
         * mark — and it flips with the language: in Arabic the row mirrors,
         * the key sits at the reading-start edge, and the arrow must point
         * the way the reading goes.
         */
        Rectangle {
            id: submitButton

            Layout.alignment: Qt.AlignVCenter
            visible: display.actionVisible
            implicitWidth: 48
            implicitHeight: 48
            radius: Tokens.radius.sm

            color: !display.actionEnabled ? Tokens.disabledFill
                 : submitArea.pressed ? Tokens.brandPressed
                 : submitArea.containsMouse ? Tokens.brandHover
                 : Tokens.brand

            Behavior on color { ColorAnimation { duration: Fluent.anim.fast } }

            Icon {
                id: submitGlyph
                anchors.centerIn: parent
                icon: "ic_fluent_arrow_enter_20_regular"
                size: Tokens.icon.md
                /* onBrand rather than the theme's own foreground: this sits on a
                   saturated fill in both themes, and Tokens keeps the pair. */
                color: display.actionEnabled ? Tokens.onBrand : Fluent.textDisabled
                /* Point the way the reading goes: mirrored with the row in
                   Arabic. An arrow that keeps pointing right on a
                   right-to-left screen points backwards. */
                transform: Scale {
                    origin.x: submitGlyph.width / 2
                    origin.y: submitGlyph.height / 2
                    xScale: Strings.rtl ? -1 : 1
                }
            }

            MouseArea {
                id: submitArea
                anchors.fill: parent
                hoverEnabled: true
                /* The tooltip says the act even while the key is disabled —
                   that is exactly when the question "what would this do" is
                   asked. */
                cursorShape: Qt.PointingHandCursor
                onClicked: if (display.actionEnabled) display.applied()
            }

            QC.ToolTip.text: display.actionTooltip
            QC.ToolTip.visible: submitArea.containsMouse && display.actionVisible
            QC.ToolTip.delay: 500

            Accessible.role: Accessible.Button
            Accessible.name: display.actionTooltip
        }
    }
}
