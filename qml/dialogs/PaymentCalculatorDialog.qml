import QtQuick
import QtQuick.Controls as QC
import QtQuick.Layouts
import FluentControls
import Mizan

/*
 * Change, before the money is taken. Ported from
 * pos/app/dialogs/amount_entry.py::PaymentCalculatorDialog.
 *
 *   ┌───────────────────────────────┐
 *   │ Payment calculator            │
 *   │ TOTAL           12 480,00 DA  │
 *   │ ┌───────────────────────────┐ │
 *   │ │ 15000                     │ │
 *   │ └───────────────────────────┘ │
 *   │ CHANGE           2 520,00 DA  │
 *   │ [7][8][9]                     │
 *   │ [4][5][6]  ...                │
 *   │                      [Done]   │
 *   └───────────────────────────────┘
 *
 * COMMITS NOTHING
 *
 * It reads the cart total and works out change. It cannot take a payment, and it
 * is opened while a customer is counting notes — which is why it is a dialog over
 * the till rather than a step in the payment flow.
 *
 * WHY THE NUMPAD AND NOT AN EXPRESSION KEYPAD
 *
 * pos's version evaluates arithmetic ("1000+500*2") through a whitelisted AST.
 * The question actually being asked at a counter is "they gave me this much, what
 * do I owe them" — one number against the total — so this reuses the same numpad
 * the till uses, and the operator's fingers do not have to learn a second keypad.
 * Anything more than that is a calculator, and every till has one beside it.
 */
AppDialog {
    id: dialog

    property var context: ({})

    readonly property var till: (typeof app !== "undefined" && app) ? app.pos : null

    preferredWidth: 560
    title: Strings.t("pos.calculator.title", "Payment calculator")

    property string buffer: ""

    readonly property real total: till ? till.total : 0
    readonly property real received: {
        var value = parseFloat(buffer)
        return isNaN(value) ? 0 : value
    }
    readonly property real delta: received - total

    /* Both figures come from the same formatter as the dock, so change and total
       cannot be written two different ways on one screen. */
    function money(value) {
        return till ? till.moneyText(value) : "—"
    }

    function feed(key) {
        switch (key) {
        case "clear":
            buffer = ""
            return
        case "back":
            buffer = buffer.substring(0, buffer.length - 1)
            return
        case ".":
            if (buffer.indexOf(".") < 0)
                buffer += "."
            return
        }
        if (key.length === 1 && key >= "0" && key <= "9")
            buffer += key
    }

    component Line: RowLayout {
        id: line
        property string caption: ""
        property string value: ""
        property color ink: Fluent.textPrimary
        property int size: Tokens.font.bodyLarge

        Layout.fillWidth: true
        spacing: Tokens.spacing.md

        Text {
            text: line.caption
            font.family: Tokens.font.family
            font.pixelSize: Tokens.font.overline
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.1
            color: Fluent.textSecondary
        }

        Item { Layout.fillWidth: true }

        Text {
            text: "\u200e" + line.value
            font.family: Tokens.font.family
            font.pixelSize: line.size
            font.weight: Font.DemiBold
            color: line.ink
        }
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.md

        Line {
            caption: Strings.t("pos.summary.total", "Total")
            value: dialog.money(dialog.total) + " " + (dialog.till ? dialog.till.currencyText : "")
        }

        /*
         * A readout, and nothing else.
         *
         * No mode pill and no tick: both belong to the till's strip, where the pill
         * names what Apply will do and the tick does it. This screen commits nothing —
         * the caption above it already says TOTAL and the line below says CHANGE — so
         * the pill was labelling a mode that does not exist here and the tick was a
         * control that did nothing at all when pressed. The trailing margin closes up
         * with them, which is what leaves the number the width of the dialog.
         */
        KeypadDisplay {
            Layout.fillWidth: true
            Layout.preferredWidth: 420
            text: dialog.buffer
            actionVisible: false
        }

        /* One line, and which one depends on the sign: money owed back to the
           customer, or money still owed by them. Never both, never a negative
           number with a minus sign to decode at a counter. */
        Line {
            visible: dialog.delta >= 0.005
            caption: Strings.t("pos.calculator.change", "Change")
            value: dialog.money(dialog.delta)
            ink: Tokens.success
            size: Tokens.font.amount
        }

        Line {
            visible: dialog.delta <= -0.005
            caption: Strings.t("pos.calculator.remaining", "Remaining")
            value: dialog.money(-dialog.delta)
            ink: Tokens.danger
            size: Tokens.font.amount
        }

        Numpad {
            Layout.fillWidth: true
            /* No entry modes: there is nothing here to apply a quantity to. */
            modes: []
            onKeyPressed: (key) => dialog.feed(key)
        }

        RowLayout {
            Layout.fillWidth: true

            Item { Layout.fillWidth: true }

            GlyphButton {
                glyph: "ic_fluent_checkmark_20_regular"
                text: Strings.t("action.done", "Done")
                highlighted: true
                onClicked: dialog.close()
            }
        }
    }
}
